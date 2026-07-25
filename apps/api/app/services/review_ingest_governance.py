"""Licensed-source-ready review ingestion governance boundary.

This module is the first, independently-mergeable slice of the review/mention
ingestion pipeline. It owns *governance*, not acquisition: it validates a
supplied normalized source record, creates/reuses an idempotent ingest run,
deduplicates repeat records, routes malformed or unsafe records to quarantine,
and records counted, retry-safe run accounting.

Hard security invariant (G-TRUST): this foundation never emits raw review text
into ``rag.knowledge_chunks`` or any downstream write path. The only review
-derived output it produces is :class:`ApprovedReviewAggregate` -- a typed,
frozen, aggregate-only payload with no body/title/url fields. The runtime guard
:func:`enforce_no_raw_review_text` and the ``extra="forbid"`` model config make
any attempt to pass raw text through this boundary a quarantineable failure.

Persistence follows the repository conventions used by sibling services
(``review_mention_ingest``, ``job_runs``): DB calls ``import psycopg2`` lazily
inside the function and run behind the existing guarded batch tooling. This
module performs no live acquisition, no network calls, and reads no secrets.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from datetime import UTC, date, datetime
from typing import Any, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    ValidationError,
    field_validator,
    model_validator,
)

# Bumped only when this governance contract (models/columns/enums) changes.
GOVERNANCE_SCHEMA_VERSION = "review-ingest-governance-v1"

LicenseClass = Literal["licensed", "public_processed", "approved_export", "rejected"]
FailureCategory = Literal[
    "none",
    "schema_invalid",
    "terms_violation",
    "source_api_failure",
    "duplicate_suspect",
    "low_confidence",
    "ambiguous_match",
]
QuarantineReasonCategory = Literal[
    "schema_invalid",
    "terms_violation",
    "source_api_failure",
    "duplicate_suspect",
    "low_confidence",
    "ambiguous_match",
]

# Sources the pipeline may ingest from. ``rejected`` is registrable (so an
# operator can record a blocked source) but is never accepted for ingestion.
ALLOWED_LICENSE_CLASSES: tuple[LicenseClass, ...] = (
    "licensed",
    "public_processed",
    "approved_export",
)

# Fields that carry raw user text or private locators. Their presence in any
# record dict or downstream payload is a contract violation: the boundary
# accepts only already-normalized aggregate payloads, never raw review text.
RAW_REVIEW_TEXT_FIELDS: tuple[str, ...] = (
    "body",
    "body_ko",
    "body_en",
    "title",
    "title_ko",
    "text",
    "raw_text",
    "review_text",
    "post_url",
    "url",
)


class ReviewGovernanceError(RuntimeError):
    """Raised when governance state is inconsistent or a guard is violated."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class ReviewSourceRegistration(BaseModel):
    """A registered review source (one row in ``ingest.review_sources``)."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    source_name: str
    provider: str
    license_class: LicenseClass
    terms_version: str
    collection_method: str
    retention_policy: str
    redaction_policy: str
    source_status: Literal["active", "disabled"] = "active"


class ReviewSourceRecord(BaseModel):
    """A normalized source record supplied to the governance boundary.

    ``extra="forbid"`` is load-bearing: any raw-text field (body/title/url)
    accidentally supplied by an upstream normalizer becomes a validation error,
    which the orchestrator routes to quarantine as ``schema_invalid`` rather
    than letting raw text reach an aggregate payload.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    source_name: str
    provider: str
    external_key: str
    license_class: LicenseClass
    terms_version: str
    content_sha256: str
    received_at: datetime
    category: str | None = None
    match_confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    # Approved aggregate attributes only (e.g. {"taste": 0.7}). Never raw text.
    normalized_attributes: dict[str, Any] = Field(default_factory=dict)

    @field_validator("content_sha256")
    @classmethod
    def _content_sha256_is_hex(cls, value: str) -> str:
        normalized = value.lower()
        if len(normalized) != 64 or not all(
            character in "0123456789abcdef" for character in normalized
        ):
            raise ValueError("content_sha256 must be a 64-character hex sha256 digest")
        return normalized

    @model_validator(mode="after")
    def _no_raw_text_in_attributes(self) -> ReviewSourceRecord:
        offending = [key for key in self.normalized_attributes if key in RAW_REVIEW_TEXT_FIELDS]
        if offending:
            raise ValueError(
                "normalized_attributes must not carry raw-text fields: "
                + ", ".join(sorted(offending))
            )
        return self


class ApprovedReviewAggregate(BaseModel):
    """The only review-derived payload this foundation emits downstream.

    Deliberately aggregate-shaped: counts, scores, attribute values, and a
    hash-derived identity. No body, title, url, or provider identifier. This is
    what a later RAG slice is allowed to turn into a ``place_mention`` chunk.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    source_name: str
    aggregate_key: str
    category: str | None = None
    match_confidence: float | None = None
    mention_count: int = Field(default=1, ge=0)
    organic_mention_count: int = Field(default=1, ge=0)
    sentiment_score: float | None = Field(default=None, ge=-1.0, le=1.0)
    attribute_scores: dict[str, float] = Field(default_factory=dict)
    schema_version: str = GOVERNANCE_SCHEMA_VERSION

    def to_rag_metadata(self) -> dict[str, Any]:
        """Return the only fields a downstream RAG writer may persist."""
        return {
            "source_name": self.source_name,
            "category": self.category,
            "mention_count": self.mention_count,
            "organic_mention_count": self.organic_mention_count,
            "sentiment_score": self.sentiment_score,
            "attribute_scores": dict(self.attribute_scores),
            "schema_version": self.schema_version,
        }


class ReviewQuarantineEntry(BaseModel):
    """A dead-letter record persisted to ``community.ingest_quarantine``.

    Carries identity + hash + reason only. There is intentionally no field for
    the review body: quarantine must be diagnosable from metadata alone.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    provider: str
    external_key: str
    content_sha256: str
    reason_category: QuarantineReasonCategory
    reason: str
    source_name: str | None = None
    received_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    safe_metadata: dict[str, Any] = Field(default_factory=dict)


class ReviewIngestRunSummary(BaseModel):
    """Snapshot of the ingest-run ledger row for one governed batch."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    run_key: str
    source_name: str
    provider: str
    license_class: LicenseClass
    terms_version: str
    schema_version: str
    received_count: int
    processed_count: int
    duplicate_count: int
    quarantined_count: int
    failure_category: FailureCategory
    status: Literal["running", "succeeded", "failed"]


class ReviewIngestResult(BaseModel):
    """The full result of governing one batch of records."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    run: ReviewIngestRunSummary
    accepted: tuple[ApprovedReviewAggregate, ...]
    quarantined: tuple[ReviewQuarantineEntry, ...]


def build_run_key(
    *,
    source_name: str,
    window_start: date | None,
    schema_version: str,
) -> str:
    """Deterministic idempotency key for one (source, window, schema) batch.

    Re-running the same window with the same inputs reuses the same run row
    instead of creating a duplicate ledger entry.
    """
    window = window_start.isoformat() if window_start else "adhoc"
    return f"{source_name}|{window}|{schema_version}"


def enforce_no_raw_review_text(payload: Mapping[str, Any], *, label: str) -> None:
    """Raise if a downstream payload carries any forbidden raw-text field.

    Used to defend the RAG write boundary: even if a caller assembles a dict by
    hand, raw review text can never be admitted as an aggregate payload.
    """
    offending = [
        field for field in RAW_REVIEW_TEXT_FIELDS if payload.get(field) not in (None, "", [], {})
    ]
    if offending:
        raise ReviewGovernanceError(
            "raw_review_text_forbidden",
            f"{label} carries forbidden raw-text fields: {', '.join(sorted(offending))}",
        )


def parse_review_record(data: Mapping[str, Any]) -> ReviewSourceRecord:
    """Validate one normalized record dict, raising on malformed input."""
    return ReviewSourceRecord.model_validate(dict(data))


def approved_aggregate_from_record(
    record: ReviewSourceRecord,
) -> ApprovedReviewAggregate:
    """Project a validated record into the aggregate-only downstream payload."""
    attribute_scores = {
        key: float(value)
        for key, value in record.normalized_attributes.items()
        if isinstance(value, int | float)
    }
    return ApprovedReviewAggregate(
        source_name=record.source_name,
        # Identity for dedupe/audit, derived from the content hash -- not raw text.
        aggregate_key=f"sha256:{record.content_sha256[:16]}",
        category=record.category,
        match_confidence=record.match_confidence,
        sentiment_score=None,
        attribute_scores=attribute_scores,
    )


def _quarantine_from_raw(
    raw: Mapping[str, Any],
    *,
    registration: ReviewSourceRegistration | None,
    reason_category: QuarantineReasonCategory,
    reason: str,
) -> ReviewQuarantineEntry:
    """Build a quarantine entry from an unvalidated/raw dict, without raw text.

    Identity is best-effort from the dict; missing fields fall back to safe
    placeholders so a malformed record is still quarantinable and countable.
    """
    provider = str(raw.get("provider") or (registration.provider if registration else "unknown"))
    external_key = str(raw.get("external_key") or "unknown")
    content_sha256 = str(raw.get("content_sha256") or _fallback_hash(raw))
    source_name = (
        registration.source_name
        if registration
        else (str(raw.get("source_name")) or None if raw.get("source_name") else None)
    )
    return ReviewQuarantineEntry(
        provider=provider,
        external_key=external_key,
        content_sha256=content_sha256,
        reason_category=reason_category,
        reason=reason,
        source_name=source_name,
        safe_metadata={"malformed": True},
    )


def _fallback_hash(raw: Mapping[str, Any]) -> str:
    import hashlib

    stable = "|".join(f"{key}={raw[key]}" for key in sorted(raw))
    return hashlib.sha256(stable.encode("utf-8")).hexdigest()


def govern_review_records(
    *,
    registration: ReviewSourceRegistration,
    records: Sequence[Mapping[str, Any]],
    window_start: date | None = None,
) -> ReviewIngestResult:
    """Govern one batch: validate, dedupe, quarantine, and account.

    Pure (no DB). Persistence is performed separately by the ``*_ingest_run``
    and ``insert_quarantine_entries`` repository helpers so this function is
    deterministic and trivially testable.
    """
    run_key = build_run_key(
        source_name=registration.source_name,
        window_start=window_start,
        schema_version=GOVERNANCE_SCHEMA_VERSION,
    )
    received_count = len(records)
    accepted: list[ApprovedReviewAggregate] = []
    quarantined: list[ReviewQuarantineEntry] = []
    seen_hashes: set[str] = set()
    duplicate_count = 0

    # License gate: a non-ingestible source quarantines the whole batch.
    if registration.license_class not in ALLOWED_LICENSE_CLASSES:
        for raw in records:
            quarantined.append(
                _quarantine_from_raw(
                    raw,
                    registration=registration,
                    reason_category="terms_violation",
                    reason=(
                        f"source license_class '{registration.license_class}' "
                        "is not permitted for review ingestion"
                    ),
                )
            )
        return _build_result(
            run_key=run_key,
            registration=registration,
            received_count=received_count,
            accepted=accepted,
            quarantined=quarantined,
            duplicate_count=duplicate_count,
            failure_category="terms_violation",
            status="failed",
        )

    for raw in records:
        try:
            record = parse_review_record(raw)
        except (ValidationError, ValueError):
            quarantined.append(
                _quarantine_from_raw(
                    raw,
                    registration=registration,
                    reason_category="schema_invalid",
                    reason=(
                        "normalized record failed schema validation "
                        "(missing fields, bad hash, or raw-text field present)"
                    ),
                )
            )
            continue

        if record.content_sha256 in seen_hashes:
            duplicate_count += 1
            continue
        seen_hashes.add(record.content_sha256)
        accepted.append(approved_aggregate_from_record(record))

    failure_category: FailureCategory = (
        "none" if not quarantined else _dominant_reason_category(quarantined)
    )
    # A run that routes bad records to quarantine still completed correctly;
    # only the license-rejected path (nothing processed) is a failure.
    status: Literal["running", "succeeded", "failed"] = "succeeded"
    return _build_result(
        run_key=run_key,
        registration=registration,
        received_count=received_count,
        accepted=accepted,
        quarantined=quarantined,
        duplicate_count=duplicate_count,
        failure_category=failure_category,
        status=status,
    )


def _dominant_reason_category(
    entries: Sequence[ReviewQuarantineEntry],
) -> QuarantineReasonCategory:
    counts: dict[str, int] = {}
    for entry in entries:
        counts[entry.reason_category] = counts.get(entry.reason_category, 0) + 1
    dominant = max(counts, key=lambda key: counts[key])
    return dominant  # type: ignore[return-value]


def _build_result(
    *,
    run_key: str,
    registration: ReviewSourceRegistration,
    received_count: int,
    accepted: Sequence[ApprovedReviewAggregate],
    quarantined: Sequence[ReviewQuarantineEntry],
    duplicate_count: int,
    failure_category: FailureCategory,
    status: Literal["running", "succeeded", "failed"],
) -> ReviewIngestResult:
    summary = ReviewIngestRunSummary(
        run_key=run_key,
        source_name=registration.source_name,
        provider=registration.provider,
        license_class=registration.license_class,
        terms_version=registration.terms_version,
        schema_version=GOVERNANCE_SCHEMA_VERSION,
        received_count=received_count,
        processed_count=len(accepted),
        duplicate_count=duplicate_count,
        quarantined_count=len(quarantined),
        failure_category=failure_category,
        status=status,
    )
    return ReviewIngestResult(
        run=summary,
        accepted=tuple(accepted),
        quarantined=tuple(quarantined),
    )


# --- Repository helpers (lazy psycopg2; existing batch-tool conventions) ---


def register_review_source(
    *,
    dsn: str,
    registration: ReviewSourceRegistration,
    connect_timeout: int,
) -> None:
    """Idempotently upsert a review-source registration row."""
    if not dsn:
        raise ValueError("DB_DSN is required.")

    import psycopg2

    sql = """
        INSERT INTO ingest.review_sources (
            source_name,
            provider,
            license_class,
            terms_version,
            collection_method,
            retention_policy,
            redaction_policy,
            source_status,
            updated_at
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, now())
        ON CONFLICT (source_name) DO UPDATE SET
            provider = EXCLUDED.provider,
            license_class = EXCLUDED.license_class,
            terms_version = EXCLUDED.terms_version,
            collection_method = EXCLUDED.collection_method,
            retention_policy = EXCLUDED.retention_policy,
            redaction_policy = EXCLUDED.redaction_policy,
            source_status = EXCLUDED.source_status,
            updated_at = now()
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            cur.execute(
                sql,
                (
                    registration.source_name,
                    registration.provider,
                    registration.license_class,
                    registration.terms_version,
                    registration.collection_method,
                    registration.retention_policy,
                    registration.redaction_policy,
                    registration.source_status,
                ),
            )
        conn.commit()


def create_or_resume_ingest_run(
    *,
    dsn: str,
    run_key: str,
    registration: ReviewSourceRegistration,
    received_count: int,
    connect_timeout: int,
) -> str:
    """Create the run ledger row or resume an existing one for ``run_key``.

    Returns the run id. The no-op ``DO UPDATE`` exists only so ``RETURNING id``
    yields the existing id on retry (idempotent resume).
    """
    if not dsn:
        raise ValueError("DB_DSN is required.")

    import psycopg2

    sql = """
        INSERT INTO community.ingest_runs (
            provider,
            status,
            run_key,
            source_name,
            license_class,
            terms_version,
            schema_version,
            received_count,
            started_at
        )
        VALUES (%s, 'running', %s, %s, %s, %s, %s, %s, now())
        ON CONFLICT (run_key) WHERE run_key IS NOT NULL
        DO UPDATE SET received_count = community.ingest_runs.received_count
        RETURNING id
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            cur.execute(
                sql,
                (
                    registration.provider,
                    run_key,
                    registration.source_name,
                    registration.license_class,
                    registration.terms_version,
                    GOVERNANCE_SCHEMA_VERSION,
                    received_count,
                ),
            )
            row = cur.fetchone()
        conn.commit()
    if not row:
        raise ReviewGovernanceError(
            "run_not_created",
            "ingest run upsert returned no row",
        )
    return str(row[0])


def finalize_ingest_run(
    *,
    dsn: str,
    run_id: str,
    status: Literal["running", "succeeded", "failed"],
    processed_count: int,
    duplicate_count: int,
    quarantined_count: int,
    failure_category: FailureCategory,
    error_message: str | None,
    connect_timeout: int,
) -> None:
    """Write final counters/status to the run ledger (retry-safe, absolute)."""
    if not dsn:
        raise ValueError("DB_DSN is required.")

    import psycopg2

    sql = """
        UPDATE community.ingest_runs
        SET status = %s,
            processed_count = %s,
            duplicate_count = %s,
            quarantined_count = %s,
            failure_category = %s,
            error_message = %s,
            finished_at = now()
        WHERE id = %s
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            cur.execute(
                sql,
                (
                    status,
                    processed_count,
                    duplicate_count,
                    quarantined_count,
                    failure_category,
                    error_message,
                    run_id,
                ),
            )
        conn.commit()


def insert_quarantine_entries(
    *,
    dsn: str,
    entries: Sequence[ReviewQuarantineEntry],
    run_id: str,
    connect_timeout: int,
) -> int:
    """Persist quarantine rows, deduped by the partial unique index.

    Returns the number actually inserted so run accounting stays stable when a
    failed batch is retried (re-running does not double-count dead-letter rows).
    """
    if not dsn:
        raise ValueError("DB_DSN is required.")
    if not entries:
        return 0

    import psycopg2
    from psycopg2.extras import Json

    sql = """
        INSERT INTO community.ingest_quarantine (
            source_run_id,
            source_name,
            provider,
            external_key,
            content_sha256,
            reason_category,
            reason,
            received_at,
            safe_metadata
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (provider, external_key, reason_category)
        WHERE resolved_at IS NULL
        DO NOTHING
    """
    inserted = 0
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            for entry in entries:
                cur.execute(
                    sql,
                    (
                        run_id,
                        entry.source_name,
                        entry.provider,
                        entry.external_key,
                        entry.content_sha256,
                        entry.reason_category,
                        entry.reason,
                        entry.received_at,
                        Json(entry.safe_metadata),
                    ),
                )
                inserted += int(cur.rowcount or 0)
        conn.commit()
    return inserted
