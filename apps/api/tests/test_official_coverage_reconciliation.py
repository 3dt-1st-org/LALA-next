"""P2 Coverage Reconciliation Contract Tests.

Focused offline unit tests using synthetic in-memory fixtures.
"""

from __future__ import annotations

from datetime import UTC, datetime

from apps.api.app.services import official_coverage_reconciliation as reconciliation
from apps.api.app.services.official_source_inventory import (
    ImageUrlPolicy,
    OfficialCoverageReceipt,
    OfficialSourceInventory,
    PlaceAcceptancePolicy,
    SourceGovernance,
    SourcePaginationPolicy,
    SourceRecordIdentityPolicy,
    SourceRefreshPolicy,
)

GENERATED_AT = datetime(2026, 8, 5, 0, 0, tzinfo=UTC)


def _entry(**overrides):
    """Create synthetic source inventory entry."""
    from dataclasses import replace

    entry = OfficialSourceInventory(
        source_name="tour_api",
        dataset_name="Official Places",
        purpose="official_place_catalog",
        allowed_public_projection=(
            "place_id",
            "name_ko",
            "name_en",
            "region_code",
            "category",
            "latitude",
            "longitude",
            "image_url",
        ),
        governance=SourceGovernance(
            license_class="public_processed",
            terms_version="terms-v1",
            retention_policy="aggregate-receipt-only",
            provenance_policy="source-record-hash",
            image_rights_status="verified",
            source_status="approved",
        ),
        refresh=SourceRefreshPolicy(cadence_hours=24, freshness_sla_hours=48),
        pagination=SourcePaginationPolicy(semantics="page_cursor", cursor_field="next_cursor"),
        identity=SourceRecordIdentityPolicy(
            stable_fields=("external_id", "region_code", "category"),
            dedupe_fields=("external_id", "region_code"),
        ),
        place_policy=PlaceAcceptancePolicy(
            coverage_scope="nationwide",
            covered_regions=("seoul", "gyeonggi", "busan"),
            accepted_categories=("attraction", "culture_venue"),
            max_coordinate_precision="place_point",
            accepted_languages=("ko", "en"),
            image_url_policy=ImageUrlPolicy(),
        ),
    )
    return replace(entry, **overrides) if overrides else entry


def _receipt(**overrides):
    """Create synthetic coverage receipt."""
    from dataclasses import replace

    receipt = OfficialCoverageReceipt(
        receipt_id="receipt:abcdef123456",
        source_name="tour_api",
        dataset_name="Official Places",
        content_fingerprint="a" * 64,
        observed_at=datetime(2026, 8, 4, 0, 0, tzinfo=UTC),
        record_ids=("record:one", "record:two", "record:three"),
        coverage_scope="nationwide",
        covered_regions=("seoul", "gyeonggi"),
        coordinate_precision="place_point",
        localized_languages=("ko", "en"),
        image_rights_status="verified",
    )
    return replace(receipt, **overrides) if overrides else receipt


def test_reconciliation_report_counts_all_sources():
    """Reconciliation report counts all sources regardless of status."""
    inventory_entries = [
        _entry(source_name="source_a"),
        _entry(source_name="source_b"),
        _entry(source_name="source_c"),
    ]

    receipts = [_receipt(source_name="source_a")]

    report = reconciliation.build_reconciliation_report(
        source_inventory=inventory_entries,
        receipts=receipts,
        generated_at=GENERATED_AT,
    )

    assert report.total_sources == 3
    assert report.usable_sources == 1
    assert report.unknown_sources == 2  # source_b, source_c have no receipts


def test_reconciliation_report_identifies_governance_blocked_sources():
    """Governance-blocked sources create specific gaps."""
    blocked_entry = _entry(
        governance=SourceGovernance(
            license_class=None,
            terms_version=None,
            retention_policy=None,
            provenance_policy=None,
            image_rights_status="unknown",
            source_status="blocked_external",
        )
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[blocked_entry],
        receipts=[],
        generated_at=GENERATED_AT,
    )

    assert report.blocked_sources == 1
    assert any(g.gap_type == "governance_blocked" for g in report.gaps)


def test_reconciliation_report_identifies_stale_coverage():
    """Stale receipts create specific gaps."""
    stale_receipt = _receipt(
        observed_at=datetime(2026, 8, 1, 0, 0, tzinfo=UTC)  # 4 days old, exceeds 48h SLA
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry()],
        receipts=[stale_receipt],
        generated_at=GENERATED_AT,
    )

    assert report.stale_sources == 1
    assert any(g.gap_type == "stale_coverage" for g in report.gaps)


def test_reconciliation_report_identifies_unknown_coverage():
    """Missing coverage creates specific gaps."""
    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry()],
        receipts=[],
        generated_at=GENERATED_AT,
    )

    assert report.unknown_sources == 1
    assert any(g.gap_type == "no_coverage" for g in report.gaps)


def test_regional_breakdown_identifies_missing_regions():
    """Nationwide sources must cover all expected regions."""
    partial_coverage_receipt = _receipt(
        covered_regions=("seoul", "gyeonggi")  # Missing 15 other regions
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry()],
        receipts=[partial_coverage_receipt],
        generated_at=GENERATED_AT,
    )

    assert not report.nationwide_coverage_complete
    assert any(g.gap_type == "scope_mismatch" for g in report.gaps)

    # Check regional breakdown
    seoul_breakdown = next(rb for rb in report.regional_breakdown if rb.region_code == "seoul")
    assert seoul_breakdown.has_coverage is True

    busan_breakdown = next(rb for rb in report.regional_breakdown if rb.region_code == "busan")
    assert busan_breakdown.has_coverage is False


def test_regional_breakdown_complete_coverage():
    """Complete nationwide coverage yields no region gaps."""
    all_regions = (
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

    full_coverage_receipt = _receipt(
        covered_regions=all_regions, record_ids=tuple(f"record:{i}" for i in range(100))
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry()],
        receipts=[full_coverage_receipt],
        generated_at=GENERATED_AT,
    )

    assert report.nationwide_coverage_complete
    assert all(rb.has_coverage for rb in report.regional_breakdown)


def test_full_ingest_validation_fails_on_incomplete_nationwide():
    """Full ingest validation fails when nationwide coverage is incomplete."""
    partial_receipt = _receipt(covered_regions=("seoul", "gyeonggi"))

    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry()],
        receipts=[partial_receipt],
        generated_at=GENERATED_AT,
    )

    validation = reconciliation.validate_full_ingest_dry_run(
        reconciliation_report=report,
        require_nationwide_coverage=True,
        validation_timestamp=GENERATED_AT,
    )

    assert not validation.is_approved
    assert any("Nationwide coverage incomplete" for b in validation.blockers)


def test_full_ingest_validation_fails_on_governance_blocked():
    """Full ingest validation fails when sources are governance blocked."""
    blocked_entry = _entry(
        source_name="blocked_source",
        governance=SourceGovernance(
            license_class=None,
            terms_version=None,
            retention_policy=None,
            provenance_policy=None,
            image_rights_status="unknown",
            source_status="blocked_external",
        ),
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[blocked_entry],
        receipts=[],
        generated_at=GENERATED_AT,
    )

    validation = reconciliation.validate_full_ingest_dry_run(
        reconciliation_report=report,
        require_nationwide_coverage=False,
        validation_timestamp=GENERATED_AT,
    )

    assert not validation.is_approved
    assert any("governance" in b.lower() for b in validation.blockers)


def test_full_ingest_validation_allows_lax_requirements():
    """Full ingest validation passes with relaxed requirements."""
    full_coverage_receipt = _receipt(
        covered_regions=("seoul", "gyeonggi", "busan"),  # Partial coverage
        observed_at=datetime(2026, 8, 4, 23, 0, tzinfo=UTC),  # Fresh
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry()],
        receipts=[full_coverage_receipt],
        generated_at=GENERATED_AT,
    )

    validation = reconciliation.validate_full_ingest_dry_run(
        reconciliation_report=report,
        require_nationwide_coverage=False,  # Relaxed
        require_all_sources_usable=False,
        validation_timestamp=GENERATED_AT,
    )

    assert validation.is_approved


def test_reconcile_specific_source_missing_from_inventory():
    """Specific source reconciliation returns gap for missing inventory."""
    gap = reconciliation.reconcile_receipt_coverage(
        source_name="unknown_source",
        dataset_name="Unknown Dataset",
        source_inventory=[],
        receipts=[],
    )

    assert gap is not None
    assert gap.gap_type == "missing_source"


def test_reconcile_specific_source_no_coverage():
    """Specific source reconciliation returns gap for no coverage."""
    gap = reconciliation.reconcile_receipt_coverage(
        source_name="tour_api",
        dataset_name="Official Places",
        source_inventory=[_entry()],
        receipts=[],
    )

    assert gap is not None
    assert gap.gap_type in ("no_coverage", "stale_coverage")


def test_reconcile_specific_source_below_minimum():
    """Specific source reconciliation returns gap when below minimum records."""
    minimal_receipt = _receipt(record_ids=("record:1", "record:2"))  # Only 2 records

    gap = reconciliation.reconcile_receipt_coverage(
        source_name="tour_api",
        dataset_name="Official Places",
        source_inventory=[_entry()],
        receipts=[minimal_receipt],
        expected_minimum_records=10,
    )

    assert gap is not None
    assert gap.gap_type == "scope_mismatch"
    assert gap.actual_record_count == 2
    assert gap.expected_record_count == 10


def test_reconcile_specific_source_adequate_coverage():
    """Specific source reconciliation returns None when coverage is adequate."""
    adequate_receipt = _receipt(record_ids=tuple(f"record:{i}" for i in range(50)))

    gap = reconciliation.reconcile_receipt_coverage(
        source_name="tour_api",
        dataset_name="Official Places",
        source_inventory=[_entry()],
        receipts=[adequate_receipt],
        expected_minimum_records=10,
    )

    assert gap is None


def test_public_dict_contains_metadata_only():
    """Public projection omits sensitive internal metadata."""
    full_coverage_receipt = _receipt(record_ids=tuple(f"record:{i}" for i in range(50)))

    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry()],
        receipts=[full_coverage_receipt],
        generated_at=GENERATED_AT,
    )

    public = report.to_public_dict()

    # Check metadata is included
    assert "generated_at" in public
    assert "summary" in public
    assert "gaps" in public
    assert "regional_breakdown" in public

    # Check sensitive fields are omitted
    assert "content_fingerprint" not in str(public)
    assert "record_ids" not in str(public)


def test_multiple_nationwide_sources_aggregate_regional_coverage():
    """Multiple nationwide sources combine for regional coverage."""
    source_a_entry = _entry(source_name="source_a")
    source_b_entry = _entry(source_name="source_b")

    source_a_receipt = _receipt(
        source_name="source_a",
        covered_regions=("seoul", "gyeonggi", "busan", "daegu"),
        record_ids=tuple(f"source_a:{i}" for i in range(40)),
    )

    source_b_receipt = _receipt(
        source_name="source_b",
        covered_regions=("busan", "daegu", "gwangju", "incheon"),
        record_ids=tuple(f"source_b:{i}" for i in range(40)),
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[source_a_entry, source_b_entry],
        receipts=[source_a_receipt, source_b_receipt],
        generated_at=GENERATED_AT,
    )

    # Check that both sources contribute to regional coverage
    busan_breakdown = next(rb for rb in report.regional_breakdown if rb.region_code == "busan")
    assert busan_breakdown.has_coverage is True
    assert "source_a" in busan_breakdown.sources_covered
    assert "source_b" in busan_breakdown.sources_covered

    # Check that only source_a covers seoul
    seoul_breakdown = next(rb for rb in report.regional_breakdown if rb.region_code == "seoul")
    assert seoul_breakdown.has_coverage is True
    assert "source_a" in seoul_breakdown.sources_covered
    assert "source_b" not in seoul_breakdown.sources_covered


def test_total_source_scoped_record_count_aggregates_all_sources():
    """Total source-scoped record count sums across all usable sources."""
    source_a_receipt = _receipt(
        source_name="source_a", record_ids=tuple(f"a:{i}" for i in range(20))
    )
    source_b_receipt = _receipt(
        source_name="source_b", record_ids=tuple(f"b:{i}" for i in range(30))
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry(source_name="source_a"), _entry(source_name="source_b")],
        receipts=[source_a_receipt, source_b_receipt],
        generated_at=GENERATED_AT,
    )

    assert report.total_source_scoped_record_count == 50


def test_validation_respects_max_stale_threshold():
    """Validation allows configurable threshold for stale sources."""
    # Create 2 stale receipts and 1 usable receipt
    stale_receipt_1 = _receipt(
        source_name="source_a", observed_at=datetime(2026, 8, 1, 0, 0, tzinfo=UTC)
    )
    stale_receipt_2 = _receipt(
        source_name="source_b", observed_at=datetime(2026, 8, 1, 0, 0, tzinfo=UTC)
    )
    usable_receipt = _receipt(source_name="source_c", observed_at=GENERATED_AT)

    report = reconciliation.build_reconciliation_report(
        source_inventory=[
            _entry(source_name="source_a"),
            _entry(source_name="source_b"),
            _entry(source_name="source_c"),
        ],
        receipts=[stale_receipt_1, stale_receipt_2, usable_receipt],
        generated_at=GENERATED_AT,
    )

    # Should fail with threshold of 0
    validation_strict = reconciliation.validate_full_ingest_dry_run(
        reconciliation_report=report,
        max_stale_sources=0,
        validation_timestamp=GENERATED_AT,
    )
    assert not validation_strict.is_approved

    # Should pass with threshold of 2
    validation_lenient = reconciliation.validate_full_ingest_dry_run(
        reconciliation_report=report,
        max_stale_sources=2,
        validation_timestamp=GENERATED_AT,
        require_nationwide_coverage=False,  # Don't require nationwide for this test
        require_all_sources_usable=False,  # Allow stale sources within threshold
    )
    assert validation_lenient.is_approved


def test_warnings_for_non_critical_issues():
    """Validation produces warnings for non-blocking issues."""
    # Create one unknown source
    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry(source_name="unknown")],
        receipts=[],
        generated_at=GENERATED_AT,
    )

    validation = reconciliation.validate_full_ingest_dry_run(
        reconciliation_report=report,
        require_nationwide_coverage=False,
        validation_timestamp=GENERATED_AT,
    )

    # Should pass but have warnings
    assert validation.is_approved
    assert len(validation.warnings) > 0
    assert any("unknown" in w.lower() for w in validation.warnings)


def test_regional_counts_remain_none_with_only_global_record_ids():
    """Regional record counts must be None when only global record IDs are available."""
    receipt_with_global_ids = _receipt(
        source_name="source_a",
        covered_regions=("seoul", "gyeonggi", "busan"),
        record_ids=tuple(f"global_record:{i}" for i in range(100)),
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry(source_name="source_a")],
        receipts=[receipt_with_global_ids],
        generated_at=GENERATED_AT,
    )

    # Check that all regional breakdowns have None for record_count
    for regional_breakdown in report.regional_breakdown:
        assert regional_breakdown.record_count is None, (
            f"Region {regional_breakdown.region_code} should have None record_count"
        )


def test_regional_counts_preserve_empty_rows():
    """Empty/unknown regional rows are preserved without claiming coverage."""
    partial_coverage_receipt = _receipt(
        source_name="source_a",
        covered_regions=("seoul", "gyeonggi"),  # Only covers 2 regions
        record_ids=tuple(f"record:{i}" for i in range(50)),
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry(source_name="source_a")],
        receipts=[partial_coverage_receipt],
        generated_at=GENERATED_AT,
    )

    # Check that seoul and gyeonggi have coverage
    seoul_breakdown = next(rb for rb in report.regional_breakdown if rb.region_code == "seoul")
    assert seoul_breakdown.has_coverage is True
    assert seoul_breakdown.record_count is None  # No per-region evidence

    gyeonggi_breakdown = next(
        rb for rb in report.regional_breakdown if rb.region_code == "gyeonggi"
    )
    assert gyeonggi_breakdown.has_coverage is True
    assert gyeonggi_breakdown.record_count is None  # No per-region evidence

    # Check that busan has no coverage
    busan_breakdown = next(rb for rb in report.regional_breakdown if rb.region_code == "busan")
    assert busan_breakdown.has_coverage is False
    assert busan_breakdown.record_count is None  # No per-region evidence


def test_rejected_sources_create_specific_gaps():
    """Rejected sources create rejected_source gaps and are counted separately."""
    rejected_entry = _entry(
        source_name="rejected_source",
        governance=SourceGovernance(
            license_class="public_processed",
            terms_version="terms-v1",
            retention_policy="aggregate-receipt-only",
            provenance_policy="source-record-hash",
            image_rights_status="verified",
            source_status="rejected",  # Explicitly rejected
        ),
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[rejected_entry],
        receipts=[],
        generated_at=GENERATED_AT,
    )

    assert report.rejected_sources == 1
    assert any(g.gap_type == "rejected_source" for g in report.gaps)
    assert report.usable_sources == 0
    assert report.blocked_sources == 0
    assert report.stale_sources == 0


def test_reconcile_specific_source_rejected_state():
    """Specific source reconciliation returns rejected_source gap for rejected sources."""
    rejected_entry = _entry(
        source_name="rejected_source",
        governance=SourceGovernance(
            license_class="public_processed",
            terms_version="terms-v1",
            retention_policy="aggregate-receipt-only",
            provenance_policy="source-record-hash",
            image_rights_status="verified",
            source_status="rejected",
        ),
    )

    gap = reconciliation.reconcile_receipt_coverage(
        source_name="rejected_source",
        dataset_name="Official Places",
        source_inventory=[rejected_entry],
        receipts=[],
    )

    assert gap is not None
    assert gap.gap_type == "rejected_source"
    assert "rejected" in gap.description.lower()


def test_quality_metrics_missing_denominator_returns_unknown():
    """Quality metrics without denominators return None/unknown, never inferred percentages."""
    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    # Metric with only numerator (no denominator)
    partial_metric = CoverageQualityMetrics(
        source_name="test_source",
        dataset_name="Test Dataset",
        valid_coordinate_count=80,
        # total_coordinate_count=None - denominator missing
    )

    computed = partial_metric.compute_rates()

    assert computed.valid_coordinate_rate is None  # Should not infer 100%

    public = computed.to_public_dict()
    assert public["coordinate_quality"]["valid_rate"] is None


def test_quality_metrics_valid_denominator_computes_rate():
    """Quality metrics with valid denominators compute rates correctly."""
    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    valid_metric = CoverageQualityMetrics(
        source_name="test_source",
        dataset_name="Test Dataset",
        valid_coordinate_count=80,
        total_coordinate_count=100,
        image_rights_ready_count=90,
        total_image_count=100,
    )

    computed = valid_metric.compute_rates()

    assert computed.valid_coordinate_rate == 0.8
    assert computed.image_rights_ready_rate == 0.9


def test_quality_metrics_rejects_negative_counts():
    """Quality metrics reject negative count values."""
    import pytest

    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    with pytest.raises(ValueError, match="Invalid quality metrics"):
        CoverageQualityMetrics(
            source_name="test_source",
            dataset_name="Test Dataset",
            valid_coordinate_count=-1,  # Invalid negative count
            total_coordinate_count=100,
        )


def test_quality_metrics_rejects_impossible_numerator():
    """Quality metrics reject numerators that exceed denominators."""
    import pytest

    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    with pytest.raises(ValueError, match="Invalid quality metrics"):
        CoverageQualityMetrics(
            source_name="test_source",
            dataset_name="Test Dataset",
            valid_coordinate_count=150,  # More than total
            total_coordinate_count=100,
        )


def test_quality_metrics_included_in_report():
    """Quality metrics are included in reconciliation report and public projection."""
    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    quality_metrics = [
        CoverageQualityMetrics(
            source_name="source_a",
            dataset_name="Official Places",  # Must match inventory dataset_name
            valid_coordinate_count=95,
            total_coordinate_count=100,
        )
    ]

    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry(source_name="source_a")],
        receipts=[_receipt(source_name="source_a")],
        generated_at=GENERATED_AT,
        quality_metrics=quality_metrics,
    )

    assert len(report.quality_metrics) == 1
    assert report.quality_metrics[0].source_name == "source_a"

    public = report.to_public_dict()
    assert "quality_metrics" in public
    assert len(public["quality_metrics"]) == 1
    assert public["quality_metrics"][0]["coordinate_quality"]["valid_rate"] == 0.95


def test_quality_metrics_invalid_rejected_during_instantiation():
    """Invalid quality metrics are rejected during instantiation with clear error."""
    import pytest

    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    with pytest.raises(ValueError, match="Invalid quality metrics"):
        CoverageQualityMetrics(
            source_name="source_a",
            dataset_name="Dataset A",
            valid_coordinate_count=150,  # Invalid: exceeds total
            total_coordinate_count=100,
        )


def test_quality_metrics_scope_mismatch_creates_gap():
    """Valid metrics but source not in inventory create scope_mismatch gap."""
    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    orphan_metrics = [
        CoverageQualityMetrics(
            source_name="unknown_source",  # Not in inventory
            dataset_name="Orphan Dataset",
            valid_coordinate_count=80,
            total_coordinate_count=100,
        )
    ]

    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry(source_name="source_a")],
        receipts=[_receipt(source_name="source_a")],
        generated_at=GENERATED_AT,
        quality_metrics=orphan_metrics,
    )

    # Should have a gap for orphaned metrics
    assert any(
        g.gap_type == "scope_mismatch"
        and g.source_name == "unknown_source"
        and g.dataset_name == "Orphan Dataset"
        for g in report.gaps
    )

    # Quality metrics tuple should be empty (orphans rejected)
    assert len(report.quality_metrics) == 0


def test_all_five_state_distinctions_preserved():
    """All five state distinctions are preserved: usable, blocked_external, rejected, stale, unknown."""
    from apps.api.app.services.official_source_inventory import SourceGovernance

    usable_entry = _entry(
        source_name="usable_source",
        governance=SourceGovernance(
            license_class="public_processed",
            terms_version="terms-v1",
            retention_policy="aggregate-receipt-only",
            provenance_policy="source-record-hash",
            image_rights_status="verified",
            source_status="approved",
        ),
    )

    blocked_entry = _entry(
        source_name="blocked_source",
        governance=SourceGovernance(
            license_class=None,
            terms_version=None,
            retention_policy=None,
            provenance_policy=None,
            image_rights_status="unknown",
            source_status="blocked_external",
        ),
    )

    rejected_entry = _entry(
        source_name="rejected_source",
        governance=SourceGovernance(
            license_class="public_processed",
            terms_version="terms-v1",
            retention_policy="aggregate-receipt-only",
            provenance_policy="source-record-hash",
            image_rights_status="verified",
            source_status="rejected",
        ),
    )

    # Fresh receipt for usable source
    fresh_receipt = _receipt(
        source_name="usable_source",
        observed_at=GENERATED_AT,
    )

    # Stale receipt for rejected source (to make it stale instead of rejected)
    stale_receipt = _receipt(
        source_name="stale_source",
        observed_at=datetime(2026, 8, 1, 0, 0, tzinfo=UTC),  # 4 days old
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[
            usable_entry,
            blocked_entry,
            rejected_entry,
            _entry(source_name="stale_source"),
        ],
        receipts=[fresh_receipt, stale_receipt],
        generated_at=GENERATED_AT,
    )

    # Verify all five state counts are preserved
    assert report.total_sources == 4
    assert report.usable_sources == 1  # usable_source
    assert report.blocked_sources == 1  # blocked_source
    assert report.rejected_sources == 1  # rejected_source
    assert report.stale_sources == 1  # stale_source
    assert report.unknown_sources == 0  # All have receipts or governance status


def test_quality_metrics_rejects_unknown_category_key():
    """Quality metrics reject unknown category keys not in canonical set."""
    import pytest

    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    with pytest.raises(ValueError, match="Invalid quality metrics"):
        CoverageQualityMetrics(
            source_name="test_source",
            dataset_name="Test Dataset",
            category_counts={"unknown_category": 10},  # Not in canonical set
            total_category_count=10,
        )


def test_quality_metrics_rejects_negative_category_count():
    """Quality metrics reject negative category counts."""
    import pytest

    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    with pytest.raises(ValueError, match="Invalid quality metrics"):
        CoverageQualityMetrics(
            source_name="test_source",
            dataset_name="Test Dataset",
            category_counts={"attraction": -5},  # Negative count
            total_category_count=10,
        )


def test_quality_metrics_valid_category_keys_accepted():
    """Quality metrics accept valid category keys from canonical set."""
    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    # Use multiple valid categories
    valid_metric = CoverageQualityMetrics(
        source_name="test_source",
        dataset_name="Test Dataset",
        category_counts={
            "attraction": 10,
            "restaurant": 20,
            "lodging": 15,
        },
        total_category_count=45,
    )

    computed = valid_metric.compute_rates()
    assert computed.category_counts == {
        "attraction": 10,
        "restaurant": 20,
        "lodging": 15,
    }
    assert computed.total_category_count == 45


def test_quality_metrics_exception_hides_secret_category_key():
    """Exception messages never include unknown/secret-shaped category keys."""
    import pytest

    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    # Test with a secret-shaped unknown category key
    secret_key = "secret_api_key_abc123"  # pragma: allowlist secret

    with pytest.raises(ValueError) as exc_info:
        CoverageQualityMetrics(
            source_name="test_source",
            dataset_name="Test Dataset",
            category_counts={secret_key: 10},  # Secret-shaped unknown key
            total_category_count=10,
        )

    # Verify the secret key never appears in the exception string
    exception_str = str(exc_info.value)
    assert secret_key not in exception_str, "Secret category key must not appear in exception"
    assert exception_str == "Invalid quality metrics"


def test_quality_metrics_rates_with_valid_denominator():
    """Quality metrics compute all rates when total_quality_checked has valid denominator."""
    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    valid_metric = CoverageQualityMetrics(
        source_name="test_source",
        dataset_name="Test Dataset",
        duplicate_count=10,
        quarantined_count=5,
        failed_validation_count=3,
        total_quality_checked=100,  # Valid denominator > 0
    )

    computed = valid_metric.compute_rates()

    # All rates should be computed
    assert computed.duplicate_rate == 0.1  # 10/100
    assert computed.quarantined_rate == 0.05  # 5/100
    assert computed.failed_validation_rate == 0.03  # 3/100

    # Check public projection includes rates
    public = computed.to_public_dict()
    assert public["data_quality"]["duplicate_rate"] == 0.1
    assert public["data_quality"]["quarantined_rate"] == 0.05
    assert public["data_quality"]["failed_validation_rate"] == 0.03


def test_quality_metrics_rates_with_zero_denominator():
    """Quality metrics return None rates when total_quality_checked is zero."""
    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    zero_denom_metric = CoverageQualityMetrics(
        source_name="test_source",
        dataset_name="Test Dataset",
        duplicate_count=0,
        quarantined_count=0,
        failed_validation_count=0,
        total_quality_checked=0,  # Zero denominator
    )

    computed = zero_denom_metric.compute_rates()

    # All rates should be None (avoid division by zero)
    assert computed.duplicate_rate is None
    assert computed.quarantined_rate is None
    assert computed.failed_validation_rate is None


def test_quality_metrics_rates_with_missing_denominator():
    """Quality metrics return None rates when total_quality_checked is missing."""
    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    missing_denom_metric = CoverageQualityMetrics(
        source_name="test_source",
        dataset_name="Test Dataset",
        duplicate_count=10,
        quarantined_count=5,
        failed_validation_count=3,
        # total_quality_checked=None - denominator missing
    )

    computed = missing_denom_metric.compute_rates()

    # All rates should be None when denominator is missing
    assert computed.duplicate_rate is None
    assert computed.quarantined_rate is None
    assert computed.failed_validation_rate is None


def test_quality_metrics_partial_quality_issue_rates():
    """Quality metrics compute rates for only the issue types that have counts."""
    from apps.api.app.services.official_coverage_reconciliation import CoverageQualityMetrics

    partial_metric = CoverageQualityMetrics(
        source_name="test_source",
        dataset_name="Test Dataset",
        duplicate_count=10,
        quarantined_count=None,  # Missing
        failed_validation_count=5,
        total_quality_checked=100,
    )

    computed = partial_metric.compute_rates()

    # Only rates for present counts should be computed
    assert computed.duplicate_rate == 0.1  # 10/100
    assert computed.quarantined_rate is None  # No count provided
    assert computed.failed_validation_rate == 0.05  # 5/100

    # Check public projection
    public = computed.to_public_dict()
    assert public["data_quality"]["duplicate_rate"] == 0.1
    assert public["data_quality"]["quarantined_rate"] is None
    assert public["data_quality"]["failed_validation_rate"] == 0.05


def test_custom_region_list_rejects_nationwide_coverage():
    """Custom reduced region list cannot approve nationwide coverage."""
    # Try to pass a reduced region list (only 2 regions)
    reduced_regions = ("seoul", "busan")

    # Create a receipt that covers the reduced regions
    partial_receipt = _receipt(
        covered_regions=reduced_regions, record_ids=tuple(f"record:{i}" for i in range(50))
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry()],
        receipts=[partial_receipt],
        expected_regions=reduced_regions,  # Non-canonical set
        generated_at=GENERATED_AT,
    )

    # Should have scope_mismatch gap for non-canonical regions
    assert any(
        g.gap_type == "scope_mismatch"
        and g.source_name == "region_validation"
        and g.dataset_name == "expected_regions"
        for g in report.gaps
    )

    # Nationwide coverage must be incomplete for non-canonical sets
    assert not report.nationwide_coverage_complete

    # Regional breakdown should still be canonical (17 regions)
    assert len(report.regional_breakdown) == 17

    # Validation should fail for nationwide requirements
    validation = reconciliation.validate_full_ingest_dry_run(
        reconciliation_report=report,
        require_nationwide_coverage=True,
        validation_timestamp=GENERATED_AT,
    )

    assert not validation.is_approved
    assert any("Nationwide coverage incomplete" in b for b in validation.blockers)


def test_custom_region_list_incomplete_cannot_approve():
    """Even with all reduced regions covered, cannot approve true nationwide."""
    # Try with 3 regions instead of canonical 17
    custom_regions = ("seoul", "busan", "daegu")

    # Create receipt that covers all custom regions
    full_custom_receipt = _receipt(
        covered_regions=custom_regions, record_ids=tuple(f"record:{i}" for i in range(100))
    )

    report = reconciliation.build_reconciliation_report(
        source_inventory=[_entry()],
        receipts=[full_custom_receipt],
        expected_regions=custom_regions,
        generated_at=GENERATED_AT,
    )

    # Should still have scope_mismatch for non-canonical regions
    assert any(
        g.gap_type == "scope_mismatch" and g.source_name == "region_validation" for g in report.gaps
    ), "Non-canonical region list must create scope_mismatch gap"

    # Nationwide coverage must be False even though all custom regions are covered
    assert not report.nationwide_coverage_complete, (
        "Non-canonical region sets cannot approve nationwide coverage"
    )

    # Regional breakdown preserves all 17 canonical regions
    assert len(report.regional_breakdown) == 17
    seoul_breakdown = next(rb for rb in report.regional_breakdown if rb.region_code == "seoul")
    assert seoul_breakdown.has_coverage is True

    # Other canonical regions should show no coverage
    gangwon_breakdown = next(rb for rb in report.regional_breakdown if rb.region_code == "gangwon")
    assert gangwon_breakdown.has_coverage is False
