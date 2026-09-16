from __future__ import annotations

from typing import Any

from apps.api.app.services import db_repository
from apps.api.app.services import weather_provider_adapters as weather_providers
from apps.api.app.services.dust_quality import (
    air_quality_outdoor_status,
    build_dust_payload,
    unknown_dust_payload,
)
from apps.api.app.services.weather_provider_adapters import (
    AIRKOREA_REQUEST_TIMEOUT_SECONDS,
    AIRKOREA_SIDO_REALTIME_URL,
    AIRKOREA_SOURCE,
    KMA_REQUEST_TIMEOUT_SECONDS,
    KMA_SOURCE,
    KMA_ULTRA_SHORT_NOWCAST_URL,
    KST,
)

UNAVAILABLE_SOURCE = "unavailable"
__all__ = [
    "AIRKOREA_REQUEST_TIMEOUT_SECONDS",
    "AIRKOREA_SIDO_REALTIME_URL",
    "AIRKOREA_SOURCE",
    "KMA_REQUEST_TIMEOUT_SECONDS",
    "KMA_SOURCE",
    "KMA_ULTRA_SHORT_NOWCAST_URL",
    "KST",
    "build_dust_payload",
    "current_weather",
    "clear_official_weather_cache",
    "unknown_dust_payload",
]


def current_weather(*, lat: float, lng: float, force: bool = False) -> dict:
    db_weather = db_repository.fetch_latest_weather(lat=lat, lng=lng)
    if db_weather:
        # P4 provenance: the weather-only status must be captured before the dust
        # merge overwrites outdoor_status. Only the DB's explicit weather-only
        # key (flags without is_bad_dust) is a weather observation — a legacy row
        # without the key carries no weather provenance, so it stays "unknown".
        # Never inferred from the merged aggregate, icon or temperature.
        weather_only_status = (
            _normalize_outdoor_status(db_weather.get("weather_outdoor_status"))
            if "weather_outdoor_status" in db_weather
            else "unknown"
        )
        air_quality = weather_providers.fetch_airkorea_sido_air_quality(lat=lat, lng=lng)
        if air_quality:
            db_weather["dust"] = air_quality["dust"]
            db_weather["air_quality_location"] = air_quality.get("location")
            db_weather["air_quality_record_time"] = air_quality.get("record_time")
            db_weather["source"] = _source_with_air_quality(db_weather.get("source"))
            if _is_internal_weather_location(db_weather.get("location")):
                db_weather["location"] = _weather_observation_location(
                    air_quality=air_quality,
                    fallback=db_weather.get("location"),
                )
            db_weather["outdoor_status"] = _merge_outdoor_status_with_dust(
                db_weather.get("outdoor_status"),
                air_quality["dust"],
            )
            db_weather["air_quality_outdoor_status"] = air_quality_outdoor_status(
                air_quality["dust"]
            )
        else:
            db_weather["air_quality_outdoor_status"] = air_quality_outdoor_status(
                db_weather.get("dust")
            )
        db_weather["weather_outdoor_status"] = weather_only_status
        if not db_weather.get("forecast"):
            db_weather["forecast"] = _derived_forecast_from_observation(db_weather)
        db_weather["force"] = force
        return db_weather

    official_weather, air_quality = weather_providers.fetch_official_weather_pair(
        lat=lat,
        lng=lng,
        force=force,
    )
    if official_weather:
        # KMA-only observation status, captured before the dust merge.
        weather_only_status = _normalize_outdoor_status(official_weather.get("outdoor_status"))
        if air_quality:
            official_weather["dust"] = air_quality["dust"]
            official_weather["air_quality_location"] = air_quality.get("location")
            official_weather["air_quality_record_time"] = air_quality.get("record_time")
            official_weather["location"] = _weather_observation_location(
                air_quality=air_quality,
                fallback=official_weather.get("location"),
            )
            official_weather["source"] = f"{KMA_SOURCE}+{AIRKOREA_SOURCE}"
            official_weather["outdoor_status"] = _merge_outdoor_status_with_dust(
                official_weather.get("outdoor_status"),
                air_quality["dust"],
            )
            official_weather["air_quality_outdoor_status"] = air_quality_outdoor_status(
                air_quality["dust"]
            )
        else:
            official_weather["air_quality_outdoor_status"] = air_quality_outdoor_status(
                official_weather.get("dust")
            )
        official_weather["weather_outdoor_status"] = weather_only_status
        return official_weather
    if air_quality:
        weather = {
            "lat": lat,
            "lng": lng,
            "location": _weather_observation_location(
                air_quality=air_quality,
                fallback=air_quality.get("sido_name"),
            ),
            "temp": "",
            "icon": "unavailable",
            "dust": air_quality["dust"],
            "forecast": [],
            "outdoor_status": _dust_outdoor_status(air_quality["dust"]),
            "force": force,
            "location_match": True,
            "record_time": air_quality.get("record_time"),
            "air_quality_location": air_quality.get("location"),
            "air_quality_record_time": air_quality.get("record_time"),
            "source": AIRKOREA_SOURCE,
            # P4: an AirKorea-only response observed no KMA weather — unknown,
            # never inferred from the merged status/icon/temperature.
            "weather_outdoor_status": "unknown",
            "air_quality_outdoor_status": air_quality_outdoor_status(air_quality["dust"]),
        }
        return weather

    return {
        "lat": lat,
        "lng": lng,
        "temp": "",
        "icon": "unavailable",
        "dust": unknown_dust_payload(),
        "forecast": [],
        "outdoor_status": "unknown",
        "force": force,
        "source": UNAVAILABLE_SOURCE,
        "weather_outdoor_status": "unknown",
        "air_quality_outdoor_status": "unknown",
    }


def clear_official_weather_cache() -> None:
    weather_providers.clear_official_weather_cache()


def _fetch_official_weather_pair(
    *,
    lat: float,
    lng: float,
    force: bool,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    return weather_providers.fetch_official_weather_pair(lat=lat, lng=lng, force=force)


def _source_with_air_quality(source: Any) -> str:
    normalized = str(source or "").strip()
    if not normalized:
        return AIRKOREA_SOURCE
    if AIRKOREA_SOURCE in normalized:
        return normalized
    return f"{normalized}+{AIRKOREA_SOURCE}"


def _weather_observation_location(
    *,
    air_quality: dict[str, Any],
    fallback: Any,
) -> str:
    for key in ("location", "sido_name"):
        value = str(air_quality.get(key) or "").strip()
        if value:
            return value
    return str(fallback or "").strip() or "현재 위치"


def _is_internal_weather_location(value: Any) -> bool:
    normalized = str(value or "").strip().lower().replace(" ", "")
    return normalized in {"", "기상청격자", "kmagrid"}


def _dust_outdoor_status(dust: dict[str, Any]) -> str:
    return "bad" if str(dust.get("grade") or "").strip() in {"bad", "very_bad"} else "good"


def _normalize_outdoor_status(value: Any) -> str:
    # P4: unknown stays unknown — anything outside good/bad/unknown is not a
    # weather observation we can attribute.
    text = str(value or "").strip()
    if text in {"good", "bad", "unknown"}:
        return text
    return "unknown"


def _merge_outdoor_status_with_dust(status: Any, dust: dict[str, Any]) -> str:
    if str(status or "").strip() == "bad" or _dust_outdoor_status(dust) == "bad":
        return "bad"
    return "good"


def _derived_forecast_from_observation(weather: dict[str, Any]) -> list[dict[str, str]]:
    return weather_providers.derived_forecast_from_observation(weather)
