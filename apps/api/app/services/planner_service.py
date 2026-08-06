from __future__ import annotations

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
    period_start_time,
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
    # P5B §12.4: observable trigger classification + honest-unavailable fields.
    # authority(travel-time/indoor-outdoor)가 없으면 값을 차단할 뿐 contract 는 유지.
    return {
        "center": {"lat": lat, "lng": lng},
        "radius_m": radius_m,
        "should_intervene": is_bad_weather,
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
        # 기존 추천을 slot 구조로 옮김(P5A _plan_slot 재사용, period=afternoon).
        "original_slot": _plan_slot(
            period="afternoon",
            title=("오후" if normalized == "ko" else "Afternoon"),
            place=candidate,
            weather_hint=outdoor_status,
            unavailable_reason=(
                "추천 장소가 부족해요" if normalized == "ko" else "Not enough nearby options"
            ),
            language=normalized,
        ),
        # indoor/outdoor provenance: bad weather 시 실내 대체 장소 검색(AI enrichment 기반).
        "alternative_slot": _find_indoor_alternative(
            place_candidates=places.get("places") or [],
            exclude_place_id=(candidate or {}).get("place_id"),
            language=normalized,
            weather_hint=outdoor_status,
            unavailable_reason=(
                "추천 장소가 부족해요" if normalized == "ko" else "Not enough nearby options"
            ),
        )
        if is_bad_weather
        else None,
        # observable trigger 만. good/unknown → null. 발명 금지.
        "trigger_type": "bad_weather" if is_bad_weather else None,
        "trigger_factors": _intervention_trigger_factors(outdoor_status=outdoor_status),
        # travel-time authority 부재 → 거리/이동시간 비교 불가(honest null).
        "distance_comparison": None,
        # contract boundary: API 는 항상 default. 실제 상태 관리는 P5C UI/persistence.
        "user_decision": "pending",
        "apply_state": "not_applied",
        "history": [],
    }


def _fallback_candidate_name(language: str) -> str:
    return "근처 로컬 장소" if language == "ko" else "nearby local places"


def _intervention_trigger_factors(*, outdoor_status: str) -> list[dict]:
    """관측가능 trigger 요소만. 발명된 factor 없음(honest)."""
    if outdoor_status == "bad":
        return [{"factor": "weather_outdoor_status", "value": "bad"}]
    return []


def _find_indoor_alternative(
    *,
    place_candidates: list[dict],
    exclude_place_id: str | None,
    language: str,
    weather_hint: str | None,
    unavailable_reason: str,
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
        prev_place = place if place is not None else prev_place

    return [
        _plan_slot(
            period=period,
            title=titles[period],
            place=assigned[period],
            weather_hint=weather_hint,
            unavailable_reason=unavailable_reason,
            language=language,
            travel_time=travel_times[period],
        )
        for period in _PERIOD_ORDER
    ]


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

    return {
        "period": period,
        "title": title,
        "place": place,
        "weather_hint": weather_hint,
        "start_time": period_start_time(period),
        "stay_duration_minutes": None,
        "travel_time_from_previous_minutes": travel_time,
        "opening_hours_valid": oh_valid,
        "estimated_opening_hours": f"{open_t}-{close_t}" if place else None,
        "indoor_outdoor": indoor_outdoor,
        "recommendation_reason": (_recommendation_reason(place, language) if place else None),
        "local_franchise_confidence": None,
        "swappable_alternatives": [],
        "unavailable_reason": None if place else unavailable_reason,
    }


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
