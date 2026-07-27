from __future__ import annotations

import json
import sys
from dataclasses import replace
from datetime import date
from pathlib import Path
from types import SimpleNamespace

import pytest

from apps.api.app.services import review_attribute_batch
from apps.api.app.tools import run_review_attribute_batch


def test_review_attribute_batch_plan_is_safe(capsys):
    exit_code = run_review_attribute_batch.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["live_ai_call"] is False
    assert payload["db_mutation"] is False
    assert payload["target"] == "community.place_mentions_weekly"
    assert payload["model_role"] == "review_bulk"
    assert payload["model_envs"]["review_bulk"].startswith("LALA_MODEL_ROLE_REVIEW_BULK")
    assert payload["model_envs"]["review_recheck"].startswith("LALA_MODEL_ROLE_REVIEW_RECHECK")
    assert "community.posts" in payload["input_relations"]
    assert "attributes.review_attributes" in payload["output_attributes"]
    assert run_review_attribute_batch.ALLOW_ENV in payload["apply_required_env"]
    assert "OPENAI_API_KEY" in payload["apply_required_env"]
    assert "LALA_ENABLE_LIVE_AI" in payload["apply_required_env"]


def test_deterministic_preview_builds_review_quality_for_sufficient_evidence():
    candidate = _candidate(
        category="restaurant",
        organic=3,
        posts=[
            {"title": "카페포렛 커피 맛집", "body": "디저트가 맛있고 직원이 친절했어요"},
            {"title": "카페포렛 브런치", "body": "분위기가 조용하고 메뉴가 좋았어요"},
        ],
    )

    enrichment = review_attribute_batch.build_deterministic_enrichments([candidate])[0]
    quality = review_attribute_batch.review_quality_payload(candidate, enrichment)

    assert enrichment.schema_version == review_attribute_batch.DETERMINISTIC_VERSION
    assert enrichment.attribute_scores["taste"] > 0.45
    assert enrichment.attribute_scores["service"] > 0.45
    assert quality is not None
    assert quality["schema_version"] == review_attribute_batch.QUALITY_VERSION
    assert quality["score"] > 0


def test_candidate_public_projection_keeps_source_text_in_memory_only():
    candidate = _candidate(
        category="restaurant",
        organic=3,
        posts=[{"external_key": "post-1", "title": "원문 제목", "body": "원문 본문"}],
    )

    public = candidate.to_public_dict()
    prompt = candidate.to_prompt_record()

    assert "원문 제목" not in json.dumps(public, ensure_ascii=False)
    assert "원문 본문" not in json.dumps(public, ensure_ascii=False)
    assert prompt["retained_snippets"]


def test_candidate_fetch_requires_active_registered_source_provenance(monkeypatch):
    executed = []

    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))

        def fetchall(self):
            return []

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self, **kwargs):
            return Cursor()

    monkeypatch.setitem(
        sys.modules,
        "psycopg2",
        SimpleNamespace(connect=lambda *args, **kwargs: Connection()),
    )
    monkeypatch.setitem(
        sys.modules,
        "psycopg2.extras",
        SimpleNamespace(RealDictCursor=object()),
    )

    assert (
        review_attribute_batch.fetch_review_attribute_candidates(
            dsn="postgresql://redacted",
            category="all",
            min_organic=3,
            limit=10,
            connect_timeout=5,
        )
        == []
    )
    sql = executed[0][0]
    assert "JOIN ingest.review_sources sources" in sql
    assert "sources.source_status = 'active'" in sql
    assert "sources.license_class IN" in sql
    assert "sources.terms_version = NULLIF" in sql
    assert "{preprocess,source_name}" in sql


def test_low_evidence_keeps_review_quality_null():
    candidate = _candidate(category="culture_venue", organic=2)
    enrichment = review_attribute_batch.build_deterministic_enrichments([candidate])[0]

    assert review_attribute_batch.review_quality_payload(candidate, enrichment) is None


def test_parse_ai_response_filters_category_attributes_and_keeps_ids():
    candidate = _candidate(category="culture_venue", organic=3)
    raw = json.dumps(
        {
            "results": [
                {
                    "mention_id": candidate.mention_id,
                    "schema_version": review_attribute_batch.PROMPT_VERSION,
                    "sentiment_score": 0.4,
                    "sentiment_confidence": 0.8,
                    "attribute_scores": {
                        "cultural_story": 0.9,
                        "walking_comfort": 0.7,
                    },
                    "attribute_confidence_avg": 0.75,
                    "is_ad": False,
                    "ad_confidence": 0.05,
                    "ad_reason": "organic",
                }
            ]
        },
        ensure_ascii=False,
    )

    parsed = review_attribute_batch.parse_ai_response(raw, [candidate])[0]

    assert parsed.mention_id == candidate.mention_id
    assert parsed.schema_version == review_attribute_batch.PROMPT_VERSION
    assert parsed.sentiment_score == 0.4
    assert parsed.attribute_scores == {
        "cultural_story": 0.9,
        "walking_comfort": 0.7,
    }
    assert parsed.to_attributes_payload()["status"] == "accepted"
    assert "evidence_terms" not in parsed.to_attributes_payload()


def test_ai_contract_is_strict_and_payload_is_aggregate_only():
    candidate = _candidate(category="restaurant", organic=3)
    result = {
        "mention_id": candidate.mention_id,
        "schema_version": review_attribute_batch.PROMPT_VERSION,
        "sentiment_score": 0.2,
        "sentiment_confidence": 0.8,
        "attribute_scores": {"taste": 0.7},
        "attribute_confidence_avg": 0.8,
        "is_ad": False,
        "ad_confidence": 0.1,
        "ad_reason": "organic",
        # These must not be accepted as part of the strict model contract.
        "summary_ko": "raw-derived summary",
    }

    with pytest.raises(ValueError, match="exactly one result"):
        review_attribute_batch.parse_ai_response(json.dumps({"results": []}), [candidate])

    parsed = review_attribute_batch.parse_ai_response(
        json.dumps(
            {"results": [{key: value for key, value in result.items() if key != "summary_ko"}]}
        ),
        [candidate],
    )[0]
    payload = parsed.to_attributes_payload()
    assert "summary_ko" not in payload
    assert "evidence_terms" not in payload
    assert "reason" not in payload
    assert payload["status"] == "accepted"


def test_ai_ad_and_low_confidence_statuses_are_fail_closed():
    candidate = _candidate(category="restaurant", organic=3)
    base = {
        "mention_id": candidate.mention_id,
        "schema_version": review_attribute_batch.PROMPT_VERSION,
        "sentiment_score": 0.0,
        "sentiment_confidence": 0.4,
        "attribute_scores": {"taste": 0.5},
        "attribute_confidence_avg": 0.4,
        "is_ad": True,
        "ad_confidence": 0.7,
        "ad_reason": "ambiguous_ad_signal",
    }
    parsed = review_attribute_batch.parse_ai_response(json.dumps({"results": [base]}), [candidate])[
        0
    ]
    assert parsed.status == "recheck_required"
    assert review_attribute_batch.review_quality_payload(candidate, parsed) is None

    filtered = dict(
        base, sentiment_confidence=0.9, attribute_confidence_avg=0.9, ad_confidence=0.95
    )
    parsed_filtered = review_attribute_batch.parse_ai_response(
        json.dumps({"results": [filtered]}), [candidate]
    )[0]
    assert parsed_filtered.status == "ad_filtered"


def test_ambiguous_ad_is_routed_to_selective_recheck():
    low_ad = _runner_enrichment("ambiguous", 0.95)
    low_ad = replace(low_ad, is_ad=True, ad_confidence=0.2)

    routed = review_attribute_batch.route_low_confidence_enrichments([low_ad])

    assert [item.mention_id for item in routed] == ["ambiguous"]


def test_disabled_dry_run_never_reads_db_or_calls_ai(monkeypatch, capsys):
    _runner_settings(monkeypatch)
    monkeypatch.setattr(
        run_review_attribute_batch,
        "get_settings",
        lambda: SimpleNamespace(
            db_dsn="postgresql://must-not-connect",
            openai_api_key="",
            openai_base_url="https://api.openai.com/v1",
            enable_live_ai=False,
            openai_review_batch_model="gpt-5.4-nano",
            openai_review_recheck_model="gpt-5.4-mini",
        ),
    )
    monkeypatch.setattr(
        run_review_attribute_batch,
        "fetch_review_attribute_candidates",
        lambda **kwargs: (_ for _ in ()).throw(AssertionError("DB must not be read")),
    )

    exit_code = run_review_attribute_batch.main(["--dry-run-ai", "--json"])
    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["mode"] == "disabled"
    assert payload["live_ai_call"] is False
    assert payload["candidate_count"] == 0
    assert "must-not-connect" not in json.dumps(payload)


def test_dry_run_ai_requires_explicit_live_operation_guard(monkeypatch, capsys):
    _runner_settings(monkeypatch)
    monkeypatch.setattr(
        run_review_attribute_batch,
        "fetch_review_attribute_candidates",
        lambda **kwargs: (_ for _ in ()).throw(AssertionError("DB must not be read")),
    )

    exit_code = run_review_attribute_batch.main(["--dry-run-ai", "--json"])
    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert payload["live_ai_call"] is False
    assert "--allow-live-ai" in payload["error"]


def test_apply_requires_guard_before_reading_db(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.delenv(run_review_attribute_batch.ALLOW_ENV, raising=False)

    exit_code = run_review_attribute_batch.main(
        ["--apply", "--confirm", run_review_attribute_batch.CONFIRM_TEXT]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_review_attribute_batch.ALLOW_ENV in output
    assert dsn not in output
    assert password not in output


def test_apply_review_attribute_enrichments_targets_mentions_and_quality(monkeypatch):
    executed = []
    candidate = _candidate(category="restaurant", organic=3)
    enrichment = review_attribute_batch.build_deterministic_enrichments([candidate])[0]

    class Cursor:
        rowcount = 1

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self):
            return Cursor()

        def commit(self):
            executed.append(("commit", None))

    def connect(dsn, connect_timeout):
        executed.append(("connect", {"dsn": dsn, "connect_timeout": connect_timeout}))
        return Connection()

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))
    monkeypatch.setitem(
        sys.modules,
        "psycopg2.extras",
        SimpleNamespace(Json=lambda value: value),
    )

    updated = review_attribute_batch.apply_review_attribute_enrichments(
        dsn="postgresql://redacted",
        candidates=[candidate],
        enrichments=[enrichment],
        source_method="deterministic",
        connect_timeout=7,
    )

    assert updated == 1
    assert "UPDATE community.place_mentions_weekly" in executed[1][0]
    assert any("INSERT INTO travel.place_enrichments" in sql for sql, _ in executed)
    assert "review_attribute_batch" in executed[1][0]
    assert executed[1][1]["mention_id"] == candidate.mention_id
    assert "summary_ko" not in executed[1][1]["review_attributes"]
    assert "evidence_terms" not in executed[1][1]["review_attributes"]
    assert executed[1][1]["review_quality"]["schema_version"] == (
        review_attribute_batch.QUALITY_VERSION
    )
    assert executed[-1] == ("commit", None)


def test_nonaccepted_enrichment_clears_canonical_outputs_and_skips_mirror(monkeypatch):
    executed = []
    candidate = _candidate(category="restaurant", organic=3)
    enrichment = replace(
        review_attribute_batch.build_deterministic_enrichments([candidate])[0],
        status="recheck_required",
        is_ad=True,
        ad_confidence=0.4,
    )

    class Cursor:
        rowcount = 1

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self):
            return Cursor()

        def commit(self):
            executed.append(("commit", None))

    monkeypatch.setitem(
        sys.modules, "psycopg2", SimpleNamespace(connect=lambda *a, **k: Connection())
    )
    monkeypatch.setitem(sys.modules, "psycopg2.extras", SimpleNamespace(Json=lambda value: value))

    assert (
        review_attribute_batch.apply_review_attribute_enrichments(
            dsn="postgresql://redacted",
            candidates=[candidate],
            enrichments=[enrichment],
            source_method="openai",
            connect_timeout=7,
        )
        == 1
    )
    update_sql, params = executed[0]
    assert "attributes - 'review_quality'" in update_sql
    assert params["sentiment_score"] is None
    assert params["review_quality"] is None
    assert params["review_attributes"]["status"] == "recheck_required"
    assert "attribute_scores" not in params["review_attributes"]
    assert not any("INSERT INTO travel.place_enrichments" in sql for sql, _ in executed)


def test_generate_ai_enrichments_uses_openai_review_batch_model(monkeypatch):
    captured: dict[str, object] = {}
    candidate = _candidate(category="restaurant", organic=3)

    class FakeCompletions:
        def create(self, **kwargs):
            captured["completion"] = kwargs
            return SimpleNamespace(
                choices=[
                    SimpleNamespace(
                        message=SimpleNamespace(
                            content=json.dumps(
                                {
                                    "results": [
                                        {
                                            "mention_id": candidate.mention_id,
                                            "schema_version": review_attribute_batch.PROMPT_VERSION,
                                            "sentiment_score": 0.6,
                                            "sentiment_confidence": 0.8,
                                            "attribute_scores": {
                                                "taste": 0.9,
                                                "service": 0.7,
                                            },
                                            "attribute_confidence_avg": 0.75,
                                            "is_ad": False,
                                            "ad_confidence": 0.05,
                                            "ad_reason": "organic",
                                        }
                                    ]
                                },
                                ensure_ascii=False,
                            )
                        )
                    )
                ]
            )

    class FakeOpenAI:
        def __init__(self, **kwargs):
            self.chat = SimpleNamespace(completions=FakeCompletions())

    # Standard OpenAI only (never Azure): the client is openai.OpenAI and the
    # model is the OpenAI review-batch model name. The key value is never asserted
    # on or exposed.
    fake_openai = SimpleNamespace(OpenAI=FakeOpenAI)
    monkeypatch.setitem(sys.modules, "openai", fake_openai)
    monkeypatch.setattr(
        review_attribute_batch,
        "get_settings",
        lambda: SimpleNamespace(
            openai_api_key="dummy",  # pragma: allowlist secret -- fake test fixture, never a real key
            openai_base_url="https://api.openai.com/v1",
            enable_live_ai=True,
            openai_review_batch_model="review-nano-model",
        ),
    )

    enrichments = review_attribute_batch.generate_ai_enrichments(
        candidates=[candidate],
        batch_size=10,
        retry_attempts=1,
        retry_delay_sec=0.0,
    )

    assert len(enrichments) == 1
    assert captured["completion"]["model"] == "review-nano-model"


def _candidate(
    *,
    category: str,
    organic: int,
    posts: list[dict[str, str]] | None = None,
) -> review_attribute_batch.ReviewAttributeCandidate:
    return review_attribute_batch.ReviewAttributeCandidate(
        mention_id="11111111-1111-1111-1111-111111111111",
        week_start=date(2026, 6, 22),
        place_id="place-1",
        place_name_ko="카페포렛",
        provider="naver_blog",
        category=category,
        mention_count=max(organic, 1),
        organic_mention_count=organic,
        sentiment_score=0.2,
        attributes={
            "top_terms": ["커피", "디저트", "친절", "전시"],
            "filtered_ad_count": 0,
            "category_policy": "restaurant_food_terms_retained",
        },
        posts=tuple(posts or [{"title": "카페포렛 후기", "body": "전시 동선과 분위기가 좋았어요"}]),
    )


# ---------------------------------------------------------------------------
# Runner flow: bulk -> selective recheck wiring (Improvement B runtime path)
# ---------------------------------------------------------------------------


def _runner_candidate(mention_id: str) -> review_attribute_batch.ReviewAttributeCandidate:
    return review_attribute_batch.ReviewAttributeCandidate(
        mention_id=mention_id,
        week_start=date(2026, 6, 22),
        place_id="place-1",
        place_name_ko="테스트 식당",
        provider="fictional_provider",
        category="restaurant",
        mention_count=5,
        organic_mention_count=5,
        sentiment_score=0.2,
        attributes={"top_terms": []},
        posts=(),
    )


def _runner_enrichment(
    mention_id: str, confidence: float, *, source_method: str = "openai"
) -> review_attribute_batch.ReviewAttributeEnrichment:
    return review_attribute_batch.ReviewAttributeEnrichment(
        mention_id=mention_id,
        schema_version=review_attribute_batch.PROMPT_VERSION,
        sentiment_score=0.2,
        sentiment_confidence=confidence,
        attribute_scores={"taste": 0.5},
        attribute_confidence_avg=confidence,
        evidence_terms={},
        summary_ko=None,
        reason=None,
        source_method=source_method,
    )


def _runner_settings(monkeypatch) -> None:
    # Standard OpenAI only (never Azure). Key never read (live funcs are mocked).
    monkeypatch.setattr(
        run_review_attribute_batch,
        "get_settings",
        lambda: SimpleNamespace(
            db_dsn="postgresql://redacted",
            openai_api_key="test-key",  # pragma: allowlist secret -- fake test fixture
            openai_base_url="https://api.openai.com/v1",
            enable_live_ai=True,
            openai_review_batch_model="gpt-5.4-nano",
            openai_review_recheck_model="gpt-5.4-mini",
        ),
    )


def test_preview_never_invokes_either_live_lane(monkeypatch, capsys):
    _runner_settings(monkeypatch)
    monkeypatch.setattr(
        run_review_attribute_batch,
        "fetch_review_attribute_candidates",
        lambda **kwargs: [_runner_candidate("c1")],
    )

    def boom(*args, **kwargs):  # noqa: ANN002
        raise AssertionError("preview must not invoke any live lane")

    monkeypatch.setattr(run_review_attribute_batch, "generate_ai_enrichments", boom)
    monkeypatch.setattr(run_review_attribute_batch, "generate_ai_recheck", boom)

    exit_code = run_review_attribute_batch.main(["--preview", "--json"])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["mode"] == "preview"
    assert payload["live_ai_call"] is False
    assert payload["recheck_routed_count"] == 0
    assert payload["recheck_upgraded_count"] == 0


def test_dry_run_invokes_recheck_after_bulk_when_low_confidence_present(monkeypatch, capsys):
    _runner_settings(monkeypatch)
    low = _runner_enrichment("c1", 0.4)  # below threshold -> routed
    high = _runner_enrichment("c2", 0.95)  # above threshold -> not routed
    bulk_calls: list[dict] = []
    recheck_calls: list[object] = []

    monkeypatch.setattr(
        run_review_attribute_batch,
        "fetch_review_attribute_candidates",
        lambda **kwargs: [_runner_candidate("c1"), _runner_candidate("c2")],
    )
    monkeypatch.setattr(
        run_review_attribute_batch,
        "generate_ai_enrichments",
        lambda **kwargs: bulk_calls.append(kwargs) or [low, high],
    )

    def fake_recheck(*, enrichments, **kwargs):
        recheck_calls.append(enrichments)
        # Upgrade only the routed (low-confidence) row to the mini lane.
        return [_runner_enrichment("c1", 0.9, source_method="openai_recheck"), enrichments[1]]

    monkeypatch.setattr(run_review_attribute_batch, "generate_ai_recheck", fake_recheck)

    exit_code = run_review_attribute_batch.main(["--dry-run-ai", "--allow-live-ai", "--json"])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["mode"] == "dry-run-ai"
    assert payload["live_ai_call"] is True
    assert len(bulk_calls) == 1  # bulk ran exactly once
    assert len(recheck_calls) == 1  # recheck ran exactly once, after bulk
    assert payload["recheck_routed_count"] == 1  # only the low-confidence row routed
    assert payload["recheck_upgraded_count"] == 1


def test_dry_run_skips_recheck_when_no_low_confidence_rows(monkeypatch, capsys):
    _runner_settings(monkeypatch)
    high1 = _runner_enrichment("c1", 0.95)
    high2 = _runner_enrichment("c2", 0.9)

    def boom_recheck(*args, **kwargs):  # noqa: ANN002
        raise AssertionError("recheck must not run when there are no low-confidence rows")

    monkeypatch.setattr(
        run_review_attribute_batch,
        "fetch_review_attribute_candidates",
        lambda **kwargs: [_runner_candidate("c1"), _runner_candidate("c2")],
    )
    monkeypatch.setattr(
        run_review_attribute_batch,
        "generate_ai_enrichments",
        lambda **kwargs: [high1, high2],
    )
    monkeypatch.setattr(run_review_attribute_batch, "generate_ai_recheck", boom_recheck)

    exit_code = run_review_attribute_batch.main(["--dry-run-ai", "--allow-live-ai", "--json"])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["recheck_routed_count"] == 0
    assert payload["recheck_upgraded_count"] == 0


def test_apply_runs_bulk_then_recheck_and_applies_per_row_source(monkeypatch, capsys):
    _runner_settings(monkeypatch)
    monkeypatch.setenv(run_review_attribute_batch.ALLOW_ENV, "1")
    bulk_calls: list[dict] = []
    recheck_calls: list[dict] = []
    apply_calls: list[dict] = []

    monkeypatch.setattr(
        run_review_attribute_batch,
        "fetch_review_attribute_candidates",
        lambda **kwargs: [_runner_candidate("c1")],
    )
    monkeypatch.setattr(
        run_review_attribute_batch,
        "generate_ai_enrichments",
        lambda **kwargs: bulk_calls.append(kwargs) or [_runner_enrichment("c1", 0.4)],
    )
    monkeypatch.setattr(
        run_review_attribute_batch,
        "generate_ai_recheck",
        lambda **kwargs: (
            recheck_calls.append(kwargs)
            or [_runner_enrichment("c1", 0.9, source_method="openai_recheck")]
        ),
    )
    monkeypatch.setattr(
        run_review_attribute_batch,
        "apply_review_attribute_enrichments",
        lambda **kwargs: apply_calls.append(kwargs) or 1,
    )
    monkeypatch.setattr(run_review_attribute_batch, "record_job_run", lambda **kwargs: None)

    exit_code = run_review_attribute_batch.main(
        ["--apply", "--confirm", run_review_attribute_batch.CONFIRM_TEXT, "--json"]
    )

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["mode"] == "apply"
    assert payload["db_mutation"] is True
    assert len(bulk_calls) == 1 and len(recheck_calls) == 1 and len(apply_calls) == 1
    # The rechecked row reaches apply tagged openai_recheck (per-row provenance).
    assert apply_calls[0]["enrichments"][0].source_method == "openai_recheck"
    assert payload["recheck_upgraded_count"] == 1


def test_recheck_returning_bulk_preserves_result(monkeypatch, capsys):
    _runner_settings(monkeypatch)
    # A graceful recheck (e.g. mini lane unavailable / failed) returns the bulk
    # list unchanged; the runner must keep that bulk result.
    monkeypatch.setattr(
        run_review_attribute_batch,
        "fetch_review_attribute_candidates",
        lambda **kwargs: [_runner_candidate("c1")],
    )
    monkeypatch.setattr(
        run_review_attribute_batch,
        "generate_ai_enrichments",
        lambda **kwargs: [_runner_enrichment("c1", 0.4)],
    )

    def failed_recheck(**kwargs):
        kwargs["recheck_stats"]["recheck_failed_count"] = 1
        return kwargs["enrichments"]

    monkeypatch.setattr(run_review_attribute_batch, "generate_ai_recheck", failed_recheck)

    exit_code = run_review_attribute_batch.main(["--dry-run-ai", "--allow-live-ai", "--json"])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["recheck_routed_count"] == 1  # the row was eligible
    assert payload["recheck_upgraded_count"] == 0  # but nothing was upgraded
    assert payload["recheck_failed_count"] == 1


def test_review_openai_client_rejects_azure_base_url():
    settings = SimpleNamespace(
        openai_api_key="dummy",  # pragma: allowlist secret -- fake test fixture
        openai_base_url="https://tenant.openai.azure.com/openai/v1",
        enable_live_ai=True,
        openai_review_batch_model="gpt-5.4-nano",
    )

    with pytest.raises(RuntimeError, match="Azure OpenAI base URLs are not supported"):
        review_attribute_batch._build_openai_client(settings)


def test_apply_row_provenance_keeps_openai_recheck_tag(monkeypatch):
    # Direct apply contract: a rechecked enrichment persists as openai_recheck in
    # the per-row review_attribute_batch metadata, not a generic runner string.
    executed: list[tuple] = []
    candidate = _candidate(category="restaurant", organic=3)
    enrichment = review_attribute_batch.ReviewAttributeEnrichment(
        mention_id=candidate.mention_id,
        schema_version=review_attribute_batch.PROMPT_VERSION,
        sentiment_score=0.6,
        sentiment_confidence=0.9,
        attribute_scores={"taste": 0.85},
        attribute_confidence_avg=0.9,
        evidence_terms={},
        summary_ko=None,
        reason=None,
        source_method="openai_recheck",
    )

    class Cursor:
        rowcount = 1

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self):
            return Cursor()

        def commit(self):
            executed.append(("commit", None))

    monkeypatch.setitem(
        sys.modules, "psycopg2", SimpleNamespace(connect=lambda *a, **k: Connection())
    )
    monkeypatch.setitem(sys.modules, "psycopg2.extras", SimpleNamespace(Json=lambda value: value))

    updated = review_attribute_batch.apply_review_attribute_enrichments(
        dsn="postgresql://redacted",
        candidates=[candidate],
        enrichments=[enrichment],
        source_method="openai",  # generic runner-level string must NOT override per-row
        connect_timeout=7,
    )

    assert updated == 1
    # Per-row source_method (openai_recheck) is what gets written, not "openai".
    assert executed[0][1]["source_method"] == "openai_recheck"


# ---------------------------------------------------------------------------
# OpenAI wording guards (prevent Azure regression in error messages / selectors)
# ---------------------------------------------------------------------------


def test_parse_ai_response_error_uses_openai_wording():
    candidate = _candidate(category="restaurant", organic=3)
    try:
        review_attribute_batch.parse_ai_response('{"not_results": []}', [candidate])
    except ValueError as exc:
        message = str(exc)
        assert "OpenAI" in message
        assert "Azure" not in message
    else:  # pragma: no cover - guard against the raise disappearing
        raise AssertionError("parse_ai_response should raise on a non-results payload")


def test_ai_path_error_messages_do_not_use_azure_wording():
    # Regression guard: the two AI-path error literals must stay OpenAI-worded.
    source = Path(review_attribute_batch.__file__).read_text(encoding="utf-8")
    assert '"Azure OpenAI JSON response' not in source
    assert '"Azure OpenAI completion' not in source


def test_selected_review_recheck_model_defaults_to_mini_even_when_unset():
    # Resolution always yields gpt-5.4-mini even with an empty/missing setting,
    # so recheck is always available -- not disableable via an empty env var.
    empty = SimpleNamespace(openai_review_recheck_model="")
    missing = SimpleNamespace()
    configured = SimpleNamespace(openai_review_recheck_model="gpt-5.4-mini-custom")

    assert review_attribute_batch.selected_review_recheck_model(empty) == "gpt-5.4-mini"
    assert review_attribute_batch.selected_review_recheck_model(missing) == "gpt-5.4-mini"
    assert review_attribute_batch.selected_review_recheck_model(configured) == "gpt-5.4-mini-custom"
