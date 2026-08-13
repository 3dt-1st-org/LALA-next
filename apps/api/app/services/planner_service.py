from __future__ import annotations

from datetime import datetime, timedelta, timezone

from apps.api.app.core.config import get_settings
from apps.api.app.schemas.planner import DailyPlanRequest
from apps.api.app.services.normalization import normalize_language
from apps.api.app.services.opening_hours_service import (
    estimated_opening_hours,
    is_within_hours,
)
from apps.api.app.services.places_service import list_places
from apps.api.app.services.request_identity import generation_identity
from apps.api.app.services.travel_time_service import (
    estimate_walking_minutes,
    live_routing_enabled,
    period_start_time,
    resolve_travel_time_authority_minutes,
)
from apps.api.app.services.weather_service import current_weather


def daily_plan(request: DailyPlanRequest) -> dict:
    language = normalize_language(request.language)
    weather = current_weather(lat=request.lat, lng=request.lng)
    places = list_places(
        lat=request.lat,
        lng=request.lng,
        radius_m=request.radius_m,
        category="all",
        language=language,
    )
    source = _combined_source(places.get("source"), weather.get("source"))
    place_candidates = places.get("places") or []
    return {
        "language": language,
        "center": {"lat": request.lat, "lng": request.lng},
        "radius_m": request.radius_m,
        "weather": weather,
        "slots": _daily_plan_slots(
            place_candidates=place_candidates, weather=weather, language=language
        ),
        "source": source,
        **daily_plan_identity(request, language=language),
    }


def intervention(*, lat: float, lng: float, radius_m: int, language: str = "en") -> dict:
    normalized = normalize_language(language)
    weather = current_weather(lat=lat, lng=lng)
    places = list_places(
        lat=lat,
        lng=lng,
        radius_m=radius_m,
        category="all",
        language="ko",
    )
    candidate = (places.get("places") or [None])[0]
    source = _combined_source(places.get("source"), weather.get("source"))
    candidate_name = (candidate or {}).get("name") or _fallback_candidate_name(normalized)
    outdoor_status = weather["outdoor_status"]
    is_bad_weather = outdoor_status == "bad"
    full_slots = _full_slots_enabled()
    unavailable_reason = (
        "추천 장소가 부족해요" if normalized == "ko" else "Not enough nearby options"
    )
    # 기존 추천을 slot 구조로 옮김(P5A _plan_slot 재사용, period=afternoon).
    original_slot = _plan_slot(
        period="afternoon",
        title=("오후" if normalized == "ko" else "Afternoon"),
        place=candidate,
        weather_hint=outdoor_status,
        unavailable_reason=unavailable_reason,
        language=normalized,
        weather=weather,
        full_slots=full_slots,
    )
    # D5: closure trigger derived offline from original_slot's category-based
    # closure_state. No external feed (BLOCKED_EXTERNAL V7); flag-off → never emits.
    closure_factors: list[dict] = []
    is_closure = full_slots and original_slot.get("closure_state") == "closed"
    if is_closure:
        closure_factors = [
            {"factor": "slot_closure_state", "value": "closed", "period": "afternoon"}
        ]
    # P5B §12.4: observable trigger classification + honest-unavailable fields.
    # authority(travel-time/indoor-outdoor)가 없으면 값을 차단할 뿐 contract 는 유지.
    return {
        "center": {"lat": lat, "lng": lng},
        "radius_m": radius_m,
        "should_intervene": is_bad_weather or is_closure,
        "reason": _intervention_reason(
            weather_status=outdoor_status,
            candidate_name=candidate_name,
            language=normalized,
        ),
        "recommended_action": _recommended_action(
            weather_status=outdoor_status,
            candidate_name=candidate_name,
            language=normalized,
        ),
        "place": candidate,
        "source": source,
        "original_slot": original_slot,
        # indoor/outdoor provenance: bad weather 시 실내 대체 장소 검색(AI enrichment 기반).
        "alternative_slot": _find_indoor_alternative(
            place_candidates=places.get("places") or [],
            exclude_place_id=(candidate or {}).get("place_id"),
            language=normalized,
            weather_hint=outdoor_status,
            unavailable_reason=unavailable_reason,
            weather=weather,
            full_slots=full_slots,
        )
        if is_bad_weather
        else None,
        # observable trigger 만. good/unknown + closure 없음 → null. 발명 금지.
        "trigger_type": _intervention_trigger_type(
            is_bad_weather=is_bad_weather, is_closure=is_closure
        ),
        "trigger_factors": _intervention_trigger_factors(
            outdoor_status=outdoor_status, closure_factors=closure_factors
        ),
        # travel-time authority 부재 → 거리/이동시간 비교 불가(honest null).
        "distance_comparison": None,
        # contract boundary: API 는 항상 default. 실제 상태 관리는 P5C UI/persistence.
        "user_decision": "pending",
        "apply_state": "not_applied",
        "history": [],
    }


def _fallback_candidate_name(language: str) -> str:
    return "근처 로컬 장소" if language == "ko" else "nearby local places"


def _full_slots_enabled() -> bool:
    # PLAN_FULL_SLOTS gates the V3 additive slot projections (D2/D3/D4/D6) and the
    # closure trigger (D5). getattr fallback mirrors places_service: test doubles that
    # omit feature_flags stay flag-off (byte-for-byte pre-V3 behavior).
    flags = getattr(get_settings(), "feature_flags", None) or {}
    return bool(flags.get("PLAN_FULL_SLOTS", False))


def _intervention_trigger_type(*, is_bad_weather: bool, is_closure: bool) -> str | None:
    # D5: additive enum widening on a nullable string. Flag-off ⇒ is_closure False ⇒
    # the pre-V3 "bad_weather"/None result is preserved exactly.
    if is_bad_weather and is_closure:
        return "bad_weather_and_closure"
    if is_bad_weather:
        return "bad_weather"
    if is_closure:
        return "closure_detected"
    return None


def _intervention_trigger_factors(
    *, outdoor_status: str, closure_factors: list[dict] | None = None
) -> list[dict]:
    """관측가능 trigger 요소만. 발명된 factor 없음(honest)."""
    factors: list[dict] = []
    if outdoor_status == "bad":
        factors.append({"factor": "weather_outdoor_status", "value": "bad"})
    if closure_factors:
        factors.extend(closure_factors)
    return factors


def _find_indoor_alternative(
    *,
    place_candidates: list[dict],
    exclude_place_id: str | None,
    language: str,
    weather_hint: str | None,
    unavailable_reason: str,
    weather: dict | None = None,
    full_slots: bool = False,
) -> dict | None:
    """AI enrichment is_indoor=true 인 첫 번째 대체 장소를 slot 으로 반환.

    provenance 없거나 실내 장소가 없으면 None(honest). 발명된 대체 금지.
    """
    for place in place_candidates:
        if place.get("place_id") == exclude_place_id:
            continue
        if place.get("is_indoor") is True:
            return _plan_slot(
                period="afternoon",
                title="오후" if language == "ko" else "Afternoon",
                place=place,
                weather_hint=weather_hint,
                unavailable_reason=unavailable_reason,
                language=language,
                weather=weather,
                full_slots=full_slots,
            )
    return None


def _combined_source(place_source: str | None, weather_source: str | None) -> str:
    sources = {place_source or "unavailable", weather_source or "unavailable"}
    if sources == {"db"}:
        return "db"
    if sources == {"public_mvp_snapshot"}:
        return "public_mvp_snapshot"
    if "db" in sources:
        return "mixed"
    if "public_mvp_snapshot" in sources:
        return "mixed"
    return "unavailable"


_PERIOD_ORDER = ("morning", "lunch", "afternoon", "dinner")


def _daily_plan_slots(*, place_candidates: list[dict], weather: dict, language: str) -> list[dict]:
    """정확히 4 period 슬롯(morning/lunch/afternoon/dinner)을 발생한다(순서 고정).

    truthfulness: place 는 실제 candidate 만 dedupe 배정한다. travel-time /
    opening-hours / franchise 등 authority 가 없으면 관련 필드는 null(honest
    unavailable)이고, 후보가 부족해 place 가 없는 slot 은 unavailable_reason 로
    정직한 부재를 전달한다. timestamp/fake authority 값은 절대 발명하지 않는다.
    """
    ko = language == "ko"
    titles = {
        "morning": "오전" if ko else "Morning",
        "lunch": "점심" if ko else "Lunch",
        "afternoon": "오후" if ko else "Afternoon",
        "dinner": "저녁" if ko else "Dinner",
    }
    weather_hint = weather.get("outdoor_status")
    unavailable_reason = "추천 장소가 부족해요" if ko else "Not enough nearby options"

    # restaurant 후보는 식사 slot(lunch/dinner) 에, non-restaurant 후보는
    # morning/afternoon 에 우선 배정(deterministic, 입력 순서 유지).
    restaurants = [p for p in place_candidates if p.get("category") == "restaurant"]
    others = [p for p in place_candidates if p.get("category") != "restaurant"]
    used_place_ids: set[str] = set()
    ri = 0
    ni = 0

    def _take_restaurant() -> dict | None:
        return _take_deduping(restaurants, "r")

    def _take_other() -> dict | None:
        return _take_deduping(others, "n")

    def _take_deduping(group: list[dict], state_key: str) -> dict | None:
        # advance the matching pointer, skipping already-used place_ids (dedupe).
        nonlocal ri, ni
        i = ri if state_key == "r" else ni
        while i < len(group):
            candidate = group[i]
            i += 1
            place_id = candidate.get("place_id")
            if place_id is not None and place_id in used_place_ids:
                continue
            if place_id is not None:
                used_place_ids.add(place_id)
            if state_key == "r":
                ri = i
            else:
                ni = i
            return candidate
        if state_key == "r":
            ri = i
        else:
            ni = i
        return None

    # deterministic allocation: primary list, fallback to the other list.
    morning = _take_other()
    lunch = _take_restaurant()
    if lunch is None:
        lunch = _take_other()
    afternoon = _take_other()
    if afternoon is None:
        afternoon = _take_restaurant()
    dinner = _take_restaurant()
    if dinner is None:
        dinner = _take_other()

    assigned = {
        "morning": morning,
        "lunch": lunch,
        "afternoon": afternoon,
        "dinner": dinner,
    }

    # Consecutive-slot estimated walking time (Haversine ÷ 4 km/h).
    # First slot has no previous → null. Slots without place → null.
    prev_place: dict | None = None
    travel_times: dict[str, int | None] = {}
    # V5-C routing seam: authoritative Directions ETA per slot. Gated hook — computed
    # only when LALA_ENABLE_LIVE_ROUTING is on; honestly null in V5 (Directions are
    # BLOCKED_EXTERNAL/V7). Flag-off keeps the slot key set byte-for-byte pre-V5.
    routing_authority_enabled = live_routing_enabled()
    travel_time_authorities: dict[str, int | None] = {}
    for period in _PERIOD_ORDER:
        place = assigned[period]
        if prev_place is not None and place is not None:
            travel_times[period] = estimate_walking_minutes(
                float(prev_place.get("lat") or 0),
                float(prev_place.get("lng") or 0),
                float(place.get("lat") or 0),
                float(place.get("lng") or 0),
            )
        else:
            travel_times[period] = None
        if routing_authority_enabled and prev_place is not None and place is not None:
            travel_time_authorities[period] = resolve_travel_time_authority_minutes(
                float(prev_place.get("lat") or 0),
                float(prev_place.get("lng") or 0),
                float(place.get("lat") or 0),
                float(place.get("lng") or 0),
            )
        else:
            travel_time_authorities[period] = None
        prev_place = place if place is not None else prev_place

    # D6: swappable_alternatives populated from the existing candidate-pool leftovers
    # (already-fetched places not assigned to any slot). Flag-off ⇒ empty dict ⇒ each
    # slot stays swappable_alternatives: [] (byte-for-byte pre-V3).
    full_slots = _full_slots_enabled()
    swappable = (
        _swappable_alternatives_by_period(assigned=assigned, place_candidates=place_candidates)
        if full_slots
        else {}
    )

    return [
        _plan_slot(
            period=period,
            title=titles[period],
            place=assigned[period],
            weather_hint=weather_hint,
            unavailable_reason=unavailable_reason,
            language=language,
            travel_time=travel_times[period],
            weather=weather,
            full_slots=full_slots,
            swappable_alternatives=swappable.get(period),
            routing_authority_enabled=routing_authority_enabled,
            travel_time_authority=travel_time_authorities[period],
        )
        for period in _PERIOD_ORDER
    ]


def _swappable_alternatives_by_period(
    *, assigned: dict[str, dict | None], place_candidates: list[dict]
) -> dict[str, list[dict]]:
    # D6: per-slot swap candidates = pool leftovers (not assigned to any slot), same
    # category first, capped at 3. Honest [] when the pool is exhausted. No new fetch.
    assigned_places = [p for p in assigned.values() if p is not None]
    assigned_ids = {p.get("place_id") for p in assigned_places if p.get("place_id") is not None}
    assigned_obj_ids = {id(p) for p in assigned_places}
    leftovers = [
        p
        for p in place_candidates
        if id(p) not in assigned_obj_ids and p.get("place_id") not in assigned_ids
    ]
    by_period: dict[str, list[dict]] = {}
    for period in _PERIOD_ORDER:
        slot_place = assigned[period]
        if slot_place is None:
            by_period[period] = []
            continue
        category = slot_place.get("category")
        same = [p for p in leftovers if p.get("category") == category]
        other = [p for p in leftovers if p.get("category") != category]
        by_period[period] = (same + other)[:3]
    return by_period


_RECOMMENDATION_REASON = {
    "restaurant": ("맛집으로 추천해요", "Recommended as a local restaurant"),
    "attraction": ("명소로 추천해요", "Recommended as a local attraction"),
    "event": ("진행 중인 행사예요", "An ongoing event"),
    "culture_venue": ("문화 공간이에요", "A culture venue"),
}
_DEFAULT_REASON = ("가까운 추천 장소예요", "A nearby recommended stop")


def _recommendation_reason(place: dict, language: str) -> str:
    ko_label, en_label = _RECOMMENDATION_REASON.get(
        place.get("category") or "other", _DEFAULT_REASON
    )
    return ko_label if language == "ko" else en_label


def _plan_slot(
    *,
    period: str,
    title: str,
    place: dict | None,
    weather_hint: str | None,
    unavailable_reason: str,
    language: str,
    travel_time: int | None = None,
    weather: dict | None = None,
    full_slots: bool = False,
    swappable_alternatives: list[dict] | None = None,
    routing_authority_enabled: bool = False,
    travel_time_authority: int | None = None,
) -> dict:
    # start_time: 관용적 시간대 시작 시각(09:00/12:00/14:00/18:00). opening-hours authority
    # 확보 전까지 표준 관례 기반 추정값.
    # travel_time: Haversine 직선거리 기반 도보 추정(분). routing authority 확보 전까지 추정.
    # stay_duration/opening_hours_valid/indoor_outdoor/franchise: authority 부재 → null.
    indoor_outdoor = None
    if place and place.get("is_indoor") is not None:
        indoor_outdoor = "indoor" if place["is_indoor"] else "outdoor"

    # opening_hours: 카테고리 기반 추정 운영시간 (authority 아님, estimated).
    open_t, close_t = estimated_opening_hours(place.get("category", "") if place else "")
    start_t = period_start_time(period)
    oh_valid = is_within_hours(start_t, open_t, close_t) if place else None

    slot = {
        "period": period,
        "title": title,
        "place": place,
        "weather_hint": weather_hint,
        "start_time": start_t,
        "stay_duration_minutes": None,
        "travel_time_from_previous_minutes": travel_time,
        "opening_hours_valid": oh_valid,
        "estimated_opening_hours": f"{open_t}-{close_t}" if place else None,
        "indoor_outdoor": indoor_outdoor,
        "recommendation_reason": (_recommendation_reason(place, language) if place else None),
        "local_franchise_confidence": None,
        "swappable_alternatives": (
            list(swappable_alternatives) if (full_slots and swappable_alternatives) else []
        ),
        "unavailable_reason": None if place else unavailable_reason,
    }
    if full_slots:
        # PLAN_FULL_SLOTS additive projections (D2/D3/D4). Flag-off omits these keys so
        # the slot payload stays byte-for-byte the pre-V3 shape; values are projections
        # of already-fetched weather/AQ + opening-hours data (no new external call).
        slot["closure_state"] = _closure_state(oh_valid=oh_valid, place=place)
        slot["forecast_window"] = _nearest_forecast_window(start_time=start_t, weather=weather)
        slot["air_quality_bad"] = _air_quality_bad(indoor_outdoor=indoor_outdoor, weather=weather)
    if routing_authority_enabled:
        # V5-C routing-seam projection (C3/D4). Flag-off omits this key so the slot
        # payload stays byte-for-byte pre-V5. Honestly null in V5: real Kakao/Naver
        # Directions are BLOCKED_EXTERNAL/V7, so the authority never guesses a route.
        slot["travel_time_authority_minutes"] = travel_time_authority
    return slot


_KST = timezone(timedelta(hours=9))
_BAD_DUST_GRADES = frozenset({"bad", "very_bad"})
_OK_DUST_GRADES = frozenset({"good", "normal"})


def _closure_state(*, oh_valid: bool | None, place: dict | None) -> str:
    # D4: projection of the category-based opening-hours estimate. Real temporary/holiday
    # closure is NOT knowable here — those map to "unknown" (BLOCKED_EXTERNAL V7).
    if place is None or oh_valid is None:
        return "unknown"
    return "open" if oh_valid else "closed"


def _hhmm_to_minutes(value: str | None) -> int | None:
    if not value or len(value) < 5:
        return None
    try:
        return int(value[:2]) * 60 + int(value[3:5])
    except (ValueError, IndexError):
        return None


def _forecast_item_minutes(time_str: object) -> int | None:
    # Forecast items carry ISO datetime strings; the slot start is a Korean-local HH:MM
    # convention, so normalize the forecast side to KST before comparing minute-of-day.
    if not isinstance(time_str, str) or not time_str:
        return None
    text = time_str.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=_KST)
    dt_kst = dt.astimezone(_KST)
    return dt_kst.hour * 60 + dt_kst.minute


def _nearest_forecast_window(*, start_time: str | None, weather: dict | None) -> dict | None:
    # D2: nearest-time projection from the existing plan-level forecast list — no new
    # weather call. Tie-break on equidistant items: earliest (contract A4). Null when the
    # forecast list is empty (AirKorea-only / unavailable paths).
    if not start_time or not weather:
        return None
    forecast = weather.get("forecast") or []
    if not forecast:
        return None
    target = _hhmm_to_minutes(start_time)
    if target is None:
        return None
    best_item: dict | None = None
    best_key: tuple[int, int] | None = None
    for item in forecast:
        if not isinstance(item, dict):
            continue
        minutes = _forecast_item_minutes(item.get("time"))
        if minutes is None:
            continue
        # Sort by (abs delta, forecast minute-of-day) so equidistant ties go to earliest.
        key = (abs(minutes - target), minutes)
        if best_key is None or key < best_key:
            best_key = key
            best_item = item
    if best_item is None:
        return None
    # Project exactly the ForecastItem shape {time,temp,icon} (schema-closed).
    return {
        "time": best_item.get("time"),
        "temp": best_item.get("temp"),
        "icon": best_item.get("icon"),
    }


def _air_quality_bad(*, indoor_outdoor: str | None, weather: dict | None) -> bool | None:
    # D3: outdoor-relevance flag projected from the plan-level dust grade (one station per
    # region; per-slot AQ would be fabricated). Indoor → null; unknown grade → null.
    if indoor_outdoor == "indoor":
        return None
    grade = ((weather or {}).get("dust") or {}).get("grade")
    if grade in _BAD_DUST_GRADES:
        return True
    if grade in _OK_DUST_GRADES:
        return False
    return None


def _intervention_reason(*, weather_status: str, candidate_name: str, language: str = "en") -> str:
    ko = language == "ko"
    if weather_status == "good":
        return (
            f"날씨가 좋아 {candidate_name} 방향으로 일정을 유지해요."
            if ko
            else f"Weather is suitable, so keep the current route toward {candidate_name}."
        )
    if weather_status == "unknown":
        return (
            f"날씨 정보를 확인 중이에요. {candidate_name}을(를) 우선 유지해요."
            if ko
            else f"Weather data is still pending, so keep {candidate_name} as the current option."
        )
    return (
        f"날씨가 좋지 않아요. {candidate_name} 근처의 가까운 실내 동선을 우선해요."
        if ko
        else (
            "Weather is not ideal; prioritize short-walk or indoor-friendly "
            f"options near {candidate_name}."
        )
    )


def _recommended_action(*, weather_status: str, candidate_name: str, language: str = "en") -> str:
    ko = language == "ko"
    if weather_status == "good":
        return (
            f"{candidate_name}을(를) 우선 추천해요."
            if ko
            else f"Keep {candidate_name} as the primary local stop."
        )
    if weather_status == "unknown":
        return (
            f"날씨 확인까지 {candidate_name}을(를) 유지해요."
            if ko
            else f"Keep {candidate_name} while weather data is pending."
        )
    return (
        f"{candidate_name} 주변의 실내 또는 가까운 동선을 보여줘요."
        if ko
        else f"Show indoor or short-walk alternatives around {candidate_name}."
    )


def daily_plan_identity(
    request: DailyPlanRequest, *, language: str | None = None
) -> dict[str, str]:
    return generation_identity(
        "daily_plan",
        {
            "lat": request.lat,
            "lng": request.lng,
            "radius_m": request.radius_m,
            "language": language or normalize_language(request.language),
        },
    )
