"""P2 Official-Data Coverage Reconciliation Contract.

Provider-neutral, offline-only coverage reconciliation/report contract consumable
by future approved full-ingest dry runs. Reuses existing P1 inventory, governance,
receipt, and normalized-record semantics.

This contract extends P1 coverage reporting with focused reconciliation semantics
for full-ingest preparation and validation.
"""

from __future__ import annotations

import hashlib
import json
from collections import defaultdict
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime
from typing import Any, Final, Literal

from apps.api.app.services import official_source_inventory as inventory
from apps.api.app.services.official_source_inventory import OfficialCoverageReceipt

CoverageState = Literal["usable", "blocked_external", "rejected", "stale", "unknown"]
ReconciliationGap = Literal["missing_source", "no_coverage", "stale_coverage", "governance_blocked", "scope_mismatch"]


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
            "latest_receipt_at": self.latest_receipt_at.isoformat() if self.latest_receipt_at else None,
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
    - Deterministic, offline-only, JSON-safe output
    """

    generated_at: datetime
    total_sources: int
    usable_sources: int
    blocked_sources: int
    stale_sources: int
    unknown_sources: int
    total_gaps: int
    gaps: tuple[CoverageGap, ...]
    regional_breakdown: tuple[RegionalCoverageBreakdown, ...]
    nationwide_coverage_complete: bool
    total_distinct_records: int

    def to_public_dict(self) -> dict[str, Any]:
        """Metadata-only public projection safe for external reporting."""
        return {
            "generated_at": self.generated_at.isoformat(),
            "summary": {
                "total_sources": self.total_sources,
                "usable_sources": self.usable_sources,
                "blocked_sources": self.blocked_sources,
                "stale_sources": self.stale_sources,
                "unknown_sources": self.unknown_sources,
                "total_gaps": self.total_gaps,
                "nationwide_coverage_complete": self.nationwide_coverage_complete,
                "total_distinct_records": self.total_distinct_records,
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
    expected_regions: tuple[str, ...] = (
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
    ),
    generated_at: datetime | None = None,
) -> ReconciliationReport:
    """Build focused reconciliation report for full-ingest preparation.

    Extends P1 coverage reporting with:
    - Gap analysis against expected 17-province coverage
    - Regional breakdown for nationwide validation
    - Governance and freshness reconciliation

    Args:
        source_inventory: Official source inventory entries
        receipts: Coverage receipts to reconcile
        expected_regions: 17 provinces for nationwide coverage validation
        generated_at: Report generation timestamp (defaults to now)

    Returns:
        ReconciliationReport with gap analysis and regional breakdown
    """
    if generated_at is None:
        generated_at = datetime.now(UTC)

    # Build P1 coverage report as foundation
    p1_report = inventory.build_official_coverage_report(
        inventory=source_inventory, receipts=receipts, generated_at=generated_at
    )

    # Analyze gaps and regional coverage
    gaps: list[CoverageGap] = []
    regional_coverage: dict[str, RegionalCoverageBreakdown] = {}
    source_status_by_region: dict[str, dict[str, CoverageState]] = defaultdict(lambda: defaultdict(str))

    usable_count = 0
    blocked_count = 0
    stale_count = 0
    unknown_count = 0
    total_records = 0

    for source_summary in p1_report.sources:
        # Track source states
        if source_summary.readiness == "usable":
            usable_count += 1
        elif source_summary.readiness == "blocked_external":
            blocked_count += 1
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

        # Regional coverage analysis for nationwide sources
        if source_summary.coverage_scope == "nationwide" and source_summary.readiness == "usable":
            covered_regions = set(source_summary.covered_regions)
            for region in expected_regions:
                source_status_by_region[region][source_summary.source_name] = (
                    "usable" if region in covered_regions else "unknown"
                )

    # Build regional breakdown
    for region in expected_regions:
        region_has_coverage = False
        region_record_count: int | None = None
        region_sources: list[str] = []

        for source_summary in p1_report.sources:
            if (
                source_summary.readiness == "usable"
                and source_summary.coverage_scope == "nationwide"
                and region in source_summary.covered_regions
            ):
                region_has_coverage = True
                region_sources.append(source_summary.source_name)
                if source_summary.distinct_record_count is not None:
                    if region_record_count is None:
                        region_record_count = 0
                    # Approximate regional count as proportional share
                    region_record_count += source_summary.distinct_record_count // len(source_summary.covered_regions or [1])

        regional_coverage[region] = RegionalCoverageBreakdown(
            region_code=region,
            has_coverage=region_has_coverage,
            record_count=region_record_count,
            source_status="usable" if region_has_coverage else "unknown",
            sources_covered=tuple(region_sources),
        )

    # Check for missing expected regions (nationwide coverage gap)
    covered_regions = set(rb.region_code for rb in regional_coverage.values() if rb.has_coverage)
    missing_regions = set(expected_regions) - covered_regions
    if missing_regions:
        gaps.append(
            CoverageGap(
                gap_type="scope_mismatch",
                source_name="nationwide",
                dataset_name="aggregate",
                description=f"Expected nationwide coverage missing {len(missing_regions)} regions",
                expected_regions=expected_regions,
                actual_regions=tuple(sorted(covered_regions)),
            )
        )

    return ReconciliationReport(
        generated_at=generated_at,
        total_sources=len(p1_report.sources),
        usable_sources=usable_count,
        blocked_sources=blocked_count,
        stale_sources=stale_count,
        unknown_sources=unknown_count,
        total_gaps=len(gaps),
        gaps=tuple(gaps),
        regional_breakdown=tuple(regional_coverage.values()),
        nationwide_coverage_complete=len(missing_regions) == 0,
        total_distinct_records=total_records,
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
            rb.region_code
            for rb in reconciliation_report.regional_breakdown
            if not rb.has_coverage
        ]
        blockers.append(
            f"Nationwide coverage incomplete: {len(missing_regions)} regions missing coverage ({', '.join(sorted(missing_regions))})"
        )

    # Check all sources usable requirement
    if require_all_sources_usable:
        non_usable = reconciliation_report.blocked_sources + reconciliation_report.stale_sources + reconciliation_report.unknown_sources
        if non_usable > 0:
            blockers.append(
                f"Require all sources usable: {non_usable} sources not usable "
                f"({reconciliation_report.blocked_sources} blocked, "
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
        blockers.append(f"Governance blocks {len(blocked_source_names)} sources: {', '.join(blocked_source_names)}")

    # Add warnings for non-critical issues
    if reconciliation_report.unknown_sources > 0:
        warnings.append(f"{reconciliation_report.unknown_sources} sources have unknown coverage status")

    total_approved = reconciliation_report.usable_sources
    total_blocked = reconciliation_report.blocked_sources + reconciliation_report.stale_sources + reconciliation_report.unknown_sources

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
    matching_inventory = [inv for inv in source_inventory if inv.source_name == source_name and inv.dataset_name == dataset_name]
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

    # Check readiness state
    if summary.readiness != "usable":
        return CoverageGap(
            gap_type="governance_blocked" if summary.readiness == "blocked_external" else "stale_coverage",
            source_name=source_name,
            dataset_name=dataset_name,
            description=f"Source readiness is {summary.readiness}, not usable",
            actual_record_count=summary.distinct_record_count,
            latest_receipt_at=summary.latest_receipt_at,
        )

    # Check minimum record count
    if expected_minimum_records is not None and summary.distinct_record_count is not None:
        if summary.distinct_record_count < expected_minimum_records:
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
