from __future__ import annotations

import json

from apps.api.app.core.errors import ServiceError
from apps.api.app.services import docent_quality_qa
from apps.api.app.tools import run_docent_quality_qa


def test_docent_quality_qa_plan_names_canonical_inputs(capsys):
    exit_code = run_docent_quality_qa.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["target"] == "output/local/docent-qa"
    assert payload["db_mutation"] is False
    assert payload["file_write"] is False
    assert "travel.places" in payload["input_relations"]
    assert "travel.docent_scripts" in payload["input_relations"]
    assert "rag.knowledge_chunks" in payload["input_relations"]
    assert payload["manual_thresholds"]["blocker_count"] == 0


def test_representative_selection_keeps_category_coverage():
    candidates = []
    for category in docent_quality_qa.CATEGORY_ORDER:
        for index in range(12):
            candidates.append(
                docent_quality_qa.DocentQaCandidate(
                    place_id=f"{category}-{index}",
                    name_ko=f"{category} 장소 {index}",
                    category=category,
                    region_name_ko="수원시" if index % 2 == 0 else "서울특별시",
                    final_score=1 - index / 20,
                    rag_chunk_count=index % 3,
                )
            )

    selected = docent_quality_qa.select_representative_candidates(
        candidates,
        limit=30,
    )
    counts = {}
    for candidate in selected:
        counts[candidate.category] = counts.get(candidate.category, 0) + 1

    assert len(selected) == 30
    assert counts["attraction"] >= 8
    assert counts["restaurant"] >= 8
    assert counts["event"] >= 6
    assert counts["culture_venue"] >= 8


def test_docent_precheck_flags_raw_score_mock_and_missing_pm_context():
    candidate = docent_quality_qa.DocentQaCandidate(
        place_id="place-1",
        name_ko="화성행궁",
        category="attraction",
        region_name_ko="수원시",
        rag_chunk_count=2,
        weather_pm10=42,
        weather_pm25=21,
        script_source_method="live_ai",
        script=(
            "화성행궁은 데모 안내입니다. final_score 0.91 기준으로 추천합니다. "
            "근처 코스로 이동해 보세요."
        ),
    )

    result = docent_quality_qa.evaluate_docent_script(candidate, language="ko")

    assert result.blocker is True
    assert "fallback_or_mock_wording" in result.issue_tags
    assert "raw_score_leakage" in result.issue_tags
    assert "missing_pm_context" in result.issue_tags
    assert result.auto_precheck_score is not None
    assert result.auto_precheck_score < 80


def test_docent_precheck_passes_grounded_korean_route_copy():
    candidate = docent_quality_qa.DocentQaCandidate(
        place_id="place-2",
        name_ko="호암미술관",
        category="culture_venue",
        region_name_ko="용인시",
        rag_chunk_count=3,
        dynamic_rag_chunk_count=1,
        review_organic_mention_count=4,
        weather_pm10=30,
        weather_pm25=12,
        script_source_method="live_ai",
        script=(
            "호암미술관은 전시와 정원이 함께 이어지는 문화 공간입니다. "
            "오늘은 미세먼지 PM10 30, 초미세먼지 PM2.5 12 수준이라 야외 정원 산책도 "
            "무리 없이 넣을 수 있습니다. 관람 뒤에는 주변 로컬 코스로 이동해 여유를 "
            "이어가 보세요."
        ),
    )

    result = docent_quality_qa.evaluate_docent_script(candidate, language="ko")

    assert result.blocker is False
    assert "missing_pm_context" not in result.issue_tags
    assert "route_action_missing" not in result.issue_tags
    assert "language_purity" not in result.issue_tags
    assert result.auto_precheck_score is not None
    assert result.auto_precheck_score >= 85


def test_build_records_marks_missing_script_as_generation_needed():
    candidate = docent_quality_qa.DocentQaCandidate(
        place_id="place-3",
        name_ko="스크립트 없는 장소",
        category="event",
        region_name_ko="서울특별시",
    )

    records = docent_quality_qa.build_docent_qa_records(
        [candidate],
        language="ko",
        mode="brief",
        qa_date="2026-06-23",
    )

    assert records[0]["qa_date"] == "2026-06-23"
    assert records[0]["auto_precheck"]["auto_precheck_score"] is None
    assert records[0]["auto_precheck"]["blocker"] is False
    assert records[0]["auto_precheck"]["issue_tags"] == ["needs_script_generation"]


def test_generate_docent_scripts_for_qa_populates_local_candidate(monkeypatch):
    requests = []

    def fake_generate_script(request):
        requests.append(request)
        return {
            "script": (
                "호암미술관은 전시와 정원을 함께 살필 수 있는 문화 공간입니다. "
                "오늘은 미세먼지 PM10 30, 초미세먼지 PM2.5 12 수준이라 "
                "관람 전후 주변 로컬 코스로 이동하기 좋습니다."
            ),
            "source": "rule_based_curation",
            "generated_at": "2026-06-23T09:00:00+00:00",
        }

    monkeypatch.setattr(
        "apps.api.app.services.docent_service.generate_script",
        fake_generate_script,
    )
    candidate = docent_quality_qa.DocentQaCandidate(
        place_id="place-4",
        name_ko="호암미술관",
        category="culture_venue",
        region_name_ko="용인시",
        primary_source="tour_api",
        final_score=0.9,
        local_spending_score=0.8,
        small_merchant_fit_score=0.7,
        weather_temperature_c=21.6,
        weather_pm10=30,
        weather_pm25=12,
    )

    generated = docent_quality_qa.generate_docent_scripts_for_qa(
        [candidate],
        language="ko",
        mode="brief",
    )

    assert generated[0].script_source_method == "rule_based_curation"
    assert generated[0].script_generated_at == "2026-06-23T09:00:00+00:00"
    assert generated[0].script_generation_error is None
    assert "호암미술관" in (generated[0].script or "")
    assert requests[0].source == "db"
    assert requests[0].place_name == "호암미술관"
    assert requests[0].weather_temp == "21.6"
    assert requests[0].dust_pm10 == "30"
    assert requests[0].dust_pm25 == "12"
    assert requests[0].dust_pm10_grade == "좋음"
    assert requests[0].dust_pm25_grade == "좋음"


def test_generate_docent_scripts_for_qa_keeps_batch_on_generation_error(monkeypatch):
    def fail_generation(request):
        raise ServiceError(
            status_code=422,
            code="DOCENT_GROUNDING_REQUIRED",
            message="Live DB docent scripts require verified place grounding.",
            retryable=False,
        )

    monkeypatch.setattr(
        "apps.api.app.services.docent_service.generate_script",
        fail_generation,
    )
    candidate = docent_quality_qa.DocentQaCandidate(
        place_id="place-5",
        name_ko="근거 부족 장소",
        category="event",
    )

    generated = docent_quality_qa.generate_docent_scripts_for_qa(
        [candidate],
        language="ko",
        mode="brief",
    )
    records = docent_quality_qa.build_docent_qa_records(
        generated,
        language="ko",
        mode="brief",
        qa_date="2026-06-23",
    )
    summary = docent_quality_qa.summarize_qa_records(records)

    assert generated[0].script is None
    assert generated[0].script_generation_error.startswith("DOCENT_GROUNDING_REQUIRED:")
    assert records[0]["script_generation_error"].startswith("DOCENT_GROUNDING_REQUIRED:")
    assert summary["generation_error_count"] == 1
