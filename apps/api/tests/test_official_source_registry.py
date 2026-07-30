from __future__ import annotations

import dataclasses
import json
from datetime import UTC, datetime

import pytest

from apps.api.app.services import (
    card_spending_ingest,
    culture_info_ingest,
    franchise_reference_ingest,
    kopis_ingest,
    tour_api_ingest,
)
from apps.api.app.services import (
    official_source_adapters as adapters,
)
from apps.api.app.services import (
    official_source_registry as registry,
)

REGISTERED_SOURCES = ("tour_api", "kcisa", "kopis", "fair_trade_commission", "data_portal")


def _entry(source_name: str) -> registry.SourceRegistryEntry:
    entry = registry.get_registered_source(source_name)
    assert entry is not None, f"{source_name} should be registered"
    return entry


def test_registry_contains_exactly_the_five_official_sources():
    entries = registry.get_official_source_registry()
    assert tuple(sorted(entry.source_name for entry in entries)) == tuple(
        sorted(REGISTERED_SOURCES)
    )
    assert registry.get_registered_source_names() == frozenset(REGISTERED_SOURCES)
    assert len(entries) == 5


@pytest.mark.parametrize("source_name", REGISTERED_SOURCES)
def test_each_entry_carries_governance_refresh_pagination_identity_and_image_policy(source_name):
    entry = _entry(source_name)
    assert entry.governance.source_status == "blocked_external"
    assert entry.governance.image_rights_status == "unknown"
    # Honest: nothing externally confirmed, so no invented license/terms values.
    assert entry.governance.license_class is None
    assert entry.governance.terms_version is None
    assert entry.governance.retention_policy is None
    assert entry.governance.provenance_policy is None

    assert entry.refresh.cadence_hours > 0
    assert entry.refresh.freshness_sla_hours > 0
    assert entry.identity.stable_fields
    assert set(entry.identity.dedupe_fields).issubset(entry.identity.stable_fields)
    assert entry.image_url_policy.accepted_schemes == ("https",)
    assert entry.place_policy.max_coordinate_precision != "personal_precise"
    assert entry.allowed_public_projection


@pytest.mark.parametrize("source_name", REGISTERED_SOURCES)
def test_every_source_is_honestly_blocked_for_live_collection(source_name):
    assert _entry(source_name).live_ingest_status == "blocked_external"
    assert registry.is_live_ingest_permitted(source_name) is False
    decision, reasons = registry.evaluate_live_ingest_gate(source_name)
    assert decision == "blocked_external"
    assert reasons
    with pytest.raises(registry.OfficialSourceRegistryError, match="Live ingest is not permitted"):
        registry.assert_live_ingest_permitted(source_name)


def test_registry_has_no_falsely_approved_live_source():
    for entry in registry.get_official_source_registry():
        assert entry.live_ingest_status != "approved"
        assert entry.governance.source_status != "approved"
        assert entry.governance.image_rights_status != "verified"


def test_unknown_source_is_rejected_and_not_live_usable():
    assert registry.get_registered_source("not_a_registered_source") is None
    assert registry.is_source_registered("not_a_registered_source") is False
    assert registry.is_live_ingest_permitted("not_a_registered_source") is False
    decision, reasons = registry.evaluate_live_ingest_gate("not_a_registered_source")
    assert decision == "unknown_source"
    assert reasons
    with pytest.raises(registry.OfficialSourceRegistryError, match="not registered"):
        registry.assert_source_registered("not_a_registered_source")
    with pytest.raises(registry.OfficialSourceRegistryError, match="not registered"):
        registry.assert_live_ingest_permitted("not_a_registered_source")


def test_offline_normalization_is_approved_only_for_registered_sources():
    for source_name in REGISTERED_SOURCES:
        assert registry.is_offline_normalization_permitted(source_name) is True
        assert (
            registry.assert_offline_normalization_permitted(source_name).source_name == source_name
        )
    assert registry.is_offline_normalization_permitted("ghost_source") is False
    with pytest.raises(registry.OfficialSourceRegistryError, match="unregistered source"):
        registry.assert_offline_normalization_permitted("ghost_source")


def test_registry_dataset_names_match_each_parser_ssot_constant():
    expected = {
        "tour_api": tour_api_ingest.DEFAULT_DATASET_NAME,
        "kcisa": culture_info_ingest.DEFAULT_DATASET_NAME,
        "kopis": kopis_ingest.DEFAULT_DATASET_NAME,
        "fair_trade_commission": franchise_reference_ingest.DEFAULT_DATASET_NAME,
        "data_portal": card_spending_ingest.DETAIL_DATASET_NAME,
    }
    for source_name, dataset_name in expected.items():
        assert _entry(source_name).dataset_name == dataset_name


def test_registry_lookup_is_case_and_whitespace_insensitive():
    entry = registry.get_registered_source("  Tour_API ")
    assert entry is not None
    assert entry.source_name == "tour_api"


def test_public_projection_contains_no_secrets_reviews_or_provenance_payload():
    payload = _entry("tour_api").to_public_dict()
    serialized = json.dumps(payload, ensure_ascii=False).lower()
    for forbidden in ("review", "author", "token", "secret", "apikey", "embedding", "password"):
        assert forbidden not in serialized
    assert "license_class" in payload["governance"]
    assert payload["governance"]["license_class"] is None
    assert payload["live_ingest_status"] == "blocked_external"
    assert payload["offline_normalization_status"] == "approved"


def test_normalize_entries_wraps_raw_inventory_with_blocked_live_gate():
    raw = registry.SourceRegistryEntry(
        inventory=_entry("tour_api").inventory,
        offline_normalization_status="approved",
        live_ingest_status="blocked_external",
        live_blocker_reasons=("test reason",),
    )
    normalized = registry.normalize_entries([raw])
    assert normalized[0].live_ingest_status == "blocked_external"
    with pytest.raises(registry.OfficialSourceInventoryError, match="Duplicate"):
        registry.normalize_entries([raw, raw])


OBSERVED_AT = datetime(2026, 7, 28, 0, 0, tzinfo=UTC)


def _metadata():
    return adapters.SourceFixtureMetadata(
        observed_at=OBSERVED_AT,
        source_updated_at=datetime(2026, 7, 27, 0, 0, tzinfo=UTC),
        coverage_scope="nationwide",
        covered_regions=("gyeonggi", "seoul"),
        localized_languages=("ko",),
        image_rights_status="verified",
        source_year=2025,
    )


def _tour_item():
    return {
        "contentid": "tour-42",
        "contenttypeid": "12",
        "title": "Synthetic Place",
        "addr1": "경기도 수원시 팔달구",
        "areacode": "31",
        "sigungucode": "13",
        "mapx": "127.025",
        "mapy": "37.263",
        "firstimage": "https://tong.visitkorea.or.kr/cms/resource/synthetic.jpg",
    }


def test_tour_api_dataset_name_is_ssot_across_adapter_parser_and_registry():
    # The adapter output, the parser dataclass default, and the registry entry
    # all reference the same DEFAULT_DATASET_NAME constant (no literal drift).
    result = adapters.normalize_official_source_fixture(
        source_name="tour_api", payload=_tour_item(), metadata=_metadata()
    )
    assert result.dataset_name == tour_api_ingest.DEFAULT_DATASET_NAME
    assert _entry("tour_api").dataset_name == tour_api_ingest.DEFAULT_DATASET_NAME

    fields = {field.name: field for field in dataclasses.fields(tour_api_ingest.TourApiFetchResult)}
    assert fields["dataset_name"].default == tour_api_ingest.DEFAULT_DATASET_NAME
    # The adapter definition also imports the constant rather than a literal.
    assert adapters._SOURCE_DEFINITIONS["tour_api"][1] is tour_api_ingest.DEFAULT_DATASET_NAME
