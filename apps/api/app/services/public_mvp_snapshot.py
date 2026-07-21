from __future__ import annotations

import json
from collections.abc import Sequence
from contextlib import closing
from datetime import UTC, date, datetime
from decimal import Decimal
from typing import Any

from apps.api.app.services import region_catalog
from apps.api.app.services.official_media import normalize_official_image_url

SNAPSHOT_DATA_BASIS = "public_mvp_snapshot"
DEFAULT_SNAPSHOT_DESCRIPTION = (
    "Read-only static snapshot exported from the canonical DB read model. It is "
    "reserved for DB outage fallback and isolated local checks."
)
DEFAULT_OUTPUT_PATH = "apps/api/app/data/public_mvp_places.json"

GYEONGGI_REGION_NAME_EN = region_catalog.region_name_en_map(province_names=("경기도",))
SEOUL_REGION_NAME_EN = region_catalog.region_name_en_map(province_names=("서울특별시",))
DEFAULT_REGION_NAME_EN = region_catalog.region_name_en_map(province_names=("경기도", "서울특별시"))


def build_snapshot_payload(
    places: Sequence[dict[str, Any]],
    *,
    snapshot_id: str,
    description: str = DEFAULT_SNAPSHOT_DESCRIPTION,
    lat: float,
    lng: float,
    radius_m: int,
    category: str,
) -> dict[str, Any]:
    return {
        "snapshot_id": snapshot_id,
        "description": description,
        "generated_at": datetime.now(UTC).isoformat(),
        "query": {
            "lat": lat,
            "lng": lng,
            "radius_m": radius_m,
            "category": category,
        },
        "places": [_snapshot_place(row) for row in places],
    }


def fetch_snapshot_places(
    *,
    dsn: str,
    lat: float,
    lng: float,
    radius_m: int,
    category: str,
    limit: int,
    connect_timeout: int,
    coverage_region_names: Sequence[str] | None = tuple(DEFAULT_REGION_NAME_EN),
) -> list[dict[str, Any]]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    coverage_regions = list(coverage_region_names or [])
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
                source AS upstream_source,
                updated_at,
                SQRT(POWER((lat - %s) * 111000, 2) + POWER((lng - %s) * 88000, 2)) AS distance_m
            FROM travel.public_places
            WHERE (%s = 'all' OR category = %s)
              AND COALESCE(source, '') NOT IN ('dev_seed', 'local_fixture')
        ),
        latest_scores AS (
            SELECT DISTINCT ON (place_id)
                place_id,
                (to_jsonb(score_snapshot)->>'local_spending_score')::numeric AS local_spending_score,
                (to_jsonb(score_snapshot)->>'small_merchant_fit_score')::numeric AS small_merchant_fit_score,
                (to_jsonb(score_snapshot)->>'demand_dispersion_score')::numeric AS demand_dispersion_score,
                (to_jsonb(score_snapshot)->>'culture_relevance_score')::numeric AS culture_relevance_score,
                (to_jsonb(score_snapshot)->>'weather_fit_score')::numeric AS weather_fit_score,
                (to_jsonb(score_snapshot)->>'review_quality_score')::numeric AS review_quality_score,
                (to_jsonb(score_snapshot)->>'accessibility_fit_score')::numeric AS accessibility_fit_score,
                final_score,
                formula_version,
                features
            FROM analytics.place_score_snapshots score_snapshot
            ORDER BY place_id, scored_at DESC
        ),
        scored_places AS (
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
                latest_scores.small_merchant_fit_score,
                latest_scores.demand_dispersion_score,
                latest_scores.culture_relevance_score,
                latest_scores.weather_fit_score,
                latest_scores.review_quality_score,
                latest_scores.accessibility_fit_score,
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
        ),
        primary_rows AS (
            SELECT scored_places.*, 0 AS snapshot_row_group
            FROM scored_places
            WHERE distance_m <= %s
            ORDER BY FLOOR(distance_m / 500.0) ASC, COALESCE(final_score, 0) DESC, distance_m ASC, updated_at DESC
            LIMIT %s
        ),
        coverage_rows AS (
            SELECT DISTINCT ON (region_ko) scored_places.*, 1 AS snapshot_row_group
            FROM scored_places
            WHERE %s = 'all'
              AND region_ko = ANY(%s)
            ORDER BY
                region_ko,
                COALESCE(final_score, 0) DESC,
                updated_at DESC,
                distance_m ASC
        ),
        merged_rows AS (
            SELECT * FROM primary_rows
            UNION ALL
            SELECT * FROM coverage_rows
        ),
        deduped_rows AS (
            SELECT DISTINCT ON (place_id) *
            FROM merged_rows
            ORDER BY place_id, snapshot_row_group ASC, COALESCE(final_score, 0) DESC
        )
        SELECT
            *
        FROM deduped_rows
        ORDER BY snapshot_row_group ASC, FLOOR(distance_m / 500.0) ASC, COALESCE(final_score, 0) DESC, distance_m ASC, updated_at DESC
    """
    with closing(psycopg2.connect(dsn, connect_timeout=connect_timeout)) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                sql,
                (lat, lng, category, category, radius_m, limit, category, coverage_regions),
            )
            return [dict(row) for row in cur.fetchall()]


def payload_to_json(payload: dict[str, Any]) -> str:
    return json.dumps(_json_safe(payload), ensure_ascii=False, indent=2, sort_keys=False) + "\n"


def _snapshot_place(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "place_id": str(row.get("place_id") or ""),
        "name_ko": str(row.get("name_ko") or ""),
        "name_en": _optional_text(row.get("name_en")),
        "category": str(row.get("category") or ""),
        "lat": _required_float(row.get("lat")),
        "lng": _required_float(row.get("lng")),
        "address_ko": _optional_text(row.get("address_ko")),
        "address_en": _snapshot_address_en(row),
        "image_url": normalize_official_image_url(row.get("image_url")),
        "region_ko": _optional_text(row.get("region_ko")),
        "region_en": _snapshot_region_en(row),
        "event_start_date": _optional_text(row.get("event_start_date")),
        "event_end_date": _optional_text(row.get("event_end_date")),
        "event_url": _optional_text(row.get("event_url")),
        "is_ongoing": _optional_bool(row.get("is_ongoing")),
        "is_approximate_location": _optional_bool(row.get("is_approximate_location")),
        "upstream_source": _optional_text(row.get("upstream_source")) or "canonical",
        "score": _snapshot_score(row),
    }


def _snapshot_score(row: dict[str, Any]) -> dict[str, Any] | None:
    final_score = _optional_float(row.get("final_score"))
    if final_score is None:
        return None
    features = _json_safe(row.get("score_features") or {})
    if not isinstance(features, dict):
        features = {"raw_features": features}
    features.setdefault("snapshot_source", "analytics.place_score_snapshots")
    return {
        "final_score": final_score,
        "formula_version": str(row.get("formula_version") or "unknown"),
        "components": {
            "local_spending_score": _optional_float(row.get("local_spending_score")),
            "small_merchant_fit_score": _optional_float(row.get("small_merchant_fit_score")),
            "demand_dispersion_score": _optional_float(row.get("demand_dispersion_score")),
            "culture_relevance_score": _optional_float(row.get("culture_relevance_score")),
            "weather_fit_score": _optional_float(row.get("weather_fit_score")),
            "review_quality_score": _optional_float(row.get("review_quality_score")),
            "accessibility_fit_score": _optional_float(row.get("accessibility_fit_score")),
        },
        "data_basis": SNAPSHOT_DATA_BASIS,
        "features": features,
    }


def _snapshot_address_en(row: dict[str, Any]) -> str | None:
    address_en = _optional_text(row.get("address_en"))
    if not address_en:
        return None
    address_ko = _optional_text(row.get("address_ko")) or ""
    province_ko = region_catalog.infer_province_name_from_address(address_ko)
    province_en = region_catalog.province_name_en(province_ko)
    if province_en and province_en.lower() not in address_en.lower():
        return f"{address_en}, {province_en}"
    return address_en


def _snapshot_region_en(row: dict[str, Any]) -> str | None:
    region_ko = _optional_text(row.get("region_ko"))
    if region_ko:
        canonical_region = region_catalog.region_name_en(region_ko)
        if canonical_region:
            return canonical_region
    return _optional_text(row.get("region_en"))


def _json_safe(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(item) for item in value]
    return value


def _optional_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _required_float(value: Any) -> float:
    return _optional_float(value) or 0.0


def _optional_bool(value: Any) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    text = str(value).strip().lower()
    if text in {"true", "t", "1", "yes", "y"}:
        return True
    if text in {"false", "f", "0", "no", "n"}:
        return False
    return None


def _optional_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None
