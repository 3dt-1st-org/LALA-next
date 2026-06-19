from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from datetime import date
from decimal import Decimal
from typing import Any, Sequence

from apps.api.app.services.recommendation_scoring import (
    FORMULA_VERSION,
    build_place_score,
)

OFFICIAL_CULTURE_SOURCES = {
    "tour_api",
    "kcisa",
    "kopis",
    "culture_info",
    "data_portal",
}


@dataclass(frozen=True)
class PlaceSignal:
    place_id: str
    name_ko: str
    category: str
    region_name_ko: str | None
    is_indoor: bool | None
    primary_source: str | None
    region_spend_amount: float | None = None
    region_transaction_count: int | None = None
    card_month: str | None = None
    region_place_count: int | None = None
    culture_event_count: int = 0
    place_event_count: int = 0
    business_identity_type: str | None = None
    is_franchise: bool | None = None
    franchise_brand_name: str | None = None
    franchise_match_confidence: float | None = None
    chain_scale_score: float | None = None
    small_merchant_fit_score: float | None = None
    is_rain_snow: bool | None = None
    is_bad_dust: bool | None = None
    is_heatwave: bool | None = None
    is_coldwave: bool | None = None
    is_strong_wind: bool | None = None

    @classmethod
    def from_row(cls, row: dict[str, Any]) -> "PlaceSignal":
        return cls(
            place_id=str(row.get("place_id") or ""),
            name_ko=str(row.get("name_ko") or ""),
            category=str(row.get("category") or ""),
            region_name_ko=_optional_text(row.get("region_name_ko")),
            is_indoor=_optional_bool(row.get("is_indoor")),
            primary_source=_optional_text(row.get("primary_source")),
            region_spend_amount=_optional_float(row.get("region_spend_amount")),
            region_transaction_count=_optional_int(row.get("region_transaction_count")),
            card_month=_optional_date_text(row.get("card_month")),
            region_place_count=_optional_int(row.get("region_place_count")),
            culture_event_count=_optional_int(row.get("culture_event_count")) or 0,
            place_event_count=_optional_int(row.get("place_event_count")) or 0,
            business_identity_type=_optional_text(row.get("business_identity_type")),
            is_franchise=_optional_bool(row.get("is_franchise")),
            franchise_brand_name=_optional_text(row.get("franchise_brand_name")),
            franchise_match_confidence=_optional_float(row.get("franchise_match_confidence")),
            chain_scale_score=_optional_float(row.get("chain_scale_score")),
            small_merchant_fit_score=_optional_float(row.get("small_merchant_fit_score")),
            is_rain_snow=_optional_bool(row.get("is_rain_snow")),
            is_bad_dust=_optional_bool(row.get("is_bad_dust")),
            is_heatwave=_optional_bool(row.get("is_heatwave")),
            is_coldwave=_optional_bool(row.get("is_coldwave")),
            is_strong_wind=_optional_bool(row.get("is_strong_wind")),
        )


@dataclass(frozen=True)
class PlaceScoreSnapshot:
    place_id: str
    local_spending_score: float | None
    small_merchant_fit_score: float | None
    demand_dispersion_score: float | None
    culture_relevance_score: float | None
    weather_fit_score: float | None
    review_quality_score: float | None
    accessibility_fit_score: float | None
    final_score: float
    formula_version: str
    features: dict[str, Any]

    @classmethod
    def from_score(cls, *, place_id: str, score: dict[str, Any]) -> "PlaceScoreSnapshot":
        components = score["components"]
        return cls(
            place_id=place_id,
            local_spending_score=components["local_spending_score"],
            small_merchant_fit_score=components["small_merchant_fit_score"],
            demand_dispersion_score=components["demand_dispersion_score"],
            culture_relevance_score=components["culture_relevance_score"],
            weather_fit_score=components["weather_fit_score"],
            review_quality_score=components["review_quality_score"],
            accessibility_fit_score=components["accessibility_fit_score"],
            final_score=score["final_score"],
            formula_version=score["formula_version"],
            features=score["features"],
        )

    def to_public_dict(self) -> dict[str, Any]:
        return asdict(self)


def compute_score_snapshots(signals: Sequence[PlaceSignal]) -> list[PlaceScoreSnapshot]:
    spending_values = [
        signal.region_spend_amount
        for signal in signals
        if signal.region_spend_amount is not None
    ]
    place_count_values = [
        float(signal.region_place_count)
        for signal in signals
        if signal.region_place_count is not None
    ]

    snapshots: list[PlaceScoreSnapshot] = []
    for signal in signals:
        local_spending_score = _relative_score(
            signal.region_spend_amount,
            spending_values,
            equal_default=0.70,
        )
        density_score = _inverse_relative_score(
            float(signal.region_place_count) if signal.region_place_count is not None else None,
            place_count_values,
            equal_default=0.65,
        )
        components = {
            "local_spending_score": local_spending_score,
            "small_merchant_fit_score": signal.small_merchant_fit_score,
            "demand_dispersion_score": density_score,
            "culture_relevance_score": _culture_relevance_score(signal),
            "weather_fit_score": _weather_fit_score(signal),
            "review_quality_score": None,
            "accessibility_fit_score": _accessibility_fit_score(signal),
        }
        score = build_place_score(
            components=components,
            data_basis="analytics.place_score_snapshots",
            features=_features(signal),
        )
        snapshots.append(PlaceScoreSnapshot.from_score(place_id=signal.place_id, score=score))
    return snapshots


def fetch_place_signals(
    *,
    dsn: str,
    category: str,
    limit: int,
    connect_timeout: int,
) -> list[PlaceSignal]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    business_identity_select = """
            business_identity.business_identity_type,
            business_identity.is_franchise,
            business_identity.franchise_brand_name,
            business_identity.franchise_match_confidence,
            business_identity.chain_scale_score,
            business_identity.small_merchant_fit_score
    """
    business_identity_join = """
        LEFT JOIN analytics.place_business_identity business_identity
          ON business_identity.place_id = places.place_id
    """

    fallback_business_identity_select = """
            NULL::text AS business_identity_type,
            NULL::boolean AS is_franchise,
            NULL::text AS franchise_brand_name,
            NULL::numeric AS franchise_match_confidence,
            NULL::numeric AS chain_scale_score,
            NULL::numeric AS small_merchant_fit_score
    """

    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            has_business_identity = _relation_exists(cur, "analytics.place_business_identity")
            sql = f"""
        WITH latest_area_month AS (
            SELECT region_name_ko, max(month) AS month
            FROM economy.card_spending_area_monthly
            WHERE spend_amount IS NOT NULL
            GROUP BY region_name_ko
        ),
        area_spending AS (
            SELECT
                spending.region_name_ko,
                spending.month AS card_month,
                sum(spending.spend_amount) AS region_spend_amount,
                sum(spending.transaction_count) AS region_transaction_count
            FROM economy.card_spending_area_monthly spending
            JOIN latest_area_month latest
              ON latest.region_name_ko = spending.region_name_ko
             AND latest.month = spending.month
            GROUP BY spending.region_name_ko, spending.month
        ),
        region_place_counts AS (
            SELECT region_name_ko, count(*) AS region_place_count
            FROM travel.places
            GROUP BY region_name_ko
        ),
        culture_event_counts AS (
            SELECT region_name_ko, count(*) AS culture_event_count
            FROM culture.events
            WHERE ends_on IS NULL OR ends_on >= current_date
            GROUP BY region_name_ko
        ),
        place_event_counts AS (
            SELECT place_id, count(*) AS place_event_count
            FROM travel.place_events
            WHERE ends_at IS NULL OR ends_at >= now()
            GROUP BY place_id
        ),
        latest_weather AS (
            SELECT DISTINCT ON (location_name)
                location_name,
                is_rain_snow,
                is_bad_dust,
                is_heatwave,
                is_coldwave,
                is_strong_wind
            FROM travel.weather_observations
            ORDER BY location_name, observed_at DESC
        )
        SELECT
            places.place_id,
            places.name_ko,
            places.category,
            places.region_name_ko,
            places.is_indoor,
            places.primary_source,
            area_spending.region_spend_amount,
            area_spending.region_transaction_count,
            area_spending.card_month,
            region_place_counts.region_place_count,
            coalesce(culture_event_counts.culture_event_count, 0) AS culture_event_count,
            coalesce(place_event_counts.place_event_count, 0) AS place_event_count,
            latest_weather.is_rain_snow,
            latest_weather.is_bad_dust,
            latest_weather.is_heatwave,
            latest_weather.is_coldwave,
            latest_weather.is_strong_wind,
{business_identity_select if has_business_identity else fallback_business_identity_select}
        FROM travel.places places
        LEFT JOIN area_spending
          ON area_spending.region_name_ko = places.region_name_ko
        LEFT JOIN region_place_counts
          ON region_place_counts.region_name_ko = places.region_name_ko
        LEFT JOIN culture_event_counts
          ON culture_event_counts.region_name_ko = places.region_name_ko
        LEFT JOIN place_event_counts
          ON place_event_counts.place_id = places.place_id
        LEFT JOIN latest_weather
          ON latest_weather.location_name = places.region_name_ko
{business_identity_join if has_business_identity else ""}
        WHERE (%s = 'all' OR places.category = %s)
        ORDER BY places.updated_at DESC, places.place_id
        LIMIT %s
    """
            cur.execute(sql, (category, category, limit))
            return [PlaceSignal.from_row(dict(row)) for row in cur.fetchall()]


def insert_score_snapshots(
    *,
    dsn: str,
    snapshots: Sequence[PlaceScoreSnapshot],
    connect_timeout: int,
) -> int:
    import psycopg2
    from psycopg2.extras import Json

    if not snapshots:
        return 0

    sql = """
        INSERT INTO analytics.place_score_snapshots (
            place_id,
            local_spending_score,
            small_merchant_fit_score,
            demand_dispersion_score,
            culture_relevance_score,
            weather_fit_score,
            review_quality_score,
            accessibility_fit_score,
            final_score,
            formula_version,
            features
        )
        VALUES (
            %(place_id)s,
            %(local_spending_score)s,
            %(small_merchant_fit_score)s,
            %(demand_dispersion_score)s,
            %(culture_relevance_score)s,
            %(weather_fit_score)s,
            %(review_quality_score)s,
            %(accessibility_fit_score)s,
            %(final_score)s,
            %(formula_version)s,
            %(features)s
        )
    """
    inserted = 0
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            for snapshot in snapshots:
                params = asdict(snapshot)
                params["features"] = Json(snapshot.features, dumps=_json_dumps)
                cur.execute(sql, params)
                inserted += cur.rowcount
        conn.commit()
    return inserted


def _features(signal: PlaceSignal) -> dict[str, Any]:
    missing_signals: list[str] = []
    if signal.region_spend_amount is None:
        missing_signals.append("card_spending_area_monthly")
    if signal.small_merchant_fit_score is None:
        missing_signals.append("place_business_identity")
    missing_signals.append("review_attribute_analysis")
    if not _has_weather(signal):
        missing_signals.append("weather_observations")

    return {
        "region_name_ko": signal.region_name_ko,
        "category": signal.category,
        "primary_source": signal.primary_source,
        "card_month": signal.card_month,
        "region_spend_amount": signal.region_spend_amount,
        "region_transaction_count": signal.region_transaction_count,
        "region_place_count": signal.region_place_count,
        "culture_event_count": signal.culture_event_count,
        "place_event_count": signal.place_event_count,
        "business_identity": {
            "business_identity_type": signal.business_identity_type,
            "is_franchise": signal.is_franchise,
            "franchise_brand_name": signal.franchise_brand_name,
            "franchise_match_confidence": signal.franchise_match_confidence,
            "chain_scale_score": signal.chain_scale_score,
        },
        "weather_flags": {
            "is_rain_snow": signal.is_rain_snow,
            "is_bad_dust": signal.is_bad_dust,
            "is_heatwave": signal.is_heatwave,
            "is_coldwave": signal.is_coldwave,
            "is_strong_wind": signal.is_strong_wind,
        },
        "input_sources": [
            "travel.places",
            "economy.card_spending_area_monthly",
            "culture.events",
            "travel.place_events",
            "analytics.place_business_identity",
            "travel.weather_observations",
        ],
        "missing_signals": missing_signals,
    }


def _weather_fit_score(signal: PlaceSignal) -> float | None:
    if not _has_weather(signal):
        return None

    severe_weather = any(
        flag is True
        for flag in (
            signal.is_rain_snow,
            signal.is_bad_dust,
            signal.is_heatwave,
            signal.is_coldwave,
            signal.is_strong_wind,
        )
    )
    if severe_weather:
        if signal.is_indoor is True:
            return 0.90
        if signal.is_indoor is False:
            return 0.45
        return 0.62
    if signal.is_indoor is False:
        return 0.85
    if signal.is_indoor is True:
        return 0.75
    return 0.72


def _culture_relevance_score(signal: PlaceSignal) -> float:
    score = 0.35
    source = (signal.primary_source or "").lower()
    if source in OFFICIAL_CULTURE_SOURCES:
        score += 0.15
    if signal.category in {"event", "culture_venue"}:
        score += 0.20
    elif signal.category == "attraction":
        score += 0.10
    score += min(signal.place_event_count, 2) * 0.15
    score += min(signal.culture_event_count, 5) * 0.04
    return min(score, 1.0)


def _accessibility_fit_score(signal: PlaceSignal) -> float | None:
    if signal.region_place_count is None:
        return None
    score = 0.60
    if signal.category in {"restaurant", "culture_venue"}:
        score += 0.08
    if signal.is_indoor is True:
        score += 0.04
    if signal.region_place_count >= 8:
        score += 0.08
    elif signal.region_place_count <= 2:
        score -= 0.05
    return min(max(score, 0.0), 1.0)


def _relative_score(
    value: float | None,
    values: Sequence[float],
    *,
    equal_default: float,
) -> float | None:
    if value is None or not values:
        return None
    minimum = min(values)
    maximum = max(values)
    if maximum == minimum:
        return equal_default
    return 0.35 + ((value - minimum) / (maximum - minimum)) * 0.60


def _inverse_relative_score(
    value: float | None,
    values: Sequence[float],
    *,
    equal_default: float,
) -> float | None:
    relative = _relative_score(value, values, equal_default=equal_default)
    if relative is None:
        return None
    if len(set(values)) <= 1:
        return relative
    return 1.0 - relative + 0.30


def _has_weather(signal: PlaceSignal) -> bool:
    return any(
        flag is not None
        for flag in (
            signal.is_rain_snow,
            signal.is_bad_dust,
            signal.is_heatwave,
            signal.is_coldwave,
            signal.is_strong_wind,
        )
    )


def _relation_exists(cur: Any, relation_name: str) -> bool:
    cur.execute("SELECT to_regclass(%s) IS NOT NULL", (relation_name,))
    row = cur.fetchone()
    if isinstance(row, dict):
        return bool(next(iter(row.values()), False))
    if isinstance(row, (tuple, list)):
        return bool(row[0]) if row else False
    return bool(row)


def _optional_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _optional_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _optional_int(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _optional_bool(value: Any) -> bool | None:
    if value is None or isinstance(value, bool):
        return value
    if isinstance(value, (int, float, Decimal)):
        return bool(value)
    text = str(value).strip().lower()
    if text in {"true", "1", "yes", "y", "실내"}:
        return True
    if text in {"false", "0", "no", "n", "실외"}:
        return False
    return None


def _optional_date_text(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, date):
        return value.isoformat()
    text = str(value).strip()
    return text or None


def _json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)
