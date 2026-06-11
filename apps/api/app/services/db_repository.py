from __future__ import annotations

from contextlib import closing
from datetime import UTC, datetime
from typing import Any

from apps.api.app.core.config import get_settings


def check_db_status(dsn: str) -> str:
    if not dsn:
        return "skipped"
    try:
        import psycopg2
    except Exception:
        return "degraded"
    try:
        with closing(psycopg2.connect(dsn, connect_timeout=3)) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
    except Exception:
        return "degraded"
    return "configured"


def fetch_places(
    *,
    lat: float,
    lng: float,
    radius_m: int,
    category: str,
    language: str,
) -> list[dict[str, Any]]:
    dsn = get_settings().db_dsn
    if not dsn:
        return []
    try:
        import psycopg2
        from psycopg2.extras import RealDictCursor
    except Exception:
        return []

    sql = """
        WITH ranked_places AS (
            SELECT
                place_id,
                name_ko,
                name_en,
                category,
                address_ko,
                address_en,
                region_ko,
                region_en,
                lat,
                lng,
                source,
                updated_at,
                SQRT(POWER((lat - %s) * 111000, 2) + POWER((lng - %s) * 88000, 2)) AS distance_m
            FROM locallink.v_public_places
            WHERE (%s = 'all' OR category = %s)
        )
        SELECT *
        FROM ranked_places
        WHERE distance_m <= %s
        ORDER BY distance_m ASC, updated_at DESC
        LIMIT 20
    """
    params = (lat, lng, category, category, radius_m)
    try:
        with closing(psycopg2.connect(dsn, connect_timeout=3)) as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(sql, params)
                rows = list(cur.fetchall())
    except Exception:
        return []

    places: list[dict[str, Any]] = []
    for row in rows:
        distance_m = float(row.get("distance_m") or 0)
        if distance_m > radius_m:
            continue
        name = row.get("name_en") if language == "en" and row.get("name_en") else row.get("name_ko")
        address = (
            row.get("address_en")
            if language == "en" and row.get("address_en")
            else row.get("address_ko")
        )
        places.append(
            {
                "place_id": row["place_id"],
                "name": name,
                "name_ko": row.get("name_ko"),
                "name_en": row.get("name_en"),
                "category": row["category"],
                "lat": float(row["lat"]),
                "lng": float(row["lng"]),
                "address": address,
                "region_ko": row.get("region_ko"),
                "region_en": row.get("region_en"),
                "distance_m": int(round(distance_m)),
                "source": "db",
                "upstream_source": row.get("source") or "canonical",
            }
        )
    return places


def fetch_latest_weather(*, lat: float, lng: float) -> dict[str, Any] | None:
    dsn = get_settings().db_dsn
    if not dsn:
        return None
    try:
        import psycopg2
        from psycopg2.extras import RealDictCursor
    except Exception:
        return None

    sql = """
        WITH nearest_region AS (
            SELECT
                NULLIF(TRIM(region_ko), '') AS region_ko,
                NULLIF(TRIM(region_en), '') AS region_en
            FROM locallink.v_public_places
            ORDER BY SQRT(POWER((lat - %s) * 111000, 2) + POWER((lng - %s) * 88000, 2))
            LIMIT 1
        )
        SELECT
            w.location,
            w.temperature,
            w.precipitation_type,
            w.pm10,
            w.pm25,
            w.is_rain_snow,
            w.is_bad_dust,
            w.is_heatwave,
            w.is_coldwave,
            w.is_strong_wind,
            w.record_time,
            CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM nearest_region nr
                    WHERE LOWER(REPLACE(COALESCE(w.location, ''), ' ', '')) =
                          LOWER(REPLACE(COALESCE(nr.region_ko, ''), ' ', ''))
                       OR LOWER(REPLACE(COALESCE(w.location, ''), ' ', '')) =
                          LOWER(REPLACE(COALESCE(nr.region_en, ''), ' ', ''))
                ) THEN 0
                ELSE 1
            END AS location_match_rank
        FROM locallink.realtime_weather_conditions w
        ORDER BY location_match_rank ASC, w.record_time DESC
        LIMIT 1
    """
    try:
        with closing(psycopg2.connect(dsn, connect_timeout=3)) as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(sql, (lat, lng))
                row = cur.fetchone()
    except Exception:
        return None
    if not row:
        return None

    outdoor_status = "bad" if any(
        [
            row.get("is_rain_snow"),
            row.get("is_bad_dust"),
            row.get("is_heatwave"),
            row.get("is_coldwave"),
            row.get("is_strong_wind"),
        ]
    ) else "good"
    return {
        "lat": lat,
        "lng": lng,
        "location": row.get("location"),
        "temp": str(row.get("temperature") or ""),
        "icon": _weather_icon(row.get("precipitation_type")),
        "dust": {
            "pm10": str(row.get("pm10") or ""),
            "pm25": str(row.get("pm25") or ""),
            "grade": "bad" if row.get("is_bad_dust") else "normal",
            "grade_ko": "나쁨" if row.get("is_bad_dust") else "보통",
        },
        "forecast": [],
        "outdoor_status": outdoor_status,
        "location_match": row.get("location_match_rank") == 0,
        "record_time": row.get("record_time").isoformat() if row.get("record_time") else None,
        "source": "db",
    }


def fetch_docent_script_cache(
    *,
    place_id: str,
    category: str,
    language: str,
    mode: str,
) -> dict[str, Any] | None:
    dsn = get_settings().db_dsn
    if not dsn:
        return None
    try:
        import psycopg2
        from psycopg2.extras import RealDictCursor
    except Exception:
        return None

    sql = """
        SELECT
            place_id,
            category,
            language,
            mode,
            script,
            source,
            generated_at,
            expires_at
        FROM locallink.docent_cache
        WHERE place_id = %s
          AND category = %s
          AND language = %s
          AND mode = %s
          AND (expires_at IS NULL OR expires_at > now())
        ORDER BY generated_at DESC
        LIMIT 1
    """
    params = (place_id, category, language, mode)
    try:
        with closing(psycopg2.connect(dsn, connect_timeout=3)) as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(sql, params)
                row = cur.fetchone()
    except Exception:
        return None
    if not row:
        return None

    return {
        "place_id": row["place_id"],
        "category": row["category"],
        "language": row["language"],
        "mode": row["mode"],
        "script": row["script"],
        "source": "db_cache",
        "upstream_source": row.get("source") or "unknown",
        "generated_at": row.get("generated_at").isoformat() if row.get("generated_at") else None,
        "ttl_sec": _remaining_ttl_sec(row.get("expires_at")),
    }


def save_docent_script_cache(
    *,
    place_id: str,
    category: str,
    language: str,
    mode: str,
    script: str,
    source: str,
    ttl_sec: int,
) -> bool:
    dsn = get_settings().db_dsn
    if not dsn:
        return False
    try:
        import psycopg2
    except Exception:
        return False

    sql = """
        INSERT INTO locallink.docent_cache (
            place_id,
            category,
            language,
            mode,
            script,
            source,
            generated_at,
            expires_at
        )
        VALUES (
            %s,
            %s,
            %s,
            %s,
            %s,
            %s,
            now(),
            now() + (%s * interval '1 second')
        )
        ON CONFLICT (place_id, category, language, mode)
        DO UPDATE SET
            script = EXCLUDED.script,
            source = EXCLUDED.source,
            generated_at = EXCLUDED.generated_at,
            expires_at = EXCLUDED.expires_at
    """
    params = (place_id, category, language, mode, script, source, ttl_sec)
    try:
        with closing(psycopg2.connect(dsn, connect_timeout=3)) as conn:
            with conn.cursor() as cur:
                cur.execute(sql, params)
            conn.commit()
    except Exception:
        return False
    return True


def _weather_icon(precipitation_type: Any) -> str:
    raw = str(precipitation_type or "").strip().lower()
    if raw in {"rain", "비", "1"}:
        return "rain"
    if raw in {"snow", "눈", "3"}:
        return "snow"
    return "partly-cloudy"


def _remaining_ttl_sec(expires_at: Any) -> int:
    if not expires_at:
        return 0
    if isinstance(expires_at, datetime):
        expires_at_aware = expires_at
        if expires_at_aware.tzinfo is None:
            expires_at_aware = expires_at_aware.replace(tzinfo=UTC)
        now = datetime.now(expires_at_aware.tzinfo)
        return max(0, int((expires_at_aware - now).total_seconds()))
    return 0
