from __future__ import annotations

from apps.api.app.services import recommendation_scoring


def test_weighted_score_renormalizes_when_review_signal_is_missing():
    score = recommendation_scoring.weighted_score(
        {
            "local_spending_score": 0.8,
            "demand_dispersion_score": 0.6,
            "weather_fit_score": 0.7,
            "review_quality_score": None,
            "culture_relevance_score": 0.9,
        }
    )

    assert score == 0.7412


def test_demo_place_score_marks_fallback_basis_and_missing_signals():
    score = recommendation_scoring.demo_place_score(category="attraction", distance_m=420)

    assert score["formula_version"] == recommendation_scoring.FORMULA_VERSION
    assert score["data_basis"] == "demo_fallback"
    assert 0 < score["final_score"] <= 1
    assert score["components"]["review_quality_score"] is None
    assert "card_spending_snapshot" in score["features"]["missing_signals"]
