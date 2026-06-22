from __future__ import annotations

import json

from apps.api.app.services import docent_qa
from apps.api.app.tools import plan_docent_qa


def test_docent_qa_plan_is_non_mutating(capsys):
    exit_code = plan_docent_qa.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["db_mutation"] is False
    assert payload["target"] == "manual_docent_qa_record"
    assert "travel.places" in payload["source"]
    assert "factual_grounding" in payload["rubric"]


def test_docent_qa_selection_balances_categories_and_regions():
    candidates = []
    for category in ("attraction", "culture_venue", "restaurant", "event"):
        for index in range(8):
            candidates.append(
                docent_qa.DocentQACandidate(
                    place_id=f"{category}-{index}",
                    name_ko=f"{category} {index}",
                    name_en=None,
                    category=category,
                    region_name_ko="중구" if index % 2 == 0 else "수원시",
                    primary_source="tour_api",
                    is_indoor=index % 3 == 0,
                    has_image_url=index % 2 == 0,
                    final_score=0.7 + index * 0.01,
                    local_spending_score=0.6,
                    small_merchant_fit_score=0.5,
                    review_quality_score=0.65 if index == 0 else None,
                    rag_chunk_count=2,
                    place_profile_chunk_count=1,
                    place_mention_chunk_count=1 if index == 0 else 0,
                    culture_event_chunk_count=0,
                    weather_context_chunk_count=0,
                    has_weather_observation=index % 2 == 0,
                    missing_signals=(),
                )
            )

    selected = docent_qa.select_docent_qa_candidates(candidates, limit=30)
    plan = docent_qa.build_docent_qa_plan(selected)
    coverage = plan.coverage

    assert len(selected) == 30
    assert set(coverage["category_counts"]) == {
        "attraction",
        "culture_venue",
        "restaurant",
        "event",
    }
    assert coverage["has_seoul_and_gyeonggi"] is True
    assert coverage["passes_sample_size_target"] is True


def test_docent_qa_evaluation_flags_mock_and_raw_score_leaks():
    result = docent_qa.evaluate_docent_script(
        script="demo placeholder 입니다. 추천 점수는 0.92입니다.",
        language="ko",
        source="rule_based_curation",
        grounding_count=0,
        grounding_sources=[],
        weather_context_expected=True,
    )

    assert result["blocker"] is True
    assert "internal_or_mock_wording" in result["blockers"]
    assert "raw_score_leak" in result["blockers"]
    assert "missing_grounding" in result["blockers"]
    assert result["score_total"] < 50
