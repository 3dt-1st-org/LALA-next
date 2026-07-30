from __future__ import annotations

from apps.api.app.schemas.planner import DailyPlanRequest
from apps.api.app.services.normalization import normalize_language
from apps.api.app.services.places_service import list_places
from apps.api.app.services.request_identity import generation_identity
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


def intervention(*, lat: float, lng: float, radius_m: int) -> dict:
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
    candidate_name = (candidate or {}).get("name") or "nearby local places"
    is_bad_weather = weather["outdoor_status"] == "bad"
    return {
        "center": {"lat": lat, "lng": lng},
        "radius_m": radius_m,
        "should_intervene": is_bad_weather,
        "reason": _intervention_reason(
            weather_status=weather["outdoor_status"],
            candidate_name=candidate_name,
        ),
        "recommended_action": _recommended_action(
            weather_status=weather["outdoor_status"],
            candidate_name=candidate_name,
        ),
        "place": candidate,
        "source": source,
    }


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
    return [
        _plan_slot(
            period=period,
            title=titles[period],
            place=assigned[period],
            weather_hint=weather_hint,
            unavailable_reason=unavailable_reason,
            language=language,
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
) -> dict:
    # authority(travel-time/opening-hours/franchise/indoor-outdoor) 부재 → null.
    return {
        "period": period,
        "title": title,
        "place": place,
        "weather_hint": weather_hint,
        "start_time": None,
        "stay_duration_minutes": None,
        "travel_time_from_previous_minutes": None,
        "opening_hours_valid": None,
        "indoor_outdoor": None,
        "recommendation_reason": (_recommendation_reason(place, language) if place else None),
        "local_franchise_confidence": None,
        "swappable_alternatives": [],
        "unavailable_reason": None if place else unavailable_reason,
    }


def _intervention_reason(*, weather_status: str, candidate_name: str) -> str:
    if weather_status == "good":
        return f"Weather is suitable, so keep the current route toward {candidate_name}."
    if weather_status == "unknown":
        return f"Weather data is still pending, so keep {candidate_name} as the current option."
    return (
        "Weather is not ideal; prioritize short-walk or indoor-friendly "
        f"options near {candidate_name}."
    )


def _recommended_action(*, weather_status: str, candidate_name: str) -> str:
    if weather_status == "good":
        return f"Keep {candidate_name} as the primary local stop."
    if weather_status == "unknown":
        return f"Keep {candidate_name} while weather data is pending."
    return f"Show indoor or short-walk alternatives around {candidate_name}."


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
