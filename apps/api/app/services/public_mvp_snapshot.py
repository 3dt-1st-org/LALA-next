from __future__ import annotations

import json
from contextlib import closing
from datetime import UTC, date, datetime
from decimal import Decimal
from typing import Any, Sequence

SNAPSHOT_DATA_BASIS = "public_mvp_snapshot"
DEFAULT_SNAPSHOT_DESCRIPTION = (
    "Public MVP snapshot exported from the canonical DB read model. It is used "
    "only when the public demo API has no DB_DSN."
)
DEFAULT_OUTPUT_PATH = "apps/api/app/data/public_mvp_places.json"


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
) -> list[dict[str, Any]]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

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
                source AS upstream_source,
                updated_at,
                SQRT(POWER((lat - %s) * 111000, 2) + POWER((lng - %s) * 88000, 2)) AS distance_m
            FROM travel.public_places
            WHERE (%s = 'all' OR category = %s)
        ),
        latest_scores AS (
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
        WHERE distance_m <= %s
        ORDER BY COALESCE(latest_scores.final_score, 0) DESC, distance_m ASC, updated_at DESC
        LIMIT %s
    """
    with closing(psycopg2.connect(dsn, connect_timeout=connect_timeout)) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, (lat, lng, category, category, radius_m, limit))
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
        "region_ko": _optional_text(row.get("region_ko")),
        "region_en": _optional_text(row.get("region_en")),
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
            "demand_dispersion_score": _optional_float(row.get("demand_dispersion_score")),
            "weather_fit_score": _optional_float(row.get("weather_fit_score")),
            "review_quality_score": _optional_float(row.get("review_quality_score")),
            "culture_relevance_score": _optional_float(row.get("culture_relevance_score")),
        },
        "data_basis": SNAPSHOT_DATA_BASIS,
        "features": features,
    }


def _snapshot_address_en(row: dict[str, Any]) -> str | None:
    address_en = _optional_text(row.get("address_en"))
    if not address_en:
        return None
    address_ko = _optional_text(row.get("address_ko")) or ""
    if "경기도" in address_ko and "gyeonggi" not in address_en.lower():
        return f"{address_en}, Gyeonggi-do"
    return address_en


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


def _optional_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None
