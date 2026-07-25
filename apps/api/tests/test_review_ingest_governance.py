from __future__ import annotations

import hashlib
import sys
from datetime import UTC, date, datetime
from pathlib import Path
from types import SimpleNamespace

import pytest

from apps.api.app.services import review_ingest_governance as governance

FICTIONAL_SOURCE_NAME = "fictional_licensed_review_provider"
FICTIONAL_PROVIDER = "fictional_provider"
TERMS_VERSION = "fictional-license-v1"
RECEIVED_AT = datetime(2026, 7, 25, 9, 0, tzinfo=UTC)


def _registration(license_class: str = "licensed") -> governance.ReviewSourceRegistration:
    return governance.ReviewSourceRegistration(
        source_name=FICTIONAL_SOURCE_NAME,
        provider=FICTIONAL_PROVIDER,
        license_class=license_class,  # type: ignore[arg-type]
        terms_version=TERMS_VERSION,
        collection_method="licensed_api_discovery",
        retention_policy="metadata_and_aggregates_only",
        redaction_policy="no_raw_text_no_pii",
    )


def _sha(external_key: str, seed: str) -> str:
    return hashlib.sha256(f"{FICTIONAL_PROVIDER}|{external_key}|{seed}".encode()).hexdigest()


def _record_dict(
    external_key: str,
    *,
    seed: str,
    license_class: str = "licensed",
    **overrides: object,
) -> dict[str, object]:
    record: dict[str, object] = {
        "source_name": FICTIONAL_SOURCE_NAME,
        "provider": FICTIONAL_PROVIDER,
        "external_key": external_key,
        "license_class": license_class,
        "terms_version": TERMS_VERSION,
        "content_sha256": _sha(external_key, seed),
        "received_at": RECEIVED_AT,
        "category": "restaurant",
        "match_confidence": 0.92,
        "normalized_attributes": {"taste": 0.8, "service": 0.7},
    }
    record.update(overrides)
    return record


# --- pure governance logic ---


def test_govern_accepts_licensed_normalized_records_and_builds_aggregate_only_payload():
    result = governance.govern_review_records(
        registration=_registration(),
        records=[_record_dict("post-1", seed="warm service and good coffee")],
    )

    assert result.run.status == "succeeded"
    assert result.run.failure_category == "none"
    assert result.run.received_count == 1
    assert result.run.processed_count == 1
    assert result.run.quarantined_count == 0
    assert len(result.accepted) == 1

    aggregate = result.accepted[0]
    assert aggregate.source_name == FICTIONAL_SOURCE_NAME
    assert aggregate.attribute_scores == {"taste": 0.8, "service": 0.7}
    # The downstream payload is aggregate-only -- it must not carry raw text.
    governance.enforce_no_raw_review_text(aggregate.to_rag_metadata(), label="accepted")
    assert aggregate.schema_version == governance.GOVERNANCE_SCHEMA_VERSION


def test_govern_deduplicates_repeat_records_by_content_hash():
    duplicate = _record_dict("post-1", seed="same text")
    result = governance.govern_review_records(
        registration=_registration(),
        records=[duplicate, duplicate],
    )

    assert result.run.received_count == 2
    assert result.run.processed_count == 1
    assert result.run.duplicate_count == 1
    assert result.run.quarantined_count == 0
    assert len(result.accepted) == 1


def test_govern_routes_malformed_records_to_quarantine_as_schema_invalid():
    malformed = _record_dict("post-bad", seed="x")
    del malformed["content_sha256"]  # required field missing

    result = governance.govern_review_records(
        registration=_registration(),
        records=[malformed],
    )

    assert result.run.processed_count == 0
    assert result.run.quarantined_count == 1
    entry = result.quarantined[0]
    assert entry.reason_category == "schema_invalid"
    assert entry.provider == FICTIONAL_PROVIDER
    assert entry.external_key == "post-bad"
    # Quarantine entry exposes no raw review text.
    governance.enforce_no_raw_review_text(entry.model_dump(), label="quarantine")


def test_govern_quarantines_entire_batch_when_source_license_is_rejected():
    records = [_record_dict("post-1", seed="a"), _record_dict("post-2", seed="b")]
    result = governance.govern_review_records(
        registration=_registration(license_class="rejected"),
        records=records,
    )

    assert result.run.status == "failed"
    assert result.run.failure_category == "terms_violation"
    assert result.run.processed_count == 0
    assert result.run.quarantined_count == 2
    assert all(entry.reason_category == "terms_violation" for entry in result.quarantined)
    assert result.accepted == ()


def test_govern_record_carrying_raw_text_field_is_quarantined_not_accepted():
    # An upstream normalizer must never hand raw text to this boundary.
    # extra="forbid" turns the raw body into a schema_invalid quarantine.
    raw_leak = _record_dict("post-leak", seed="clean")
    raw_leak["body"] = "전시가 정말 좋았습니다."  # type: ignore[assignment]

    result = governance.govern_review_records(
        registration=_registration(),
        records=[raw_leak],
    )

    assert result.run.processed_count == 0
    assert result.run.quarantined_count == 1
    assert result.quarantined[0].reason_category == "schema_invalid"


def test_approved_review_aggregate_model_has_no_raw_text_fields():
    # Invariant: the downstream payload type can never represent raw text.
    field_names = set(governance.ApprovedReviewAggregate.model_fields)
    assert field_names.isdisjoint(governance.RAW_REVIEW_TEXT_FIELDS)


def test_enforce_no_raw_review_text_rejects_raw_body_and_allows_clean_payload():
    with pytest.raises(governance.ReviewGovernanceError) as exc_info:
        governance.enforce_no_raw_review_text(
            {"mention_count": 3, "body": "raw review text"},
            label="rag_payload",
        )
    assert exc_info.value.code == "raw_review_text_forbidden"

    # A clean aggregate payload passes.
    governance.enforce_no_raw_review_text(
        {"mention_count": 3, "sentiment_score": 0.5},
        label="rag_payload",
    )


def test_build_run_key_is_deterministic_for_same_window_and_schema():
    window = date(2026, 7, 20)
    first = governance.build_run_key(
        source_name=FICTIONAL_SOURCE_NAME,
        window_start=window,
        schema_version=governance.GOVERNANCE_SCHEMA_VERSION,
    )
    second = governance.build_run_key(
        source_name=FICTIONAL_SOURCE_NAME,
        window_start=window,
        schema_version=governance.GOVERNANCE_SCHEMA_VERSION,
    )
    assert first == second
    other_window = governance.build_run_key(
        source_name=FICTIONAL_SOURCE_NAME,
        window_start=date(2026, 7, 27),
        schema_version=governance.GOVERNANCE_SCHEMA_VERSION,
    )
    assert other_window != first


def test_governance_module_does_not_couple_to_rag_write_path():
    # The foundation must not call the RAG writer or embed raw text. Coupling
    # would show up as an import of / reference to rag_index.upsert_knowledge_chunks.
    source = Path(governance.__file__).read_text(encoding="utf-8")
    assert "import rag_index" not in source
    assert "from apps.api.app.services.rag_index" not in source
    assert "rag_index" not in source
    assert "upsert_knowledge_chunks" not in source


# --- repository helpers (fake psycopg2) ---


class _FakeCursor:
    def __init__(self, store: dict[str, object]) -> None:
        self.store = store
        self.rowcount = 0
        self._fetchone: tuple[object, ...] | None = None

    def __enter__(self) -> _FakeCursor:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def execute(self, sql: str, params: tuple[object, ...] | None = None) -> None:
        executed = self.store.setdefault("executed", [])  # type: ignore[union-attr]
        executed.append(sql)  # type: ignore[union-attr]
        params = params or ()
        if "RETURNING id" in sql:
            run_key = str(params[1])
            runs = self.store.setdefault("runs", {})  # type: ignore[union-attr]
            assigned = runs.get(run_key)  # type: ignore[union-attr]
            if assigned is None:
                assigned = f"run-{len(runs) + 1}"  # type: ignore[union-attr]
                runs[run_key] = assigned  # type: ignore[union-attr]
            self._fetchone = (assigned,)
            self.rowcount = 1
        elif "community.ingest_quarantine" in sql:
            provider = str(params[2])
            external_key = str(params[3])
            reason_category = str(params[5])
            key = (provider, external_key, reason_category)
            seen = self.store.setdefault("quarantine_seen", set())  # type: ignore[union-attr]
            if key in seen:
                self.rowcount = 0
            else:
                seen.add(key)  # type: ignore[union-attr]
                self.rowcount = 1
        else:
            self.rowcount = 1

    def fetchone(self) -> tuple[object, ...] | None:
        return self._fetchone


class _FakeConnection:
    def __init__(self, store: dict[str, object]) -> None:
        self.store = store

    def __enter__(self) -> _FakeConnection:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def cursor(self) -> _FakeCursor:
        return _FakeCursor(self.store)

    def commit(self) -> None:
        return None


def _install_fake_psycopg2(monkeypatch, store: dict[str, object]) -> None:
    def connect(dsn: str, connect_timeout: int) -> _FakeConnection:
        store.setdefault("connects", []).append((dsn, connect_timeout))  # type: ignore[union-attr]
        return _FakeConnection(store)

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))
    monkeypatch.setitem(
        sys.modules,
        "psycopg2.extras",
        SimpleNamespace(Json=lambda value: value),
    )


def _sql(store: dict[str, object]) -> str:
    return "\n".join(store.get("executed", []))  # type: ignore[arg-type]


def test_register_review_source_upserts_by_source_name(monkeypatch):
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    governance.register_review_source(
        dsn="postgresql://redacted",
        registration=_registration(),
        connect_timeout=7,
    )

    assert store["connects"] == [("postgresql://redacted", 7)]
    sql = _sql(store)
    assert "INSERT INTO ingest.review_sources" in sql
    assert "ON CONFLICT (source_name) DO UPDATE" in sql


def test_create_or_resume_ingest_run_is_idempotent_on_run_key(monkeypatch):
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    registration = _registration()
    run_key = governance.build_run_key(
        source_name=registration.source_name,
        window_start=date(2026, 7, 20),
        schema_version=governance.GOVERNANCE_SCHEMA_VERSION,
    )

    first_id = governance.create_or_resume_ingest_run(
        dsn="postgresql://redacted",
        run_key=run_key,
        registration=registration,
        received_count=3,
        connect_timeout=7,
    )
    second_id = governance.create_or_resume_ingest_run(
        dsn="postgresql://redacted",
        run_key=run_key,
        registration=registration,
        received_count=3,
        connect_timeout=7,
    )

    assert first_id == second_id  # retry resumes the same ledger row
    sql = _sql(store)
    assert "INSERT INTO community.ingest_runs" in sql
    assert "ON CONFLICT (run_key)" in sql
    assert "RETURNING id" in sql


def test_finalize_ingest_run_writes_retry_safe_counters(monkeypatch):
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    governance.finalize_ingest_run(
        dsn="postgresql://redacted",
        run_id="run-1",
        status="succeeded",
        processed_count=2,
        duplicate_count=1,
        quarantined_count=0,
        failure_category="none",
        error_message=None,
        connect_timeout=7,
    )

    sql = _sql(store)
    assert "UPDATE community.ingest_runs" in sql
    assert "processed_count = %s" in sql
    assert "failure_category = %s" in sql
    assert "WHERE id = %s" in sql


def test_insert_quarantine_entries_deduplicates_on_retry(monkeypatch):
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    entry = governance.ReviewQuarantineEntry(
        provider=FICTIONAL_PROVIDER,
        external_key="post-bad",
        content_sha256=_sha("post-bad", "x"),
        reason_category="schema_invalid",
        reason="normalized record failed schema validation",
        source_name=FICTIONAL_SOURCE_NAME,
    )

    first = governance.insert_quarantine_entries(
        dsn="postgresql://redacted",
        entries=[entry, entry],
        run_id="run-1",
        connect_timeout=7,
    )
    # Retrying the same failed batch must not double-count dead-letter rows.
    second = governance.insert_quarantine_entries(
        dsn="postgresql://redacted",
        entries=[entry],
        run_id="run-1",
        connect_timeout=7,
    )

    assert first == 1  # the second in-batch duplicate is skipped by ON CONFLICT
    assert second == 0  # the cross-batch retry is also skipped
    sql = _sql(store)
    assert "INSERT INTO community.ingest_quarantine" in sql
    assert "ON CONFLICT (provider, external_key, reason_category)" in sql
