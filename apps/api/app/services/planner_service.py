from __future__ import annotations

from apps.api.app.schemas.planner import DailyPlanRequest
from apps.api.app.services.normalization import normalize_language
from apps.api.app.services.places_service import list_places
from apps.api.app.services.weather_service import current_weather


def daily_plan(request: DailyPlanRequest) -> dict:
    language = normalize_language(request.language)
    weather = current_weather(lat=request.lat, lng=request.lng)
    places = list_places(
        lat=request.lat,
        lng=request.lng,
        radius_m=3000,
        category="all",
        language=language,
    )
    source = _combined_source(places.get("source"), weather.get("source"))
    return {
        "language": language,
        "center": {"lat": request.lat, "lng": request.lng},
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
    }


def intervention(*, lat: float, lng: float, radius_m: int) -> dict:
    weather = current_weather(lat=lat, lng=lng)
    return {
        "center": {"lat": lat, "lng": lng},
        "radius_m": radius_m,
        "should_intervene": weather["outdoor_status"] != "good",
        "reason": "Weather-aware placeholder intervention from LALA-next skeleton.",
        "recommended_action": "Show nearby indoor or short-walk alternatives.",
        "source": "db" if weather.get("source") == "db" else "skeleton",
    }


def _combined_source(place_source: str | None, weather_source: str | None) -> str:
    sources = {place_source or "skeleton", weather_source or "skeleton"}
    if sources == {"db"}:
        return "db"
    if "db" in sources:
        return "mixed"
    return "skeleton"
