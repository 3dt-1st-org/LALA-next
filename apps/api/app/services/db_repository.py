from __future__ import annotations

from contextlib import closing
from datetime import UTC, datetime
from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.services.official_media import normalize_official_image_url
from apps.api.app.services.public_mvp_snapshot import GYEONGGI_REGION_NAME_EN

_REQUIRED_DB_RELATIONS = (
    "travel.public_places",
    "travel.place_events",
    "travel.weather_observations",
    "travel.docent_scripts",
    "analytics.place_score_snapshots",
    "rag.knowledge_chunks",
)


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
                cur.execute(
                    """
                    SELECT
                        to_regclass('travel.public_places') IS NOT NULL,
                        to_regclass('travel.place_events') IS NOT NULL,
                        to_regclass('travel.weather_observations') IS NOT NULL,
                        to_regclass('travel.docent_scripts') IS NOT NULL,
                        to_regclass('analytics.place_score_snapshots') IS NOT NULL,
                        to_regclass('rag.knowledge_chunks') IS NOT NULL
                    """
                )
                row = cur.fetchone()
    except Exception:
        return "degraded"
    if not row or not all(bool(value) for value in row):
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
                image_url,
                region_ko,
                region_en,
                lat,
                lng,
                source,
                updated_at,
                SQRT(POWER((lat - %s) * 111000, 2) + POWER((lng - %s) * 88000, 2)) AS distance_m
            FROM travel.public_places
            WHERE (%s = 'all' OR category = %s)
        )
        , latest_scores AS (
            SELECT DISTINCT ON (place_id)
                place_id,
                local_spending_score,
                demand_dispersion_score,
                weather_fit_score,
                review_quality_score,
                culture_relevance_score,
                final_score,
                formula_version,
                features
            FROM analytics.place_score_snapshots
            ORDER BY place_id, scored_at DESC
        )
        SELECT
            ranked_places.*,
            CASE
                WHEN ranked_places.category = 'event' AND linked_event.place_id IS NOT NULL
                THEN to_char(linked_event.starts_at AT TIME ZONE 'Asia/Seoul', 'YYYY-MM-DD')
                ELSE NULL
            END AS event_start_date,
            CASE
                WHEN ranked_places.category = 'event' AND linked_event.place_id IS NOT NULL
                THEN to_char(linked_event.ends_at AT TIME ZONE 'Asia/Seoul', 'YYYY-MM-DD')
                ELSE NULL
            END AS event_end_date,
            CASE
                WHEN ranked_places.category = 'event' AND linked_event.place_id IS NOT NULL
                THEN linked_event.url
                ELSE NULL
            END AS event_url,
            CASE
                WHEN ranked_places.category = 'event' AND linked_event.place_id IS NOT NULL
                THEN linked_event.ends_at IS NULL OR linked_event.ends_at >= now()
                ELSE NULL
            END AS is_ongoing,
            false AS is_approximate_location,
            latest_scores.local_spending_score,
            latest_scores.demand_dispersion_score,
            latest_scores.weather_fit_score,
            latest_scores.review_quality_score,
            latest_scores.culture_relevance_score,
            latest_scores.final_score,
            latest_scores.formula_version,
            latest_scores.features AS score_features
        FROM ranked_places
        LEFT JOIN latest_scores ON latest_scores.place_id = ranked_places.place_id
        LEFT JOIN LATERAL (
            SELECT
                place_id,
                starts_at,
                ends_at,
                url
            FROM travel.place_events
            WHERE place_id = ranked_places.place_id
            ORDER BY
                CASE WHEN ends_at IS NULL OR ends_at >= now() THEN 0 ELSE 1 END,
                starts_at DESC NULLS LAST,
                updated_at DESC
            LIMIT 1
        ) linked_event ON TRUE
        WHERE distance_m <= %s
        ORDER BY COALESCE(latest_scores.final_score, 0) DESC, distance_m ASC, updated_at DESC
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
        name = (
            row.get("name_en")
            if language == "en" and row.get("name_en")
            else _english_display_name(row)
            if language == "en"
            else row.get("name_ko")
        )
        address = (
            row.get("address_en")
            if language == "en" and row.get("address_en")
            else _english_display_address(row)
            if language == "en"
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
                "image_url": normalize_official_image_url(row.get("image_url")),
                "region_ko": row.get("region_ko"),
                "region_en": row.get("region_en"),
                "event_start_date": row.get("event_start_date"),
                "event_end_date": row.get("event_end_date"),
                "event_url": row.get("event_url"),
                "is_ongoing": row.get("is_ongoing"),
                "is_approximate_location": row.get("is_approximate_location"),
                "distance_m": int(round(distance_m)),
                "source": "db",
                "upstream_source": row.get("source") or "canonical",
                "score": _place_score_from_row(row),
            }
        )
    return places


def _place_score_from_row(row: dict[str, Any]) -> dict[str, Any] | None:
    if row.get("final_score") is None:
        return None
    return {
        "final_score": _optional_float(row.get("final_score")) or 0.0,
        "formula_version": row.get("formula_version") or "unknown",
        "components": {
            "local_spending_score": _optional_float(row.get("local_spending_score")),
            "demand_dispersion_score": _optional_float(row.get("demand_dispersion_score")),
            "weather_fit_score": _optional_float(row.get("weather_fit_score")),
            "review_quality_score": _optional_float(row.get("review_quality_score")),
            "culture_relevance_score": _optional_float(row.get("culture_relevance_score")),
        },
        "data_basis": "analytics.place_score_snapshots",
        "features": row.get("score_features") or {},
    }


def _optional_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _english_display_name(row: dict[str, Any]) -> str:
    region = _english_region(row)
    category = str(row.get("category") or "").strip()
    category_label = {
        "attraction": "Attraction",
        "culture_venue": "Culture venue",
        "event": "Event",
        "restaurant": "Restaurant",
    }.get(category, "Local place")
    return f"{category_label} in {region}" if region else category_label


def _english_display_address(row: dict[str, Any]) -> str:
    region = _english_region(row)
    return f"{region}, Gyeonggi-do" if region else "Gyeonggi-do"


def _english_region(row: dict[str, Any]) -> str | None:
    region_ko = str(row.get("region_ko") or "").strip()
    canonical_region = GYEONGGI_REGION_NAME_EN.get(region_ko)
    if canonical_region:
        return canonical_region
    region = str(row.get("region_en") or "").strip()
    if region:
        return region
    return None


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
            FROM travel.public_places
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
        FROM travel.latest_weather w
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
            source_method,
            generated_at,
            expires_at
        FROM travel.docent_scripts
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
        "upstream_source": row.get("source_method") or "unknown",
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
        INSERT INTO travel.docent_scripts (
            place_id,
            category,
            language,
            mode,
            script,
            source_method,
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
            source_method = EXCLUDED.source_method,
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
