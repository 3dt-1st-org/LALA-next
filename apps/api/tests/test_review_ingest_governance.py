from __future__ import annotations

import hashlib
import json
import sys
from datetime import UTC, date, datetime
from pathlib import Path
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

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


# --- pure validation & projection (no DB, no network) ---


def test_parse_review_record_accepts_valid_aggregate_record():
    record = governance.parse_review_record(_record_dict("post-1", seed="warm coffee"))
    assert record.source_name == FICTIONAL_SOURCE_NAME
    assert record.content_sha256 == _sha("post-1", "warm coffee")


def test_approved_aggregate_from_record_is_aggregate_only_and_rag_safe():
    record = governance.parse_review_record(_record_dict("post-1", seed="good service"))
    aggregate = governance.approved_aggregate_from_record(record)

    assert aggregate.attribute_scores == {"taste": 0.8, "service": 0.7}
    assert aggregate.schema_version == governance.GOVERNANCE_SCHEMA_VERSION
    # The downstream payload is aggregate-only -- it must not carry raw text.
    governance.enforce_no_raw_review_text(aggregate.to_rag_metadata(), label="accepted")
    governance.enforce_no_raw_review_text(aggregate.model_dump(), label="aggregate")


def test_record_carrying_raw_body_field_is_rejected_by_allowlist():
    raw_leak = _record_dict("post-leak", seed="clean")
    raw_leak["body"] = "전시가 정말 좋았습니다."  # type: ignore[assignment]

    with pytest.raises(ValidationError):
        governance.parse_review_record(raw_leak)


def test_record_with_raw_text_key_in_normalized_attributes_is_rejected():
    raw = _record_dict("post-attr", seed="x")
    raw["normalized_attributes"] = {"body": "raw"}  # type: ignore[assignment]
    with pytest.raises(ValidationError):
        governance.parse_review_record(raw)


def test_approved_review_aggregate_model_has_no_raw_text_fields():
    field_names = set(governance.ApprovedReviewAggregate.model_fields)
    assert field_names.isdisjoint(governance.RAW_REVIEW_TEXT_FIELDS)


def test_enforce_no_raw_review_text_rejects_raw_body_and_allows_clean_payload():
    with pytest.raises(governance.ReviewGovernanceError) as exc_info:
        governance.enforce_no_raw_review_text(
            {"mention_count": 3, "body": "raw review text"},
            label="rag_payload",
        )
    assert exc_info.value.code == "raw_review_text_forbidden"

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
    other = governance.build_run_key(
        source_name=FICTIONAL_SOURCE_NAME,
        window_start=date(2026, 7, 27),
        schema_version=governance.GOVERNANCE_SCHEMA_VERSION,
    )
    assert other != first


def test_governance_module_does_not_couple_to_rag_write_path():
    source = Path(governance.__file__).read_text(encoding="utf-8")
    assert "import rag_index" not in source
    assert "from apps.api.app.services.rag_index" not in source
    assert "rag_index" not in source
    assert "upsert_knowledge_chunks" not in source


def test_governance_module_has_no_public_endpoint_or_router_coupling():
    # Source registration stays internal/admin-only: no FastAPI router import.
    source = Path(governance.__file__).read_text(encoding="utf-8")
    assert "APIRouter" not in source
    assert "from apps.api.app.routers" not in source


# --- classify_review_records: pure validation -> typed quarantine ---


def test_classify_review_records_splits_valid_and_malformed():
    malformed = _record_dict("post-bad", seed="x")
    del malformed["content_sha256"]
    valid_dict = _record_dict("post-1", seed="good")

    valid, quarantined = governance.classify_review_records(
        registration=_registration(),
        records=[valid_dict, malformed],
    )

    assert len(valid) == 1
    assert valid[0].external_key == "post-1"
    assert len(quarantined) == 1
    entry = quarantined[0]
    assert entry.reason_category == "schema_invalid"
    assert entry.provider == FICTIONAL_PROVIDER
    assert entry.external_key == "post-bad"


def test_classify_routes_missing_field_to_specific_code_and_typed_metadata():
    malformed = _record_dict("post-missing", seed="x")
    del malformed["content_sha256"]

    _, quarantined = governance.classify_review_records(
        registration=_registration(),
        records=[malformed],
    )

    entry = quarantined[0]
    assert entry.reason_code == "schema_invalid_missing_field"
    assert entry.safe_metadata.missing_field_name == "content_sha256"
    assert entry.safe_metadata.bad_hash is False


def test_classify_routes_bad_hash_to_specific_code():
    malformed = _record_dict("post-hash", seed="x", content_sha256="not-a-hex")
    # The literal must be a valid sha-shaped override for the bad-hash path:
    malformed["content_sha256"] = "zz" * 32  # 64 chars but non-hex

    _, quarantined = governance.classify_review_records(
        registration=_registration(),
        records=[malformed],
    )

    entry = quarantined[0]
    assert entry.reason_code == "schema_invalid_bad_hash"
    assert entry.safe_metadata.bad_hash is True


def test_classify_routes_raw_text_field_to_specific_code():
    raw_leak = _record_dict("post-leak", seed="x")
    raw_leak["body"] = "전시가 좋았습니다."  # type: ignore[assignment]

    _, quarantined = governance.classify_review_records(
        registration=_registration(),
        records=[raw_leak],
    )

    entry = quarantined[0]
    assert entry.reason_code == "schema_invalid_raw_text_field"
    assert entry.safe_metadata.raw_text_field == "body"


def test_quarantine_reason_is_code_backed_and_never_interpolates_raw_input():
    # reason/reason_category are always derived from a fixed template via REASON_SPEC.
    for _code, (category, reason) in governance.REASON_SPEC.items():
        assert category in {
            "schema_invalid",
            "terms_violation",
            "source_api_failure",
            "duplicate_suspect",
            "low_confidence",
            "ambiguous_match",
        }
        # Templates are fixed strings that never name a raw content field.
        assert isinstance(reason, str) and reason
        for forbidden in ("body", "title", "post_url", "raw_text"):
            assert forbidden not in reason


def test_quarantine_safe_metadata_is_typed_and_carries_no_raw_text():
    entry = governance._quarantine_for_code(  # noqa: SLF001 -- exercising the builder
        {"provider": FICTIONAL_PROVIDER, "external_key": "k", "content_sha256": _sha("k", "s")},
        registration=_registration(),
        reason_code="schema_invalid_missing_field",
        safe_metadata=governance.QuarantineSafeMetadata(
            malformed=True, missing_field_name="content_sha256"
        ),
    )

    # No free-form str field exists on the typed metadata model.
    for name, field in governance.QuarantineSafeMetadata.model_fields.items():
        assert name not in governance.RAW_REVIEW_TEXT_FIELDS
        # Fields are bool/int/float or Literal-enumerable; never arbitrary text.
        assert field.annotation is not str

    dumped = entry.safe_metadata.model_dump(exclude_none=True)
    governance.enforce_no_raw_review_text(dumped, label="safe_metadata")
    governance.enforce_no_raw_review_text(entry.model_dump(), label="quarantine_entry")


# --- Finding 2: strict, bounded normalized-attribute contract ---


def test_classify_quarantines_string_valued_attribute():
    raw = _record_dict("post-1", seed="x", normalized_attributes={"taste": "0.8"})

    valid, quarantined = governance.classify_review_records(
        registration=_registration(), records=[raw]
    )

    assert valid == ()
    assert len(quarantined) == 1
    entry = quarantined[0]
    assert entry.reason_code == "schema_invalid_attribute_shape"
    assert entry.reason_category == "schema_invalid"
    assert entry.safe_metadata.attribute_shape_violation == "non_numeric_value"


def test_classify_quarantines_nested_object_attribute():
    raw = _record_dict("post-1", seed="x", normalized_attributes={"taste": {"review": "raw text"}})

    valid, quarantined = governance.classify_review_records(
        registration=_registration(), records=[raw]
    )

    assert valid == ()
    assert quarantined[0].safe_metadata.attribute_shape_violation == "nested_object"
    # The nested raw-text object is never carried into the quarantine entry.
    governance.enforce_no_raw_review_text(quarantined[0].model_dump(), label="q")


def test_classify_quarantines_raw_text_like_attribute_key():
    raw = _record_dict("post-1", seed="x", normalized_attributes={"body": 0.5})

    valid, quarantined = governance.classify_review_records(
        registration=_registration(), records=[raw]
    )

    assert valid == ()
    assert quarantined[0].safe_metadata.attribute_shape_violation == "raw_text_key"


def test_classify_quarantines_unknown_attribute_key():
    raw = _record_dict("post-1", seed="x", normalized_attributes={"arbitrary_freeform_key": 0.5})

    valid, quarantined = governance.classify_review_records(
        registration=_registration(), records=[raw]
    )

    assert valid == ()
    assert quarantined[0].safe_metadata.attribute_shape_violation == "unknown_key"


def test_classify_quarantines_out_of_range_attribute():
    raw_high = _record_dict("post-1", seed="x", normalized_attributes={"taste": 1.5})
    raw_low = _record_dict("post-2", seed="x", normalized_attributes={"taste": -0.1})

    for raw in (raw_high, raw_low):
        valid, quarantined = governance.classify_review_records(
            registration=_registration(), records=[raw]
        )
        assert valid == ()
        assert quarantined[0].safe_metadata.attribute_shape_violation == "out_of_range"


@pytest.mark.parametrize(
    "bad_attributes",
    [
        {"taste": "0.8"},  # string value
        {"taste": {"review": "raw"}},  # nested object
        {"body": 0.5},  # raw-text-like key
        {"unknown_metric": 0.5},  # free-form key
        {"taste": True},  # bool is not a score
        {"taste": [0.8]},  # nested list
    ],
)
def test_parse_review_record_rejects_attribute_shape_violation(bad_attributes):
    raw = _record_dict("post-1", seed="x", normalized_attributes=bad_attributes)
    with pytest.raises(ValidationError):
        governance.parse_review_record(raw)


def test_normalized_attribute_contract_accepts_legitimate_scores():
    raw = _record_dict(
        "post-1",
        seed="x",
        normalized_attributes={
            "taste": 0.8,
            "service": 0.7,
            "cleanliness": 0.0,
            "atmosphere": 1.0,
        },
    )
    record = governance.parse_review_record(raw)
    assert record.normalized_attributes == {
        "taste": 0.8,
        "service": 0.7,
        "cleanliness": 0.0,
        "atmosphere": 1.0,
    }


def test_normalized_attribute_contract_rejects_non_dict_payload():
    raw = _record_dict("post-1", seed="x")
    raw["normalized_attributes"] = "taste=0.8"  # type: ignore[assignment]
    with pytest.raises(ValidationError):
        governance.parse_review_record(raw)


# --- Finding 1: per-record DB-authoritative source identity ---


@pytest.mark.parametrize(
    "override,expected_field",
    [
        ({"source_name": "other_source"}, "source_name"),
        ({"provider": "attacker_provider"}, "provider"),
        ({"license_class": "public_processed"}, "license_class"),
        ({"terms_version": "other-terms-v9"}, "terms_version"),
    ],
)
def test_classify_quarantines_record_with_mismatched_identity(override, expected_field):
    raw = _record_dict("post-1", seed="x", **override)

    valid, quarantined = governance.classify_review_records(
        registration=_registration(), records=[raw]
    )

    assert valid == ()
    assert len(quarantined) == 1
    entry = quarantined[0]
    assert entry.reason_code == "source_identity_mismatch"
    assert entry.reason_category == "terms_violation"
    assert entry.safe_metadata.mismatched_identity_field == expected_field
    # Even a mismatched record is quarantined under the registered provider, not
    # any caller/attacker-supplied value.
    assert entry.provider == FICTIONAL_PROVIDER


def test_classify_binds_accepted_record_identity_to_registration():
    raw = _record_dict("post-1", seed="x")  # identity matches the registration

    valid, _ = governance.classify_review_records(registration=_registration(), records=[raw])

    assert len(valid) == 1
    record = valid[0]
    reg = _registration()
    # The accepted record is bound to the DB registration identity, never the
    # caller-supplied copy.
    assert record.source_name == reg.source_name
    assert record.provider == reg.provider
    assert record.license_class == reg.license_class
    assert record.terms_version == reg.terms_version


def test_aggregate_from_classified_record_carries_registered_source_only():
    reg = _registration()
    # Caller tries to inject a different source_name; it is quarantined (above).
    # For a matching record the emitted aggregate source is the registration's.
    raw = _record_dict("post-1", seed="x")
    valid, quarantined = governance.classify_review_records(registration=reg, records=[raw])

    assert len(valid) == 1
    assert quarantined == ()
    aggregate = governance.approved_aggregate_from_record(valid[0])
    assert aggregate.source_name == reg.source_name
    assert aggregate.attribute_scores == {"taste": 0.8, "service": 0.7}


def test_mixed_batch_accepts_only_identity_matching_records():
    reg = _registration()
    matching = _record_dict("post-ok", seed="good")
    mismatched = _record_dict("post-bad", seed="good", provider="other_provider")

    valid, quarantined = governance.classify_review_records(
        registration=reg, records=[matching, mismatched]
    )

    assert len(valid) == 1
    assert valid[0].external_key == "post-ok"
    assert len(quarantined) == 1
    assert quarantined[0].reason_code == "source_identity_mismatch"


# --- Finding 3: safe quarantine identity (no raw provider/URL text) ---


def test_safe_identity_uses_registered_provider_and_hashes_url_like_external_key():
    reg = _registration()
    raw = {
        "provider": "attacker-provider",  # caller/attacker-controlled
        "external_key": "https://evil.example.com/exfil?token=secret",  # URL-like
        "content_sha256": _sha("k", "s"),
    }

    provider, external_key, _content_sha, source_name, replaced = governance._safe_identity(  # noqa: SLF001
        raw, registration=reg
    )

    assert provider == FICTIONAL_PROVIDER  # registered, never attacker
    assert source_name == FICTIONAL_SOURCE_NAME
    assert replaced is True
    assert external_key.startswith("external_key_sha256:")
    # No raw URL material survives into the identity.
    assert "evil.example.com" not in external_key
    assert "https" not in external_key
    assert "token" not in external_key


def test_safe_identity_hashes_non_string_external_key():
    reg = _registration()
    _provider, external_key, _content_sha, _src, replaced = governance._safe_identity(  # noqa: SLF001
        {"external_key": 12345}, registration=reg
    )
    assert replaced is True
    assert external_key.startswith("external_key_sha256:")


def test_safe_identity_clean_external_key_passes_through_unchanged():
    reg = _registration()
    _provider, external_key, _content_sha, _src, replaced = governance._safe_identity(  # noqa: SLF001
        {"external_key": "naver-post-9281"}, registration=reg
    )
    assert replaced is False
    assert external_key == "naver-post-9281"


def test_safe_identity_replacement_is_deterministic_for_dedupe():
    reg = _registration()
    raw = {"external_key": "https://evil.example.com/x?token=secret"}
    first = governance._safe_identity(raw, registration=reg)[1]  # noqa: SLF001
    second = governance._safe_identity(raw, registration=reg)[1]  # noqa: SLF001
    assert first == second  # retry-safe quarantine dedupe


def test_quarantine_entry_never_persists_raw_url_or_attacker_provider():
    reg = _registration()
    entry = governance._quarantine_for_code(  # noqa: SLF001
        {
            "provider": "attacker-provider",
            "external_key": "https://evil.example.com/exfil?x=1",
        },
        registration=reg,
        reason_code="schema_invalid",
    )

    serialized = json.dumps(entry.model_dump(mode="json"))
    assert entry.provider == FICTIONAL_PROVIDER  # registered provider persisted
    assert entry.safe_metadata.replaced_external_key is True
    # Neither the attacker provider nor the URL-like locator appears anywhere in
    # the persisted entry or its typed metadata.
    assert "attacker-provider" not in serialized
    assert "evil.example.com" not in serialized
    assert "https://" not in serialized
    assert "exfil" not in serialized


def test_quarantine_entry_for_missing_record_uses_registration_identity():
    # A malformed record with no identity of its own is still quarantined under
    # the registered provider/source, never raw/unknown text.
    reg = _registration()
    entry = governance._quarantine_for_code(  # noqa: SLF001
        {}, registration=reg, reason_code="schema_invalid_missing_field"
    )
    assert entry.provider == FICTIONAL_PROVIDER
    assert entry.source_name == FICTIONAL_SOURCE_NAME
    assert entry.content_sha256 != ""  # a digest, never raw content


# --- DB-backed source gate (Finding 1): deterministic, no network ---


class _StubCursor:
    """Minimal cursor that records SQL and returns a preset source row."""

    def __init__(self, row: tuple | None) -> None:
        self.row = row
        self.executed: list[tuple[str, tuple]] = []
        self.rowcount = 0

    def __enter__(self) -> _StubCursor:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def execute(self, sql: str, params: tuple | None = None) -> None:
        self.executed.append((sql, params or ()))

    def fetchone(self) -> tuple | None:
        return self.row


def _source_row(
    *,
    provider: str = FICTIONAL_PROVIDER,
    license_class: str = "licensed",
    terms_version: str = TERMS_VERSION,
    status: str = "active",
) -> tuple:
    return (
        provider,
        license_class,
        terms_version,
        "licensed_api_discovery",
        "metadata_and_aggregates_only",
        "no_raw_text_no_pii",
        status,
    )


def test_load_active_review_source_rejects_unregistered_source():
    cur = _StubCursor(row=None)
    with pytest.raises(governance.ReviewGovernanceError) as exc:
        governance.load_active_review_source(
            cur,
            source_name=FICTIONAL_SOURCE_NAME,
            expected_provider=FICTIONAL_PROVIDER,
            expected_terms_version=TERMS_VERSION,
        )
    assert exc.value.code == "source_not_registered"
    assert "ingest.review_sources" in cur.executed[0][0]


def test_load_active_review_source_rejects_disabled_source():
    cur = _StubCursor(row=_source_row(status="disabled"))
    with pytest.raises(governance.ReviewGovernanceError) as exc:
        governance.load_active_review_source(
            cur,
            source_name=FICTIONAL_SOURCE_NAME,
            expected_provider=FICTIONAL_PROVIDER,
            expected_terms_version=TERMS_VERSION,
        )
    assert exc.value.code == "source_disabled"


def test_load_active_review_source_rejects_rejected_license_class():
    cur = _StubCursor(row=_source_row(license_class="rejected"))
    with pytest.raises(governance.ReviewGovernanceError) as exc:
        governance.load_active_review_source(
            cur,
            source_name=FICTIONAL_SOURCE_NAME,
            expected_provider=FICTIONAL_PROVIDER,
            expected_terms_version=TERMS_VERSION,
        )
    assert exc.value.code == "source_license_rejected"


def test_load_active_review_source_rejects_provider_mismatch():
    cur = _StubCursor(row=_source_row(provider="other_provider"))
    with pytest.raises(governance.ReviewGovernanceError) as exc:
        governance.load_active_review_source(
            cur,
            source_name=FICTIONAL_SOURCE_NAME,
            expected_provider=FICTIONAL_PROVIDER,
            expected_terms_version=TERMS_VERSION,
        )
    assert exc.value.code == "source_provider_mismatch"


def test_load_active_review_source_rejects_terms_mismatch():
    cur = _StubCursor(row=_source_row(terms_version="other-terms-v2"))
    with pytest.raises(governance.ReviewGovernanceError) as exc:
        governance.load_active_review_source(
            cur,
            source_name=FICTIONAL_SOURCE_NAME,
            expected_provider=FICTIONAL_PROVIDER,
            expected_terms_version=TERMS_VERSION,
        )
    assert exc.value.code == "source_terms_mismatch"


def test_load_active_review_source_does_not_trust_caller_license_value():
    # The DB row says "licensed"; the caller passes nothing about license_class.
    # The gate trusts the DB row, not any caller-supplied licensed assertion.
    cur = _StubCursor(row=_source_row(license_class="licensed"))
    registration = governance.load_active_review_source(
        cur,
        source_name=FICTIONAL_SOURCE_NAME,
        expected_provider=FICTIONAL_PROVIDER,
        expected_terms_version=TERMS_VERSION,
    )
    assert registration.license_class == "licensed"
    assert registration.source_status == "active"


# --- Fake psycopg2 harness for the persistent path (one shared store) ---


class _FakeCursor:
    def __init__(self, store: dict[str, object]) -> None:
        self.store = store
        self.rowcount = 0
        self._fetchone: tuple | None = None

    def __enter__(self) -> _FakeCursor:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def execute(self, sql: str, params: tuple | None = None) -> None:
        params = tuple(params or ())
        self.store.setdefault("executed", []).append((sql, params))  # type: ignore[union-attr]
        sql_l = sql.lower()

        fail_on = self.store.get("fail_on")
        if isinstance(fail_on, str) and fail_on in sql_l:
            raise RuntimeError("simulated db failure")

        if "from ingest.review_sources" in sql_l:
            self._fetchone = self.store.get("source_row")  # type: ignore[assignment]
            self.rowcount = 0 if self._fetchone is None else 1
        elif "returning id" in sql_l:
            run_key = str(params[1])
            runs = self.store.setdefault("runs", {})  # type: ignore[union-attr]
            run_id = runs.get(run_key)  # type: ignore[union-attr]
            if run_id is None:
                run_id = f"run-{len(runs) + 1}"  # type: ignore[union-attr]
                runs[run_key] = run_id  # type: ignore[union-attr]
            self._fetchone = (run_id,)  # type: ignore[assignment]
            self.rowcount = 1
        elif "insert into ingest.review_ingest_receipts" in sql_l:
            source_name, external_key, content_sha256 = params[0], params[1], params[2]
            receipts = self.store.setdefault("receipts", {})  # type: ignore[union-attr]
            key = (source_name, external_key, content_sha256)
            if key in receipts:  # type: ignore[operator]
                self.rowcount = 0
            else:
                receipts[key] = {  # type: ignore[index]
                    "first_run_id": params[3],
                    "last_run_id": params[4],
                }
                self.rowcount = 1
        elif "update ingest.review_ingest_receipts" in sql_l:
            # Refresh last_run_id/last_seen_at on exact replay.
            source_name, external_key, content_sha256 = params[1], params[2], params[3]
            receipts = self.store.setdefault("receipts", {})  # type: ignore[union-attr]
            key = (source_name, external_key, content_sha256)
            if key in receipts:  # type: ignore[operator]
                receipts[key]["last_run_id"] = params[0]  # type: ignore[index]
            self.rowcount = 1
        elif "insert into community.ingest_quarantine" in sql_l:
            provider, external_key, reason_category = params[2], params[3], params[5]
            seen = self.store.setdefault("quarantine_seen", set())  # type: ignore[union-attr]
            key = (provider, external_key, reason_category)
            if key in seen:  # type: ignore[operator]
                self.rowcount = 0
            else:
                seen.add(key)  # type: ignore[union-attr]
                self.store.setdefault("quarantine_rows", []).append(params)  # type: ignore[union-attr]
                self.rowcount = 1
        elif "update community.ingest_runs" in sql_l:
            self.store.setdefault("finalized", []).append(params)  # type: ignore[union-attr]
            self.rowcount = 1
        elif "insert into ingest.review_sources" in sql_l:
            self.rowcount = 1
        else:
            self.rowcount = 1

    def fetchone(self) -> tuple | None:
        return self._fetchone


class _FakeConnection:
    def __init__(self, store: dict[str, object]) -> None:
        self.store = store

    def __enter__(self) -> _FakeConnection:
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:
        if exc_type is None:
            self.commit()
        else:
            self.rollback()
        return False

    def cursor(self) -> _FakeCursor:
        return _FakeCursor(self.store)

    def commit(self) -> None:
        self.store["committed"] = True  # type: ignore[assignment]

    def rollback(self) -> None:
        self.store["rolled_back"] = True  # type: ignore[assignment]

    def close(self) -> None:
        self.store["closed"] = True  # type: ignore[assignment]


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


def _prime_happy_source(store: dict[str, object]) -> None:
    store["source_row"] = _source_row()


# --- repository helpers (cursor-based) ---


def test_register_review_source_upserts_by_source_name_and_closes_connection(monkeypatch):
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    governance.register_review_source(
        dsn="postgresql://redacted",
        registration=_registration(),
        connect_timeout=7,
    )

    assert store["connects"] == [("postgresql://redacted", 7)]
    executed = [sql for sql, _ in store["executed"]]  # type: ignore[union-attr]
    assert any("INSERT INTO ingest.review_sources" in s for s in executed)
    assert any("ON CONFLICT (source_name) DO UPDATE" in s for s in executed)
    # Connection lifecycle: closed + committed (not leaked like the old
    # ``with psycopg2.connect(...)`` pattern).
    assert store.get("closed") is True
    assert store.get("committed") is True


def test_create_or_resume_ingest_run_writes_registered_source_fk():
    store: dict[str, object] = {}
    cur = _FakeCursor(store)
    registration = _registration()
    run_key = governance.build_run_key(
        source_name=registration.source_name,
        window_start=date(2026, 7, 20),
        schema_version=governance.GOVERNANCE_SCHEMA_VERSION,
    )

    first = governance._create_or_resume_ingest_run(  # noqa: SLF001
        cur, run_key=run_key, registration=registration, received_count=3
    )
    second = governance._create_or_resume_ingest_run(  # noqa: SLF001
        cur, run_key=run_key, registration=registration, received_count=3
    )

    assert first == second  # idempotent resume
    insert_sql = store["executed"][0][0]  # type: ignore[index]
    assert "INSERT INTO community.ingest_runs" in insert_sql
    assert "review_source_name" in insert_sql  # registered-source FK (Finding 2)
    assert "ON CONFLICT (run_key)" in insert_sql


def test_record_review_receipts_distinguishes_new_from_exact_replay():
    store: dict[str, object] = {}
    cur = _FakeCursor(store)
    record = governance.parse_review_record(_record_dict("post-1", seed="same"))

    new, replay = governance._record_review_receipts(  # noqa: SLF001
        cur, run_id="run-1", source_name=FICTIONAL_SOURCE_NAME, records=[record]
    )
    assert len(new) == 1 and len(replay) == 0

    # Same (source, external_key, content_sha256) in a *different* run -> replay.
    new2, replay2 = governance._record_review_receipts(  # noqa: SLF001
        cur, run_id="run-2", source_name=FICTIONAL_SOURCE_NAME, records=[record]
    )
    assert len(new2) == 0 and len(replay2) == 1
    # last_run_id is refreshed to the latest run on replay.
    assert (
        store["receipts"][  # type: ignore[index]
            (FICTIONAL_SOURCE_NAME, "post-1", record.content_sha256)
        ]["last_run_id"]
        == "run-2"
    )


def test_record_review_receipts_treats_content_revision_as_new():
    store: dict[str, object] = {}
    cur = _FakeCursor(store)
    original = governance.parse_review_record(_record_dict("post-1", seed="original text"))
    revised = governance.parse_review_record(
        _record_dict("post-1", seed="edited text")  # same external_key, NEW hash
    )
    assert original.content_sha256 != revised.content_sha256

    new1, _ = governance._record_review_receipts(  # noqa: SLF001
        cur, run_id="run-1", source_name=FICTIONAL_SOURCE_NAME, records=[original]
    )
    new2, _ = governance._record_review_receipts(  # noqa: SLF001
        cur, run_id="run-2", source_name=FICTIONAL_SOURCE_NAME, records=[revised]
    )

    assert len(new1) == 1
    assert len(new2) == 1  # content revision -> emits a fresh aggregate
    # Both receipt rows coexist (different content_sha256 for same external_key).
    assert len(store["receipts"]) == 2  # type: ignore[arg-type]


def test_record_review_receipts_dedupes_within_batch_via_persistent_arbiter():
    store: dict[str, object] = {}
    cur = _FakeCursor(store)
    record = governance.parse_review_record(_record_dict("post-1", seed="dup"))

    new, replay = governance._record_review_receipts(  # noqa: SLF001
        cur,
        run_id="run-1",
        source_name=FICTIONAL_SOURCE_NAME,
        records=[record, record],  # identical content twice in one batch
    )
    assert len(new) == 1
    assert len(replay) == 1


def test_insert_quarantine_entries_deduplicates_on_retry_and_persists_typed_metadata(
    monkeypatch,
):
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)  # makes psycopg2.extras.Json identity
    cur = _FakeCursor(store)
    entry = governance.ReviewQuarantineEntry(
        provider=FICTIONAL_PROVIDER,
        external_key="post-bad",
        content_sha256=_sha("post-bad", "x"),
        reason_code="schema_invalid_missing_field",
        source_name=FICTIONAL_SOURCE_NAME,
        received_at=RECEIVED_AT,
        safe_metadata=governance.QuarantineSafeMetadata(
            malformed=True, missing_field_name="content_sha256"
        ),
    )

    first = governance._insert_quarantine_entries(  # noqa: SLF001
        cur, entries=[entry, entry], run_id="run-1"
    )
    second = governance._insert_quarantine_entries(  # noqa: SLF001
        cur, entries=[entry], run_id="run-1"
    )

    assert first == 1  # in-batch dup skipped by ON CONFLICT
    assert second == 0  # cross-batch retry skipped too
    persisted = store["quarantine_rows"][0]  # type: ignore[index]
    # reason_code (params[6]) + code-backed reason (params[7]) persisted.
    assert persisted[6] == "schema_invalid_missing_field"
    assert persisted[7] == governance.REASON_SPEC["schema_invalid_missing_field"][1]
    # persisted[9] is the Json-wrapped typed metadata (here the raw dict).
    metadata = persisted[9]
    assert metadata["malformed"] is True  # type: ignore[index]
    assert metadata["missing_field_name"] == "content_sha256"  # type: ignore[index]
    # Typed metadata carries no raw-text keys, by construction.
    governance.enforce_no_raw_review_text(metadata, label="persisted_metadata")


def test_finalize_ingest_run_writes_retry_safe_absolute_counters():
    store: dict[str, object] = {}
    cur = _FakeCursor(store)
    governance._finalize_ingest_run(  # noqa: SLF001
        cur,
        run_id="run-1",
        status="succeeded",
        received_count=3,
        processed_count=2,
        duplicate_count=1,
        quarantined_count=0,
        failure_category="none",
        error_message=None,
    )
    sql = store["executed"][0][0]  # type: ignore[index]
    assert "UPDATE community.ingest_runs" in sql
    assert "received_count = %s" in sql  # retry-safe: overwritten, not just INSERT-time
    assert "processed_count = %s" in sql
    assert "duplicate_count = %s" in sql
    assert "failure_category = %s" in sql
    assert "WHERE id = %s" in sql
    # params[0]=status, params[1]=received_count -> the value is persisted.
    params = store["executed"][0][1]  # type: ignore[index]
    assert params[1] == 3


# --- atomic orchestrator (Finding 5): single transaction boundary ---


def test_persist_review_ingest_run_happy_path_emits_aggregate_for_new_only(monkeypatch):
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    _prime_happy_source(store)

    result = governance.persist_review_ingest_run(
        dsn="postgresql://redacted",
        source_name=FICTIONAL_SOURCE_NAME,
        expected_provider=FICTIONAL_PROVIDER,
        expected_terms_version=TERMS_VERSION,
        records=[_record_dict("post-1", seed="warm coffee")],
        window_start=date(2026, 7, 20),
        connect_timeout=7,
    )

    assert result.run.status == "succeeded"
    assert result.run.received_count == 1
    assert result.run.processed_count == 1
    assert result.run.duplicate_count == 0
    assert len(result.accepted) == 1
    governance.enforce_no_raw_review_text(result.accepted[0].to_rag_metadata(), label="accepted")
    # One connection == one transaction boundary.
    assert len(store["connects"]) == 1  # type: ignore[arg-type]
    assert store.get("committed") is True


def test_persist_review_ingest_run_skips_replay_across_separate_runs(monkeypatch):
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    _prime_happy_source(store)

    record = _record_dict("post-1", seed="stable content")
    first = governance.persist_review_ingest_run(
        dsn="postgresql://redacted",
        source_name=FICTIONAL_SOURCE_NAME,
        expected_provider=FICTIONAL_PROVIDER,
        expected_terms_version=TERMS_VERSION,
        records=[record],
        window_start=date(2026, 7, 20),
    )
    # Separate run, identical content -> exact replay, no downstream aggregate.
    second = governance.persist_review_ingest_run(
        dsn="postgresql://redacted",
        source_name=FICTIONAL_SOURCE_NAME,
        expected_provider=FICTIONAL_PROVIDER,
        expected_terms_version=TERMS_VERSION,
        records=[record],
        window_start=date(2026, 7, 27),  # different window -> different run_key
    )

    assert first.run.processed_count == 1
    assert len(first.accepted) == 1
    assert second.run.processed_count == 0
    assert second.run.duplicate_count == 1
    assert second.accepted == ()


def test_persist_review_ingest_run_emits_for_content_revision(monkeypatch):
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    _prime_happy_source(store)

    original = _record_dict("post-1", seed="original")
    governance.persist_review_ingest_run(
        dsn="postgresql://redacted",
        source_name=FICTIONAL_SOURCE_NAME,
        expected_provider=FICTIONAL_PROVIDER,
        expected_terms_version=TERMS_VERSION,
        records=[original],
        window_start=date(2026, 7, 20),
    )
    revised = _record_dict("post-1", seed="revised")  # same key, new hash
    second = governance.persist_review_ingest_run(
        dsn="postgresql://redacted",
        source_name=FICTIONAL_SOURCE_NAME,
        expected_provider=FICTIONAL_PROVIDER,
        expected_terms_version=TERMS_VERSION,
        records=[revised],
        window_start=date(2026, 7, 27),
    )

    assert second.run.processed_count == 1
    assert len(second.accepted) == 1


def test_persist_review_ingest_run_quarantines_malformed_with_typed_metadata(monkeypatch):
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    _prime_happy_source(store)

    malformed = _record_dict("post-bad", seed="x")
    del malformed["content_sha256"]

    result = governance.persist_review_ingest_run(
        dsn="postgresql://redacted",
        source_name=FICTIONAL_SOURCE_NAME,
        expected_provider=FICTIONAL_PROVIDER,
        expected_terms_version=TERMS_VERSION,
        records=[malformed],
        window_start=date(2026, 7, 20),
    )

    assert result.run.quarantined_count == 1
    assert result.run.processed_count == 0
    assert result.run.status == "succeeded"  # bad records routed correctly
    entry = result.quarantined[0]
    assert entry.reason_code == "schema_invalid_missing_field"
    assert entry.safe_metadata.missing_field_name == "content_sha256"
    governance.enforce_no_raw_review_text(entry.model_dump(), label="quarantine")
    governance.enforce_no_raw_review_text(
        entry.safe_metadata.model_dump(exclude_none=True), label="safe_metadata"
    )


@pytest.mark.parametrize(
    "source_row,expected_code",
    [
        (None, "source_not_registered"),
        (_source_row(status="disabled"), "source_disabled"),
        (_source_row(license_class="rejected"), "source_license_rejected"),
        (_source_row(provider="other_provider"), "source_provider_mismatch"),
        (_source_row(terms_version="other-terms-v2"), "source_terms_mismatch"),
    ],
)
def test_persist_review_ingest_run_rejects_gate_failures_and_writes_nothing(
    monkeypatch, source_row, expected_code
):
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    store["source_row"] = source_row

    with pytest.raises(governance.ReviewGovernanceError) as exc:
        governance.persist_review_ingest_run(
            dsn="postgresql://redacted",
            source_name=FICTIONAL_SOURCE_NAME,
            expected_provider=FICTIONAL_PROVIDER,
            expected_terms_version=TERMS_VERSION,
            records=[_record_dict("post-1", seed="x")],
            window_start=date(2026, 7, 20),
        )
    assert exc.value.code == expected_code
    # Gate fails before any run/receipt/quarantine is written -> nothing committed.
    assert store.get("committed") is not True
    assert "runs" not in store
    assert "receipts" not in store
    assert "quarantine_rows" not in store


def test_persist_review_ingest_run_rolls_back_on_late_failure(monkeypatch):
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    _prime_happy_source(store)
    # Inject a failure at the finalize step so the transaction must roll back.
    store["fail_on"] = "update community.ingest_runs"

    with pytest.raises(RuntimeError, match="simulated db failure"):
        governance.persist_review_ingest_run(
            dsn="postgresql://redacted",
            source_name=FICTIONAL_SOURCE_NAME,
            expected_provider=FICTIONAL_PROVIDER,
            expected_terms_version=TERMS_VERSION,
            records=[_record_dict("post-1", seed="x")],
            window_start=date(2026, 7, 20),
        )

    # Partial failure never exposes accepted aggregates (nothing returned) and
    # the single transaction boundary rolled back rather than committing.
    assert store.get("rolled_back") is True
    assert store.get("committed") is not True


# --- Additional hardening: resume idempotency, mid-tx rollback, invariants ---


def test_persist_review_ingest_run_resume_same_window_is_idempotent(monkeypatch):
    """Re-running the SAME window (same run_key) must not double-emit.

    The run row is resumed (same run id), and every receipt already exists
    from the first run, so the second run emits zero new aggregates and
    counts the records as duplicates.  This is the cross-run persistent
    dedupe guarantee for the *same* run_key, complementing the separate-run
    test which uses a different window.
    """
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    _prime_happy_source(store)

    record = _record_dict("post-1", seed="stable content")
    first = governance.persist_review_ingest_run(
        dsn="postgresql://redacted",
        source_name=FICTIONAL_SOURCE_NAME,
        expected_provider=FICTIONAL_PROVIDER,
        expected_terms_version=TERMS_VERSION,
        records=[record],
        window_start=date(2026, 7, 20),  # same window -> same run_key
    )
    second = governance.persist_review_ingest_run(
        dsn="postgresql://redacted",
        source_name=FICTIONAL_SOURCE_NAME,
        expected_provider=FICTIONAL_PROVIDER,
        expected_terms_version=TERMS_VERSION,
        records=[record],
        window_start=date(2026, 7, 20),  # SAME window -> resume same run_key
    )

    assert first.run.processed_count == 1
    assert len(first.accepted) == 1
    # Resume: run row reused, receipt already exists -> all replays.
    assert second.run.processed_count == 0
    assert second.run.duplicate_count == 1
    assert second.accepted == ()


def test_persist_review_ingest_run_received_count_is_retry_safe_on_resume(monkeypatch):
    """received_count must be retry-safe idempotent accounting (Finding 2).

    A resumed run (same ``run_key``) with an *expanded* record set must
    overwrite the DB accounting row's ``received_count`` with the latest
    value, exactly like processed/duplicate/quarantined counts. Finalize is
    the single retry-safe source of truth for the whole row -- the INSERT-time
    value must not survive a resume and go stale.
    """
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    _prime_happy_source(store)

    single = _record_dict("post-1", seed="stable content")
    governance.persist_review_ingest_run(
        dsn="postgresql://redacted",
        source_name=FICTIONAL_SOURCE_NAME,
        expected_provider=FICTIONAL_PROVIDER,
        expected_terms_version=TERMS_VERSION,
        records=[single],
        window_start=date(2026, 7, 20),
    )
    # First run finalized with received_count=1.
    finalized = [
        params for sql, params in store["executed"] if "status" in sql and "WHERE id" in sql
    ]  # type: ignore[union-attr]
    assert finalized, "finalize UPDATE should have executed"
    assert finalized[-1][1] == 1  # received_count is params[1] in the finalize UPDATE

    # Resume the SAME window (same run_key) with an expanded batch of 3 records.
    expanded = [
        single,  # exact replay (already receipted)
        _record_dict("post-2", seed="new content a"),  # new
        _record_dict("post-3", seed="new content b"),  # new
    ]
    result = governance.persist_review_ingest_run(
        dsn="postgresql://redacted",
        source_name=FICTIONAL_SOURCE_NAME,
        expected_provider=FICTIONAL_PROVIDER,
        expected_terms_version=TERMS_VERSION,
        records=expanded,
        window_start=date(2026, 7, 20),  # SAME window -> resume same run_key
    )
    # The returned summary reflects this attempt's input (3 received).
    assert result.run.received_count == 3
    assert result.run.processed_count == 2  # post-2/post-3 are new content
    assert result.run.duplicate_count == 1  # post-1 is an exact replay
    # The DB accounting row's received_count was overwritten to 3 (not stale at 1).
    finalized = [
        params for sql, params in store["executed"] if "status" in sql and "WHERE id" in sql
    ]  # type: ignore[union-attr]
    assert finalized[-1][1] == 3


def test_persist_review_ingest_run_rolls_back_on_receipt_failure(monkeypatch):
    """Failure during receipt insert must roll back the entire transaction.

    No aggregates are returned, nothing is committed, and the run row
    write (which happened before receipts) is rolled back by the single
    transaction boundary.
    """
    store: dict[str, object] = {}
    _install_fake_psycopg2(monkeypatch, store)
    _prime_happy_source(store)
    # Fail at the receipt-insert step (after run row is created).
    store["fail_on"] = "insert into ingest.review_ingest_receipts"

    with pytest.raises(RuntimeError, match="simulated db failure"):
        governance.persist_review_ingest_run(
            dsn="postgresql://redacted",
            source_name=FICTIONAL_SOURCE_NAME,
            expected_provider=FICTIONAL_PROVIDER,
            expected_terms_version=TERMS_VERSION,
            records=[_record_dict("post-1", seed="x")],
            window_start=date(2026, 7, 20),
        )

    assert store.get("rolled_back") is True
    assert store.get("committed") is not True


@pytest.mark.parametrize(
    "model_cls",
    [
        governance.ReviewIngestResult,
        governance.ReviewIngestRunSummary,
        governance.ApprovedReviewAggregate,
        governance.ReviewQuarantineEntry,
        governance.QuarantineSafeMetadata,
    ],
)
def test_review_models_carry_no_raw_text_field_names(model_cls):
    """No governance model field name may shadow a raw-text column."""
    field_names = set(model_cls.model_fields)
    assert field_names.isdisjoint(governance.RAW_REVIEW_TEXT_FIELDS), (
        f"{model_cls.__name__} declares a raw-text field name: "
        f"{field_names & set(governance.RAW_REVIEW_TEXT_FIELDS)}"
    )
