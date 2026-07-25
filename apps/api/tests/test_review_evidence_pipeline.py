"""Focused contract tests for the review-evidence-pipeline clean-room slice.

Covers the four bounded improvements against the mission's non-negotiables:
  A. non-organic/ad exclusion at the governed boundary (never a positive mention)
  B. confidence-routed mini-model selective recheck (bulk=mini-nano, recheck=mini)
  C. governed aggregate -> RAG place_mention handoff (no raw text, replay-safe)
  D. community_post RAG chunk never embeds the raw post body/title/url

No live AI calls (a fake OpenAI client is injected). No live DB.
"""

from __future__ import annotations

import json
from datetime import UTC, date, datetime
from types import SimpleNamespace

from apps.api.app.services import rag_index
from apps.api.app.services import review_attribute_batch as batch
from apps.api.app.services import review_ingest_governance as governance
from apps.api.app.services import review_rag_handoff as handoff

SOURCE_NAME = "fictional_licensed_review_provider"
PROVIDER = "fictional_provider"
TERMS_VERSION = "fictional-license-v1"
RECEIVED_AT = datetime(2026, 7, 25, 9, 0, tzinfo=UTC)


def _registration() -> governance.ReviewSourceRegistration:
    return governance.ReviewSourceRegistration(
        source_name=SOURCE_NAME,
        provider=PROVIDER,
        license_class="licensed",
        terms_version=TERMS_VERSION,
        collection_method="licensed_api_discovery",
        retention_policy="metadata_and_aggregates_only",
        redaction_policy="no_raw_text_no_pii",
    )


def _record(
    external_key: str,
    *,
    content_sha256: str | None = "a" * 64,
    is_organic: bool = True,
    non_organic_reason: str | None = None,
) -> dict[str, object]:
    record: dict[str, object] = {
        "source_name": SOURCE_NAME,
        "provider": PROVIDER,
        "external_key": external_key,
        "license_class": "licensed",
        "terms_version": TERMS_VERSION,
        "content_sha256": content_sha256,
        "received_at": RECEIVED_AT,
        "category": "restaurant",
        "match_confidence": 0.92,
        "normalized_attributes": {"taste": 0.8, "service": 0.7},
        "is_organic": is_organic,
        "non_organic_reason": non_organic_reason,
    }
    return record


# ---------------------------------------------------------------------------
# A. Non-organic / advertising exclusion at the governed boundary
# ---------------------------------------------------------------------------


def test_non_organic_record_is_quarantined_not_accepted():
    valid, quarantined = governance.classify_review_records(
        registration=_registration(),
        records=[_record("post-ad", is_organic=False, non_organic_reason="advertising")],
    )

    assert valid == ()
    assert len(quarantined) == 1
    entry = quarantined[0]
    assert entry.reason_code == "terms_violation_non_organic"
    assert entry.reason_category == "terms_violation"
    assert entry.provider == PROVIDER  # registered identity, not raw
    assert entry.safe_metadata.non_organic_reason == "advertising"


def test_organic_record_passes_through_unchanged():
    valid, quarantined = governance.classify_review_records(
        registration=_registration(),
        records=[_record("post-ok")],  # is_organic defaults to True
    )

    assert len(valid) == 1
    assert valid[0].external_key == "post-ok"
    assert quarantined == ()


def test_mixed_batch_quarantines_only_non_organic():
    records = [
        _record("post-ok"),
        _record("post-ad", is_organic=False, non_organic_reason="sponsored"),
        _record("post-ok-2"),
    ]
    valid, quarantined = governance.classify_review_records(
        registration=_registration(), records=records
    )

    assert {item.external_key for item in valid} == {"post-ok", "post-ok-2"}
    assert len(quarantined) == 1
    assert quarantined[0].external_key == "post-ad"


def test_non_organic_quarantine_entry_carries_no_raw_text():
    _, quarantined = governance.classify_review_records(
        registration=_registration(),
        records=[_record("post-ad", is_organic=False, non_organic_reason="incentivized")],
    )

    entry = quarantined[0]
    governance.enforce_no_raw_review_text(entry.model_dump(), label="quarantine_entry")
    governance.enforce_no_raw_review_text(
        entry.safe_metadata.model_dump(exclude_none=True), label="safe_metadata"
    )


def test_non_organic_reason_code_is_in_reason_spec_and_template_carries_no_raw():
    assert "terms_violation_non_organic" in governance.REASON_SPEC
    category, reason = governance.REASON_SPEC["terms_violation_non_organic"]
    assert category == "terms_violation"
    for forbidden in ("body", "title", "post_url", "raw_text"):
        assert forbidden not in reason


def test_contradictory_organic_record_with_reason_is_rejected():
    # is_organic=True while declaring a non_organic_reason is contradictory.
    valid, quarantined = governance.classify_review_records(
        registration=_registration(),
        records=[_record("post-x", is_organic=True, non_organic_reason="advertising")],
    )

    assert valid == ()
    assert len(quarantined) == 1
    entry = quarantined[0]
    assert entry.reason_code == "schema_invalid_contradictory_organic"
    assert entry.reason_category == "schema_invalid"


def test_non_organic_record_without_bounded_reason_is_rejected():
    # is_organic=False must carry a bounded non_organic_reason; otherwise reject.
    valid, quarantined = governance.classify_review_records(
        registration=_registration(),
        records=[_record("post-y", is_organic=False)],  # no reason
    )

    assert valid == ()
    assert len(quarantined) == 1
    entry = quarantined[0]
    assert entry.reason_code == "schema_invalid_non_organic_reason_missing"
    assert entry.reason_category == "schema_invalid"
    governance.enforce_no_raw_review_text(entry.model_dump(), label="quarantine_entry")


# ---------------------------------------------------------------------------
# B. Confidence routing + selective mini-model recheck (injectable client)
# ---------------------------------------------------------------------------


def _fake_settings(
    *,
    batch_model: str = "gpt-5.4-nano",
    recheck_model: str = "gpt-5.4-mini",
) -> SimpleNamespace:
    # Standard OpenAI only (never Azure). All tests below inject a fake client,
    # so the key is never read or exposed; left empty to avoid secret-like noise.
    return SimpleNamespace(
        openai_review_batch_model=batch_model,
        openai_review_recheck_model=recheck_model,
        openai_api_key="",
        openai_base_url="https://api.openai.com/v1",
        enable_live_ai=True,
    )


def _enrichment(mention_id: str, *, confidence: float) -> batch.ReviewAttributeEnrichment:
    return batch.ReviewAttributeEnrichment(
        mention_id=mention_id,
        schema_version=batch.PROMPT_VERSION,
        sentiment_score=0.2,
        sentiment_confidence=confidence,
        attribute_scores={"taste": 0.5},
        attribute_confidence_avg=confidence,
        evidence_terms={},
        summary_ko=None,
        reason=None,
        source_method="openai",
    )


def _candidate(mention_id: str = "m1") -> batch.ReviewAttributeCandidate:
    return batch.ReviewAttributeCandidate(
        mention_id=mention_id,
        week_start=date(2026, 7, 20),
        place_id="place-1",
        place_name_ko="테스트 식당",
        provider=PROVIDER,
        category="restaurant",
        mention_count=5,
        organic_mention_count=5,
        sentiment_score=0.2,
        attributes={"top_terms": []},
        posts=(),
    )


def test_route_low_confidence_picks_only_uncertain():
    enrichments = [
        _enrichment("low", confidence=0.4),
        _enrichment("border", confidence=0.59),
        _enrichment("high", confidence=0.9),
    ]

    routed = batch.route_low_confidence_enrichments(enrichments)

    assert {item.mention_id for item in routed} == {"low", "border"}
    assert all(item.mention_id != "high" for item in routed)


def test_bulk_uses_nano_and_recheck_uses_mini_with_injected_client(monkeypatch):
    monkeypatch.setattr(batch, "get_settings", lambda: _fake_settings())

    recorded_models: list[str] = []

    class _FakeClient:
        def __init__(self, responses_by_model: dict[str, str]) -> None:
            self._responses = responses_by_model

        @property
        def chat(self):
            return self

        @property
        def completions(self):
            return self

        def create(self, *, model: str, **kwargs):  # noqa: ANN001
            recorded_models.append(model)
            content = self._responses.get(model, '{"results": []}')
            message = SimpleNamespace(content=content)
            choice = SimpleNamespace(message=message)
            return SimpleNamespace(choices=[choice])

    bulk_json = json.dumps(
        {
            "results": [
                {
                    "mention_id": "m1",
                    "attribute_scores": {"taste": 0.5},
                    "attribute_confidence_avg": 0.4,
                    "sentiment_confidence": 0.4,
                    "sentiment_score": 0.2,
                    "evidence_terms": {},
                }
            ]
        },
        ensure_ascii=False,
    )
    recheck_json = json.dumps(
        {
            "results": [
                {
                    "mention_id": "m1",
                    "attribute_scores": {"taste": 0.85},
                    "attribute_confidence_avg": 0.9,
                    "sentiment_confidence": 0.9,
                    "sentiment_score": 0.6,
                    "evidence_terms": {},
                }
            ]
        },
        ensure_ascii=False,
    )
    fake = _FakeClient(
        {
            "gpt-5.4-nano": bulk_json,
            "gpt-5.4-mini": recheck_json,
        }
    )

    candidates = [_candidate("m1")]
    bulk = batch.generate_ai_enrichments(
        candidates=candidates,
        batch_size=10,
        retry_attempts=1,
        retry_delay_sec=0.0,
        client=fake,
    )
    assert len(bulk) == 1
    assert bulk[0].attribute_confidence_avg == 0.4  # low confidence -> routed

    merged = batch.generate_ai_recheck(
        candidates=candidates,
        enrichments=bulk,
        batch_size=10,
        retry_attempts=1,
        retry_delay_sec=0.0,
        client=fake,
    )

    # Bulk lane used gpt-5.4-nano; selective recheck used gpt-5.4-mini -- no live AI.
    assert "gpt-5.4-nano" in recorded_models
    assert "gpt-5.4-mini" in recorded_models
    # The routed row was upgraded by the recheck lane, id preserved.
    assert merged[0].mention_id == "m1"
    assert merged[0].source_method == "openai_recheck"
    assert merged[0].attribute_confidence_avg == 0.9


def test_recheck_leaves_high_confidence_rows_untouched(monkeypatch):
    monkeypatch.setattr(batch, "get_settings", lambda: _fake_settings())

    recorded_models: list[str] = []

    class _FakeClient:
        @property
        def chat(self):
            return self

        @property
        def completions(self):
            return self

        def create(self, *, model: str, **kwargs):  # noqa: ANN001
            recorded_models.append(model)
            message = SimpleNamespace(content='{"results": []}')
            return SimpleNamespace(choices=[SimpleNamespace(message=message)])

    bulk = [
        _enrichment("m1", confidence=0.95),  # high confidence -> not routed
    ]
    merged = batch.generate_ai_recheck(
        candidates=[_candidate("m1")],
        enrichments=bulk,
        batch_size=10,
        retry_attempts=1,
        retry_delay_sec=0.0,
        client=_FakeClient(),
    )

    assert merged == bulk  # unchanged
    assert recorded_models == []  # no recheck call for high-confidence rows


def test_recheck_is_noop_when_selector_returns_empty(monkeypatch):
    # Defensive guard: a selector override that returns "" makes generate_ai_recheck
    # a no-op that keeps the bulk result (non-fatal). Note this cannot happen via
    # normal config -- selected_review_recheck_model always resolves to gpt-5.4-mini
    # even when the env is empty -- so this exercises the guard directly.
    monkeypatch.setattr(
        batch,
        "get_settings",
        lambda: _fake_settings(recheck_model=""),
    )
    monkeypatch.setattr(batch, "selected_review_recheck_model", lambda settings=None: "")

    bulk = [_enrichment("m1", confidence=0.3)]  # would route, but no mini model
    merged = batch.generate_ai_recheck(
        candidates=[_candidate("m1")],
        enrichments=bulk,
        batch_size=10,
        retry_attempts=1,
        retry_delay_sec=0.0,
        client=None,  # also no client -> must stay non-fatal
    )

    assert merged == bulk  # bulk result kept; recheck unavailable is non-fatal


# ---------------------------------------------------------------------------
# C. Governed aggregate -> RAG place_mention handoff (no raw text, replay-safe)
# ---------------------------------------------------------------------------


def _aggregate(*, category: str = "restaurant") -> governance.ApprovedReviewAggregate:
    return governance.ApprovedReviewAggregate(
        source_name=SOURCE_NAME,
        aggregate_key="sha256:abcdef0123456789",
        category=category,
        match_confidence=0.92,
        mention_count=5,
        organic_mention_count=4,
        sentiment_score=0.3,
        attribute_scores={"taste": 0.8, "service": 0.7},
    )


def test_aggregate_to_place_mention_chunk_has_no_raw_text():
    chunk = handoff.aggregate_to_place_mention_chunk(
        _aggregate(), place_id="place-1", place_name_ko="테스트 식당"
    )

    assert chunk.source_type == "place_mention"
    assert chunk.source_table == handoff.GOVERNED_EVIDENCE_SOURCE_TABLE
    # Metadata is raw-text-clean (defended inside the builder).
    governance.enforce_no_raw_review_text(chunk.metadata or {}, label="chunk_metadata")
    # Body carries aggregate signals only; no raw review text is read or embedded.
    assert "테스트 식당" in chunk.body_ko
    assert "속성 점수는" in chunk.body_ko


def test_handoff_chunk_carries_category_for_docent_food_rule():
    chunk = handoff.aggregate_to_place_mention_chunk(
        _aggregate(category="attraction"), place_id="place-2", place_name_ko="테스트 명소"
    )
    # Category is carried so the docent-side food-rule guard still applies.
    assert chunk.metadata["category"] == "attraction"


def test_replay_aggregate_yields_same_sha_and_no_duplicate_signal():
    chunk_a = handoff.aggregate_to_place_mention_chunk(
        _aggregate(), place_id="place-1", place_name_ko="테스트 식당"
    )
    chunk_b = handoff.aggregate_to_place_mention_chunk(
        _aggregate(), place_id="place-1", place_name_ko="테스트 식당"
    )

    assert chunk_a.content_sha256 == chunk_b.content_sha256  # deterministic

    # Exact replay against the stored sha -> no rebuild signal (no duplicate work).
    replay = handoff.rebuild_signals(
        [chunk_a], previous_shas={chunk_a.source_id: chunk_a.content_sha256}
    )
    assert replay == [
        {
            "source_type": "place_mention",
            "source_id": chunk_a.source_id,
            "content_sha256": chunk_a.content_sha256,
            "changed": False,
        }
    ]

    # A different stored sha (content revision / first build) -> changed=True.
    changed = handoff.changed_signals([chunk_a], previous_shas={chunk_a.source_id: "different"})
    assert len(changed) == 1
    assert changed[0]["changed"] is True


# ---------------------------------------------------------------------------
# D. community_post RAG chunk never embeds raw body/title/url
# ---------------------------------------------------------------------------


def test_community_post_chunk_never_embeds_raw_body_title_or_url():
    raw_row = {
        "provider": "community_provider",
        "external_key": "ext-1",
        "keyword": "수원 카페",
        "region_slug": "suwon",
        "title": "RAW REVIEW TITLE TEXT",
        "body": "RAW REVIEW BODY TEXT THAT MUST NOT LEAK",
        "post_url": "https://evil.example.com/exfil?token=secret",
        "created_at_source": RECEIVED_AT,
        "collected_at": RECEIVED_AT,
    }

    chunk = rag_index._community_post_chunk(raw_row)

    # Raw body/title/url never reach the user-facing chunk body.
    assert "RAW REVIEW BODY TEXT THAT MUST NOT LEAK" not in chunk.body_ko
    assert "RAW REVIEW TITLE TEXT" not in chunk.body_ko
    assert "evil.example.com" not in chunk.body_ko
    assert "token=secret" not in chunk.body_ko
    # And never reach metadata (no raw-text locator fields).
    metadata = chunk.metadata or {}
    for forbidden in ("body", "title", "post_url", "url"):
        assert forbidden not in metadata
    # The chunk is still categorical/grounded (not emptied).
    assert chunk.source_type == "community_post"
    assert "수원 카페" in chunk.body_ko or chunk.title_ko == "수원 카페"
