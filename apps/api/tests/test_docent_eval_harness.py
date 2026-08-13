"""Tests for the V4-C offline docent QA eval harness.

Covers: fixture schema validity, harness pass/fail on the committed fixture, category coverage,
the honest-empty path (empty/unavailable, no fabricated content), single-language rendering,
and the boundary-mock guarantee that a live OpenAI client is never constructed.
"""

from __future__ import annotations

import os

import pytest

from apps.api.app.services import docent_eval

REQUIRED_KEYS = {
    "place_id",
    "category",
    "region_ko",
    "region_en",
    "place_name_ko",
    "place_name_en",
    "language_samples",
    "grounding_anchors",
    "expect_nonempty",
}


@pytest.fixture()
def fixture_places() -> list[dict]:
    return docent_eval.load_fixture()


# --- Fixture schema -----------------------------------------------------------


def test_fixture_count_within_representative_range(fixture_places: list[dict]) -> None:
    assert 30 <= len(fixture_places) <= 50, len(fixture_places)


def test_fixture_place_ids_all_use_eval_prefix(fixture_places: list[dict]) -> None:
    assert fixture_places, "fixture must not be empty"
    assert all(p["place_id"].startswith("eval_") for p in fixture_places)


def test_fixture_covers_all_four_categories(fixture_places: list[dict]) -> None:
    categories = {p["category"] for p in fixture_places}
    assert categories == set(docent_eval.CATEGORIES)


def test_fixture_has_at_least_one_honest_empty_case(fixture_places: list[dict]) -> None:
    honest_empty = [p for p in fixture_places if not p["expect_nonempty"]]
    assert len(honest_empty) >= 1


def test_fixture_objects_have_required_schema(fixture_places: list[dict]) -> None:
    for place in fixture_places:
        assert REQUIRED_KEYS.issubset(place.keys()), place["place_id"]
        assert place["category"] in docent_eval.CATEGORIES
        assert place["language_samples"]
        for language in place["language_samples"]:
            assert language in {"ko", "en"}
        assert isinstance(place["grounding_anchors"], list)


# --- Harness pass/fail on the committed fixture -------------------------------


def test_eval_report_passes_on_committed_fixture(fixture_places: list[dict]) -> None:
    with docent_eval.offline_openai_guard():
        report = docent_eval.evaluate_docent(fixture_places)
    assert report.passed, report.failures
    assert report.failures == []
    # The rule-based path was the only source used; no live client was constructed.
    assert report.live_client_constructions == 0


def test_eval_category_counts_cover_every_category(fixture_places: list[dict]) -> None:
    with docent_eval.offline_openai_guard():
        report = docent_eval.evaluate_docent(fixture_places)
    for category in docent_eval.CATEGORIES:
        assert report.category_counts[category] > 0, category


def test_eval_report_total_matches_fixture(fixture_places: list[dict]) -> None:
    with docent_eval.offline_openai_guard():
        report = docent_eval.evaluate_docent(fixture_places)
    assert report.total_places == len(fixture_places)


# --- Honest-empty path --------------------------------------------------------


def test_honest_empty_fixture_builds_context_free_request(fixture_places: list[dict]) -> None:
    honest_empty = next(p for p in fixture_places if not p["expect_nonempty"])
    request = docent_eval.build_request(honest_empty, "ko")
    # No request context and no score context -> the service must decline.
    assert request.place_name is None
    assert request.region_ko is None
    assert request.region_en is None
    assert request.final_score is None
    assert request.local_spending_score is None


def test_honest_empty_yields_unavailable_no_fabrication(fixture_places: list[dict]) -> None:
    honest_empty = next(p for p in fixture_places if not p["expect_nonempty"])
    with docent_eval.offline_openai_guard():
        result = docent_eval.evaluate_place(honest_empty)
    assert result.expect_met is True
    assert result.languages, "honest-empty must still evaluate each language without crashing"
    for language_result in result.languages:
        assert language_result.unavailable is True
        assert language_result.script == ""
        assert language_result.nonempty is False
        assert language_result.no_placeholder is True
        assert language_result.no_internal_id_leak is True
        # The docent service surfaces its structured unavailable code rather than crashing.
        assert language_result.reason == "DOCENT_CONTEXT_REQUIRED"


# --- Non-empty places: single-language KO/EN ---------------------------------


def test_nonempty_places_render_single_language_scripts(fixture_places: list[dict]) -> None:
    nonempty = [p for p in fixture_places if p["expect_nonempty"]]
    assert nonempty
    with docent_eval.offline_openai_guard():
        for place in nonempty:
            result = docent_eval.evaluate_place(place)
            assert result.expect_met is True, place["place_id"]
            assert result.languages
            for language_result in result.languages:
                assert language_result.nonempty is True
                assert language_result.single_language_ok is True, place["place_id"]
                assert language_result.source == "rule_based_curation"
                assert language_result.no_internal_id_leak is True
                assert language_result.no_placeholder is True


# --- Boundary-mock guarantees -------------------------------------------------


def test_offline_guard_clears_live_ai_flag_and_installs_fake_module(monkeypatch) -> None:
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    import sys

    original_module = sys.modules.get("openai")
    with docent_eval.offline_openai_guard():
        assert os.environ.get("LALA_ENABLE_LIVE_AI") is None
        assert sys.modules["openai"].OpenAI is docent_eval._FakeOpenAI
        assert docent_eval._LIVE_CLIENT_STATE["constructed"] == 0
    # Guard restores state on exit.
    assert os.environ.get("LALA_ENABLE_LIVE_AI") == "true"
    if original_module is not None:
        assert sys.modules.get("openai") is original_module


def test_live_client_construction_marks_report_failed(monkeypatch) -> None:
    """If a live OpenAI client were ever constructed, the report must fail loudly."""
    monkeypatch.setitem(docent_eval._LIVE_CLIENT_STATE, "constructed", 1)
    places = docent_eval.load_fixture()
    report = docent_eval.evaluate_docent(places[:3])
    assert report.passed is False
    assert any("live OpenAI client constructed" in failure for failure in report.failures)


def test_run_docent_eval_cli_exits_zero_on_pass(fixture_places: list[dict], tmp_path) -> None:
    from apps.api.app.tools import run_docent_eval

    fixture_path = tmp_path / "fixture.json"
    import json

    fixture_path.write_text(json.dumps(fixture_places, ensure_ascii=False), encoding="utf-8")
    output_path = tmp_path / "report.json"
    exit_code = run_docent_eval.main(["--fixture", str(fixture_path), "--output", str(output_path)])
    assert exit_code == 0
    assert output_path.exists()
    import json as _json

    written = _json.loads(output_path.read_text(encoding="utf-8"))
    assert written["passed"] is True
