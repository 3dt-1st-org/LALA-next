from __future__ import annotations

import re
from datetime import date
from pathlib import Path

import pytest
from pydantic import ValidationError

from apps.api.app.schemas.local_signals import (
    LocalSignalDraftCreate,
    LocalSignalFeedContext,
    LocalSignalPublicItem,
    LocalSignalTranslation,
)
from apps.api.app.services import canonical_sql

ROOT = Path(__file__).resolve().parents[3]
LOCAL_SIGNALS_SQL = ROOT / "sql" / "canonical" / "063_local_signals_contract.sql"


def test_local_signals_migration_is_next_ordered_additive_contract():
    plan = canonical_sql.load_canonical_sql_plan()

    assert plan.ok is True
    assert [item.name for item in plan.files][-5:] == [
        "063_local_signals_contract.sql",
        "064_planning_action_tables.sql",
        "065_user_travel_preferences.sql",
        "066_trip_library_and_visit_feedback.sql",
        "067_community_post_reports.sql",
    ]
    sql = LOCAL_SIGNALS_SQL.read_text(encoding="utf-8")
    assert not re.search(r"\b(DROP|TRUNCATE|DELETE\s+FROM)\b", sql, re.IGNORECASE)
    assert "CREATE TABLE IF NOT EXISTS community.local_signals" in sql
    assert "CREATE OR REPLACE VIEW community.local_signal_public" in sql


def test_local_signals_schema_covers_policy_lifecycle_and_safe_boundaries():
    sql = LOCAL_SIGNALS_SQL.read_text(encoding="utf-8")

    for table in (
        "local_signals",
        "local_signal_places",
        "local_signal_routes",
        "local_signal_translations",
        "local_signal_reactions",
        "local_signal_comments",
        "local_signal_saves",
        "local_signal_reports",
        "local_signal_moderation_actions",
        "local_signal_capabilities",
        "local_signal_aggregate_eligibility",
    ):
        assert f"CREATE TABLE IF NOT EXISTS community.{table}" in sql

    for policy in (
        "local_signals_kind_check",
        "local_signals_status_check",
        "local_signals_moderation_state_check",
        "local_signals_visibility_check",
        "local_signals_locality_check",
        "local_signals_disclosure_check",
        "local_signal_aggregate_eligible_gate",
    ):
        assert policy in sql

    assert "REFERENCES identity.users (issuer, subject)" in sql
    assert "ON DELETE SET NULL" in sql
    assert "token_sha256 bytea" in sql
    assert "octet_length(token_sha256) = 32" in sql

    public_view_sql = sql.split("CREATE OR REPLACE VIEW community.local_signal_public", 1)[1]
    public_view_sql = public_view_sql.split(
        "CREATE OR REPLACE VIEW community.local_signal_aggregate_candidates", 1
    )[0]
    assert "author_issuer" not in public_view_sql
    assert "author_subject" not in public_view_sql
    assert not re.search(r"\b(latitude|longitude|lat|lng)\b", public_view_sql, re.IGNORECASE)
    assert "provider" not in public_view_sql
    assert "post_url" not in public_view_sql

    aggregate_view_sql = sql.split(
        "CREATE OR REPLACE VIEW community.local_signal_aggregate_candidates", 1
    )[1]
    assert "body" not in aggregate_view_sql
    assert "author_issuer" not in aggregate_view_sql
    assert "author_subject" not in aggregate_view_sql
    assert "safe_summary_hash" in aggregate_view_sql


def test_draft_schema_has_no_client_identity_or_exact_location_fields():
    fields = set(LocalSignalDraftCreate.model_fields)
    assert not fields.intersection(
        {
            "author_id",
            "author_issuer",
            "author_subject",
            "user_id",
            "lat",
            "lng",
            "latitude",
            "longitude",
        }
    )

    draft = LocalSignalDraftCreate(
        kind="place_tip",
        source_language="Korean",
        title="  A short tip  ",
        body="  Visit before sunset.  ",
        locality_level="district",
        locality_code="suwon:paldalmun",
        commercial_disclosure="none",
        observation_date=date(2026, 7, 26),
        place_links=[{"place_id": "place-1"}],
    )
    assert draft.source_language == "ko"
    assert draft.title == "A short tip"
    assert draft.body == "Visit before sunset."


def test_draft_schema_rejects_coordinates_unknown_language_and_duplicate_links():
    base = {
        "kind": "place_tip",
        "source_language": "ko",
        "title": "Tip",
        "body": "Body",
        "observation_date": date(2026, 7, 26),
    }

    with pytest.raises(ValidationError):
        LocalSignalDraftCreate(**base, lat=37.2)
    with pytest.raises(ValidationError):
        LocalSignalDraftCreate(**{**base, "source_language": "ja"})
    with pytest.raises(ValidationError):
        LocalSignalDraftCreate(
            **base,
            place_links=[
                {"place_id": "place-1", "relation": "primary"},
                {"place_id": "place-1", "relation": "primary"},
            ],
        )


def test_translation_contract_requires_provenance_and_single_language_target():
    translation = LocalSignalTranslation(
        source_language="ko",
        target_language="en",
        body="A translated tip.",
        method="machine",
        translator_version="translation-policy-v1",
        source_content_hash="a" * 64,
        provenance="machine_reviewed",
        review_state="available",
    )
    assert translation.target_language == "en"
    with pytest.raises(ValidationError):
        LocalSignalTranslation(
            **translation.model_dump(exclude={"target_language"}),
            target_language="ko",
        )


def test_public_response_schema_excludes_identity_and_internal_score_fields():
    fields = set(LocalSignalPublicItem.model_fields)
    assert not fields.intersection(
        {
            "author_id",
            "author_issuer",
            "author_subject",
            "user_id",
            "exact_location",
            "latitude",
            "longitude",
            "score",
            "internal_score",
        }
    )

    context = LocalSignalFeedContext(language="en", locality_level="city", sort="recent")
    assert context.language == "en"
