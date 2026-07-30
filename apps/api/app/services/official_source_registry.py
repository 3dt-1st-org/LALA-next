"""Declarative governance registry for official sources (offline contract).

This module is a **data-driven gate**, not an ingest path. It declares the five
official sources that the offline adapter (P1-2) knows how to normalize, their
governance and policy shape, and -- honestly -- that **live collection is
``blocked_external`` for every source** until terms, license, retention,
provenance, and image rights are externally confirmed by their owners.

It performs no network, DB, apply, seed, crawl, AI/TTS, or secret access. A
future live-ingest slice must call :func:`assert_live_ingest_permitted` before
any acquisition; that gate raises (fail-closed) unless the source is registered
AND its governance has been promoted to externally confirmed ``approved``. No
source meets that bar today, and this PR does not promote any source.

Reuses the raw inventory types from :mod:`official_source_inventory`
(``OfficialSourceInventory``, ``SourceGovernance``, ``SourceRefreshPolicy``,
``SourcePaginationPolicy``, ``SourceRecordIdentityPolicy``, ``ImageUrlPolicy``,
``PlaceAcceptancePolicy``) rather than introducing a competing identity model.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from typing import Final, Literal

from apps.api.app.services.official_source_inventory import (
    CoordinatePrecision,
    CoverageScope,
    GovernanceStatus,
    ImageUrlPolicy,
    OfficialSourceInventory,
    OfficialSourceInventoryError,
    PlaceAcceptancePolicy,
    SourceGovernance,
    SourcePaginationPolicy,
    SourcePurpose,
    SourceRecordIdentityPolicy,
    SourceRefreshPolicy,
    normalize_source_inventory,
)

LiveIngestReadiness = Literal["approved", "blocked_external"]
OfflineNormalizationReadiness = Literal["approved", "blocked_external"]
LiveGateDecision = Literal["approved", "blocked_external", "unknown_source"]


class OfficialSourceRegistryError(ValueError):
    """Raised when a registry lookup or live-ingest gate fails closed."""


@dataclass(frozen=True)
class SourceRegistryEntry:
    """One declared official source and its honest readiness gate.

    ``inventory`` reuses the shared inventory shape (source/dataset identity,
    governance, refresh, pagination, record-identity, place/image policy).

    ``offline_normalization_status`` and ``live_ingest_status`` make the
    distinction explicit: offline fixture normalization may be approved for a
    source while live collection remains externally blocked. The two values are
    kept separate so a future live slice cannot mistake one for the other.
    """

    inventory: OfficialSourceInventory
    offline_normalization_status: OfflineNormalizationReadiness
    live_ingest_status: LiveIngestReadiness
    live_blocker_reasons: tuple[str, ...]

    @property
    def source_name(self) -> str:
        return self.inventory.source_name

    @property
    def dataset_name(self) -> str:
        return self.inventory.dataset_name

    @property
    def purpose(self) -> SourcePurpose:
        return self.inventory.purpose

    @property
    def allowed_public_projection(self) -> tuple[str, ...]:
        return self.inventory.allowed_public_projection

    @property
    def governance(self) -> SourceGovernance:
        return self.inventory.governance

    @property
    def refresh(self) -> SourceRefreshPolicy:
        return self.inventory.refresh

    @property
    def pagination(self) -> SourcePaginationPolicy:
        return self.inventory.pagination

    @property
    def identity(self) -> SourceRecordIdentityPolicy:
        return self.inventory.identity

    @property
    def place_policy(self) -> PlaceAcceptancePolicy:
        return self.inventory.place_policy

    @property
    def image_url_policy(self) -> ImageUrlPolicy:
        return self.inventory.place_policy.image_url_policy

    def to_public_dict(self) -> dict[str, object]:
        """Expose registry metadata only, never source content or secrets."""
        return {
            "source_name": self.source_name,
            "dataset_name": self.dataset_name,
            "purpose": self.purpose,
            "allowed_public_projection": list(self.allowed_public_projection),
            "governance": {
                "license_class": self.governance.license_class,
                "terms_version": self.governance.terms_version,
                "retention_policy": self.governance.retention_policy,
                "provenance_policy": self.governance.provenance_policy,
                "image_rights_status": self.governance.image_rights_status,
                "source_status": self.governance.source_status,
            },
            "refresh": {
                "cadence_hours": self.refresh.cadence_hours,
                "freshness_sla_hours": self.refresh.freshness_sla_hours,
            },
            "pagination": {
                "semantics": self.pagination.semantics,
                "cursor_field": self.pagination.cursor_field,
                "snapshot_field": self.pagination.snapshot_field,
            },
            "identity": {
                "stable_fields": list(self.identity.stable_fields),
                "dedupe_fields": list(self.identity.dedupe_fields),
            },
            "image_url_policy": {
                "accepted_schemes": list(self.image_url_policy.accepted_schemes),
                "reject_credentials": self.image_url_policy.reject_credentials,
                "require_verified_rights": self.image_url_policy.require_verified_rights,
            },
            "place_policy": {
                "coverage_scope": self.place_policy.coverage_scope,
                "covered_regions": list(self.place_policy.covered_regions),
                "accepted_categories": list(self.place_policy.accepted_categories),
                "max_coordinate_precision": self.place_policy.max_coordinate_precision,
                "accepted_languages": list(self.place_policy.accepted_languages),
            },
            "offline_normalization_status": self.offline_normalization_status,
            "live_ingest_status": self.live_ingest_status,
            "live_blocker_reasons": list(self.live_blocker_reasons),
        }


_LIVE_BLOCKED_REASONS: Final[tuple[str, ...]] = (
    "source terms/license/retention/provenance are not externally confirmed",
    "image rights are not verified for live collection",
    "no live ingest slice is approved in this repository",
)


def _blocked_live_governance(source_status: GovernanceStatus) -> SourceGovernance:
    """Build an honest not-confirmed governance record for a source.

    Every declared governance field that is not externally confirmed is left
    ``None``/``unknown`` rather than invented. ``source_status`` is set to the
    supplied value so the inventory's own governance state and the registry's
    live gate agree.
    """
    return SourceGovernance(
        license_class=None,
        terms_version=None,
        retention_policy=None,
        provenance_policy=None,
        image_rights_status="unknown",
        source_status=source_status,
    )


def _place_policy(
    *,
    coverage_scope: CoverageScope,
    covered_regions: tuple[str, ...],
    accepted_categories: tuple[str, ...],
    max_coordinate_precision: CoordinatePrecision,
) -> PlaceAcceptancePolicy:
    return PlaceAcceptancePolicy(
        coverage_scope=coverage_scope,
        covered_regions=covered_regions,
        accepted_categories=accepted_categories,
        max_coordinate_precision=max_coordinate_precision,
        accepted_languages=("ko", "en"),
        image_url_policy=ImageUrlPolicy(),
    )


def _raw_inventory_entries() -> tuple[OfficialSourceInventory, ...]:
    """The five declared official-source inventories (live = blocked_external).

    Dataset names are sourced from each parser's SSOT constant to avoid literal
    drift. Governance is honestly not-confirmed: live collection is
    ``blocked_external`` for every source; offline fixture normalization is the
    only approved use and is represented at the registry-entry level.
    """
    from apps.api.app.services import (
        card_spending_ingest,
        culture_info_ingest,
        franchise_reference_ingest,
        kopis_ingest,
        tour_api_ingest,
    )

    blocked = "blocked_external"
    return (
        OfficialSourceInventory(
            source_name="tour_api",
            dataset_name=tour_api_ingest.DEFAULT_DATASET_NAME,
            purpose="official_place_catalog",
            allowed_public_projection=(
                "place_id",
                "name_ko",
                "category",
                "address_ko",
                "region_name_ko",
                "province_code",
                "city_code",
                "latitude",
                "longitude",
                "image_url",
            ),
            governance=_blocked_live_governance(blocked),
            refresh=SourceRefreshPolicy(cadence_hours=24, freshness_sla_hours=48),
            pagination=SourcePaginationPolicy(semantics="page_cursor", cursor_field="page_no"),
            identity=SourceRecordIdentityPolicy(
                stable_fields=("source_record_id",), dedupe_fields=("source_record_id",)
            ),
            place_policy=_place_policy(
                coverage_scope="nationwide",
                covered_regions=(),
                accepted_categories=("attraction", "culture_venue", "event", "restaurant"),
                max_coordinate_precision="place_point",
            ),
        ),
        OfficialSourceInventory(
            source_name="kcisa",
            dataset_name=culture_info_ingest.DEFAULT_DATASET_NAME,
            purpose="culture_event_catalog",
            allowed_public_projection=(
                "event_id",
                "title_ko",
                "category",
                "venue_name_ko",
                "region_name_ko",
                "starts_on",
                "ends_on",
                "latitude",
                "longitude",
                "image_url",
            ),
            governance=_blocked_live_governance(blocked),
            refresh=SourceRefreshPolicy(cadence_hours=24, freshness_sla_hours=48),
            pagination=SourcePaginationPolicy(semantics="page_cursor", cursor_field="page_no"),
            identity=SourceRecordIdentityPolicy(
                stable_fields=("source_record_id",), dedupe_fields=("source_record_id",)
            ),
            place_policy=_place_policy(
                coverage_scope="nationwide",
                covered_regions=(),
                accepted_categories=("culture_event",),
                max_coordinate_precision="place_point",
            ),
        ),
        OfficialSourceInventory(
            source_name="kopis",
            dataset_name=kopis_ingest.DEFAULT_DATASET_NAME,
            purpose="culture_event_catalog",
            allowed_public_projection=(
                "event_id",
                "title_ko",
                "category",
                "venue_name_ko",
                "region_name_ko",
                "starts_on",
                "ends_on",
                "image_url",
                "openrun",
                "performance_state",
            ),
            governance=_blocked_live_governance(blocked),
            refresh=SourceRefreshPolicy(cadence_hours=24, freshness_sla_hours=48),
            pagination=SourcePaginationPolicy(semantics="page_cursor", cursor_field="page_no"),
            identity=SourceRecordIdentityPolicy(
                stable_fields=("source_record_id",), dedupe_fields=("source_record_id",)
            ),
            place_policy=_place_policy(
                coverage_scope="nationwide",
                covered_regions=(),
                accepted_categories=("performance_event",),
                max_coordinate_precision="none",
            ),
        ),
        OfficialSourceInventory(
            source_name="fair_trade_commission",
            dataset_name=franchise_reference_ingest.DEFAULT_DATASET_NAME,
            purpose="franchise_reference",
            allowed_public_projection=(
                "brand_id",
                "brand_name_ko",
                "normalized_brand_name",
                "headquarters_name_ko",
                "category",
                "main_product",
                "franchise_store_count",
                "average_sales_amount",
                "chain_scale_score",
            ),
            governance=_blocked_live_governance(blocked),
            refresh=SourceRefreshPolicy(cadence_hours=720, freshness_sla_hours=1440),
            pagination=SourcePaginationPolicy(
                semantics="snapshot", snapshot_field="brand_stats_year"
            ),
            identity=SourceRecordIdentityPolicy(
                stable_fields=("source_record_id",), dedupe_fields=("source_record_id",)
            ),
            place_policy=_place_policy(
                coverage_scope="nationwide",
                covered_regions=(),
                accepted_categories=("franchise_reference",),
                max_coordinate_precision="none",
            ),
        ),
        OfficialSourceInventory(
            source_name="data_portal",
            dataset_name=card_spending_ingest.DETAIL_DATASET_NAME,
            purpose="aggregate_card_spending",
            allowed_public_projection=(
                "month",
                "region_name_ko",
                "industry_code",
                "industry_name_ko",
                "gender",
                "age_group",
                "spend_amount",
                "transaction_count",
                "visitor_type",
            ),
            governance=_blocked_live_governance(blocked),
            refresh=SourceRefreshPolicy(cadence_hours=720, freshness_sla_hours=1440),
            pagination=SourcePaginationPolicy(
                semantics="snapshot", snapshot_field="card_spending_month"
            ),
            identity=SourceRecordIdentityPolicy(
                stable_fields=("month", "region_name_ko", "industry_code"),
                dedupe_fields=("month", "region_name_ko", "industry_code"),
            ),
            place_policy=_place_policy(
                coverage_scope="coarse_region",
                covered_regions=(),
                accepted_categories=("aggregate_card_spending",),
                max_coordinate_precision="coarse_region",
            ),
        ),
    )


def _build_registry() -> tuple[SourceRegistryEntry, ...]:
    """Normalize the declared inventories and attach the honest readiness gate.

    Offline fixture normalization is approved for all five registered sources
    (the P1-2 adapter owns the actual normalization contract). Live ingest is
    ``blocked_external`` for all five; neither this function nor any caller in
    this PR may promote a source to live-approved.
    """
    normalized = normalize_source_inventory(_raw_inventory_entries())
    entries: list[SourceRegistryEntry] = []
    for inventory_entry in normalized:
        entries.append(
            SourceRegistryEntry(
                inventory=inventory_entry,
                offline_normalization_status="approved",
                live_ingest_status="blocked_external",
                live_blocker_reasons=_LIVE_BLOCKED_REASONS,
            )
        )
    return tuple(entries)


OFFICIAL_SOURCE_REGISTRY: Final[tuple[SourceRegistryEntry, ...]] = _build_registry()
_REGISTERED_SOURCES: Final[dict[str, SourceRegistryEntry]] = {
    entry.source_name: entry for entry in OFFICIAL_SOURCE_REGISTRY
}
_REGISTERED_SOURCE_NAMES: Final[frozenset[str]] = frozenset(_REGISTERED_SOURCES)


def get_official_source_registry() -> tuple[SourceRegistryEntry, ...]:
    """Return the immutable declarative registry of official sources."""
    return OFFICIAL_SOURCE_REGISTRY


def get_registered_source_names() -> frozenset[str]:
    """Return the set of registered source names."""
    return _REGISTERED_SOURCE_NAMES


def get_registered_source(source_name: str) -> SourceRegistryEntry | None:
    """Return the registry entry for ``source_name`` or ``None`` if unknown."""
    return _REGISTERED_SOURCES.get(_normalize_source_name(source_name))


def is_source_registered(source_name: str) -> bool:
    """Return ``True`` only if ``source_name`` is a registered official source."""
    return _normalize_source_name(source_name) in _REGISTERED_SOURCES


def assert_source_registered(source_name: str) -> SourceRegistryEntry:
    """Fail closed when ``source_name`` is not a registered official source."""
    entry = get_registered_source(source_name)
    if entry is None:
        raise OfficialSourceRegistryError(
            f"Source is not registered in the official source registry: {source_name!r}."
        )
    return entry


def is_offline_normalization_permitted(source_name: str) -> bool:
    """Return ``True`` only if offline fixture normalization is approved.

    This is the gate for the offline adapter path (test-only synthetic
    fixtures). It is ``True`` only for registered sources whose
    ``offline_normalization_status`` is ``approved``.
    """
    entry = get_registered_source(source_name)
    return entry is not None and entry.offline_normalization_status == "approved"


def evaluate_live_ingest_gate(source_name: str) -> tuple[LiveGateDecision, tuple[str, ...]]:
    """Evaluate the live-ingest gate without raising.

    Returns a ``(decision, reasons)`` pair. The decision is:

    * ``unknown_source`` -- the source is not registered at all.
    * ``blocked_external`` -- the source is registered but live collection is
      not externally confirmed (the honest state for every source today).
    * ``approved`` -- the source is registered and its governance has been
      promoted to externally confirmed ``approved`` with verified license,
      terms, retention, provenance, and image rights.

    No source is ``approved`` in this PR.
    """
    entry = get_registered_source(source_name)
    if entry is None:
        return "unknown_source", ("source is not registered in the registry",)
    if entry.live_ingest_status != "approved":
        return "blocked_external", entry.live_blocker_reasons
    governance = entry.governance
    missing = [
        label
        for label, value in (
            ("license", governance.license_class),
            ("terms", governance.terms_version),
            ("retention", governance.retention_policy),
            ("provenance", governance.provenance_policy),
        )
        if not value
    ]
    if governance.image_rights_status != "verified":
        missing.append("image rights")
    if governance.source_status != "approved":
        missing.append("governance approval")
    if missing:
        return "blocked_external", tuple(
            reason for reason in (*entry.live_blocker_reasons, f"missing: {', '.join(missing)}")
        )
    return "approved", ()


def is_live_ingest_permitted(source_name: str) -> bool:
    """Return ``True`` only if live collection is fully approved for the source.

    Always ``False`` for every source in this PR (live ingest is
    ``blocked_external``). Provided as a boolean gate for future live slices.
    """
    decision, _reasons = evaluate_live_ingest_gate(source_name)
    return decision == "approved"


def assert_live_ingest_permitted(source_name: str) -> None:
    """Fail closed before any live acquisition unless the source is approved.

    A future live-ingest slice must call this before any network, crawl, or DB
    write. It raises :class:`OfficialSourceRegistryError` when the source is
    unknown or live collection is not externally confirmed. It never raises for
    an approved source, but no source reaches that state in this PR.
    """
    decision, reasons = evaluate_live_ingest_gate(source_name)
    if decision != "approved":
        raise OfficialSourceRegistryError(
            f"Live ingest is not permitted for source {source_name!r}: "
            f"{decision} ({'; '.join(reasons)})."
        )


def assert_offline_normalization_permitted(source_name: str) -> SourceRegistryEntry:
    """Fail closed when offline fixture normalization is not approved.

    Returns the registry entry on success so the offline adapter can reuse the
    declared identity/policy shape without re-deriving it.
    """
    entry = get_registered_source(source_name)
    if entry is None:
        raise OfficialSourceRegistryError(
            f"Offline normalization is not permitted for an unregistered source: {source_name!r}."
        )
    if entry.offline_normalization_status != "approved":
        raise OfficialSourceRegistryError(
            f"Offline normalization is not approved for source: {source_name!r}."
        )
    return entry


def _normalize_source_name(value: object) -> str:
    text = " ".join(str(value or "").strip().split()).lower()
    return "_".join(part for part in text.split() if part) or ""


def normalize_entries(
    entries: Sequence[SourceRegistryEntry | OfficialSourceInventory],
) -> tuple[SourceRegistryEntry, ...]:
    """Normalize a caller-supplied sequence into registry entries.

    Accepts either :class:`SourceRegistryEntry` objects (passed through) or raw
    :class:`OfficialSourceInventory` objects, which are wrapped with the same
    honest default gate (offline approved, live blocked_external) used by the
    declarative registry. Provided for tests and future reconciliation slices
    that build a registry view from supplied inventory without promoting any
    source to live-approved.
    """
    seen: set[str] = set()
    out: list[SourceRegistryEntry] = []
    for raw in entries:
        entry = (
            raw
            if isinstance(raw, SourceRegistryEntry)
            else SourceRegistryEntry(
                inventory=raw,
                offline_normalization_status="approved",
                live_ingest_status="blocked_external",
                live_blocker_reasons=_LIVE_BLOCKED_REASONS,
            )
        )
        if entry.source_name in seen:
            raise OfficialSourceInventoryError(
                f"Duplicate official source registry entry: {entry.source_name}."
            )
        seen.add(entry.source_name)
        out.append(entry)
    return tuple(out)


__all__ = [
    "LiveGateDecision",
    "LiveIngestReadiness",
    "OFFICIAL_SOURCE_REGISTRY",
    "OfflineNormalizationReadiness",
    "OfficialSourceRegistryError",
    "SourceRegistryEntry",
    "assert_live_ingest_permitted",
    "assert_offline_normalization_permitted",
    "assert_source_registered",
    "evaluate_live_ingest_gate",
    "get_official_source_registry",
    "get_registered_source",
    "get_registered_source_names",
    "is_live_ingest_permitted",
    "is_offline_normalization_permitted",
    "is_source_registered",
    "normalize_entries",
]
