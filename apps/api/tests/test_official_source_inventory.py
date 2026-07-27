from __future__ import annotations

from dataclasses import replace
from datetime import UTC, datetime

import pytest

from apps.api.app.services import official_source_inventory as inventory

GENERATED_AT = datetime(2026, 7, 28, 0, 0, tzinfo=UTC)


def _entry(**overrides):
    entry = inventory.OfficialSourceInventory(
        source_name=" Tour API ",
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
        governance=inventory.SourceGovernance(
            license_class="public_processed",
            terms_version="terms-v1",
            retention_policy="aggregate-receipt-only",
            provenance_policy="source-record-hash",
            image_rights_status="verified",
            source_status="approved",
        ),
        refresh=inventory.SourceRefreshPolicy(cadence_hours=24, freshness_sla_hours=48),
        pagination=inventory.SourcePaginationPolicy(
            semantics="page_cursor", cursor_field="next_cursor"
        ),
        identity=inventory.SourceRecordIdentityPolicy(
            stable_fields=("external_id", "region_code", "category"),
            dedupe_fields=("external_id", "region_code"),
        ),
        place_policy=inventory.PlaceAcceptancePolicy(
            coverage_scope="nationwide",
            covered_regions=("seoul", "gyeonggi"),
            accepted_categories=("attraction", "culture_venue"),
            max_coordinate_precision="place_point",
            accepted_languages=("ko", "en"),
            image_url_policy=inventory.ImageUrlPolicy(),
        ),
    )
    return replace(entry, **overrides)


def _receipt(
    *,
    fingerprint: str = "a" * 64,
    observed_at: datetime = datetime(2026, 7, 27, 0, 0, tzinfo=UTC),
    record_ids: tuple[str, ...] | None = ("record:one", "record:two"),
    coverage_scope: inventory.CoverageScope = "nationwide",
    coordinate_precision: inventory.CoordinatePrecision = "place_point",
    image_rights_status: inventory.ImageRightsStatus = "verified",
):
    return inventory.OfficialCoverageReceipt(
        receipt_id=f"receipt:{fingerprint[:8]}",
        source_name="tour_api",
        dataset_name="Official Places",
        content_fingerprint=fingerprint,
        observed_at=observed_at,
        record_ids=record_ids,
        coverage_scope=coverage_scope,
        covered_regions=("gyeonggi", "seoul"),
        coordinate_precision=coordinate_precision,
        localized_languages=("en", "ko"),
        image_rights_status=image_rights_status,
    )


def test_inventory_normalization_and_record_identity_are_deterministic():
    normalized = inventory.normalize_source_inventory([_entry()])
    assert normalized[0].source_name == "tour_api"
    assert normalized[0].allowed_public_projection == tuple(
        sorted(normalized[0].allowed_public_projection)
    )

    policy = normalized[0].identity
    first = inventory.stable_source_record_identity(
        source_name="tour_api",
        dataset_name="Official Places",
        policy=policy,
        record={"external_id": " 42 ", "region_code": "SEOUL", "category": "attraction"},
    )
    second = inventory.stable_source_record_identity(
        source_name=" TOUR_API ",
        dataset_name="Official Places",
        policy=policy,
        record={"category": "attraction", "region_code": "SEOUL", "external_id": "42"},
    )
    assert first == second
    assert first.startswith("record:")


def test_duplicate_source_identity_is_rejected():
    with pytest.raises(inventory.OfficialSourceInventoryError, match="Duplicate official source"):
        inventory.normalize_source_inventory([_entry(), _entry()])


def test_missing_governance_fails_closed_without_count_or_coverage():
    blocked = replace(
        _entry(),
        governance=replace(_entry().governance, terms_version=None),
    )

    report = inventory.build_official_coverage_report(
        inventory=[blocked], receipts=[_receipt()], generated_at=GENERATED_AT
    )
    summary = report.sources[0]

    assert summary.readiness == "blocked_external"
    assert summary.coverage_scope == "unknown"
    assert summary.distinct_record_count is None
    assert summary.accepted_receipt_count == 0
    assert "missing source governance" in " ".join(summary.reasons)


def test_no_accepted_receipt_is_unknown_not_healthy():
    report = inventory.build_official_coverage_report(
        inventory=[_entry()], receipts=[], generated_at=GENERATED_AT
    )
    summary = report.sources[0]

    assert summary.readiness == "unknown"
    assert summary.coverage_scope == "unknown"
    assert summary.distinct_record_count is None
    assert summary.latest_receipt_at is None
    assert summary.accepted_receipt_count == 0


def test_duplicate_receipts_and_record_ids_do_not_inflate_coverage():
    first = _receipt(record_ids=("record:one", "record:two", "record:two"))
    duplicate = replace(first, receipt_id="receipt:duplicate")

    report = inventory.build_official_coverage_report(
        inventory=[_entry()], receipts=[first, duplicate], generated_at=GENERATED_AT
    )
    summary = report.sources[0]

    assert summary.readiness == "usable"
    assert summary.accepted_receipt_count == 1
    assert summary.duplicate_receipt_count == 1
    assert summary.distinct_record_count == 2


def test_stale_receipt_remains_stale():
    stale_receipt = _receipt(observed_at=datetime(2026, 7, 24, 0, 0, tzinfo=UTC))

    report = inventory.build_official_coverage_report(
        inventory=[_entry()], receipts=[stale_receipt], generated_at=GENERATED_AT
    )

    assert report.sources[0].readiness == "stale"
    assert "freshness SLA" in " ".join(report.sources[0].reasons)


@pytest.mark.parametrize(
    ("source_status", "expected"),
    [("blocked_external", "blocked_external"), ("rejected", "rejected")],
)
def test_explicit_governance_state_is_preserved(source_status, expected):
    source = replace(
        _entry(),
        governance=replace(_entry().governance, source_status=source_status),
    )

    report = inventory.build_official_coverage_report(
        inventory=[source], receipts=[_receipt()], generated_at=GENERATED_AT
    )

    assert report.sources[0].readiness == expected
    assert report.sources[0].distinct_record_count is None


def test_unsafe_image_url_and_personal_precision_are_rejected():
    with pytest.raises(inventory.OfficialSourceInventoryError, match="accepted public scheme"):
        inventory.validate_image_url(
            "http://images.example.invalid/place.jpg", inventory.ImageUrlPolicy()
        )

    unsafe_entry = replace(
        _entry(),
        place_policy=replace(_entry().place_policy, max_coordinate_precision="personal_precise"),
    )
    with pytest.raises(inventory.OfficialSourceInventoryError, match="Personal-precise"):
        inventory.normalize_source_inventory([unsafe_entry])

    report = inventory.build_official_coverage_report(
        inventory=[_entry()],
        receipts=[_receipt(coordinate_precision="personal_precise")],
        generated_at=GENERATED_AT,
    )
    assert report.sources[0].rejected_receipt_count == 1
    assert report.sources[0].accepted_receipt_count == 0
    assert report.sources[0].distinct_record_count is None


def test_raw_review_projection_and_identity_fields_are_rejected():
    with pytest.raises(inventory.OfficialSourceInventoryError, match="Raw review"):
        inventory.normalize_source_inventory(
            [_entry(allowed_public_projection=("place_id", "review_body"))]
        )

    with pytest.raises(inventory.OfficialSourceInventoryError, match="Raw review or identity"):
        inventory.stable_source_record_identity(
            source_name="tour_api",
            dataset_name="Official Places",
            policy=inventory.SourceRecordIdentityPolicy(
                stable_fields=("review_body",), dedupe_fields=("review_body",)
            ),
            record={"review_body": "synthetic raw text must not be accepted"},
        )


def test_unknown_receipt_cannot_create_a_source_or_fake_coverage():
    unknown_receipt = replace(_receipt(), source_name="unregistered_source")

    report = inventory.build_official_coverage_report(
        inventory=[_entry()], receipts=[unknown_receipt], generated_at=GENERATED_AT
    )
    summary = report.sources[0]

    assert len(report.sources) == 1
    assert report.ignored_receipt_count == 1
    assert summary.readiness == "unknown"
    assert summary.distinct_record_count is None


def test_public_report_contains_metadata_only():
    report = inventory.build_official_coverage_report(
        inventory=[_entry()], receipts=[_receipt()], generated_at=GENERATED_AT
    )
    payload = report.to_public_dict()
    serialized = repr(payload).lower()

    assert "review_body" not in serialized
    assert "synthetic raw text" not in serialized
    assert "content_fingerprint" not in payload["sources"][0]
    assert "record_ids" not in payload["sources"][0]
