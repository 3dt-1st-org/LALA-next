"""Offline contract for governed official-source inventory and coverage reports.

This module deliberately stops before acquisition. It reuses the identity
concepts of ``ingest.source_files`` receipts (source, dataset, fingerprint,
and observed time) without adding a competing table or making provider calls.
"""

from __future__ import annotations

import hashlib
import ipaddress
import json
import re
from collections import defaultdict
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, replace
from datetime import UTC, datetime
from typing import Any, Final, Literal
from urllib.parse import urlparse

SourceReadiness = Literal["usable", "blocked_external", "rejected", "stale", "unknown"]
GovernanceStatus = Literal["approved", "blocked_external", "rejected", "unknown"]
GovernanceDecision = Literal["approved", "blocked_external", "rejected"]
CoverageScope = Literal["nationwide", "coarse_region", "unknown"]
CursorSemantics = Literal["page_cursor", "offset", "snapshot", "date_window", "unknown"]
CoordinatePrecision = Literal["none", "coarse_region", "place_point", "personal_precise"]
ImageRightsStatus = Literal["verified", "not_permitted", "unknown"]
SourcePurpose = Literal[
    "official_place_catalog",
    "culture_event_catalog",
    "franchise_reference",
    "aggregate_card_spending",
]

_HASH_PATTERN: Final[re.Pattern[str]] = re.compile(r"^[0-9a-f]{64}$")
_OPAQUE_ID_PATTERN: Final[re.Pattern[str]] = re.compile(r"^[A-Za-z0-9][A-Za-z0-9:._-]{0,127}$")
_SAFE_SCHEMES: Final[tuple[str, ...]] = ("https",)
_FORBIDDEN_PROJECTION_TERMS: Final[tuple[str, ...]] = (
    "author",
    "body",
    "email",
    "phone",
    "raw",
    "review",
    "text",
    "token",
    "url_source",
)
_PRECISION_RANK: Final[dict[CoordinatePrecision, int]] = {
    "none": 0,
    "coarse_region": 1,
    "place_point": 2,
    "personal_precise": 3,
}
_SOURCE_PURPOSES: Final[frozenset[str]] = frozenset(
    {
        "official_place_catalog",
        "culture_event_catalog",
        "franchise_reference",
        "aggregate_card_spending",
    }
)


class OfficialSourceInventoryError(ValueError):
    """Raised when an inventory or receipt violates the offline contract."""


@dataclass(frozen=True)
class SourceGovernance:
    license_class: str | None
    terms_version: str | None
    retention_policy: str | None
    provenance_policy: str | None
    image_rights_status: ImageRightsStatus
    source_status: GovernanceStatus


@dataclass(frozen=True)
class SourceRefreshPolicy:
    cadence_hours: int
    freshness_sla_hours: int


@dataclass(frozen=True)
class SourcePaginationPolicy:
    semantics: CursorSemantics
    cursor_field: str | None = None
    snapshot_field: str | None = None


@dataclass(frozen=True)
class SourceRecordIdentityPolicy:
    stable_fields: tuple[str, ...]
    dedupe_fields: tuple[str, ...]


@dataclass(frozen=True)
class ImageUrlPolicy:
    accepted_schemes: tuple[str, ...] = _SAFE_SCHEMES
    reject_credentials: bool = True
    require_verified_rights: bool = True


@dataclass(frozen=True)
class PlaceAcceptancePolicy:
    coverage_scope: CoverageScope
    covered_regions: tuple[str, ...]
    accepted_categories: tuple[str, ...]
    max_coordinate_precision: CoordinatePrecision
    accepted_languages: tuple[str, ...]
    image_url_policy: ImageUrlPolicy


@dataclass(frozen=True)
class OfficialSourceInventory:
    source_name: str
    dataset_name: str
    purpose: SourcePurpose
    allowed_public_projection: tuple[str, ...]
    governance: SourceGovernance
    refresh: SourceRefreshPolicy
    pagination: SourcePaginationPolicy
    identity: SourceRecordIdentityPolicy
    place_policy: PlaceAcceptancePolicy


@dataclass(frozen=True)
class OfficialCoverageReceipt:
    """Offline evidence corresponding to an existing source-file receipt.

    ``record_ids=None`` means the receipt did not prove a count. An empty tuple
    means the receipt proved an empty result; this distinction prevents counts
    from being invented when an upstream response was incomplete.
    """

    receipt_id: str
    source_name: str
    dataset_name: str
    content_fingerprint: str
    observed_at: datetime
    record_ids: tuple[str, ...] | None
    coverage_scope: CoverageScope
    covered_regions: tuple[str, ...]
    coordinate_precision: CoordinatePrecision
    localized_languages: tuple[str, ...]
    image_rights_status: ImageRightsStatus


@dataclass(frozen=True)
class SourceCoverageSummary:
    source_name: str
    dataset_name: str
    readiness: SourceReadiness
    coverage_scope: CoverageScope
    covered_regions: tuple[str, ...]
    distinct_record_count: int | None
    latest_receipt_at: datetime | None
    accepted_receipt_count: int
    duplicate_receipt_count: int
    rejected_receipt_count: int
    reasons: tuple[str, ...]
    allowed_public_projection: tuple[str, ...]

    def to_public_dict(self) -> dict[str, Any]:
        """Expose only inventory/coverage metadata, never source content."""
        return {
            "source_name": self.source_name,
            "dataset_name": self.dataset_name,
            "readiness": self.readiness,
            "coverage_scope": self.coverage_scope,
            "covered_regions": list(self.covered_regions),
            "distinct_record_count": self.distinct_record_count,
            "latest_receipt_at": self.latest_receipt_at.isoformat()
            if self.latest_receipt_at
            else None,
            "accepted_receipt_count": self.accepted_receipt_count,
            "duplicate_receipt_count": self.duplicate_receipt_count,
            "rejected_receipt_count": self.rejected_receipt_count,
            "reasons": list(self.reasons),
            "allowed_public_projection": list(self.allowed_public_projection),
        }


@dataclass(frozen=True)
class OfficialCoverageReport:
    generated_at: datetime
    sources: tuple[SourceCoverageSummary, ...]
    ignored_receipt_count: int

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "generated_at": self.generated_at.isoformat(),
            "ignored_receipt_count": self.ignored_receipt_count,
            "sources": [source.to_public_dict() for source in self.sources],
        }


def normalize_source_inventory(
    entries: Iterable[OfficialSourceInventory],
) -> tuple[OfficialSourceInventory, ...]:
    normalized = tuple(
        sorted((_normalize_inventory(entry) for entry in entries), key=_inventory_key)
    )
    seen: set[tuple[str, str]] = set()
    for entry in normalized:
        identity = _inventory_key(entry)
        if identity in seen:
            raise OfficialSourceInventoryError(
                f"Duplicate official source identity: {entry.source_name}/{entry.dataset_name}."
            )
        seen.add(identity)
    return normalized


def normalize_receipt(receipt: OfficialCoverageReceipt) -> OfficialCoverageReceipt:
    if not _OPAQUE_ID_PATTERN.fullmatch(receipt.receipt_id.strip()):
        raise OfficialSourceInventoryError("Receipt identity must be a bounded opaque reference.")
    fingerprint = receipt.content_fingerprint.strip().lower()
    if not _HASH_PATTERN.fullmatch(fingerprint):
        raise OfficialSourceInventoryError("Receipt content fingerprint must be a SHA-256 value.")
    if receipt.coverage_scope not in {"nationwide", "coarse_region", "unknown"}:
        raise OfficialSourceInventoryError("Receipt coverage scope is invalid.")
    if receipt.coordinate_precision not in _PRECISION_RANK:
        raise OfficialSourceInventoryError("Receipt coordinate precision is invalid.")
    if receipt.image_rights_status not in {"verified", "not_permitted", "unknown"}:
        raise OfficialSourceInventoryError("Receipt image-rights status is invalid.")
    record_ids = None
    if receipt.record_ids is not None:
        record_ids = tuple(sorted(set(_normalize_opaque_id(item) for item in receipt.record_ids)))
    return replace(
        receipt,
        receipt_id=receipt.receipt_id.strip(),
        source_name=_normalize_source_name(receipt.source_name),
        dataset_name=_clean_text(receipt.dataset_name),
        content_fingerprint=fingerprint,
        observed_at=_as_utc(receipt.observed_at),
        record_ids=record_ids,
        covered_regions=_normalized_values(receipt.covered_regions),
        localized_languages=_normalized_values(receipt.localized_languages),
    )


def stable_source_record_identity(
    *,
    source_name: str,
    dataset_name: str,
    policy: SourceRecordIdentityPolicy,
    record: Mapping[str, object],
) -> str:
    """Hash only approved identity fields into a stable opaque record key."""
    fields = _normalized_field_names(policy.stable_fields)
    if not fields or not set(policy.dedupe_fields).issubset(fields):
        raise OfficialSourceInventoryError("Stable and dedupe identity fields are inconsistent.")
    values: dict[str, str] = {}
    for field_name in fields:
        if _contains_forbidden_term(field_name):
            raise OfficialSourceInventoryError(
                f"Raw or identity-sensitive field is not allowed in record identity: {field_name}."
            )
        value = _clean_text(record.get(field_name))
        if not value:
            raise OfficialSourceInventoryError(f"Missing stable source-record field: {field_name}.")
        values[field_name] = value
    payload = json.dumps(values, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    digest = hashlib.sha256(
        f"{_normalize_source_name(source_name)}\x1f{_clean_text(dataset_name)}\x1f{payload}".encode()
    ).hexdigest()
    return f"record:{digest}"


def validate_image_url(url: str, policy: ImageUrlPolicy) -> str:
    value = url.strip()
    parsed = urlparse(value)
    if parsed.scheme.lower() not in policy.accepted_schemes:
        raise OfficialSourceInventoryError("Image URL must use an accepted public scheme.")
    if not parsed.hostname or (policy.reject_credentials and (parsed.username or parsed.password)):
        raise OfficialSourceInventoryError("Image URL must have a public host without credentials.")
    try:
        address = ipaddress.ip_address(parsed.hostname)
    except ValueError:
        address = None
    if address is not None and (address.is_private or address.is_loopback or address.is_reserved):
        raise OfficialSourceInventoryError("Image URL must not target a private or local host.")
    return value


def build_official_coverage_report(
    *,
    inventory: Sequence[OfficialSourceInventory],
    receipts: Sequence[OfficialCoverageReceipt],
    generated_at: datetime,
) -> OfficialCoverageReport:
    """Build a deterministic report from inventory metadata and accepted receipts."""
    entries = normalize_source_inventory(inventory)
    normalized_receipts = [normalize_receipt(receipt) for receipt in receipts]
    grouped: dict[tuple[str, str], list[OfficialCoverageReceipt]] = defaultdict(list)
    seen_receipts: set[tuple[str, str, str]] = set()
    duplicate_receipt_count: dict[tuple[str, str], int] = defaultdict(int)
    ignored_receipt_count = 0
    for receipt in normalized_receipts:
        key = (receipt.source_name, receipt.dataset_name)
        identity = (*key, receipt.content_fingerprint)
        if identity in seen_receipts:
            duplicate_receipt_count[key] += 1
            continue
        seen_receipts.add(identity)
        grouped[key].append(receipt)

    summaries: list[SourceCoverageSummary] = []
    inventory_keys = {_inventory_key(entry) for entry in entries}
    ignored_receipt_count += sum(
        len(receipt_group) for key, receipt_group in grouped.items() if key not in inventory_keys
    )
    for entry in entries:
        key = _inventory_key(entry)
        source_receipts = grouped.get(key, [])
        governance_state, governance_reasons = _governance_state(entry)
        accepted: list[OfficialCoverageReceipt] = []
        rejected_receipts = 0
        rejection_reasons: list[str] = []
        if governance_state == "approved":
            for receipt in source_receipts:
                reason = _receipt_rejection_reason(entry, receipt)
                if reason:
                    rejected_receipts += 1
                    _append_once(rejection_reasons, reason)
                else:
                    accepted.append(receipt)

        reasons = list(governance_reasons)
        reasons.extend(rejection_reasons)
        latest = max((receipt.observed_at for receipt in accepted), default=None)
        covered_regions = tuple(
            sorted({region for receipt in accepted for region in receipt.covered_regions})
        )
        distinct_record_count = _distinct_record_count(accepted)
        observed_scopes = {receipt.coverage_scope for receipt in accepted}
        coverage_scope: CoverageScope = "unknown"
        if len(observed_scopes) == 1:
            coverage_scope = next(iter(observed_scopes))
        elif len(observed_scopes) > 1:
            _append_once(reasons, "accepted receipts disagree on coverage scope")

        if governance_state != "approved":
            readiness = governance_state
        elif not accepted:
            readiness = "unknown"
            _append_once(reasons, "no accepted receipt proves coverage")
        elif coverage_scope == "unknown":
            readiness = "unknown"
            _append_once(
                reasons, "accepted receipt does not prove nationwide or coarse-region coverage"
            )
        elif latest is not None and _is_stale(
            latest, entry.refresh.freshness_sla_hours, generated_at
        ):
            readiness = "stale"
            _append_once(reasons, "latest accepted receipt is outside the freshness SLA")
        else:
            readiness = "usable"

        summaries.append(
            SourceCoverageSummary(
                source_name=entry.source_name,
                dataset_name=entry.dataset_name,
                readiness=readiness,
                coverage_scope=coverage_scope,
                covered_regions=covered_regions,
                distinct_record_count=distinct_record_count
                if accepted and all(receipt.record_ids is not None for receipt in accepted)
                else None,
                latest_receipt_at=latest,
                accepted_receipt_count=len(accepted),
                duplicate_receipt_count=duplicate_receipt_count[key],
                rejected_receipt_count=rejected_receipts,
                reasons=tuple(reasons),
                allowed_public_projection=entry.allowed_public_projection,
            )
        )
    return OfficialCoverageReport(
        generated_at=_as_utc(generated_at),
        sources=tuple(summaries),
        ignored_receipt_count=ignored_receipt_count,
    )


def _normalize_inventory(entry: OfficialSourceInventory) -> OfficialSourceInventory:
    source_name = _normalize_source_name(entry.source_name)
    dataset_name = _clean_text(entry.dataset_name)
    if not source_name or not dataset_name:
        raise OfficialSourceInventoryError("Source and dataset identities are required.")
    if entry.purpose not in _SOURCE_PURPOSES:
        raise OfficialSourceInventoryError("Official source purpose is invalid.")
    projection = _normalized_field_names(entry.allowed_public_projection)
    if not projection:
        raise OfficialSourceInventoryError("Allowed public projection must not be empty.")
    forbidden = next((field for field in projection if _contains_forbidden_term(field)), None)
    if forbidden:
        raise OfficialSourceInventoryError(
            f"Raw review or identity-sensitive projection is not allowed: {forbidden}."
        )
    identity = replace(
        entry.identity,
        stable_fields=_normalized_field_names(entry.identity.stable_fields),
        dedupe_fields=_normalized_field_names(entry.identity.dedupe_fields),
    )
    if not identity.stable_fields or not identity.dedupe_fields:
        raise OfficialSourceInventoryError("Stable and dedupe identity fields are required.")
    if not set(identity.dedupe_fields).issubset(identity.stable_fields):
        raise OfficialSourceInventoryError("Dedupe fields must be stable identity fields.")
    _validate_coordinate_precision(entry.place_policy.max_coordinate_precision)
    if not entry.place_policy.image_url_policy.accepted_schemes or not set(
        entry.place_policy.image_url_policy.accepted_schemes
    ).issubset(_SAFE_SCHEMES):
        raise OfficialSourceInventoryError("Image URL policy must allow HTTPS only.")
    languages = _normalized_values(entry.place_policy.accepted_languages)
    if not languages or not set(languages).issubset({"ko", "en"}):
        raise OfficialSourceInventoryError("Accepted localization languages must be KO or EN.")
    if entry.refresh.cadence_hours <= 0 or entry.refresh.freshness_sla_hours <= 0:
        raise OfficialSourceInventoryError("Refresh cadence and freshness SLA must be positive.")
    if (
        entry.pagination.semantics in {"page_cursor", "offset"}
        and not entry.pagination.cursor_field
    ):
        raise OfficialSourceInventoryError("Cursor or offset semantics require a cursor field.")
    if entry.pagination.semantics == "snapshot" and not entry.pagination.snapshot_field:
        raise OfficialSourceInventoryError("Snapshot semantics require a snapshot field.")
    return replace(
        entry,
        source_name=source_name,
        dataset_name=dataset_name,
        allowed_public_projection=projection,
        governance=replace(
            entry.governance,
            license_class=_optional_text(entry.governance.license_class),
            terms_version=_optional_text(entry.governance.terms_version),
            retention_policy=_optional_text(entry.governance.retention_policy),
            provenance_policy=_optional_text(entry.governance.provenance_policy),
        ),
        identity=identity,
        place_policy=replace(
            entry.place_policy,
            covered_regions=_normalized_values(entry.place_policy.covered_regions),
            accepted_categories=_normalized_values(entry.place_policy.accepted_categories),
            accepted_languages=languages,
        ),
    )


def _governance_state(entry: OfficialSourceInventory) -> tuple[GovernanceDecision, list[str]]:
    governance = entry.governance
    if governance.source_status == "rejected" or governance.image_rights_status == "not_permitted":
        return "rejected", ["source or image rights are explicitly rejected"]
    if governance.source_status != "approved":
        return "blocked_external", ["source governance approval is not confirmed"]
    missing = [
        field_name
        for field_name, value in (
            ("license", governance.license_class),
            ("terms", governance.terms_version),
            ("retention", governance.retention_policy),
            ("provenance", governance.provenance_policy),
        )
        if not value
    ]
    if governance.image_rights_status == "unknown":
        missing.append("image rights")
    if entry.pagination.semantics == "unknown":
        missing.append("cursor or snapshot semantics")
    if missing:
        return "blocked_external", [f"missing source governance: {', '.join(missing)}"]
    return "approved", []


def _receipt_rejection_reason(
    entry: OfficialSourceInventory,
    receipt: OfficialCoverageReceipt,
) -> str | None:
    if receipt.coordinate_precision == "personal_precise":
        return "receipt contains disallowed personal-precise coordinates"
    if (
        _PRECISION_RANK[receipt.coordinate_precision]
        > _PRECISION_RANK[entry.place_policy.max_coordinate_precision]
    ):
        return "receipt coordinate precision exceeds the source policy"
    if (
        entry.place_policy.image_url_policy.require_verified_rights
        and receipt.image_rights_status != "verified"
    ):
        return "receipt does not prove image rights"
    accepted_languages = set(entry.place_policy.accepted_languages)
    if not set(receipt.localized_languages).issubset(accepted_languages):
        return "receipt contains a language outside the accepted localization policy"
    return None


def _distinct_record_count(receipts: Sequence[OfficialCoverageReceipt]) -> int | None:
    if not receipts or any(receipt.record_ids is None for receipt in receipts):
        return None
    return len({record_id for receipt in receipts for record_id in receipt.record_ids or ()})


def _is_stale(latest: datetime, freshness_sla_hours: int, generated_at: datetime) -> bool:
    age_seconds = (_as_utc(generated_at) - latest).total_seconds()
    return age_seconds > freshness_sla_hours * 3600


def _inventory_key(entry: OfficialSourceInventory) -> tuple[str, str]:
    return entry.source_name, entry.dataset_name


def _normalize_source_name(value: object) -> str:
    text = _clean_text(value).lower()
    return re.sub(r"[^a-z0-9_.:-]+", "_", text).strip("_")


def _normalize_opaque_id(value: object) -> str:
    text = _clean_text(value)
    if not _OPAQUE_ID_PATTERN.fullmatch(text):
        raise OfficialSourceInventoryError(
            "Source record identity must be a bounded opaque reference."
        )
    return text


def _normalized_field_names(values: Iterable[str]) -> tuple[str, ...]:
    fields = tuple(sorted({_clean_text(value).lower() for value in values if _clean_text(value)}))
    if any(_contains_forbidden_term(field) for field in fields):
        raise OfficialSourceInventoryError(
            "Raw review or identity-sensitive fields are not allowed."
        )
    return fields


def _normalized_values(values: Iterable[str]) -> tuple[str, ...]:
    return tuple(sorted({_clean_text(value) for value in values if _clean_text(value)}))


def _contains_forbidden_term(value: str) -> bool:
    normalized = value.lower()
    return any(term in normalized for term in _FORBIDDEN_PROJECTION_TERMS)


def _validate_coordinate_precision(value: CoordinatePrecision) -> None:
    if value not in _PRECISION_RANK or value == "personal_precise":
        raise OfficialSourceInventoryError(
            "Personal-precise coordinates are not an accepted source field."
        )


def _clean_text(value: object) -> str:
    return " ".join(str(value or "").strip().split())


def _optional_text(value: object) -> str | None:
    text = _clean_text(value)
    return text or None


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def _append_once(values: list[str], value: str) -> None:
    if value not in values:
        values.append(value)
