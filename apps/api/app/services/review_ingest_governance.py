"""Licensed-source-ready review ingestion governance boundary (DB-backed).

This module is the first, independently-mergeable slice of the review/mention
ingestion pipeline. It owns *governance*, not acquisition: it loads and
validates a registered source from the database, creates/reuses an idempotent
ingest run, persistently deduplicates repeat records by content hash, routes
malformed or unsafe records to a typed quarantine, and records counted,
retry-safe run accounting -- all inside a single transaction boundary.

Trust model (G-TRUST / Finding 1): the worker ingest path never trusts a
caller-supplied ``license_class``. The active source row is loaded from
``ingest.review_sources`` and the batch is rejected up front when the source is
absent, disabled, rejected, or its provider/terms do not match the caller's
expectations. Source registration is restricted to internal/admin code
(:func:`register_review_source`); there is deliberately no public endpoint.
This is enforced **per record**, not just per batch: every accepted record's
``source_name``/``provider``/``license_class``/``terms_version`` must exactly
equal the loaded registration, and accepted records are then *bound* to the
registration so no caller-controlled source identity can reach an aggregate,
receipt, or RAG metadata.

Normalized attributes (Finding 2): :attr:`ReviewSourceRecord.normalized_attributes`
is a strict, bounded, recursively-safe ``metric_key -> score`` mapping. Keys are
restricted to the repository's existing review-attribute vocabulary and values
are numeric scores in ``[0.0, 1.0]``. Strings, bools, nested objects/lists,
raw-text keys, and unknown/free-form keys are rejected and routed to quarantine
as ``schema_invalid_attribute_shape`` -- they can never become persisted
attribute metadata or an aggregate score.

Safe quarantine identity (Finding 3): quarantine identity never carries
untrusted raw strings. Provider and source come from the DB registration
whenever one is loaded; ``external_key`` is validated as a bounded opaque
identifier and, when malformed (URL-like, too long, whitespace, non-ASCII),
replaced by a deterministic digest-derived token rather than the original
value. ``content_sha256`` is always a 64-char hex digest. Only raw-content
hashes are ever persisted -- never raw provider text or URL-like locators.

Hard security invariant (G-TRUST): this foundation never emits raw review text
into ``rag.knowledge_chunks`` or any downstream write path. The only review
-derived output it produces is :class:`ApprovedReviewAggregate` -- a typed,
frozen, aggregate-only payload with no body/title/url fields. Quarantine
entries carry identity + hash + a code-backed reason + a typed/whitelisted
metadata blob only (Finding 4): raw body/title/url/provider response text can
never be persisted to quarantine, logs, API payloads, or RAG metadata.

Persistence (Finding 5): :func:`persist_review_ingest_run` is the one
transaction boundary. Source lookup, run create/resume, receipt dedupe,
quarantine insert, and final accounting all run inside a single
``with conn:`` block -- commit on success, rollback on any error -- so partial
failures never expose accepted aggregates.

Persistence follows the repository conventions used by sibling services
(``review_mention_ingest``, ``community_service``): DB calls ``import psycopg2``
lazily inside the function and run behind the existing guarded batch tooling.
This module performs no live acquisition, no network calls, and reads no
secrets.
"""

from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from contextlib import closing
from datetime import UTC, date, datetime
from typing import Any, Literal, get_args

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    ValidationError,
    field_validator,
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
# Coarse DB-facing category (matches the community.ingest_quarantine CHECK).
QuarantineReasonCategory = Literal[
    "schema_invalid",
    "terms_violation",
    "source_api_failure",
    "duplicate_suspect",
    "low_confidence",
    "ambiguous_match",
]
# Finer, code-backed reason token. Every value is a fixed enumerable string
# drawn from this Literal -- it can never carry raw body/title/url text. The
# human-readable ``reason`` is produced from a fixed template per code
# (REASON_SPEC), never by interpolating record content.
QuarantineReasonCode = Literal[
    "schema_invalid",
    "schema_invalid_missing_field",
    "schema_invalid_bad_hash",
    "schema_invalid_raw_text_field",
    "schema_invalid_type_error",
    "schema_invalid_extra_field",
    "schema_invalid_attribute_shape",
    "source_identity_mismatch",
    "terms_violation_license_class",
    "source_api_failure_upstream",
    "duplicate_suspect_in_batch",
    "low_confidence_match",
    "ambiguous_match_place",
]
MissingFieldName = Literal[
    "source_name",
    "provider",
    "external_key",
    "license_class",
    "terms_version",
    "content_sha256",
    "received_at",
]
RawTextFieldName = Literal[
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
]
# Per-record provenance fields that must exactly match the DB-authoritative
# registered source (Finding 1). A record claiming any of these differently
# from its registered source is quarantined, never accepted.
IdentityField = Literal["source_name", "provider", "license_class", "terms_version"]
# Precise sub-reason recorded in quarantine metadata when a normalized-attribute
# payload violates the strict metric-score contract (Finding 2).
AttributeShapeViolation = Literal[
    "non_numeric_value",
    "nested_object",
    "unknown_key",
    "raw_text_key",
    "out_of_range",
]
# Conservative, explicit metric-key contract for normalized attribute scores
# (Finding 2). This is the repository's existing review-attribute vocabulary
# (the union of ATTRIBUTE_TERMS keys in review_attribute_batch.py /
# review_mention_ingest.py): taste/service/price/atmosphere/cleanliness/
# wait_crowding/cultural_story/walking_comfort/photo_view/practical_tip/
# crowding/program_quality/family_friendliness/foreign_visitor_fit/access/
# weather_indoor_fit/local_experience. No free-form key may become persisted
# attribute metadata; every accepted score is numeric and bounded to [0.0, 1.0].
NormalizedAttributeKey = Literal[
    "taste",
    "service",
    "price",
    "atmosphere",
    "cleanliness",
    "wait_crowding",
    "cultural_story",
    "walking_comfort",
    "photo_view",
    "practical_tip",
    "crowding",
    "program_quality",
    "family_friendliness",
    "foreign_visitor_fit",
    "access",
    "weather_indoor_fit",
    "local_experience",
]
ALLOWED_ATTRIBUTE_KEYS: frozenset[str] = frozenset(get_args(NormalizedAttributeKey))

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

# Fixed, code-backed reason templates (Finding 4). The persisted ``reason`` text
# is ALWAYS one of these strings -- it is never built from raw record content.
# Maps reason_code -> (coarse reason_category, human-readable reason template).
REASON_SPEC: dict[QuarantineReasonCode, tuple[QuarantineReasonCategory, str]] = {
    "schema_invalid": (
        "schema_invalid",
        "normalized record failed schema validation",
    ),
    "schema_invalid_missing_field": (
        "schema_invalid",
        "normalized record failed schema validation: required field missing",
    ),
    "schema_invalid_bad_hash": (
        "schema_invalid",
        "normalized record failed schema validation: content_sha256 is not a 64-char hex digest",
    ),
    "schema_invalid_raw_text_field": (
        "schema_invalid",
        "normalized record failed schema validation: raw-text field present",
    ),
    "schema_invalid_type_error": (
        "schema_invalid",
        "normalized record failed schema validation: field type/value out of range",
    ),
    "schema_invalid_extra_field": (
        "schema_invalid",
        "normalized record failed schema validation: extra field rejected by allowlist",
    ),
    "schema_invalid_attribute_shape": (
        "schema_invalid",
        "normalized_attributes failed the strict metric-score contract",
    ),
    "source_identity_mismatch": (
        "terms_violation",
        "record provenance does not match the registered source",
    ),
    "terms_violation_license_class": (
        "terms_violation",
        "source license class is not permitted for review ingestion",
    ),
    "source_api_failure_upstream": (
        "source_api_failure",
        "upstream source API call failed",
    ),
    "duplicate_suspect_in_batch": (
        "duplicate_suspect",
        "record flagged as duplicate suspect",
    ),
    "low_confidence_match": (
        "low_confidence",
        "match confidence below acceptance threshold",
    ),
    "ambiguous_match_place": (
        "ambiguous_match",
        "place match was ambiguous",
    ),
}


class ReviewGovernanceError(RuntimeError):
    """Raised when governance state is inconsistent or a guard is violated."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class AttributeShapeError(ValueError):
    """Raised when normalized_attributes violates the strict metric contract.

    Carries the precise :data:`AttributeShapeViolation` kind so the quarantine
    metadata can record it without ever reading raw attribute content.
    """

    def __init__(self, violation: AttributeShapeViolation, message: str) -> None:
        super().__init__(message)
        self.violation = violation


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
    # Approved aggregate attributes only (e.g. {"taste": 0.7}). The contract is
    # strict and bounded (Finding 2): keys are restricted to the repository's
    # metric vocabulary and values are numeric scores in [0.0, 1.0]. No strings,
    # nested objects/lists, or free-form keys can reach an aggregate. Enforcement
    # happens in the before-validator via _coerce_normalized_attributes.
    normalized_attributes: dict[NormalizedAttributeKey, float] = Field(default_factory=dict)

    @field_validator("content_sha256")
    @classmethod
    def _content_sha256_is_hex(cls, value: str) -> str:
        normalized = value.lower()
        if len(normalized) != 64 or not all(
            character in "0123456789abcdef" for character in normalized
        ):
            raise ValueError("content_sha256 must be a 64-character hex sha256 digest")
        return normalized

    @field_validator("normalized_attributes", mode="before")
    @classmethod
    def _strict_normalized_attributes(cls, value: Any) -> dict[str, float]:
        # Enforce the strict, bounded, recursively-safe shape before Pydantic's
        # lax coercion can turn a string ("0.8") or nested object into a score.
        return _coerce_normalized_attributes(value)


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
    attribute_scores: dict[NormalizedAttributeKey, float] = Field(default_factory=dict)
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


class QuarantineSafeMetadata(BaseModel):
    """Typed, whitelisted quarantine metadata (Finding 4).

    Every field is a boolean, a bounded number, or a fixed enumerable Literal
    token. There is intentionally no free-form ``str`` field: raw body/title/
    url/provider-response text can never be stored here. This is the only shape
    the boundary will serialize into the ``safe_metadata`` jsonb column.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    malformed: bool = False
    missing_field_name: MissingFieldName | None = None
    raw_text_field: RawTextFieldName | None = None
    extra_field_present: bool = False
    bad_hash: bool = False
    type_error: bool = False
    mismatched_identity_field: IdentityField | None = None
    attribute_shape_violation: AttributeShapeViolation | None = None
    replaced_external_key: bool = False
    received_field_count: int | None = Field(default=None, ge=0)
    attribute_count: int | None = Field(default=None, ge=0)
    match_confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    expected_license_class: LicenseClass | None = None


class ReviewQuarantineEntry(BaseModel):
    """A dead-letter record persisted to ``community.ingest_quarantine``.

    Carries identity + hash + a code-backed reason + typed metadata only. There
    is intentionally no field for the review body: quarantine must be
    diagnosable from metadata alone. ``reason`` and ``reason_category`` are
    derived from the fixed ``reason_code`` via :data:`REASON_SPEC` -- they are
    never assembled from raw record content.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    provider: str
    external_key: str
    content_sha256: str
    reason_code: QuarantineReasonCode
    source_name: str | None = None
    received_at: datetime
    safe_metadata: QuarantineSafeMetadata = Field(default_factory=QuarantineSafeMetadata)

    @property
    def reason_category(self) -> QuarantineReasonCategory:
        return REASON_SPEC[self.reason_code][0]

    @property
    def reason(self) -> str:
        return REASON_SPEC[self.reason_code][1]


class ReviewIngestRunSummary(BaseModel):
    """Snapshot of the ingest-run accounting row for one governed batch."""

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
    instead of creating a duplicate accounting entry.
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
    """Project a validated record into the aggregate-only downstream payload.

    ``record`` is the DB-registration-bound record produced by
    :func:`classify_review_records`, so ``record.source_name`` is the registered
    source -- never a caller-supplied value (Finding 1).
    """
    return ApprovedReviewAggregate(
        source_name=record.source_name,
        # Identity for dedupe/audit, derived from the content hash -- not raw text.
        aggregate_key=f"sha256:{record.content_sha256[:16]}",
        category=record.category,
        match_confidence=record.match_confidence,
        sentiment_score=None,
        attribute_scores=dict(record.normalized_attributes),
    )


# --- pure validation (no DB; deterministic; unit-tested directly) ---


def _classify_validation_error(
    exc: ValidationError,
) -> tuple[QuarantineReasonCode, QuarantineSafeMetadata]:
    """Map a Pydantic ValidationError to a code-backed reason + typed metadata.

    No raw record content is read: only Pydantic's structured error tokens
    (``type``, ``loc``), which are field names/categories rather than values.
    """
    metadata = QuarantineSafeMetadata(malformed=True)
    code: QuarantineReasonCode = "schema_invalid"
    for err in exc.errors():
        err_type = err.get("type", "")
        loc = err.get("loc", ())
        loc_leaf = str(loc[-1]) if loc else ""
        # Backstop: classify only catches attribute errors here when they reach
        # Pydantic; the normal path quarantines them precisely upstream in
        # classify_review_records via _coerce_normalized_attributes.
        if loc and loc[0] == "normalized_attributes":
            metadata = metadata.model_copy(
                update={"attribute_shape_violation": "non_numeric_value"}  # type: ignore[arg-type]
            )
            code = "schema_invalid_attribute_shape"
            return code, metadata
        if err_type == "missing" and loc_leaf in {
            "source_name",
            "provider",
            "external_key",
            "license_class",
            "terms_version",
            "content_sha256",
            "received_at",
        }:
            metadata = metadata.model_copy(
                update={"missing_field_name": loc_leaf}  # type: ignore[arg-type]
            )
            code = "schema_invalid_missing_field"
            return code, metadata
        if err_type == "extra_forbidden" or loc_leaf in RAW_REVIEW_TEXT_FIELDS:
            field_name = loc_leaf if loc_leaf in RAW_REVIEW_TEXT_FIELDS else None
            updates: dict[str, Any] = {"extra_field_present": True}
            if field_name is not None:
                updates["raw_text_field"] = field_name  # type: ignore[assignment]
            metadata = metadata.model_copy(update=updates)
            code = (
                "schema_invalid_raw_text_field"
                if field_name is not None
                else "schema_invalid_extra_field"
            )
            return code, metadata
        if loc_leaf == "content_sha256" and err_type == "value_error":
            metadata = metadata.model_copy(update={"bad_hash": True})
            code = "schema_invalid_bad_hash"
            return code, metadata
        if err_type in {
            "int_type",
            "float_type",
            "string_type",
            "bool_type",
            "less_than_equal",
            "greater_than_equal",
            "less_than",
            "greater_than",
            "datetime_parsing",
        }:
            metadata = metadata.model_copy(update={"type_error": True})
            code = "schema_invalid_type_error"
    return code, metadata


def _sha256_hex(material: str) -> str:
    """Return the sha256 hex digest of ``material`` (lazy stdlib import)."""
    import hashlib

    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def _fallback_hash(raw: Mapping[str, Any]) -> str:
    """Best-effort stable digest for an unvalidated raw dict (identity only).

    Used only when a malformed record omits a valid ``content_sha256`` so the
    row is still countable/deduplicable. Keys are field names; values enter the
    hash input via repr but ONLY the 64-char hex digest escapes -- raw text is
    never persisted, returned, or logged by this helper (Finding 3).
    """
    stable = "|".join(f"{key}={raw[key]!r}" for key in sorted(raw))
    return _sha256_hex(stable)


# Bound on the material fed to a digest token, so a pathologically large
# attacker-supplied identity field cannot make hashing unbounded.
_SAFE_HASH_INPUT_MAX = 4096


def _digest_token(label: str, raw_value: object) -> str:
    """Return a deterministic digest-derived token; never the raw value.

    Replaces an untrusted identity field (e.g. a URL-like external_key) with an
    opaque, stable id of the form ``<label>_sha256:<hex16>``. Only the digest
    escapes; the raw input is never persisted or logged (Finding 3).
    """
    material = repr(raw_value)[:_SAFE_HASH_INPUT_MAX]
    return f"{label}_sha256:{_sha256_hex(material)[:16]}"


def _coerce_normalized_attributes(value: Any) -> dict[str, float]:
    """Enforce the strict, bounded, recursively-safe attribute contract (Finding 2).

    Accepted shape: ``{metric_key: score}`` where keys are restricted to the
    repository's attribute vocabulary and scores are real numbers in [0.0, 1.0].
    Strings, bools, nested objects/lists, raw-text keys, and unknown/free-form
    keys all raise :class:`AttributeShapeError`. Returns the cleaned mapping.
    """
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise AttributeShapeError(
            "non_numeric_value", "normalized_attributes must be a metric->score object"
        )
    cleaned: dict[str, float] = {}
    for key, raw_value in value.items():
        if not isinstance(key, str):
            raise AttributeShapeError(
                "unknown_key", "normalized_attributes key must be a string metric name"
            )
        if key in RAW_REVIEW_TEXT_FIELDS:
            raise AttributeShapeError(
                "raw_text_key", f"normalized_attributes must not carry raw-text fields: {key}"
            )
        if key not in ALLOWED_ATTRIBUTE_KEYS:
            raise AttributeShapeError(
                "unknown_key", f"normalized_attributes key is not an allowed metric: {key!r}"
            )
        if isinstance(raw_value, dict | list):
            raise AttributeShapeError(
                "nested_object",
                f"normalized_attributes[{key!r}] must be a number, not a nested value",
            )
        if isinstance(raw_value, bool) or not isinstance(raw_value, int | float):
            raise AttributeShapeError(
                "non_numeric_value", f"normalized_attributes[{key!r}] must be a number"
            )
        score = float(raw_value)
        if score < 0.0 or score > 1.0:
            raise AttributeShapeError(
                "out_of_range", f"normalized_attributes[{key!r}] score must be within [0.0, 1.0]"
            )
        cleaned[key] = score
    return cleaned


# A bounded opaque external identifier: ASCII alphanumerics plus a small set of
# separator punctuation, 1-96 chars. Anything broader (URLs, free text,
# whitespace, non-ASCII) is treated as malformed and replaced by a digest token
# so no attacker-controlled locator/string is ever persisted (Finding 3).
_EXTERNAL_KEY_PATTERN = re.compile(r"[A-Za-z0-9_.:-]{1,96}")


def _sanitize_external_key(value: object) -> tuple[str, bool]:
    """Validate external_key as a bounded opaque identifier (Finding 3).

    Returns ``(external_key, replaced)``. A clean identifier is returned
    unchanged (``replaced=False``); a malformed one (URL-like, too long,
    whitespace, non-ASCII, non-string) is replaced by a deterministic digest
    token (``replaced=True``) so the raw value is never persisted.
    """
    if not isinstance(value, str):
        return _digest_token("external_key", value), True
    candidate = value.strip()
    if candidate and _EXTERNAL_KEY_PATTERN.fullmatch(candidate):
        # Keep the trimmed form; flag replacement only when trimming changed it.
        return candidate, candidate != value
    return _digest_token("external_key", candidate), True


def _safe_content_sha256(raw: Mapping[str, Any]) -> str:
    """Return a 64-char hex content digest for identity; never raw content.

    A well-formed sha256 hex digest is passed through; anything else is replaced
    by :func:`_fallback_hash` so the column always holds a digest-shaped id.
    """
    candidate = raw.get("content_sha256")
    if isinstance(candidate, str):
        normalized = candidate.lower()
        if len(normalized) == 64 and all(c in "0123456789abcdef" for c in normalized):
            return normalized
    return _fallback_hash(raw)


def _safe_identity(
    raw: Mapping[str, Any],
    *,
    registration: ReviewSourceRegistration | None,
) -> tuple[str, str, str, str | None, bool]:
    """Extract quarantine identity (provider, external_key, sha, source_name, replaced).

    Provider and source always come from the DB registration when available;
    raw caller-supplied provider/source text is never persisted (Finding 3).
    ``external_key`` is validated as a bounded opaque identifier and replaced by
    a digest token when malformed. ``content_sha256`` is always a 64-char hex
    digest. The fifth return value reports whether external_key was replaced.
    """
    # Provider/source: DB-authoritative when a registration is loaded; never raw.
    if registration is not None:
        provider = registration.provider
        source_name = registration.source_name
    else:
        provider = "unknown"
        source_name = None
    external_key, replaced_external_key = _sanitize_external_key(raw.get("external_key"))
    content_sha256 = _safe_content_sha256(raw)
    return provider, external_key, content_sha256, source_name, replaced_external_key


def _quarantine_for_code(
    raw: Mapping[str, Any],
    *,
    registration: ReviewSourceRegistration | None,
    reason_code: QuarantineReasonCode,
    safe_metadata: QuarantineSafeMetadata | None = None,
    received_at: datetime | None = None,
) -> ReviewQuarantineEntry:
    """Build a typed quarantine entry from a raw dict, without raw text."""
    (
        provider,
        external_key,
        content_sha256,
        source_name,
        replaced_external_key,
    ) = _safe_identity(raw, registration=registration)
    metadata = safe_metadata or QuarantineSafeMetadata(malformed=True)
    if replaced_external_key:
        metadata = metadata.model_copy(update={"replaced_external_key": True})
    return ReviewQuarantineEntry(
        provider=provider,
        external_key=external_key,
        content_sha256=content_sha256,
        reason_code=reason_code,
        source_name=source_name,
        received_at=received_at or datetime.now(UTC),
        safe_metadata=metadata,
    )


def _identity_mismatch(
    record: ReviewSourceRecord,
    registration: ReviewSourceRegistration,
) -> IdentityField | None:
    """Return the first per-record provenance field that differs from the
    registration, or ``None`` when the record's identity matches exactly."""
    for field_name, record_value, registered_value in (
        ("source_name", record.source_name, registration.source_name),
        ("provider", record.provider, registration.provider),
        ("license_class", record.license_class, registration.license_class),
        ("terms_version", record.terms_version, registration.terms_version),
    ):
        if record_value != registered_value:
            return field_name  # type: ignore[return-value]
    return None


def _bind_record_to_registration(
    record: ReviewSourceRecord,
    registration: ReviewSourceRegistration,
) -> ReviewSourceRecord:
    """Return a copy of ``record`` whose source identity is the DB registration.

    Defense-in-depth for Finding 1: even though records reaching this point have
    already been checked against the registration, downstream consumers read the
    registration's canonical identity, never the caller-supplied copy.
    """
    return record.model_copy(
        update={
            "source_name": registration.source_name,
            "provider": registration.provider,
            "license_class": registration.license_class,
            "terms_version": registration.terms_version,
        }
    )


def classify_review_records(
    *,
    registration: ReviewSourceRegistration,
    records: Sequence[Mapping[str, Any]],
) -> tuple[tuple[ReviewSourceRecord, ...], tuple[ReviewQuarantineEntry, ...]]:
    """Pure validation: split a batch into (valid, quarantined).

    Three layers of record-level governance run here, all routing failures to a
    typed, code-backed quarantine without ever persisting raw text:

      1. Strict normalized-attribute contract (Finding 2): strings, nested
         objects, raw-text keys, and unknown/free-form keys are rejected with
         ``schema_invalid_attribute_shape``.
      2. Structural validation via :func:`parse_review_record` (the original
         schema/raw-text-field gate).
      3. Per-record DB-authoritative source identity (Finding 1): a record whose
         source_name/provider/license_class/terms_version does not exactly match
         the loaded registration is rejected with ``source_identity_mismatch``.

    Accepted records are bound to the registration before returning, so no
    caller-controlled source identity can reach an aggregate, receipt, or RAG
    metadata path.
    """
    valid: list[ReviewSourceRecord] = []
    quarantined: list[ReviewQuarantineEntry] = []
    for raw in records:
        # Finding 2: enforce the strict attribute contract first so a precise,
        # code-backed reason is recorded for shape violations.
        try:
            _coerce_normalized_attributes(raw.get("normalized_attributes"))
        except AttributeShapeError as exc:
            quarantined.append(
                _quarantine_for_code(
                    raw,
                    registration=registration,
                    reason_code="schema_invalid_attribute_shape",
                    safe_metadata=QuarantineSafeMetadata(
                        malformed=True, attribute_shape_violation=exc.violation
                    ),
                )
            )
            continue
        # Structural validation (schema, raw-text-field allowlist, hash shape).
        try:
            record = parse_review_record(raw)
        except (ValidationError, ValueError) as exc:
            if isinstance(exc, ValidationError):
                code, metadata = _classify_validation_error(exc)
            else:
                code: QuarantineReasonCode = "schema_invalid"
                metadata = QuarantineSafeMetadata(malformed=True)
            quarantined.append(
                _quarantine_for_code(
                    raw,
                    registration=registration,
                    reason_code=code,
                    safe_metadata=metadata,
                )
            )
            continue
        # Finding 1: per-record identity must match the DB-authoritative source.
        mismatched = _identity_mismatch(record, registration)
        if mismatched is not None:
            quarantined.append(
                _quarantine_for_code(
                    raw,
                    registration=registration,
                    reason_code="source_identity_mismatch",
                    safe_metadata=QuarantineSafeMetadata(
                        malformed=True, mismatched_identity_field=mismatched
                    ),
                )
            )
            continue
        valid.append(_bind_record_to_registration(record, registration))
    return tuple(valid), tuple(quarantined)


def _dominant_reason_category(
    entries: Sequence[ReviewQuarantineEntry],
) -> QuarantineReasonCategory:
    counts: dict[str, int] = {}
    for entry in entries:
        counts[entry.reason_category] = counts.get(entry.reason_category, 0) + 1
    dominant = max(counts, key=lambda key: counts[key])
    return dominant  # type: ignore[return-value]


def build_run_summary(
    *,
    run_key: str,
    registration: ReviewSourceRegistration,
    received_count: int,
    processed_count: int,
    duplicate_count: int,
    quarantined_count: int,
    failure_category: FailureCategory,
    status: Literal["running", "succeeded", "failed"],
) -> ReviewIngestRunSummary:
    return ReviewIngestRunSummary(
        run_key=run_key,
        source_name=registration.source_name,
        provider=registration.provider,
        license_class=registration.license_class,
        terms_version=registration.terms_version,
        schema_version=GOVERNANCE_SCHEMA_VERSION,
        received_count=received_count,
        processed_count=processed_count,
        duplicate_count=duplicate_count,
        quarantined_count=quarantined_count,
        failure_category=failure_category,
        status=status,
    )


# --- Repository helpers (cursor-based; live inside the caller's transaction) ---
#
# Each helper operates on a cursor the caller owns so the whole batch shares
# ONE transaction boundary (Finding 5). None of them commit/rollback -- the
# orchestrator's ``with conn:`` owns the commit/rollback decision.


def load_active_review_source(
    cur,
    *,
    source_name: str,
    expected_provider: str,
    expected_terms_version: str,
) -> ReviewSourceRegistration:
    """DB-backed source gate (Finding 1).

    Loads the source row from ``ingest.review_sources`` and rejects -- with
    distinct governance codes -- absent, disabled, rejected-license, or
    provider/terms-mismatch sources. The caller's ``expected_*`` values are for
    *mismatch detection* only; the database row is the source of truth for
    ``license_class`` and ``source_status`` and is never overridden by input.
    """
    sql = """
        SELECT provider, license_class, terms_version,
               collection_method, retention_policy, redaction_policy,
               source_status
        FROM ingest.review_sources
        WHERE source_name = %s
    """
    cur.execute(sql, (source_name,))
    row = cur.fetchone()
    if row is None:
        raise ReviewGovernanceError(
            "source_not_registered",
            f"review source '{source_name}' is not registered",
        )
    (
        provider,
        license_class,
        terms_version,
        collection_method,
        retention_policy,
        redaction_policy,
        source_status,
    ) = row
    if source_status != "active":
        raise ReviewGovernanceError(
            "source_disabled",
            f"review source '{source_name}' is disabled (status={source_status})",
        )
    if license_class not in ALLOWED_LICENSE_CLASSES:
        raise ReviewGovernanceError(
            "source_license_rejected",
            (
                f"review source '{source_name}' license_class "
                f"'{license_class}' is not permitted for ingestion"
            ),
        )
    if provider != expected_provider:
        raise ReviewGovernanceError(
            "source_provider_mismatch",
            (
                f"review source '{source_name}' provider '{provider}' does not "
                f"match expected provider '{expected_provider}'"
            ),
        )
    if terms_version != expected_terms_version:
        raise ReviewGovernanceError(
            "source_terms_mismatch",
            (
                f"review source '{source_name}' terms_version '{terms_version}' "
                f"does not match expected '{expected_terms_version}'"
            ),
        )
    return ReviewSourceRegistration(
        source_name=source_name,
        provider=provider,
        license_class=license_class,
        terms_version=terms_version,
        collection_method=collection_method,
        retention_policy=retention_policy,
        redaction_policy=redaction_policy,
        source_status=source_status,
    )


def _create_or_resume_ingest_run(
    cur,
    *,
    run_key: str,
    registration: ReviewSourceRegistration,
    received_count: int,
) -> str:
    """Create the run accounting row or resume an existing one for ``run_key``.

    Writes the registered-source FK (``review_source_name``) so new review runs
    refer to a registered source (Finding 2). The no-op ``DO UPDATE`` exists
    only so ``RETURNING id`` yields the existing id on retry (idempotent
    resume). Returns the run id.
    """
    sql = """
        INSERT INTO community.ingest_runs (
            provider,
            status,
            run_key,
            source_name,
            review_source_name,
            license_class,
            terms_version,
            schema_version,
            received_count,
            started_at
        )
        VALUES (%s, 'running', %s, %s, %s, %s, %s, %s, %s, now())
        ON CONFLICT (run_key) WHERE run_key IS NOT NULL
        DO UPDATE SET received_count = community.ingest_runs.received_count
        RETURNING id
    """
    cur.execute(
        sql,
        (
            registration.provider,
            run_key,
            registration.source_name,
            registration.source_name,
            registration.license_class,
            registration.terms_version,
            GOVERNANCE_SCHEMA_VERSION,
            received_count,
        ),
    )
    row = cur.fetchone()
    if not row:
        raise ReviewGovernanceError(
            "run_not_created",
            "ingest run upsert returned no row",
        )
    return str(row[0])


def _record_review_receipts(
    cur,
    *,
    run_id: str,
    source_name: str,
    records: Sequence[ReviewSourceRecord],
) -> tuple[tuple[ReviewSourceRecord, ...], tuple[ReviewSourceRecord, ...]]:
    """Persistent aggregate-only dedupe (Finding 3).

    For each valid record, attempt to insert a receipt keyed by
    (source_name, external_key, content_sha256):

    * rowcount 1 -> new content -> emit a downstream aggregate.
    * rowcount 0 -> exact replay (same triple already receipted, possibly in a
      *different* run) -> do NOT emit again; just refresh last_run/last_seen.

    A *content revision* (same external_key, different content_sha256) does not
    conflict on the PK, so it inserts as new content and correctly emits a fresh
    aggregate. No raw text is stored -- only identity, a hash, and run/time.
    """
    if not records:
        return (), ()

    insert_sql = """
        INSERT INTO ingest.review_ingest_receipts (
            source_name, external_key, content_sha256,
            first_run_id, last_run_id, first_seen_at, last_seen_at
        )
        VALUES (%s, %s, %s, %s, %s, now(), now())
        ON CONFLICT (source_name, external_key, content_sha256) DO NOTHING
    """
    refresh_sql = """
        UPDATE ingest.review_ingest_receipts
        SET last_run_id = %s, last_seen_at = now()
        WHERE source_name = %s
          AND external_key = %s
          AND content_sha256 = %s
    """
    new_records: list[ReviewSourceRecord] = []
    replay_records: list[ReviewSourceRecord] = []
    for record in records:
        cur.execute(
            insert_sql,
            (
                source_name,
                record.external_key,
                record.content_sha256,
                run_id,
                run_id,
            ),
        )
        if int(getattr(cur, "rowcount", 0) or 0) == 1:
            new_records.append(record)
        else:
            cur.execute(
                refresh_sql,
                (run_id, source_name, record.external_key, record.content_sha256),
            )
            replay_records.append(record)
    return tuple(new_records), tuple(replay_records)


def _insert_quarantine_entries(
    cur,
    *,
    entries: Sequence[ReviewQuarantineEntry],
    run_id: str,
) -> int:
    """Persist typed quarantine rows, deduped by the partial unique index.

    Returns the number actually inserted so run accounting stays stable when a
    failed batch is retried (re-running does not double-count dead-letter rows).
    Only code-backed reason text and typed metadata are written.
    """
    if not entries:
        return 0

    from psycopg2.extras import Json

    sql = """
        INSERT INTO community.ingest_quarantine (
            source_run_id,
            source_name,
            provider,
            external_key,
            content_sha256,
            reason_category,
            reason_code,
            reason,
            received_at,
            safe_metadata
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (provider, external_key, reason_category)
        WHERE resolved_at IS NULL
        DO NOTHING
    """
    inserted = 0
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
                entry.reason_code,
                entry.reason,
                entry.received_at,
                Json(entry.safe_metadata.model_dump(exclude_none=True)),
            ),
        )
        inserted += int(getattr(cur, "rowcount", 0) or 0)
    return inserted


def _finalize_ingest_run(
    cur,
    *,
    run_id: str,
    status: Literal["running", "succeeded", "failed"],
    processed_count: int,
    duplicate_count: int,
    quarantined_count: int,
    failure_category: FailureCategory,
    error_message: str | None,
) -> None:
    """Write final counters/status to the run accounting row.

    Idempotent *accounting* (not immutability): retry-safe absolute overwrite
    of counters so re-running a batch converges rather than accumulates.
    """
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


def persist_review_ingest_run(
    *,
    dsn: str,
    source_name: str,
    expected_provider: str,
    expected_terms_version: str,
    records: Sequence[Mapping[str, Any]],
    window_start: date | None = None,
    connect_timeout: int = 5,
) -> ReviewIngestResult:
    """One-transaction governance + persistence boundary (Finding 5).

    Inside a single ``with conn:`` block (commit on success, rollback on any
    error):

      1. ``load_active_review_source`` -- DB-backed source gate (Finding 1).
         Any gate failure raises and aborts the whole batch before a run row or
         a receipt is written.
      2. ``classify_review_records`` -- pure validation; builds typed
         quarantines for malformed/unsafe records (Finding 4).
      3. ``_create_or_resume_ingest_run`` -- idempotent run accounting row,
         linked to the registered source via ``review_source_name`` (Finding 2).
      4. ``_record_review_receipts`` -- persistent cross-run dedupe; only new
         (non-replay) records become aggregates (Finding 3).
      5. ``_insert_quarantine_entries`` -- typed dead-letter persistence.
      6. ``_finalize_ingest_run`` -- absolute, retry-safe counter overwrite.

    Aggregates are only returned after the transaction commits, so a partial
    failure never exposes accepted aggregates to a downstream caller.
    """
    if not dsn:
        raise ValueError("DB_DSN is required.")

    import psycopg2

    run_key = build_run_key(
        source_name=source_name,
        window_start=window_start,
        schema_version=GOVERNANCE_SCHEMA_VERSION,
    )
    received_count = len(records)
    conn = psycopg2.connect(dsn, connect_timeout=connect_timeout)
    # ``closing`` owns connection lifecycle; the inner ``with conn:`` owns the
    # transaction (commit on clean exit, rollback on exception).
    with closing(conn):
        with conn:
            with conn.cursor() as cur:
                registration = load_active_review_source(
                    cur,
                    source_name=source_name,
                    expected_provider=expected_provider,
                    expected_terms_version=expected_terms_version,
                )
                valid_records, quarantined = classify_review_records(
                    registration=registration,
                    records=records,
                )
                run_id = _create_or_resume_ingest_run(
                    cur,
                    run_key=run_key,
                    registration=registration,
                    received_count=received_count,
                )
                new_records, replay_records = _record_review_receipts(
                    cur,
                    run_id=run_id,
                    source_name=registration.source_name,
                    records=valid_records,
                )
                accepted = tuple(approved_aggregate_from_record(record) for record in new_records)
                _insert_quarantine_entries(cur, entries=quarantined, run_id=run_id)
                failure_category: FailureCategory = (
                    "none" if not quarantined else _dominant_reason_category(quarantined)
                )
                _finalize_ingest_run(
                    cur,
                    run_id=run_id,
                    status="succeeded",
                    processed_count=len(new_records),
                    duplicate_count=len(replay_records),
                    quarantined_count=len(quarantined),
                    failure_category=failure_category,
                    error_message=None,
                )
                run_summary = build_run_summary(
                    run_key=run_key,
                    registration=registration,
                    received_count=received_count,
                    processed_count=len(new_records),
                    duplicate_count=len(replay_records),
                    quarantined_count=len(quarantined),
                    failure_category=failure_category,
                    status="succeeded",
                )
    return ReviewIngestResult(
        run=run_summary,
        accepted=accepted,
        quarantined=quarantined,
    )


def register_review_source(
    *,
    dsn: str,
    registration: ReviewSourceRegistration,
    connect_timeout: int = 5,
) -> None:
    """Idempotently upsert a review-source registration row.

    Internal/admin only: there is intentionally no public endpoint. This runs
    in its own transaction (separate from any ingest run) because registration
    is an operator action, not part of the worker batch boundary. The
    connection lifecycle mirrors :func:`persist_review_ingest_run`:
    ``closing(conn)`` owns the connection, ``with conn:`` owns the transaction
    (commit on success, rollback on error).
    """
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
    conn = psycopg2.connect(dsn, connect_timeout=connect_timeout)
    with closing(conn):
        with conn:
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
