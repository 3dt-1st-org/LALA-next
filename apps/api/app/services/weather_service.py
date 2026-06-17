from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

from apps.api.app.services import db_repository


def current_weather(*, lat: float, lng: float, force: bool = False) -> dict:
    db_weather = db_repository.fetch_latest_weather(lat=lat, lng=lng)
    if db_weather:
        if not db_weather.get("forecast"):
            db_weather["forecast"] = _derived_forecast_from_observation(db_weather)
        db_weather["force"] = force
        return db_weather

    return {
        "lat": lat,
        "lng": lng,
        "temp": "11",
        "icon": "partly-cloudy",
        "dust": {
            "pm10": "37",
            "pm25": "26",
            "grade": "normal",
            "grade_ko": "보통",
        },
        "forecast": [
            {"time": "2026-06-11T12:00:00+09:00", "temp": "12", "icon": "partly-cloudy"}
        ],
        "outdoor_status": "good",
        "force": force,
        "source": "skeleton",
    }


def _derived_forecast_from_observation(weather: dict[str, Any]) -> list[dict[str, str]]:
    observed_at = _parse_datetime(weather.get("record_time")) or datetime.now(UTC)
    base_temp = _parse_float(weather.get("temp")) or 0.0
    icon = str(weather.get("icon") or "partly-cloudy")
    outdoor_status = str(weather.get("outdoor_status") or "good")
    if outdoor_status == "bad" and icon == "partly-cloudy":
        icon = "rain"

    return [
        {
            "time": (observed_at + timedelta(hours=hours)).isoformat(),
            "temp": f"{base_temp + delta:.1f}",
            "icon": icon,
        }
        for hours, delta in ((1, 0.0), (3, 0.8), (6, 1.2), (9, 0.4))
    ]


def _parse_float(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _parse_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value
    if not value:
        return None
    text = str(value).strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed
