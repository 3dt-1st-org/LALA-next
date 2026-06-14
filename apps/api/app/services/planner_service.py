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
    return {
        "language": language,
        "center": {"lat": request.lat, "lng": request.lng},
        "radius_m": request.radius_m,
        "weather": weather,
        "slots": [
            {
                "period": "morning",
                "title": "Start near a landmark",
                "place": places["places"][0],
            },
            {
                "period": "afternoon",
                "title": "Adjust by weather",
                "weather_hint": weather["outdoor_status"],
            },
        ],
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
    is_bad_weather = weather["outdoor_status"] != "good"
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
    sources = {place_source or "skeleton", weather_source or "skeleton"}
    if sources == {"db"}:
        return "db"
    if sources == {"public_mvp_snapshot"}:
        return "public_mvp_snapshot"
    if "db" in sources:
        return "mixed"
    if "public_mvp_snapshot" in sources:
        return "mixed"
    return "skeleton"


def _intervention_reason(*, weather_status: str, candidate_name: str) -> str:
    if weather_status == "good":
        return f"Weather is suitable, so keep the current route toward {candidate_name}."
    return (
        "Weather is not ideal; prioritize short-walk or indoor-friendly "
        f"options near {candidate_name}."
    )


def _recommended_action(*, weather_status: str, candidate_name: str) -> str:
    if weather_status == "good":
        return f"Keep {candidate_name} as the primary local stop."
    return f"Show indoor or short-walk alternatives around {candidate_name}."


def daily_plan_identity(request: DailyPlanRequest, *, language: str | None = None) -> dict[str, str]:
    return generation_identity(
        "daily_plan",
        {
            "lat": request.lat,
            "lng": request.lng,
            "radius_m": request.radius_m,
            "language": language or normalize_language(request.language),
        },
    )
