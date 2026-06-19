from __future__ import annotations

import math
from datetime import UTC, datetime, timedelta, timezone
import logging
from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.core.observability import LOGGER_NAME
from apps.api.app.services import db_repository

KMA_ULTRA_SHORT_NOWCAST_URL = (
    "https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getUltraSrtNcst"
)
KMA_SOURCE = "kma_ultra_srt_ncst"
KST = timezone(timedelta(hours=9))
logger = logging.getLogger(LOGGER_NAME)


def current_weather(*, lat: float, lng: float, force: bool = False) -> dict:
    db_weather = db_repository.fetch_latest_weather(lat=lat, lng=lng)
    if db_weather:
        if not db_weather.get("forecast"):
            db_weather["forecast"] = _derived_forecast_from_observation(db_weather)
        db_weather["force"] = force
        return db_weather

    official_weather = _fetch_kma_ultra_short_nowcast(lat=lat, lng=lng, force=force)
    if official_weather:
        return official_weather

    return {
        "lat": lat,
        "lng": lng,
        "temp": "",
        "icon": "unavailable",
        "dust": {
            "pm10": "",
            "pm25": "",
            "grade": "unknown",
            "grade_ko": "확인 중",
        },
        "forecast": [],
        "outdoor_status": "unknown",
        "force": force,
        "source": "skeleton",
    }


def _fetch_kma_ultra_short_nowcast(*, lat: float, lng: float, force: bool) -> dict[str, Any] | None:
    service_key = get_settings().public_data_service_key
    if not service_key:
        logger.info("kma_nowcast_skipped reason=missing_public_data_service_key")
        return None
    try:
        import requests
    except Exception as exc:
        logger.warning("kma_nowcast_skipped reason=requests_unavailable error_type=%s", type(exc).__name__)
        return None

    nx, ny = _kma_grid_xy(lat, lng)
    base_time = _latest_kma_base_time()
    try:
        response = requests.get(
            KMA_ULTRA_SHORT_NOWCAST_URL,
            params={
                "serviceKey": service_key,
                "pageNo": 1,
                "numOfRows": 100,
                "dataType": "JSON",
                "base_date": base_time.strftime("%Y%m%d"),
                "base_time": base_time.strftime("%H%M"),
                "nx": nx,
                "ny": ny,
            },
            timeout=5,
        )
        response.raise_for_status()
        payload = response.json()
    except Exception as exc:
        logger.warning("kma_nowcast_failed error_type=%s", type(exc).__name__)
        return None

    items = _kma_items(payload)
    if not items:
        logger.warning("kma_nowcast_empty_items")
        return None
    values = {
        str(item.get("category") or "").strip(): str(item.get("obsrValue") or "").strip()
        for item in items
        if item.get("category")
    }
    temp = values.get("T1H", "")
    if not temp:
        logger.warning("kma_nowcast_missing_temperature")
        return None

    observed_at = base_time.isoformat()
    weather = {
        "lat": lat,
        "lng": lng,
        "location": "기상청 격자",
        "temp": temp,
        "icon": _kma_icon(values.get("PTY")),
        "dust": {
            "pm10": "",
            "pm25": "",
            "grade": "unknown",
            "grade_ko": "확인 중",
        },
        "forecast": [],
        "outdoor_status": _kma_outdoor_status(values),
        "force": force,
        "location_match": True,
        "record_time": observed_at,
        "source": KMA_SOURCE,
    }
    weather["forecast"] = _derived_forecast_from_observation(weather)
    return weather


def _kma_items(payload: dict[str, Any]) -> list[dict[str, Any]]:
    response = payload.get("response") if isinstance(payload, dict) else None
    if not isinstance(response, dict):
        return []
    header = response.get("header")
    if isinstance(header, dict) and str(header.get("resultCode") or "") != "00":
        return []
    body = response.get("body")
    if not isinstance(body, dict):
        return []
    items = body.get("items")
    if not isinstance(items, dict):
        return []
    raw_items = items.get("item")
    if isinstance(raw_items, list):
        return [item for item in raw_items if isinstance(item, dict)]
    if isinstance(raw_items, dict):
        return [raw_items]
    return []


def _latest_kma_base_time(now: datetime | None = None) -> datetime:
    current = now.astimezone(KST) if now else datetime.now(KST)
    base = current.replace(minute=0, second=0, microsecond=0)
    if current.minute < 45:
        base -= timedelta(hours=1)
    return base


def _kma_grid_xy(lat: float, lng: float) -> tuple[int, int]:
    re = 6371.00877 / 5.0
    slat1 = math.radians(30.0)
    slat2 = math.radians(60.0)
    olon = math.radians(126.0)
    olat = math.radians(38.0)
    xo = 43
    yo = 136

    sn = math.tan(math.pi * 0.25 + slat2 * 0.5) / math.tan(math.pi * 0.25 + slat1 * 0.5)
    sn = math.log(math.cos(slat1) / math.cos(slat2)) / math.log(sn)
    sf = math.tan(math.pi * 0.25 + slat1 * 0.5)
    sf = (sf**sn) * math.cos(slat1) / sn
    ro = math.tan(math.pi * 0.25 + olat * 0.5)
    ro = re * sf / (ro**sn)
    ra = math.tan(math.pi * 0.25 + math.radians(lat) * 0.5)
    ra = re * sf / (ra**sn)
    theta = math.radians(lng) - olon
    if theta > math.pi:
        theta -= 2.0 * math.pi
    if theta < -math.pi:
        theta += 2.0 * math.pi
    theta *= sn
    return int(ra * math.sin(theta) + xo + 0.5), int(ro - ra * math.cos(theta) + yo + 0.5)


def _kma_icon(precipitation_type: str | None) -> str:
    return _precipitation_icon((precipitation_type or "").strip())


def _precipitation_icon(value: str) -> str:
    if value in {"1", "5"}:
        return "rain"
    if value in {"2", "6"}:
        return "sleet"
    if value in {"3", "7"}:
        return "snow"
    return "partly-cloudy"


def _kma_outdoor_status(values: dict[str, str]) -> str:
    precipitation = values.get("PTY", "").strip()
    temperature = _parse_float(values.get("T1H"))
    wind_speed = _parse_float(values.get("WSD"))
    if precipitation and precipitation != "0":
        return "bad"
    if temperature is not None and (temperature >= 33 or temperature <= -12):
        return "bad"
    if wind_speed is not None and wind_speed >= 14:
        return "bad"
    return "good"


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
