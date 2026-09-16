from __future__ import annotations

import logging
import math
from copy import deepcopy
from datetime import UTC, datetime, timedelta, timezone
from threading import Lock
from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.core.observability import LOGGER_NAME
from apps.api.app.services import db_repository, region_catalog
from apps.api.app.services.dust_quality import (
    build_dust_payload,
    clean_air_quality_value,
    unknown_dust_payload,
)

KMA_ULTRA_SHORT_NOWCAST_URL = (
    "https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getUltraSrtNcst"
)
AIRKOREA_SIDO_REALTIME_URL = (
    "https://apis.data.go.kr/B552584/ArpltnInforInqireSvc/getCtprvnRltmMesureDnsty"
)
KMA_SOURCE = "kma_ultra_srt_ncst"
AIRKOREA_SOURCE = "airkorea_sido_realtime"
KST = timezone(timedelta(hours=9))
KMA_REQUEST_TIMEOUT_SECONDS = 3
AIRKOREA_REQUEST_TIMEOUT_SECONDS = 8
_OFFICIAL_CACHE_TTL = timedelta(minutes=20)
_official_cache_lock = Lock()
_official_weather_cache: dict[str, tuple[datetime, dict[str, Any]]] = {}
logger = logging.getLogger(LOGGER_NAME)

_PROVINCE_BOUNDS = (
    ("서울특별시", 37.42, 37.72, 126.75, 127.22),
    ("인천광역시", 37.0, 37.9, 126.25, 126.85),
    ("부산광역시", 35.0, 35.45, 128.75, 129.35),
    ("대구광역시", 35.65, 36.05, 128.35, 128.85),
    ("광주광역시", 35.0, 35.35, 126.65, 127.05),
    ("세종특별자치시", 36.35, 36.75, 127.15, 127.45),
    ("대전광역시", 36.15, 36.55, 127.2, 127.65),
    ("울산광역시", 35.35, 35.75, 129.0, 129.55),
    ("제주특별자치도", 33.0, 34.0, 126.0, 127.1),
    ("강원특별자치도", 37.0, 38.7, 127.0, 129.5),
    ("경상북도", 35.5, 37.2, 128.0, 130.0),
    ("충청북도", 36.0, 37.3, 127.2, 128.7),
    ("전북특별자치도", 35.3, 36.4, 126.4, 127.9),
    ("충청남도", 35.8, 37.2, 126.0, 127.7),
    ("전라남도", 34.0, 35.4, 126.0, 127.9),
    ("경상남도", 34.6, 35.8, 127.5, 129.5),
    ("경기도", 37.0, 38.35, 126.35, 127.95),
)
_PROVINCE_REFERENCE_POINTS = {
    "서울특별시": (37.5665, 126.9780),
    "인천광역시": (37.4563, 126.7052),
    "부산광역시": (35.1796, 129.0756),
    "대구광역시": (35.8714, 128.6014),
    "광주광역시": (35.1595, 126.8526),
    "대전광역시": (36.3504, 127.3845),
    "울산광역시": (35.5384, 129.3114),
    "세종특별자치시": (36.48, 127.2890),
    "경기도": (37.2636, 127.0286),
    "강원특별자치도": (37.8813, 127.7298),
    "충청북도": (36.6424, 127.4890),
    "충청남도": (36.6012, 126.6608),
    "전북특별자치도": (35.8242, 127.1480),
    "전라남도": (34.8118, 126.3922),
    "경상북도": (36.5760, 128.5056),
    "경상남도": (35.2278, 128.6811),
    "제주특별자치도": (33.4996, 126.5312),
}


def clear_official_weather_cache() -> None:
    with _official_cache_lock:
        _official_weather_cache.clear()


def fetch_official_weather_pair(
    *,
    lat: float,
    lng: float,
    force: bool,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    try:
        from concurrent.futures import ThreadPoolExecutor
    except Exception:
        return (
            fetch_kma_ultra_short_nowcast(lat=lat, lng=lng, force=force),
            fetch_airkorea_sido_air_quality(lat=lat, lng=lng),
        )

    with ThreadPoolExecutor(max_workers=2, thread_name_prefix="lala-weather") as executor:
        kma_future = executor.submit(fetch_kma_ultra_short_nowcast, lat=lat, lng=lng, force=force)
        air_future = executor.submit(fetch_airkorea_sido_air_quality, lat=lat, lng=lng)
        return kma_future.result(), air_future.result()


def fetch_kma_ultra_short_nowcast(
    *,
    lat: float,
    lng: float,
    force: bool,
) -> dict[str, Any] | None:
    service_key = get_settings().public_data_service_key
    if not service_key:
        logger.info("kma_nowcast_skipped reason=missing_public_data_service_key")
        return None
    try:
        import requests
    except Exception as exc:
        logger.warning(
            "kma_nowcast_skipped reason=requests_unavailable error_type=%s",
            type(exc).__name__,
        )
        return None

    nx, ny = kma_grid_xy(lat, lng)
    base_time = latest_kma_base_time()
    cache_key = f"kma:{nx}:{ny}:{base_time.strftime('%Y%m%d%H%M')}"
    cached = _cache_get(cache_key)
    if cached:
        cached["force"] = force
        return cached
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
            timeout=KMA_REQUEST_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
    except Exception as exc:
        logger.warning("kma_nowcast_failed error_type=%s", type(exc).__name__)
        return None

    items = kma_items(payload)
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
        "location": sido_name_for_coordinate(lat=lat, lng=lng),
        "temp": temp,
        "icon": kma_icon(values.get("PTY")),
        "dust": unknown_dust_payload(),
        "forecast": [],
        "outdoor_status": kma_outdoor_status(values),
        "force": force,
        "location_match": True,
        "record_time": observed_at,
        "source": KMA_SOURCE,
    }
    weather["forecast"] = derived_forecast_from_observation(weather)
    _cache_set(cache_key, weather)
    return weather


def fetch_airkorea_sido_air_quality(*, lat: float, lng: float) -> dict[str, Any] | None:
    service_key = get_settings().public_data_service_key
    if not service_key:
        logger.info("airkorea_sido_skipped reason=missing_public_data_service_key")
        return None
    try:
        import requests
    except Exception as exc:
        logger.warning(
            "airkorea_sido_skipped reason=requests_unavailable error_type=%s",
            type(exc).__name__,
        )
        return None

    sido_name = sido_name_for_coordinate(lat=lat, lng=lng)
    preferred_station_names = db_repository.fetch_nearest_region_labels(
        lat=lat,
        lng=lng,
        limit=8,
    )
    cache_key = (
        f"airkorea:{sido_name}:{coordinate_cache_bucket(lat, lng)}:"
        f"{datetime.now(KST).strftime('%Y%m%d%H')}"
    )
    cached = _cache_get(cache_key)
    if cached:
        return cached
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
            timeout=AIRKOREA_REQUEST_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
    except Exception as exc:
        logger.warning(
            "airkorea_sido_failed sido_name=%s error_type=%s",
            sido_name,
            type(exc).__name__,
        )
        return None

    items = airkorea_items(payload)
    if not items:
        logger.warning("airkorea_sido_empty_items sido_name=%s", sido_name)
        return None
    selected = select_airkorea_item(
        items,
        preferred_station_names=preferred_station_names,
    )
    if not selected:
        logger.warning("airkorea_sido_missing_values sido_name=%s", sido_name)
        return None
    dust = build_dust_payload(
        pm10=selected.get("pm10Value"),
        pm25=selected.get("pm25Value"),
        pm10_grade=selected.get("pm10Grade1h") or selected.get("pm10Grade"),
        pm25_grade=selected.get("pm25Grade1h") or selected.get("pm25Grade"),
    )
    air_quality = {
        "sido_name": sido_name,
        "location": selected.get("stationName") or sido_name,
        "location_match": station_matches_preferred(
            selected.get("stationName"),
            preferred_station_names,
        ),
        "preferred_locations": preferred_station_names[:5],
        "record_time": selected.get("dataTime"),
        "dust": dust,
    }
    _cache_set(cache_key, air_quality)
    return air_quality


def airkorea_items(payload: dict[str, Any]) -> list[dict[str, Any]]:
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


def select_airkorea_item(
    items: list[dict[str, Any]],
    *,
    preferred_station_names: list[str] | None = None,
) -> dict[str, Any] | None:
    candidates = [
        item
        for item in items
        if clean_air_quality_value(item.get("pm10Value"))
        or clean_air_quality_value(item.get("pm25Value"))
    ]
    if not candidates:
        return None
    indexed = list(enumerate(candidates))
    indexed.sort(
        key=lambda pair: airkorea_item_rank(
            pair[1],
            preferred_station_names=preferred_station_names or [],
            original_index=pair[0],
        )
    )
    return indexed[0][1]


def airkorea_item_rank(
    item: dict[str, Any],
    *,
    preferred_station_names: list[str],
    original_index: int,
) -> tuple[int, int]:
    has_pm10 = bool(clean_air_quality_value(item.get("pm10Value")))
    has_pm25 = bool(clean_air_quality_value(item.get("pm25Value")))
    has_both = has_pm10 and has_pm25
    station_matches = station_matches_preferred(
        item.get("stationName"),
        preferred_station_names,
    )
    if station_matches and has_both:
        group = 0
    elif has_both:
        group = 1
    elif station_matches:
        group = 2
    else:
        group = 3
    return group, original_index


def station_matches_preferred(
    station_name: Any,
    preferred_station_names: list[str] | None,
) -> bool:
    station = normalize_station_name(station_name)
    if not station:
        return False
    for preferred_name in preferred_station_names or []:
        preferred = normalize_station_name(preferred_name)
        if not preferred:
            continue
        if station == preferred or station in preferred or preferred in station:
            return True
    return False


def normalize_station_name(value: Any) -> str:
    text = str(value or "").strip().lower()
    for suffix in ("특별시", "광역시", "특별자치시", "특별자치도", "자치구"):
        text = text.replace(suffix, "")
    text = text.replace(" ", "")
    for suffix in ("시", "군", "구", "읍", "면", "동"):
        if len(text) > len(suffix) + 1 and text.endswith(suffix):
            text = text[: -len(suffix)]
            break
    return text


def coordinate_cache_bucket(lat: float, lng: float) -> str:
    return f"{lat:.2f}:{lng:.2f}"


def sido_name_for_coordinate(*, lat: float, lng: float) -> str:
    matches = [
        province_name_ko
        for province_name_ko, min_lat, max_lat, min_lng, max_lng in _PROVINCE_BOUNDS
        if min_lat <= lat <= max_lat and min_lng <= lng <= max_lng
    ]
    candidates = matches or list(_PROVINCE_REFERENCE_POINTS)
    province_name_ko = min(
        candidates,
        key=lambda name: coordinate_distance_squared(
            lat,
            lng,
            *_PROVINCE_REFERENCE_POINTS.get(name, (lat, lng)),
        ),
    )
    province = region_catalog.PROVINCE_BY_KO.get(province_name_ko)
    if province:
        return province.short_ko
    return region_catalog.PROVINCE_BY_KO["경기도"].short_ko


def kma_items(payload: dict[str, Any]) -> list[dict[str, Any]]:
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


def latest_kma_base_time(now: datetime | None = None) -> datetime:
    current = now.astimezone(KST) if now else datetime.now(KST)
    base = current.replace(minute=0, second=0, microsecond=0)
    if current.minute < 45:
        base -= timedelta(hours=1)
    return base


def kma_grid_xy(lat: float, lng: float) -> tuple[int, int]:
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


def kma_icon(precipitation_type: str | None) -> str:
    return precipitation_icon((precipitation_type or "").strip())


def precipitation_icon(value: str) -> str:
    if value in {"1", "5"}:
        return "rain"
    if value in {"2", "6"}:
        return "sleet"
    if value in {"3", "7"}:
        return "snow"
    return "partly-cloudy"


def kma_outdoor_status(values: dict[str, str]) -> str:
    precipitation = values.get("PTY", "").strip()
    temperature = parse_float(values.get("T1H"))
    wind_speed = parse_float(values.get("WSD"))
    if precipitation and precipitation != "0":
        return "bad"
    if temperature is not None and (temperature >= 33 or temperature <= -12):
        return "bad"
    if wind_speed is not None and wind_speed >= 14:
        return "bad"
    return "good"


def derived_forecast_from_observation(weather: dict[str, Any]) -> list[dict[str, str]]:
    observed_at = parse_datetime(weather.get("record_time")) or datetime.now(UTC)
    base_temp = parse_float(weather.get("temp")) or 0.0
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


def parse_float(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def parse_datetime(value: Any) -> datetime | None:
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


def coordinate_distance_squared(
    lat_a: float,
    lng_a: float,
    lat_b: float,
    lng_b: float,
) -> float:
    return ((lat_a - lat_b) ** 2) + ((lng_a - lng_b) ** 2)


def _cache_get(key: str) -> dict[str, Any] | None:
    now = datetime.now(UTC)
    with _official_cache_lock:
        cached = _official_weather_cache.get(key)
        if cached is None:
            return None
        stored_at, payload = cached
        if now - stored_at > _OFFICIAL_CACHE_TTL:
            _official_weather_cache.pop(key, None)
            return None
        return deepcopy(payload)


def _cache_set(key: str, payload: dict[str, Any]) -> None:
    with _official_cache_lock:
        _official_weather_cache[key] = (datetime.now(UTC), deepcopy(payload))
