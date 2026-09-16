from __future__ import annotations

from datetime import UTC, datetime
from types import SimpleNamespace

import pytest

from apps.api.app.services import (
    db_repository,
    docent_retrieval_service,
    i18n_catalog,
    intervention_decision,
    place_presentation,
    planner_service,
    public_mvp_data,
)


def test_catalog_locales_share_keys_and_required_placeholders() -> None:
    keys_by_locale = i18n_catalog.iter_catalog_keys()
    assert keys_by_locale["ko"] == keys_by_locale["en"]
    assert "{count}" in i18n_catalog.message(
        "freshness.minutes_ago", language="en", values={"count": "{count}"}
    )
    assert "{count}" in i18n_catalog.message(
        "freshness.minutes_ago", language="ko", values={"count": "{count}"}
    )


def test_catalog_namespaces_keep_organization_evidence_and_prompt_labels_distinct() -> None:
    assert i18n_catalog.source_label("tour_api", language="ko", namespace="organization") == (
        "한국관광공사"
    )
    assert i18n_catalog.source_label("tour_api", language="ko", namespace="evidence") == (
        "한국관광공사 데이터"
    )
    assert i18n_catalog.source_label("tour_api", language="en", namespace="evidence") == (
        "Korea Tourism Organization data"
    )
    assert i18n_catalog.prompt_evidence_type("tour_api") == "official tourism data"


def test_place_reason_and_freshness_preserve_cross_locale_golden_outputs() -> None:
    place = {
        "category": "culture_venue",
        "_local_activity_band": "active",
        "_has_linked_event": True,
        "is_ongoing": True,
        "distance_m": 320,
        "upstream_source": "kcisa",
    }
    weather = {"outdoor_status": "bad", "temp": 29}
    now = datetime(2026, 8, 12, 10, 30, tzinfo=UTC)

    assert (
        place_presentation.derive_place_reason(place=place, current_weather=weather, language="ko")
        == "실내활동 적합 · 로컬 소비 활발 · 진행 중인 행사 · 근접 · 문화정보원 데이터"
    )
    assert place_presentation.derive_place_reason(
        place=place, current_weather=weather, language="en"
    ) == (
        "Indoor-friendly · Active local spending · Ongoing event · Nearby · "
        "Korea Culture Information Service data"
    )
    assert place_presentation.format_freshness("2026-08-12T06:30:00Z", now, "en") == ("4 hr ago")
    assert place_presentation.format_freshness("2026-08-12T06:30:00Z", now, "ja") == ("4시간 전")


def test_common_place_presenter_matches_live_and_snapshot_facades() -> None:
    row = {"category": "culture_venue", "region_ko": "수원시", "address_ko": "경기도 수원시"}
    assert db_repository._english_display_name(row) == "Culture venue in Suwon-si"
    assert public_mvp_data._english_display_name(row) == "Culture venue in Suwon-si"
    assert db_repository._english_display_address(row) == "Suwon-si, Gyeonggi-do"
    assert public_mvp_data._english_display_address(row) == "Suwon-si, Gyeonggi-do"


def test_common_place_presenter_prefers_canonical_region_over_explicit_region_en() -> None:
    row = {
        "category": "attraction",
        "region_ko": "수원시",
        "region_en": "Custom region",
        "address_ko": "경기도 수원시",
    }

    assert place_presentation.english_display_name(row) == "Attraction in Suwon-si"


def test_place_reason_omits_non_upstream_catalog_sources() -> None:
    place = {"category": "attraction", "distance_m": 900, "upstream_source": "review"}

    assert (
        place_presentation.derive_place_reason(
            place=place,
            current_weather={},
            language="en",
        )
        == ""
    )


def test_sunny_weather_icon_remains_distinct_from_clear_for_english() -> None:
    assert i18n_catalog.weather_icon_label("sunny", language="en") == "sunny"
    assert i18n_catalog.weather_icon_label("clear", language="en") == "clear"


def test_docent_source_label_visibility_omits_retrieval_evidence_sources() -> None:
    from apps.api.app.services import docent_service

    assert docent_service._en_source_label("tour_api") == "Korea Tourism Organization data"
    assert docent_service._en_source_label("db") == "the live LALA database"
    assert docent_service._en_source_label("place_profile") is None
    assert docent_service._ko_source_label("review") is None


@pytest.mark.parametrize(
    ("bad_weather", "bad_air", "closure", "closing_soon", "expected"),
    [
        (False, False, False, False, None),
        (True, False, False, False, "bad_weather"),
        (False, True, False, False, "bad_air_quality"),
        (True, True, False, False, "bad_weather_and_air_quality"),
        (False, False, True, False, "closure_detected"),
        (True, False, True, False, "bad_weather_and_closure"),
        (False, True, True, False, "bad_air_quality_and_closure"),
        (True, True, True, False, "bad_weather_and_air_quality_and_closure"),
        (False, False, False, True, "closing_soon"),
        (True, False, False, True, "bad_weather_and_closing_soon"),
        (False, True, False, True, "bad_air_quality_and_closing_soon"),
        (True, True, False, True, "bad_weather_and_air_quality_and_closing_soon"),
        (False, False, True, True, "closure_detected"),
        (True, False, True, True, "bad_weather_and_closure"),
        (False, True, True, True, "bad_air_quality_and_closure"),
        (True, True, True, True, "bad_weather_and_air_quality_and_closure"),
    ],
)
def test_intervention_decision_exact_trigger_matrix(
    bad_weather: bool,
    bad_air: bool,
    closure: bool,
    closing_soon: bool,
    expected: str | None,
) -> None:
    decision = intervention_decision.build_decision(
        weather_status="bad" if bad_weather else "unknown",
        air_quality_status="bad" if bad_air else "unknown",
        air_quality_grade="bad" if bad_air else None,
        is_closure=closure,
        is_closing_soon=closing_soon,
        closure_factors=[{"factor": "slot_closure_state", "value": "closed"}] if closure else [],
        closing_soon_factors=[{"factor": "slot_closing_soon", "value": "within_estimated_window"}]
        if closing_soon
        else [],
    )
    assert decision.trigger_type == expected
    assert (
        planner_service._intervention_trigger_type(
            is_bad_weather=bad_weather,
            is_bad_air_quality=bad_air,
            is_closure=closure,
            is_closing_soon=closing_soon,
        )
        == expected
    )


def test_intervention_reason_selection_is_domain_owned_and_catalog_formatted() -> None:
    key, values = intervention_decision.intervention_reason_spec(
        weather_status="bad",
        air_quality_status="bad",
        closing_cause="closed",
        estimated_hours="10:00-19:00",
        candidate_name="야외 공원",
    )

    assert key == "reason.estimated.both.closed"
    assert i18n_catalog.format_intervention_template(key, language="en", values=values) == (
        "Weather and air quality are both poor. This slot is outside the estimated hours "
        "(10:00-19:00) for 야외 공원; the actual opening status needs a check."
    )


def test_alternative_selection_preserves_first_match_and_unknown_indoor_exclusion() -> None:
    places = [
        {"place_id": "original", "name": "original", "is_indoor": True},
        {"place_id": "unknown", "name": "unknown"},
        {"place_id": "outside", "name": "outside", "is_indoor": False},
        {"place_id": "inside", "name": "inside", "is_indoor": True},
    ]
    slot = planner_service._find_indoor_alternative(
        place_candidates=places,
        exclude_place_id="original",
        language="en",
        weather_hint="bad",
        unavailable_reason="Not enough nearby options",
    )
    assert slot is not None
    assert slot["place"]["place_id"] == "inside"


def test_docent_retrieval_service_owns_rerank_choice(monkeypatch) -> None:
    calls: dict[str, object] = {}
    monkeypatch.setattr(
        docent_retrieval_service,
        "get_settings",
        lambda: SimpleNamespace(rag_retrieval_mode="hybrid"),
    )
    monkeypatch.setattr(docent_retrieval_service.ai_service, "rerank_ai_enabled", lambda s: True)
    monkeypatch.setattr(
        docent_retrieval_service.ai_service,
        "rerank_docent_candidates",
        lambda prompt: '{"reranked_ids":[]}',
    )

    def fake_hybrid(**kwargs):
        calls.update(kwargs)
        return {
            "rows": [{"source_type": "place_profile", "source_id": "p1"}],
            "retrieval": {"mode": "hybrid", "reranker": "mini"},
        }

    monkeypatch.setattr(
        docent_retrieval_service.db_repository,
        "fetch_docent_knowledge_context_hybrid_result",
        fake_hybrid,
    )
    result = docent_retrieval_service.fetch_grounding_context(
        place_id="p1",
        query="query",
        category="attraction",
        language="en",
    )

    assert result["mode"] == "hybrid"
    assert calls["completion_fn"] is docent_retrieval_service.ai_service.rerank_docent_candidates
    assert "reranker" not in calls
