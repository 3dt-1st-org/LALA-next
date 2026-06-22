from __future__ import annotations

from contextlib import closing
from dataclasses import dataclass
from datetime import UTC, datetime, timezone, timedelta
from typing import Any, Iterable

from apps.api.app.services import weather_service

KST = timezone(timedelta(hours=9), "Asia/Seoul")
DEFAULT_SOURCE_NAME = "public_weather"
DEFAULT_REFRESH_TARGETS: tuple[tuple[str, float, float], ...] = (
    ("서울", 37.5665, 126.9780),
    ("수원시", 37.2636, 127.0286),
)


@dataclass(frozen=True)
class WeatherRefreshTarget:
    location_name: str
    lat: float
    lng: float

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "location_name": self.location_name,
            "lat": self.lat,
            "lng": self.lng,
        }


@dataclass(frozen=True)
class WeatherObservation:
    location_name: str
    temperature_c: float | None
    precipitation_type: str | None
    pm10: float | None
    pm25: float | None
    is_rain_snow: bool
    is_bad_dust: bool
    is_heatwave: bool
    is_coldwave: bool
    is_strong_wind: bool
    observed_at: datetime
    source: str

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "location_name": self.location_name,
            "temperature_c": self.temperature_c,
            "precipitation_type": self.precipitation_type,
            "pm10": self.pm10,
            "pm25": self.pm25,
            "is_rain_snow": self.is_rain_snow,
            "is_bad_dust": self.is_bad_dust,
            "is_heatwave": self.is_heatwave,
            "is_coldwave": self.is_coldwave,
            "is_strong_wind": self.is_strong_wind,
            "observed_at": self.observed_at.isoformat(),
            "source": self.source,
        }


@dataclass(frozen=True)
class WeatherRefreshResult:
    targets: tuple[WeatherRefreshTarget, ...]
    observations: tuple[WeatherObservation, ...]
    skipped_targets: tuple[dict[str, Any], ...]
    source_name: str = DEFAULT_SOURCE_NAME

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "source_name": self.source_name,
            "target_count": len(self.targets),
            "observation_count": len(self.observations),
            "skipped_target_count": len(self.skipped_targets),
            "targets": [target.to_public_dict() for target in self.targets[:10]],
            "preview": [item.to_public_dict() for item in self.observations[:10]],
            "skipped_targets": list(self.skipped_targets[:10]),
        }


def default_refresh_targets() -> tuple[WeatherRefreshTarget, ...]:
    return tuple(
        WeatherRefreshTarget(location_name=name, lat=lat, lng=lng)
        for name, lat, lng in DEFAULT_REFRESH_TARGETS
    )


def parse_refresh_target(value: str) -> WeatherRefreshTarget:
    text = value.strip()
    if not text:
        raise ValueError("Weather target cannot be empty.")
    if "=" not in text:
        raise ValueError("Weather target must use NAME=LAT,LNG.")
    name, coordinate_text = text.split("=", 1)
    coordinate_parts = [part.strip() for part in coordinate_text.split(",")]
    if len(coordinate_parts) != 2:
        raise ValueError("Weather target coordinates must use LAT,LNG.")
    location_name = name.strip()
    if not location_name:
        raise ValueError("Weather target name cannot be empty.")
    try:
        lat = float(coordinate_parts[0])
        lng = float(coordinate_parts[1])
    except ValueError as exc:
        raise ValueError("Weather target coordinates must be numbers.") from exc
    return WeatherRefreshTarget(location_name=location_name, lat=lat, lng=lng)


def fetch_region_targets_from_places(
    *,
    dsn: str,
    limit: int,
    connect_timeout: int,
) -> tuple[WeatherRefreshTarget, ...]:
    if not dsn:
        raise ValueError("DB_DSN is required to load DB region weather targets.")
    if limit <= 0:
        raise ValueError("limit must be positive.")

    import psycopg2
    from psycopg2.extras import RealDictCursor

    sql = """
        SELECT
            NULLIF(TRIM(region_ko), '') AS location_name,
            AVG(lat)::double precision AS lat,
            AVG(lng)::double precision AS lng,
            COUNT(*) AS place_count
        FROM travel.public_places
        WHERE region_ko IS NOT NULL
          AND TRIM(region_ko) <> ''
          AND lat IS NOT NULL
          AND lng IS NOT NULL
        GROUP BY NULLIF(TRIM(region_ko), '')
        ORDER BY place_count DESC, location_name ASC
        LIMIT %s
    """
    with closing(psycopg2.connect(dsn, connect_timeout=connect_timeout)) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, (limit,))
            rows = cur.fetchall()
    return tuple(
        WeatherRefreshTarget(
            location_name=str(row["location_name"]),
            lat=float(row["lat"]),
            lng=float(row["lng"]),
        )
        for row in rows
        if row.get("location_name") and row.get("lat") is not None and row.get("lng") is not None
    )


def refresh_weather_observations(
    *,
    targets: Iterable[WeatherRefreshTarget],
    force: bool = True,
) -> WeatherRefreshResult:
    target_tuple = tuple(_dedupe_targets(targets))
    observations: list[WeatherObservation] = []
    skipped: list[dict[str, Any]] = []
    for target in target_tuple:
        payload = weather_service.fetch_live_weather(
            lat=target.lat,
            lng=target.lng,
            force=force,
        )
        observation = weather_payload_to_observation(payload, target=target)
        if observation is None:
            skipped.append(
                {
                    "location_name": target.location_name,
                    "reason": str(payload.get("source") or "unavailable"),
                }
            )
            continue
        observations.append(observation)
    return WeatherRefreshResult(
        targets=target_tuple,
        observations=tuple(observations),
        skipped_targets=tuple(skipped),
    )


def weather_payload_to_observation(
    payload: dict[str, Any],
    *,
    target: WeatherRefreshTarget,
) -> WeatherObservation | None:
    source = str(payload.get("source") or "").strip()
    if not source or source == weather_service.UNAVAILABLE_SOURCE:
        return None

    observed_at = _parse_observed_at(
        payload.get("record_time") or payload.get("air_quality_record_time")
    )
    temperature_c = _optional_float(payload.get("temp"))
    dust = payload.get("dust") if isinstance(payload.get("dust"), dict) else {}
    pm10 = _optional_float(dust.get("pm10"))
    pm25 = _optional_float(dust.get("pm25"))
    precipitation_type = _precipitation_type(payload.get("icon"))
    is_rain_snow = precipitation_type in {"rain", "sleet", "snow"}
    is_bad_dust = _is_bad_dust(dust)
    is_heatwave = temperature_c is not None and temperature_c >= 33.0
    is_coldwave = temperature_c is not None and temperature_c <= -12.0
    if temperature_c is None and pm10 is None and pm25 is None:
        return None

    return WeatherObservation(
        location_name=target.location_name,
        temperature_c=temperature_c,
        precipitation_type=precipitation_type,
        pm10=pm10,
        pm25=pm25,
        is_rain_snow=is_rain_snow,
        is_bad_dust=is_bad_dust,
        is_heatwave=is_heatwave,
        is_coldwave=is_coldwave,
        is_strong_wind=False,
        observed_at=observed_at,
        source=source,
    )


def upsert_weather_observations(
    *,
    dsn: str,
    result: WeatherRefreshResult,
    connect_timeout: int,
) -> dict[str, Any]:
    if not dsn:
        raise ValueError("DB_DSN is required to persist weather observations.")

    import psycopg2

    insert_sql = """
        INSERT INTO travel.weather_observations (
            location_name,
            temperature_c,
            precipitation_type,
            pm10,
            pm25,
            is_rain_snow,
            is_bad_dust,
            is_heatwave,
            is_coldwave,
            is_strong_wind,
            observed_at
        )
        SELECT
            %(location_name)s,
            %(temperature_c)s,
            %(precipitation_type)s,
            %(pm10)s,
            %(pm25)s,
            %(is_rain_snow)s,
            %(is_bad_dust)s,
            %(is_heatwave)s,
            %(is_coldwave)s,
            %(is_strong_wind)s,
            %(observed_at)s
        WHERE NOT EXISTS (
            SELECT 1
            FROM travel.weather_observations
            WHERE location_name = %(location_name)s
              AND observed_at = %(observed_at)s
        )
    """
    inserted_rows = 0
    with closing(psycopg2.connect(dsn, connect_timeout=connect_timeout)) as conn:
        with conn.cursor() as cur:
            for observation in result.observations:
                cur.execute(
                    insert_sql,
                    {
                        "location_name": observation.location_name,
                        "temperature_c": observation.temperature_c,
                        "precipitation_type": observation.precipitation_type,
                        "pm10": observation.pm10,
                        "pm25": observation.pm25,
                        "is_rain_snow": observation.is_rain_snow,
                        "is_bad_dust": observation.is_bad_dust,
                        "is_heatwave": observation.is_heatwave,
                        "is_coldwave": observation.is_coldwave,
                        "is_strong_wind": observation.is_strong_wind,
                        "observed_at": observation.observed_at,
                    },
                )
                inserted_rows += max(cur.rowcount, 0)
        conn.commit()
    return {
        "inserted_rows": inserted_rows,
        "skipped_duplicate_rows": len(result.observations) - inserted_rows,
    }


def _dedupe_targets(
    targets: Iterable[WeatherRefreshTarget],
) -> Iterable[WeatherRefreshTarget]:
    seen: set[str] = set()
    for target in targets:
        key = target.location_name.strip()
        if not key or key in seen:
            continue
        seen.add(key)
        yield target


def _precipitation_type(icon: Any) -> str:
    value = str(icon or "").strip()
    if value in {"rain", "sleet", "snow"}:
        return value
    return "none"


def _is_bad_dust(dust: dict[str, Any]) -> bool:
    values = {
        str(dust.get("grade") or "").strip(),
        str(dust.get("pm10_grade") or "").strip(),
        str(dust.get("pm25_grade") or "").strip(),
    }
    return bool(values & {"bad", "very_bad"})


def _parse_observed_at(value: Any) -> datetime:
    if isinstance(value, datetime):
        return _ensure_tz(value)
    text = str(value or "").strip()
    if text:
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        for candidate in (text, text.replace(" ", "T")):
            try:
                return _ensure_tz(datetime.fromisoformat(candidate))
            except ValueError:
                continue
    return datetime.now(UTC)


def _ensure_tz(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=KST)
    return value


def _optional_float(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
