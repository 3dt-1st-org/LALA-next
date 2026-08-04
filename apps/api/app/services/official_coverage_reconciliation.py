"""P2 Official-Data Coverage Reconciliation Contract.

Provider-neutral, offline-only coverage reconciliation/report contract consumable
by future approved full-ingest dry runs. Reuses existing P1 inventory, governance,
receipt, and normalized-record semantics.

This contract extends P1 coverage reporting with focused reconciliation semantics
for full-ingest preparation and validation.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any, Literal

from apps.api.app.services import official_source_inventory as inventory
from apps.api.app.services.official_source_inventory import OfficialCoverageReceipt

CoverageState = Literal["usable", "blocked_external", "rejected", "stale", "unknown"]
ReconciliationGap = Literal[
    "missing_source",
    "no_coverage",
    "stale_coverage",
    "governance_blocked",
    "rejected_source",
    "scope_mismatch",
]

# Bounded public-safe category keys for quality metrics
# Define canonical set as frozen set for validation
CANONICAL_QUALITY_CATEGORIES = frozenset(
    [
        "attraction",
        "culture_venue",
        "lodging",
        "restaurant",
        "shopping",
        "transport",
    ]
)

QUALITY_CATEGORY_KEYS = Literal[
    "attraction",
    "culture_venue",
    "lodging",
    "restaurant",
    "shopping",
    "transport",
]

# Canonical 17-province set for nationwide coverage validation
CANONICAL_NATIONWIDE_REGIONS = (
    "seoul",
    "gyeonggi",
    "incheon",
    "busan",
    "daegu",
    "gwangju",
    "daejeon",
    "ulsan",
    "sejong",
    "gangwon",
    "chungbuk",
    "chungnam",
    "jeonbuk",
    "jeonnam",
    "gyeongbuk",
    "gyeongnam",
    "jeju",
)


@dataclass(frozen=True)
class CoverageQualityMetrics:
    """Denominator-safe quality metrics for coverage validation.

    All metrics are optional and only reported when explicit denominators are supplied.
    Numerator must not exceed denominator. Both must be non-negative.
    When metrics are absent, reports None/unknown, never inferred percentages.

    This type contains NO raw row data, only aggregated counts and rates.
    """

    source_name: str
    dataset_name: str

    # Category coverage (all optional, denominator-safe)
    category_counts: dict[str, int] | None = None  # category -> count
    total_category_count: int | None = None  # denominator for category coverage

    # Coordinate quality
    valid_coordinate_count: int | None = None
    total_coordinate_count: int | None = None
    valid_coordinate_rate: float | None = None  # computed only when both counts present

    # Image rights readiness
    image_rights_ready_count: int | None = None
    total_image_count: int | None = None
    image_rights_ready_rate: float | None = None  # computed only when both counts present

    # Operating hours availability
    operating_hours_available_count: int | None = None
    total_operating_hours_count: int | None = None
    operating_hours_available_rate: float | None = None  # computed only when both counts present

    # Data quality issues (all optional)
    duplicate_count: int | None = None
    quarantined_count: int | None = None
    failed_validation_count: int | None = None
    total_quality_checked: int | None = None  # denominator for quality metrics
    duplicate_rate: float | None = None  # computed only when total_quality_checked > 0
    quarantined_rate: float | None = None  # computed only when total_quality_checked > 0
    failed_validation_rate: float | None = None  # computed only when total_quality_checked > 0

    # Database comparison (metadata only, never a DB call)
    db_comparison_count: int | None = None  # None if unavailable, count if mismatch metadata
    db_comparison_status: Literal["unavailable", "matched", "mismatch"] | None = None

    def __post_init__(self) -> None:
        """Validate metric constraints."""
        # Validate non-negative counts
        for field_name in [
            "total_category_count",
            "valid_coordinate_count",
            "total_coordinate_count",
            "image_rights_ready_count",
            "total_image_count",
            "operating_hours_available_count",
            "total_operating_hours_count",
            "duplicate_count",
            "quarantined_count",
            "failed_validation_count",
            "total_quality_checked",
            "db_comparison_count",
        ]:
            value = getattr(self, field_name)
            if value is not None and value < 0:
                raise ValueError(f"{field_name} must be non-negative, got {value}")

        # Validate category keys against canonical set
        if self.category_counts:
            for category_key in self.category_counts:
                if category_key not in CANONICAL_QUALITY_CATEGORIES:
                    raise ValueError(f"Invalid category key: {category_key}")

        # Validate category counts are non-negative
        if self.category_counts:
            for category_key, count in self.category_counts.items():
                if count is not None and count < 0:
                    raise ValueError(
                        f"Category count for {category_key} must be non-negative, got {count}"
                    )

        # Validate numerator <= denominator for coordinate quality
        if (
            self.valid_coordinate_count is not None
            and self.total_coordinate_count is not None
            and self.valid_coordinate_count > self.total_coordinate_count
        ):
            raise ValueError(
                f"valid_coordinate_count ({self.valid_coordinate_count}) cannot exceed "
                f"total_coordinate_count ({self.total_coordinate_count})"
            )

        # Validate numerator <= denominator for image rights
        if (
            self.image_rights_ready_count is not None
            and self.total_image_count is not None
            and self.image_rights_ready_count > self.total_image_count
        ):
            raise ValueError(
                f"image_rights_ready_count ({self.image_rights_ready_count}) cannot exceed "
                f"total_image_count ({self.total_image_count})"
            )

        # Validate numerator <= denominator for operating hours
        if (
            self.operating_hours_available_count is not None
            and self.total_operating_hours_count is not None
            and self.operating_hours_available_count > self.total_operating_hours_count
        ):
            raise ValueError(
                f"operating_hours_available_count ({self.operating_hours_available_count}) cannot exceed "
                f"total_operating_hours_count ({self.total_operating_hours_count})"
            )

        # Validate quality issue counts against total
        if self.total_quality_checked is not None:
            total_issues = sum(
                [
                    self.duplicate_count or 0,
                    self.quarantined_count or 0,
                    self.failed_validation_count or 0,
                ]
            )
            if total_issues > self.total_quality_checked:
                raise ValueError(
                    f"Total quality issues ({total_issues}) cannot exceed "
                    f"total_quality_checked ({self.total_quality_checked})"
                )

        # Validate category counts against total
        if (
            self.category_counts
            and self.total_category_count is not None
            and sum(self.category_counts.values()) > self.total_category_count
        ):
            raise ValueError(
                f"Sum of category counts ({sum(self.category_counts.values())}) cannot exceed "
                f"total_category_count ({self.total_category_count})"
            )

    def compute_rates(self) -> CoverageQualityMetrics:
        """Return a new instance with computed rates filled in where possible."""
        rates = {
            "valid_coordinate_rate": None,
            "image_rights_ready_rate": None,
            "operating_hours_available_rate": None,
            "duplicate_rate": None,
            "quarantined_rate": None,
            "failed_validation_rate": None,
        }

        # Compute coordinate rate only when both counts present and denominator > 0
        if (
            self.valid_coordinate_count is not None
            and self.total_coordinate_count is not None
            and self.total_coordinate_count > 0
        ):
            rates["valid_coordinate_rate"] = (
                self.valid_coordinate_count / self.total_coordinate_count
            )

        # Compute image rights rate only when both counts present and denominator > 0
        if (
            self.image_rights_ready_count is not None
            and self.total_image_count is not None
            and self.total_image_count > 0
        ):
            rates["image_rights_ready_rate"] = (
                self.image_rights_ready_count / self.total_image_count
            )

        # Compute operating hours rate only when both counts present and denominator > 0
        if (
            self.operating_hours_available_count is not None
            and self.total_operating_hours_count is not None
            and self.total_operating_hours_count > 0
        ):
            rates["operating_hours_available_rate"] = (
                self.operating_hours_available_count / self.total_operating_hours_count
            )

        # Compute quality issue rates only when total_quality_checked > 0
        if self.total_quality_checked is not None and self.total_quality_checked > 0:
            if self.duplicate_count is not None:
                rates["duplicate_rate"] = self.duplicate_count / self.total_quality_checked
            if self.quarantined_count is not None:
                rates["quarantined_rate"] = self.quarantined_count / self.total_quality_checked
            if self.failed_validation_count is not None:
                rates["failed_validation_rate"] = (
                    self.failed_validation_count / self.total_quality_checked
                )

        return CoverageQualityMetrics(**{**self.__dict__, **rates})

    def to_public_dict(self) -> dict[str, Any]:
        """Public-safe projection omitting internal metadata."""
        return {
            "source_name": self.source_name,
            "dataset_name": self.dataset_name,
            "category_coverage": (
                {
                    "categories": list((self.category_counts or {}).keys()),
                    "counts": self.category_counts or {},
                    "total_count": self.total_category_count,
                }
                if self.category_counts or self.total_category_count is not None
                else None
            ),
            "coordinate_quality": (
                {
                    "valid_count": self.valid_coordinate_count,
                    "total_count": self.total_coordinate_count,
                    "valid_rate": self.valid_coordinate_rate,
                }
                if any(
                    x is not None
                    for x in [
                        self.valid_coordinate_count,
                        self.total_coordinate_count,
                        self.valid_coordinate_rate,
                    ]
                )
                else None
            ),
            "image_rights": (
                {
                    "ready_count": self.image_rights_ready_count,
                    "total_count": self.total_image_count,
                    "ready_rate": self.image_rights_ready_rate,
                }
                if any(
                    x is not None
                    for x in [
                        self.image_rights_ready_count,
                        self.total_image_count,
                        self.image_rights_ready_rate,
                    ]
                )
                else None
            ),
            "operating_hours": (
                {
                    "available_count": self.operating_hours_available_count,
                    "total_count": self.total_operating_hours_count,
                    "available_rate": self.operating_hours_available_rate,
                }
                if any(
                    x is not None
                    for x in [
                        self.operating_hours_available_count,
                        self.total_operating_hours_count,
                        self.operating_hours_available_rate,
                    ]
                )
                else None
            ),
            "data_quality": (
                {
                    "duplicate_count": self.duplicate_count,
                    "quarantined_count": self.quarantined_count,
                    "failed_validation_count": self.failed_validation_count,
                    "total_checked": self.total_quality_checked,
                    "duplicate_rate": self.duplicate_rate,
                    "quarantined_rate": self.quarantined_rate,
                    "failed_validation_rate": self.failed_validation_rate,
                }
                if any(
                    x is not None
                    for x in [
                        self.duplicate_count,
                        self.quarantined_count,
                        self.failed_validation_count,
                        self.total_quality_checked,
                        self.duplicate_rate,
                        self.quarantined_rate,
                        self.failed_validation_rate,
                    ]
                )
                else None
            ),
            "database_comparison": (
                {
                    "count": self.db_comparison_count,
                    "status": self.db_comparison_status,
                }
                if self.db_comparison_count is not None or self.db_comparison_status is not None
                else None
            ),
        }


@dataclass(frozen=True)
class CoverageGap:
    """A specific coverage deficiency identified during reconciliation."""

    gap_type: ReconciliationGap
    source_name: str
    dataset_name: str
    description: str
    expected_regions: tuple[str, ...] = ()
    actual_regions: tuple[str, ...] = ()
    expected_record_count: int | None = None
    actual_record_count: int | None = None
    latest_receipt_at: datetime | None = None

    def to_public_dict(self) -> dict[str, Any]:
        """Public-safe projection omitting internal metadata."""
        return {
            "gap_type": self.gap_type,
            "source_name": self.source_name,
            "dataset_name": self.dataset_name,
            "description": self.description,
            "expected_regions": self.expected_regions,
            "actual_regions": self.actual_regions,
            "expected_record_count": self.expected_record_count,
            "actual_record_count": self.actual_record_count,
            "latest_receipt_at": self.latest_receipt_at.isoformat()
            if self.latest_receipt_at
            else None,
        }


@dataclass(frozen=True)
class RegionalCoverageBreakdown:
    """Per-region coverage status for nationwide scope sources."""

    region_code: str
    has_coverage: bool
    record_count: int | None
    source_status: CoverageState
    sources_covered: tuple[str, ...]  # source_names that cover this region


@dataclass(frozen=True)
class ReconciliationReport:
    """Focused reconciliation report for full-ingest dry run validation.

    Extends P1 coverage reporting with reconciliation-specific semantics:
    - Gap analysis vs expected coverage targets
    - Regional breakdown for nationwide validation
    - Freshness and governance reconciliation
    - Denominator-safe quality metrics
    - Deterministic, offline-only, JSON-safe output
    """

    generated_at: datetime
    total_sources: int
    usable_sources: int
    blocked_sources: int
    rejected_sources: int
    stale_sources: int
    unknown_sources: int
    total_gaps: int
    gaps: tuple[CoverageGap, ...]
    regional_breakdown: tuple[RegionalCoverageBreakdown, ...]
    nationwide_coverage_complete: bool
    total_source_scoped_record_count: int
    quality_metrics: tuple[CoverageQualityMetrics, ...] = ()

    def to_public_dict(self) -> dict[str, Any]:
        """Metadata-only public projection safe for external reporting."""
        return {
            "generated_at": self.generated_at.isoformat(),
            "summary": {
                "total_sources": self.total_sources,
                "usable_sources": self.usable_sources,
                "blocked_sources": self.blocked_sources,
                "rejected_sources": self.rejected_sources,
                "stale_sources": self.stale_sources,
                "unknown_sources": self.unknown_sources,
                "total_gaps": self.total_gaps,
                "nationwide_coverage_complete": self.nationwide_coverage_complete,
                "total_source_scoped_record_count": self.total_source_scoped_record_count,
            },
            "gaps": [gap.to_public_dict() for gap in self.gaps],
            "regional_breakdown": [
                {
                    "region_code": r.region_code,
                    "has_coverage": r.has_coverage,
                    "record_count": r.record_count,
                    "source_status": r.source_status,
                    "sources_covered": r.sources_covered,
                }
                for r in self.regional_breakdown
            ],
            "quality_metrics": [m.to_public_dict() for m in self.quality_metrics],
        }


@dataclass(frozen=True)
class FullIngestDryRunValidation:
    """Validation result for a proposed full ingest.

    Provides pass/fail determination with specific blockers for ingest approval.
    """

    is_approved: bool
    validation_timestamp: datetime
    total_sources_checked: int
    approved_sources: int
    blocked_sources: int
    blockers: tuple[str, ...]
    warnings: tuple[str, ...]

    def to_public_dict(self) -> dict[str, Any]:
        """Public-safe validation projection."""
        return {
            "is_approved": self.is_approved,
            "validation_timestamp": self.validation_timestamp.isoformat(),
            "total_sources_checked": self.total_sources_checked,
            "approved_sources": self.approved_sources,
            "blocked_sources": self.blocked_sources,
            "blockers": self.blockers,
            "warnings": self.warnings,
        }


def build_reconciliation_report(
    *,
    source_inventory: Sequence[inventory.OfficialSourceInventory],
    receipts: Sequence[OfficialCoverageReceipt],
    expected_regions: tuple[str, ...] = CANONICAL_NATIONWIDE_REGIONS,
    generated_at: datetime | None = None,
    quality_metrics: Sequence[CoverageQualityMetrics] | None = None,
) -> ReconciliationReport:
    """Build focused reconciliation report for full-ingest preparation.

    Extends P1 coverage reporting with:
    - Gap analysis against expected 17-province coverage
    - Regional breakdown for nationwide validation
    - Governance and freshness reconciliation
    - Denominator-safe quality metrics (optional)

    Args:
        source_inventory: Official source inventory entries
        receipts: Coverage receipts to reconcile
        expected_regions: 17 provinces for nationwide coverage validation
        generated_at: Report generation timestamp (defaults to now)
        quality_metrics: Optional denominator-safe quality metrics keyed by (source_name, dataset_name)

    Returns:
        ReconciliationReport with gap analysis, regional breakdown, and quality metrics
    """
    if generated_at is None:
        generated_at = datetime.now(UTC)

    # Build P1 coverage report as foundation
    p1_report = inventory.build_official_coverage_report(
        inventory=source_inventory, receipts=receipts, generated_at=generated_at
    )

    # Initialize gaps list before processing
    gaps: list[CoverageGap] = []

    # Validate expected_regions against canonical set
    if set(expected_regions) != set(CANONICAL_NATIONWIDE_REGIONS):
        # Non-canonical region set: reject if trying to validate nationwide coverage
        gaps.append(
            CoverageGap(
                gap_type="scope_mismatch",
                source_name="region_validation",
                dataset_name="expected_regions",
                description="Non-canonical region set provided for nationwide coverage validation",
                expected_regions=CANONICAL_NATIONWIDE_REGIONS,
                actual_regions=expected_regions,
            )
        )

    # Process quality metrics if provided
    validated_metrics: tuple[CoverageQualityMetrics, ...] = ()
    if quality_metrics:
        computed_metrics = []
        # Build inventory lookup for scope validation
        inventory_sources = {(entry.source_name, entry.dataset_name) for entry in source_inventory}

        for metric in quality_metrics:
            try:
                # Compute rates and validate constraints
                computed_metric = metric.compute_rates()

                # Check if metric source exists in inventory
                metric_key = (computed_metric.source_name, computed_metric.dataset_name)
                if metric_key not in inventory_sources:
                    gaps.append(
                        CoverageGap(
                            gap_type="scope_mismatch",
                            source_name=computed_metric.source_name,
                            dataset_name=computed_metric.dataset_name,
                            description=f"Quality metrics provided for source not in inventory: {computed_metric.source_name}",
                        )
                    )
                else:
                    computed_metrics.append(computed_metric)

            except ValueError:
                # Reject invalid metrics without exposing raw exception details
                gaps.append(
                    CoverageGap(
                        gap_type="scope_mismatch",
                        source_name=metric.source_name,
                        dataset_name=metric.dataset_name,
                        description="Invalid quality metrics rejected during validation",
                    )
                )
        validated_metrics = tuple(computed_metrics)

    regional_coverage: dict[str, RegionalCoverageBreakdown] = {}

    usable_count = 0
    blocked_count = 0
    rejected_count = 0
    stale_count = 0
    unknown_count = 0
    total_records = 0

    for source_summary in p1_report.sources:
        # Track source states
        if source_summary.readiness == "usable":
            usable_count += 1
        elif source_summary.readiness == "blocked_external":
            blocked_count += 1
        elif source_summary.readiness == "rejected":
            rejected_count += 1
        elif source_summary.readiness == "stale":
            stale_count += 1
        else:
            unknown_count += 1

        # Count distinct records
        if source_summary.distinct_record_count is not None:
            total_records += source_summary.distinct_record_count

        # Check for governance gaps
        if source_summary.readiness == "blocked_external":
            gaps.append(
                CoverageGap(
                    gap_type="governance_blocked",
                    source_name=source_summary.source_name,
                    dataset_name=source_summary.dataset_name,
                    description="Source governance blocks ingest approval",
                    latest_receipt_at=source_summary.latest_receipt_at,
                )
            )

        # Check for rejected sources
        if source_summary.readiness == "rejected":
            gaps.append(
                CoverageGap(
                    gap_type="rejected_source",
                    source_name=source_summary.source_name,
                    dataset_name=source_summary.dataset_name,
                    description="Source rejected from ingest pipeline",
                    latest_receipt_at=source_summary.latest_receipt_at,
                )
            )

        # Check for stale coverage
        if source_summary.readiness == "stale":
            gaps.append(
                CoverageGap(
                    gap_type="stale_coverage",
                    source_name=source_summary.source_name,
                    dataset_name=source_summary.dataset_name,
                    description="Coverage is outside freshness SLA",
                    latest_receipt_at=source_summary.latest_receipt_at,
                )
            )

        # Check for unknown/no coverage
        if source_summary.readiness == "unknown" or source_summary.coverage_scope == "unknown":
            gaps.append(
                CoverageGap(
                    gap_type="no_coverage",
                    source_name=source_summary.source_name,
                    dataset_name=source_summary.dataset_name,
                    description="No accepted receipt proves coverage",
                    latest_receipt_at=source_summary.latest_receipt_at,
                )
            )

    # Build regional breakdown for canonical regions only
    for region in CANONICAL_NATIONWIDE_REGIONS:
        region_has_coverage = False
        region_sources: list[str] = []

        for source_summary in p1_report.sources:
            if (
                source_summary.readiness == "usable"
                and source_summary.coverage_scope == "nationwide"
                and region in source_summary.covered_regions
            ):
                region_has_coverage = True
                region_sources.append(source_summary.source_name)

        regional_coverage[region] = RegionalCoverageBreakdown(
            region_code=region,
            has_coverage=region_has_coverage,
            record_count=None,  # No proven per-region count available
            source_status="usable" if region_has_coverage else "unknown",
            sources_covered=tuple(region_sources),
        )

    # Check for missing expected regions (nationwide coverage gap)
    covered_regions = set(rb.region_code for rb in regional_coverage.values() if rb.has_coverage)
    missing_regions = set(CANONICAL_NATIONWIDE_REGIONS) - covered_regions
    if missing_regions:
        gaps.append(
            CoverageGap(
                gap_type="scope_mismatch",
                source_name="nationwide",
                dataset_name="aggregate",
                description=f"Expected nationwide coverage missing {len(missing_regions)} regions",
                expected_regions=CANONICAL_NATIONWIDE_REGIONS,
                actual_regions=tuple(sorted(covered_regions)),
            )
        )

    return ReconciliationReport(
        generated_at=generated_at,
        total_sources=len(p1_report.sources),
        usable_sources=usable_count,
        blocked_sources=blocked_count,
        rejected_sources=rejected_count,
        stale_sources=stale_count,
        unknown_sources=unknown_count,
        total_gaps=len(gaps),
        gaps=tuple(gaps),
        regional_breakdown=tuple(regional_coverage.values()),
        nationwide_coverage_complete=len(missing_regions) == 0
        and set(expected_regions) == set(CANONICAL_NATIONWIDE_REGIONS),
        total_source_scoped_record_count=total_records,
        quality_metrics=validated_metrics,
    )


def validate_full_ingest_dry_run(
    *,
    reconciliation_report: ReconciliationReport,
    require_nationwide_coverage: bool = True,
    require_all_sources_usable: bool = False,
    max_stale_sources: int = 0,
    validation_timestamp: datetime | None = None,
) -> FullIngestDryRunValidation:
    """Validate full ingest readiness from reconciliation report.

    Provides deterministic pass/fail determination with specific blockers.

    Args:
        reconciliation_report: Coverage reconciliation report to validate
        require_nationwide_coverage: Whether all 17 provinces must be covered
        require_all_sources_usable: Whether all sources must be usable (not blocked/stale)
        max_stale_sources: Maximum number of stale sources allowed
        validation_timestamp: Validation timestamp (defaults to now)

    Returns:
        FullIngestDryRunValidation with approval status and blockers
    """
    if validation_timestamp is None:
        validation_timestamp = datetime.now(UTC)

    blockers: list[str] = []
    warnings: list[str] = []

    # Check nationwide coverage requirement
    if require_nationwide_coverage and not reconciliation_report.nationwide_coverage_complete:
        missing_regions = [
            rb.region_code for rb in reconciliation_report.regional_breakdown if not rb.has_coverage
        ]
        blockers.append(
            f"Nationwide coverage incomplete: {len(missing_regions)} regions missing coverage ({', '.join(sorted(missing_regions))})"
        )

    # Check all sources usable requirement
    if require_all_sources_usable:
        non_usable = (
            reconciliation_report.blocked_sources
            + reconciliation_report.rejected_sources
            + reconciliation_report.stale_sources
            + reconciliation_report.unknown_sources
        )
        if non_usable > 0:
            blockers.append(
                f"Require all sources usable: {non_usable} sources not usable "
                f"({reconciliation_report.blocked_sources} blocked, "
                f"{reconciliation_report.rejected_sources} rejected, "
                f"{reconciliation_report.stale_sources} stale, "
                f"{reconciliation_report.unknown_sources} unknown)"
            )

    # Check stale sources threshold
    if reconciliation_report.stale_sources > max_stale_sources:
        blockers.append(
            f"Stale sources exceed threshold: {reconciliation_report.stale_sources} stale > {max_stale_sources} allowed"
        )

    # Check for governance blockers
    governance_gaps = [g for g in reconciliation_report.gaps if g.gap_type == "governance_blocked"]
    if governance_gaps:
        blocked_source_names = sorted(set(g.source_name for g in governance_gaps))
        blockers.append(
            f"Governance blocks {len(blocked_source_names)} sources: {', '.join(blocked_source_names)}"
        )

    # Add warnings for non-critical issues
    if reconciliation_report.unknown_sources > 0:
        warnings.append(
            f"{reconciliation_report.unknown_sources} sources have unknown coverage status"
        )

    total_approved = reconciliation_report.usable_sources
    total_blocked = (
        reconciliation_report.blocked_sources
        + reconciliation_report.rejected_sources
        + reconciliation_report.stale_sources
        + reconciliation_report.unknown_sources
    )

    return FullIngestDryRunValidation(
        is_approved=len(blockers) == 0,
        validation_timestamp=validation_timestamp,
        total_sources_checked=reconciliation_report.total_sources,
        approved_sources=total_approved,
        blocked_sources=total_blocked,
        blockers=tuple(blockers),
        warnings=tuple(warnings),
    )


def reconcile_receipt_coverage(
    *,
    source_name: str,
    dataset_name: str,
    source_inventory: Sequence[inventory.OfficialSourceInventory],
    receipts: Sequence[OfficialCoverageReceipt],
    expected_minimum_records: int | None = None,
) -> CoverageGap | None:
    """Reconcile coverage for a specific source/dataset combination.

    Args:
        source_name: Source identifier to reconcile
        dataset_name: Dataset identifier to reconcile
        source_inventory: Source inventory entries
        receipts: Coverage receipts to reconcile
        expected_minimum_records: Minimum record count expected (optional)

    Returns:
        CoverageGap if a gap is identified, None if coverage is adequate
    """
    # Build P1 report for this specific source
    matching_inventory = [
        inv
        for inv in source_inventory
        if inv.source_name == source_name and inv.dataset_name == dataset_name
    ]
    if not matching_inventory:
        return CoverageGap(
            gap_type="missing_source",
            source_name=source_name,
            dataset_name=dataset_name,
            description="Source not found in inventory",
        )

    p1_report = inventory.build_official_coverage_report(
        inventory=matching_inventory, receipts=receipts, generated_at=datetime.now(UTC)
    )

    if not p1_report.sources:
        return CoverageGap(
            gap_type="no_coverage",
            source_name=source_name,
            dataset_name=dataset_name,
            description="No coverage data available for source",
        )

    summary = p1_report.sources[0]

    # Check readiness state with deterministic mapping
    if summary.readiness == "blocked_external":
        return CoverageGap(
            gap_type="governance_blocked",
            source_name=source_name,
            dataset_name=dataset_name,
            description="Source readiness is blocked_external, not usable",
            actual_record_count=summary.distinct_record_count,
            latest_receipt_at=summary.latest_receipt_at,
        )
    if summary.readiness == "rejected":
        return CoverageGap(
            gap_type="rejected_source",
            source_name=source_name,
            dataset_name=dataset_name,
            description="Source readiness is rejected, not usable",
            actual_record_count=summary.distinct_record_count,
            latest_receipt_at=summary.latest_receipt_at,
        )
    if summary.readiness == "stale":
        return CoverageGap(
            gap_type="stale_coverage",
            source_name=source_name,
            dataset_name=dataset_name,
            description="Source readiness is stale, not usable",
            actual_record_count=summary.distinct_record_count,
            latest_receipt_at=summary.latest_receipt_at,
        )
    if summary.readiness == "unknown":
        return CoverageGap(
            gap_type="no_coverage",
            source_name=source_name,
            dataset_name=dataset_name,
            description="Source readiness is unknown, no coverage",
            actual_record_count=summary.distinct_record_count,
            latest_receipt_at=summary.latest_receipt_at,
        )

    # Check minimum record count
    if (
        expected_minimum_records is not None
        and summary.distinct_record_count is not None
        and summary.distinct_record_count < expected_minimum_records
    ):
        return CoverageGap(
            gap_type="scope_mismatch",
            source_name=source_name,
            dataset_name=dataset_name,
            description=f"Record count below minimum: {summary.distinct_record_count} < {expected_minimum_records}",
            expected_record_count=expected_minimum_records,
            actual_record_count=summary.distinct_record_count,
            latest_receipt_at=summary.latest_receipt_at,
        )

    return None
