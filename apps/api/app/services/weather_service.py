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
AIRKOREA_SIDO_REALTIME_URL = (
    "https://apis.data.go.kr/B552584/ArpltnInforInqireSvc/getCtprvnRltmMesureDnsty"
)
KMA_SOURCE = "kma_ultra_srt_ncst"
AIRKOREA_SOURCE = "airkorea_sido_realtime"
UNAVAILABLE_SOURCE = "unavailable"
KST = timezone(timedelta(hours=9))
logger = logging.getLogger(LOGGER_NAME)


def current_weather(*, lat: float, lng: float, force: bool = False) -> dict:
    db_weather = db_repository.fetch_latest_weather(lat=lat, lng=lng)
    if db_weather:
        air_quality = None
        dust = db_weather.get("dust")
        if not isinstance(dust, dict) or not (dust.get("pm10") or dust.get("pm25")):
            air_quality = _fetch_airkorea_sido_air_quality(lat=lat, lng=lng)
        if air_quality:
            db_weather["dust"] = air_quality["dust"]
            db_weather["air_quality_location"] = air_quality.get("location")
            db_weather["air_quality_record_time"] = air_quality.get("record_time")
        if not db_weather.get("forecast"):
            db_weather["forecast"] = _derived_forecast_from_observation(db_weather)
        db_weather["force"] = force
        return db_weather

    official_weather = _fetch_kma_ultra_short_nowcast(lat=lat, lng=lng, force=force)
    air_quality = _fetch_airkorea_sido_air_quality(lat=lat, lng=lng)
    if official_weather:
        if air_quality:
            official_weather["dust"] = air_quality["dust"]
            official_weather["air_quality_location"] = air_quality.get("location")
            official_weather["air_quality_record_time"] = air_quality.get("record_time")
            official_weather["source"] = f"{KMA_SOURCE}+{AIRKOREA_SOURCE}"
        return official_weather
    if air_quality:
        weather = {
            "lat": lat,
            "lng": lng,
            "location": air_quality.get("sido_name"),
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
        }
        return weather

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
        "source": UNAVAILABLE_SOURCE,
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


def _fetch_airkorea_sido_air_quality(*, lat: float, lng: float) -> dict[str, Any] | None:
    service_key = get_settings().public_data_service_key
    if not service_key:
        logger.info("airkorea_sido_skipped reason=missing_public_data_service_key")
        return None
    try:
        import requests
    except Exception as exc:
        logger.warning("airkorea_sido_skipped reason=requests_unavailable error_type=%s", type(exc).__name__)
        return None

    sido_name = _sido_name_for_coordinate(lat=lat, lng=lng)
    try:
        response = requests.get(
            AIRKOREA_SIDO_REALTIME_URL,
            params={
                "serviceKey": service_key,
                "returnType": "json",
                "numOfRows": 100,
                "pageNo": 1,
                "sidoName": sido_name,
                "ver": "1.0",
            },
            timeout=5,
        )
        response.raise_for_status()
        payload = response.json()
    except Exception as exc:
        logger.warning("airkorea_sido_failed sido_name=%s error_type=%s", sido_name, type(exc).__name__)
        return None

    items = _airkorea_items(payload)
    if not items:
        logger.warning("airkorea_sido_empty_items sido_name=%s", sido_name)
        return None
    selected = _select_airkorea_item(items)
    if not selected:
        logger.warning("airkorea_sido_missing_values sido_name=%s", sido_name)
        return None
    pm10 = _clean_airkorea_value(selected.get("pm10Value"))
    pm25 = _clean_airkorea_value(selected.get("pm25Value"))
    dust = {
        "pm10": pm10,
        "pm25": pm25,
        "grade": _airkorea_grade(
            selected.get("pm10Grade1h") or selected.get("pm10Grade"),
            selected.get("pm25Grade1h") or selected.get("pm25Grade"),
        ),
        "grade_ko": _airkorea_grade_ko(
            selected.get("pm10Grade1h") or selected.get("pm10Grade"),
            selected.get("pm25Grade1h") or selected.get("pm25Grade"),
        ),
    }
    return {
        "sido_name": sido_name,
        "location": selected.get("stationName") or sido_name,
        "record_time": selected.get("dataTime"),
        "dust": dust,
    }


def _airkorea_items(payload: dict[str, Any]) -> list[dict[str, Any]]:
    response = payload.get("response") if isinstance(payload, dict) else None
    if not isinstance(response, dict):
        return []
    header = response.get("header")
    if isinstance(header, dict) and str(header.get("resultCode") or "") != "00":
        return []
    body = response.get("body")
    if not isinstance(body, dict):
        return []
    raw_items = body.get("items")
    if isinstance(raw_items, list):
        return [item for item in raw_items if isinstance(item, dict)]
    if isinstance(raw_items, dict):
        return [raw_items]
    return []


def _select_airkorea_item(items: list[dict[str, Any]]) -> dict[str, Any] | None:
    for item in items:
        if _clean_airkorea_value(item.get("pm10Value")) or _clean_airkorea_value(item.get("pm25Value")):
            return item
    return None


def _clean_airkorea_value(value: Any) -> str:
    text = str(value or "").strip()
    if text in {"", "-", "점검중", "통신장애"}:
        return ""
    return text


def _airkorea_grade(*grades: Any) -> str:
    worst = _worst_airkorea_grade(grades)
    return {
        1: "good",
        2: "normal",
        3: "bad",
        4: "very_bad",
    }.get(worst, "unknown")


def _airkorea_grade_ko(*grades: Any) -> str:
    worst = _worst_airkorea_grade(grades)
    return {
        1: "좋음",
        2: "보통",
        3: "나쁨",
        4: "매우나쁨",
    }.get(worst, "확인 중")


def _worst_airkorea_grade(grades: tuple[Any, ...]) -> int | None:
    numeric_grades: list[int] = []
    for grade in grades:
        try:
            numeric = int(str(grade or "").strip())
        except ValueError:
            continue
        if numeric > 0:
            numeric_grades.append(numeric)
    return max(numeric_grades) if numeric_grades else None


def _dust_outdoor_status(dust: dict[str, Any]) -> str:
    return "bad" if str(dust.get("grade") or "").strip() in {"bad", "very_bad"} else "good"


def _sido_name_for_coordinate(*, lat: float, lng: float) -> str:
    if 37.42 <= lat <= 37.72 and 126.75 <= lng <= 127.22:
        return "서울"
    if 37.0 <= lat <= 38.35 and 126.35 <= lng <= 127.95:
        return "경기"
    if 37.0 <= lat <= 37.9 and 126.25 <= lng <= 126.85:
        return "인천"
    if 35.0 <= lat <= 35.45 and 128.75 <= lng <= 129.35:
        return "부산"
    if 35.65 <= lat <= 36.05 and 128.35 <= lng <= 128.85:
        return "대구"
    if 35.0 <= lat <= 35.35 and 126.65 <= lng <= 127.05:
        return "광주"
    if 36.15 <= lat <= 36.55 and 127.2 <= lng <= 127.65:
        return "대전"
    if 35.35 <= lat <= 35.75 and 129.0 <= lng <= 129.55:
        return "울산"
    if 36.35 <= lat <= 36.75 and 127.15 <= lng <= 127.45:
        return "세종"
    if 33.0 <= lat <= 34.0 and 126.0 <= lng <= 127.1:
        return "제주"
    if 37.0 <= lat <= 38.7 and 127.0 <= lng <= 129.5:
        return "강원"
    if 36.0 <= lat <= 37.3 and 127.2 <= lng <= 128.7:
        return "충북"
    if 35.8 <= lat <= 37.2 and 126.0 <= lng <= 127.7:
        return "충남"
    if 35.3 <= lat <= 36.4 and 126.4 <= lng <= 127.9:
        return "전북"
    if 34.0 <= lat <= 35.4 and 126.0 <= lng <= 127.9:
        return "전남"
    if 35.5 <= lat <= 37.2 and 128.0 <= lng <= 130.0:
        return "경북"
    if 34.6 <= lat <= 35.8 and 127.5 <= lng <= 129.5:
        return "경남"
    return "경기"


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
