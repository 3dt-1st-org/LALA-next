from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import UTC, datetime, timedelta, timezone
from typing import Any, Iterable

from apps.api.app.services import weather_service
from apps.api.app.services.dust_quality import clean_air_quality_value

KST = timezone(timedelta(hours=9), "Asia/Seoul")


@dataclass(frozen=True)
class WeatherTarget:
    location_name: str
    lat: float
    lng: float
    place_count: int = 0

    def to_public_dict(self) -> dict[str, Any]:
        return asdict(self)


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
    collected_at: datetime
    source_summary: str

    def to_public_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["observed_at"] = self.observed_at.isoformat()
        payload["collected_at"] = self.collected_at.isoformat()
        return payload


@dataclass(frozen=True)
class WeatherRefreshResult:
    target_count: int
    observation_count: int
    inserted_rows: int
    observations: tuple[WeatherObservation, ...]

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "target_count": self.target_count,
            "observation_count": self.observation_count,
            "inserted_rows": self.inserted_rows,
            "preview": [item.to_public_dict() for item in self.observations[:5]],
        }


def fetch_weather_targets(
    *,
    dsn: str,
    limit: int,
    connect_timeout: int,
) -> list[WeatherTarget]:
    if not dsn:
        raise ValueError("DB_DSN is required.")
    if limit <= 0:
        raise ValueError("limit must be positive.")
    import psycopg2
    from psycopg2.extras import RealDictCursor

    sql = """
        SELECT
            COALESCE(NULLIF(TRIM(region_name_ko), ''), '지역 미상') AS location_name,
            AVG(lat)::double precision AS lat,
            AVG(lng)::double precision AS lng,
            COUNT(*)::integer AS place_count
        FROM travel.places
        WHERE lat IS NOT NULL
          AND lng IS NOT NULL
          AND NULLIF(TRIM(region_name_ko), '') IS NOT NULL
        GROUP BY COALESCE(NULLIF(TRIM(region_name_ko), ''), '지역 미상')
        ORDER BY COUNT(*) DESC, location_name
        LIMIT %s
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, (limit,))
            return [
                WeatherTarget(
                    location_name=str(row["location_name"]),
                    lat=float(row["lat"]),
                    lng=float(row["lng"]),
                    place_count=int(row["place_count"] or 0),
                )
                for row in cur.fetchall()
            ]


def fetch_weather_observations(
    targets: Iterable[WeatherTarget],
) -> tuple[WeatherObservation, ...]:
    observations: list[WeatherObservation] = []
    weather_service.clear_official_weather_cache()
    for target in targets:
        official_weather, air_quality = weather_service._fetch_official_weather_pair(
            lat=target.lat,
            lng=target.lng,
            force=True,
        )
        observation = build_weather_observation(
            target=target,
            official_weather=official_weather,
            air_quality=air_quality,
        )
        if observation is not None:
            observations.append(observation)
    return tuple(observations)


def build_weather_observation(
    *,
    target: WeatherTarget,
    official_weather: dict[str, Any] | None,
    air_quality: dict[str, Any] | None,
    collected_at: datetime | None = None,
) -> WeatherObservation | None:
    if not official_weather and not air_quality:
        return None
    collected = collected_at or datetime.now(UTC)
    dust = air_quality.get("dust") if isinstance(air_quality, dict) else None
    if not isinstance(dust, dict):
        dust = official_weather.get("dust") if isinstance(official_weather, dict) else {}
    observed_at = _parse_observed_at(
        (official_weather or {}).get("record_time")
        or (air_quality or {}).get("record_time")
    )
    if observed_at is None:
        observed_at = collected
    temperature_c = _optional_float((official_weather or {}).get("temp"))
    pm10 = _optional_float(dust.get("pm10") if isinstance(dust, dict) else None)
    pm25 = _optional_float(dust.get("pm25") if isinstance(dust, dict) else None)
    icon = str((official_weather or {}).get("icon") or "").strip().lower()
    outdoor_status = str((official_weather or {}).get("outdoor_status") or "").strip()
    is_rain_snow = icon in {"rain", "snow"}
    return WeatherObservation(
        location_name=target.location_name,
        temperature_c=temperature_c,
        precipitation_type=icon or None,
        pm10=pm10,
        pm25=pm25,
        is_rain_snow=is_rain_snow,
        is_bad_dust=_is_bad_dust(dust),
        is_heatwave=temperature_c is not None and temperature_c >= 33,
        is_coldwave=temperature_c is not None and temperature_c <= -12,
        is_strong_wind=False,
        observed_at=observed_at,
        collected_at=collected,
        source_summary=_source_summary(official_weather, air_quality, outdoor_status),
    )


def insert_weather_observations(
    *,
    dsn: str,
    observations: Iterable[WeatherObservation],
    connect_timeout: int,
) -> int:
    if not dsn:
        raise ValueError("DB_DSN is required.")
    import psycopg2

    sql = """
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
            observed_at,
            collected_at
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
            %(observed_at)s,
            %(collected_at)s
        WHERE NOT EXISTS (
            SELECT 1
            FROM travel.weather_observations
            WHERE location_name = %(location_name)s
              AND observed_at = %(observed_at)s
        )
    """
    inserted = 0
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            for observation in observations:
                cur.execute(sql, _observation_params(observation))
                inserted += int(cur.rowcount or 0)
        conn.commit()
    return inserted


def record_job_run(
    *,
    dsn: str,
    job_name: str,
    status: str,
    started_at: datetime,
    finished_at: datetime,
    duration_ms: int,
    error_message: str | None,
    connect_timeout: int,
) -> None:
    if not dsn:
        return
    import psycopg2

    sql = """
        INSERT INTO ops.job_runs (
            job_name,
            status,
            started_at,
            finished_at,
            duration_ms,
            error_message
        )
        VALUES (%s, %s, %s, %s, %s, %s)
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            cur.execute(
                sql,
                (job_name, status, started_at, finished_at, duration_ms, error_message),
            )
        conn.commit()


def _observation_params(observation: WeatherObservation) -> dict[str, Any]:
    return {
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
        "collected_at": observation.collected_at,
    }


def _parse_observed_at(value: Any) -> datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        try:
            parsed = datetime.strptime(text, "%Y-%m-%d %H:%M").replace(tzinfo=KST)
        except ValueError:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=KST)
    return parsed.astimezone(UTC)


def _optional_float(value: Any) -> float | None:
    cleaned = clean_air_quality_value(value)
    if not cleaned:
        return None
    try:
        return float(cleaned)
    except ValueError:
        return None


def _is_bad_dust(dust: dict[str, Any] | None) -> bool:
    if not isinstance(dust, dict):
        return False
    grade_values = {
        str(dust.get("grade") or "").lower(),
        str(dust.get("pm10_grade") or "").lower(),
        str(dust.get("pm25_grade") or "").lower(),
    }
    if "bad" in grade_values:
        return True
    pm10 = _optional_float(dust.get("pm10"))
    pm25 = _optional_float(dust.get("pm25"))
    return bool((pm10 is not None and pm10 >= 81) or (pm25 is not None and pm25 >= 36))


def _source_summary(
    official_weather: dict[str, Any] | None,
    air_quality: dict[str, Any] | None,
    outdoor_status: str,
) -> str:
    sources = []
    if official_weather:
        sources.append(str(official_weather.get("source") or "kma").strip())
    if air_quality:
        sources.append("airkorea")
    if outdoor_status:
        sources.append(f"outdoor={outdoor_status}")
    return "+".join(source for source in sources if source)
