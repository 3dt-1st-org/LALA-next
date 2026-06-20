from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Any

FORMULA_VERSION = "local-value-v2"

COMPONENT_WEIGHTS = {
    "local_spending_score": 0.22,
    "small_merchant_fit_score": 0.18,
    "demand_dispersion_score": 0.20,
    "culture_relevance_score": 0.15,
    "weather_fit_score": 0.10,
    "review_quality_score": 0.10,
    "accessibility_fit_score": 0.05,
}

_CATEGORY_PRIORS = {
    "attraction": {
        "local_spending_score": 0.62,
        "small_merchant_fit_score": 0.58,
        "demand_dispersion_score": 0.70,
        "culture_relevance_score": 0.86,
        "weather_fit_score": 0.74,
        "accessibility_fit_score": 0.68,
    },
    "restaurant": {
        "local_spending_score": 0.76,
        "small_merchant_fit_score": 0.64,
        "demand_dispersion_score": 0.66,
        "culture_relevance_score": 0.52,
        "weather_fit_score": 0.82,
        "accessibility_fit_score": 0.74,
    },
    "event": {
        "local_spending_score": 0.58,
        "small_merchant_fit_score": 0.60,
        "demand_dispersion_score": 0.73,
        "culture_relevance_score": 0.90,
        "weather_fit_score": 0.68,
        "accessibility_fit_score": 0.62,
    },
    "culture_venue": {
        "local_spending_score": 0.54,
        "small_merchant_fit_score": 0.62,
        "demand_dispersion_score": 0.76,
        "culture_relevance_score": 0.94,
        "weather_fit_score": 0.86,
        "accessibility_fit_score": 0.72,
    },
}


def build_place_score(
    *,
    components: dict[str, float | int | Decimal | None],
    data_basis: str,
    formula_version: str = FORMULA_VERSION,
    features: dict[str, Any] | None = None,
) -> dict[str, Any]:
    normalized = {
        name: _normalize_component(components.get(name))
        for name in COMPONENT_WEIGHTS
    }
    return {
        "final_score": weighted_score(normalized),
        "formula_version": formula_version,
        "components": normalized,
        "data_basis": data_basis,
        "features": features or {},
    }


def weighted_score(components: dict[str, float | None]) -> float:
    weighted_total = 0.0
    active_weight = 0.0
    for name, weight in COMPONENT_WEIGHTS.items():
        value = _normalize_component(components.get(name))
        if value is None:
            continue
        weighted_total += value * weight
        active_weight += weight
    if active_weight <= 0:
        return 0.0
    return _round_score(weighted_total / active_weight)


def baseline_place_score(*, category: str, distance_m: int) -> dict[str, Any]:
    normalized_category = category if category in _CATEGORY_PRIORS else "attraction"
    components = dict(_CATEGORY_PRIORS[normalized_category])
    components["demand_dispersion_score"] = _distance_dispersion_prior(
        base=components["demand_dispersion_score"],
        distance_m=distance_m,
    )
    components["review_quality_score"] = None
    return build_place_score(
        components=components,
        data_basis="local_curation",
        features={
            "category_prior": normalized_category,
            "distance_m": distance_m,
            "missing_signals": [
                "card_spending_snapshot",
                "franchise_business_identity",
                "review_attribute_analysis",
            ],
        },
    )


def _distance_dispersion_prior(*, base: float, distance_m: int) -> float:
    if distance_m <= 500:
        adjustment = -0.04
    elif distance_m <= 1500:
        adjustment = 0.0
    else:
        adjustment = 0.04
    return max(0.0, min(1.0, base + adjustment))


def _normalize_component(value: float | int | Decimal | None) -> float | None:
    if value is None:
        return None
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return None
    if numeric < 0:
        return 0.0
    if numeric > 1:
        return 1.0
    return _round_score(numeric)


def _round_score(value: float) -> float:
    return float(Decimal(str(value)).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP))
