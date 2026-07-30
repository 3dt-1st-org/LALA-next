"""Offline adapters from existing official-source parsers to safe public records.

The adapters accept only supplied fixture-shaped payloads.  They deliberately
do not import requests, read environment variables, open files, or call the
existing fetch/upsert functions.
"""

from __future__ import annotations

import math
import re
from collections import defaultdict
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any, Final, Literal
from urllib.parse import urlparse
from xml.etree import ElementTree

from apps.api.app.services import (
    card_spending_ingest,
    culture_info_ingest,
    franchise_reference_ingest,
    kopis_ingest,
    tour_api_ingest,
)
from apps.api.app.services.official_media import official_image_url_or_none
from apps.api.app.services.official_source_inventory import (
    CoordinatePrecision,
    CoverageScope,
    ImageRightsStatus,
    ImageUrlPolicy,
    SourceRecordIdentityPolicy,
    stable_source_record_identity,
    validate_image_url,
)

SourceAdapterKind = Literal[
    "tourism_place",
    "culture_event",
    "performance_event",
    "franchise_reference",
    "card_spending_aggregate",
]
NormalizationStatus = Literal["accepted", "incomplete", "rejected"]
NormalizationReason = Literal[
    "unknown_source",
    "invalid_metadata",
    "malformed_payload",
    "unsupported_payload_shape",
    "forbidden_field",
    "missing_stable_identity",
    "unsafe_coordinate_precision",
    "invalid_image_url",
    "image_rights_not_verified",
    "unsupported_localization",
    "invalid_freshness",
    "parser_rejected_record",
]
PublicScalar = str | int | float | None
PublicField = tuple[str, PublicScalar]

_SOURCE_DEFINITIONS: Final[dict[str, tuple[SourceAdapterKind, str]]] = {
    "tour_api": ("tourism_place", tour_api_ingest.DEFAULT_DATASET_NAME),
    "kcisa": ("culture_event", culture_info_ingest.DEFAULT_DATASET_NAME),
    "kopis": ("performance_event", kopis_ingest.DEFAULT_DATASET_NAME),
    "fair_trade_commission": (
        "franchise_reference",
        franchise_reference_ingest.DEFAULT_DATASET_NAME,
    ),
    "data_portal": ("card_spending_aggregate", card_spending_ingest.DETAIL_DATASET_NAME),
}
_FORBIDDEN_FIELD_TERMS: Final[tuple[str, ...]] = (
    "author",
    "email",
    "phone",
    "review",
    "raw",
    "token",
    "secret",
    "password",
    "bearer",
    "apikey",
    "embedding",
    "vector",
    "prompt",
    "completion",
    "citation",
    "private",
    "provider",
    "payload",
    "body",
)
_SECRET_SHAPED_VALUE: Final[re.Pattern[str]] = re.compile(
    r"(?:sk-[A-Za-z0-9_-]{8,}|Bearer\s+\S+|postgres(?:ql)?://)", re.IGNORECASE
)
_ALLOWED_FIELDS: Final[dict[SourceAdapterKind, frozenset[str]]] = {
    "tourism_place": frozenset(
        {
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
        }
    ),
    "culture_event": frozenset(
        {
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
        }
    ),
    "performance_event": frozenset(
        {
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
        }
    ),
    "franchise_reference": frozenset(
        {
            "brand_id",
            "brand_name_ko",
            "normalized_brand_name",
            "headquarters_name_ko",
            "category",
            "main_product",
            "franchise_store_count",
            "average_sales_amount",
            "chain_scale_score",
        }
    ),
    "card_spending_aggregate": frozenset(
        {
            "month",
            "region_name_ko",
            "industry_code",
            "industry_name_ko",
            "gender",
            "age_group",
            "spend_amount",
            "transaction_count",
            "visitor_type",
        }
    ),
}


class OfficialSourceAdapterError(ValueError):
    """Raised internally for a bounded, non-provider-specific rejection."""

    def __init__(self, reason: NormalizationReason):
        super().__init__(reason)
        self.reason = reason


@dataclass(frozen=True)
class SourceFixtureMetadata:
    observed_at: datetime
    source_updated_at: datetime | None = None
    coverage_scope: CoverageScope = "unknown"
    covered_regions: tuple[str, ...] = ()
    localized_languages: tuple[str, ...] = ("ko",)
    image_rights_status: ImageRightsStatus = "unknown"
    source_year: int | None = None
    visitor_type: str = "domestic"
    region_code_map: tuple[tuple[str, str], ...] = ()


@dataclass(frozen=True)
class NormalizedOfficialRecord:
    kind: SourceAdapterKind
    source_name: str
    dataset_name: str
    source_record_id: str
    dedupe_key: str
    language: str | None
    category: str | None
    region_name_ko: str | None
    coverage_scope: CoverageScope
    coordinate_precision: CoordinatePrecision
    image_rights_status: ImageRightsStatus
    observed_at: datetime
    source_updated_at: datetime | None
    public_fields: tuple[PublicField, ...]

    def to_public_dict(self) -> dict[str, Any]:
        """Return the approved projection, never the supplied provider shape."""
        return {
            "kind": self.kind,
            "source_name": self.source_name,
            "dataset_name": self.dataset_name,
            "source_record_id": self.source_record_id,
            "dedupe_key": self.dedupe_key,
            "language": self.language,
            "category": self.category,
            "region_name_ko": self.region_name_ko,
            "coverage_scope": self.coverage_scope,
            "coordinate_precision": self.coordinate_precision,
            "image_rights_status": self.image_rights_status,
            "observed_at": self.observed_at.isoformat(),
            "source_updated_at": self.source_updated_at.isoformat()
            if self.source_updated_at
            else None,
            "public_fields": dict(self.public_fields),
        }


@dataclass(frozen=True)
class SourceNormalizationResult:
    source_name: str
    dataset_name: str
    kind: SourceAdapterKind | None
    status: NormalizationStatus
    records: tuple[NormalizedOfficialRecord, ...]
    accepted_record_count: int | None
    rejected_record_count: int
    duplicate_record_count: int
    rejection_reasons: tuple[NormalizationReason, ...]
    observed_at: datetime | None
    source_updated_at: datetime | None
    coverage_scope: CoverageScope
    covered_regions: tuple[str, ...]
    localized_languages: tuple[str, ...]
    image_rights_status: ImageRightsStatus

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "source_name": self.source_name,
            "dataset_name": self.dataset_name,
            "kind": self.kind,
            "status": self.status,
            "accepted_record_count": self.accepted_record_count,
            "rejected_record_count": self.rejected_record_count,
            "duplicate_record_count": self.duplicate_record_count,
            "rejection_reasons": list(self.rejection_reasons),
            "observed_at": self.observed_at.isoformat() if self.observed_at else None,
            "source_updated_at": (
                self.source_updated_at.isoformat() if self.source_updated_at else None
            ),
            "coverage_scope": self.coverage_scope,
            "covered_regions": list(self.covered_regions),
            "localized_languages": list(self.localized_languages),
            "image_rights_status": self.image_rights_status,
            "records": [record.to_public_dict() for record in self.records],
        }


def normalize_official_source_fixture(
    *,
    source_name: str,
    payload: object,
    metadata: SourceFixtureMetadata,
) -> SourceNormalizationResult:
    """Normalize one synthetic source payload without acquiring or persisting it."""
    definition = _SOURCE_DEFINITIONS.get(source_name.strip().lower())
    if definition is None:
        return _rejected(source_name=source_name.strip(), reason="unknown_source")
    kind, dataset_name = definition
    try:
        normalized_metadata = _normalize_metadata(metadata)
        if normalized_metadata.source_year is None and kind == "franchise_reference":
            raise OfficialSourceAdapterError("invalid_metadata")
        _dispatch_metadata_check(metadata=normalized_metadata, dataset_name=dataset_name)
        if kind == "tourism_place":
            records, rejected = _normalize_tourism(
                payload, source_name, dataset_name, normalized_metadata
            )
        elif kind == "culture_event":
            records, rejected = _normalize_culture_events(
                payload, source_name, dataset_name, normalized_metadata
            )
        elif kind == "performance_event":
            records, rejected = _normalize_performance_events(
                payload, source_name, dataset_name, normalized_metadata
            )
        elif kind == "franchise_reference":
            records, rejected = _normalize_franchise(
                payload, source_name, dataset_name, normalized_metadata
            )
        else:
            records, rejected = _normalize_card_spending(
                payload, source_name, dataset_name, normalized_metadata
            )
        return _finalize(
            source_name=source_name.strip().lower(),
            dataset_name=dataset_name,
            kind=kind,
            metadata=normalized_metadata,
            records=records,
            rejected_record_count=rejected,
        )
    except OfficialSourceAdapterError as error:
        return _rejected(
            source_name=source_name.strip().lower(),
            dataset_name=dataset_name,
            kind=kind,
            metadata=metadata,
            reason=error.reason,
        )
    except Exception:
        # Provider parser exceptions must not leak raw payload or provider text.
        return _rejected(
            source_name=source_name.strip().lower(),
            dataset_name=dataset_name,
            kind=kind,
            metadata=metadata,
            reason="malformed_payload",
        )


def _normalize_tourism(
    payload: object,
    source_name: str,
    dataset_name: str,
    metadata: SourceFixtureMetadata,
) -> tuple[list[NormalizedOfficialRecord], int]:
    item = _mapping_payload(payload)
    _assert_safe_mapping(item)
    raw_image = _first_value(item, "firstimage", "originimgurl", "image")
    image_url = _validate_image(raw_image, metadata)
    counter = tour_api_ingest.OfficialRejectionCounter()
    place = tour_api_ingest.parse_tour_api_place(dict(item), counter=counter)
    if place is None:
        return [], max(counter.total, 1)
    fields: dict[str, PublicScalar] = {
        "place_id": place.place_id,
        "name_ko": place.title,
        "category": place.category,
        "address_ko": place.address_ko,
        "region_name_ko": place.region_name_ko,
        "province_code": place.area_code,
        "city_code": place.sigungu_code,
        "latitude": place.lat,
        "longitude": place.lng,
        "image_url": image_url,
    }
    return [
        _make_record(
            kind="tourism_place",
            source_name=source_name,
            dataset_name=dataset_name,
            source_record_id=place.content_id,
            identity_values={"source_record_id": place.content_id},
            language="ko",
            category=place.category,
            region_name_ko=place.region_name_ko,
            coordinate_precision="place_point",
            image_rights_status=metadata.image_rights_status,
            metadata=metadata,
            fields=fields,
        )
    ], counter.total


def _normalize_culture_events(
    payload: object,
    source_name: str,
    dataset_name: str,
    metadata: SourceFixtureMetadata,
) -> tuple[list[NormalizedOfficialRecord], int]:
    xml_text = _text_payload(payload)
    root = _parse_xml_safely(xml_text)
    _assert_safe_xml_items(root)
    for item in root.findall(".//items/item"):
        _validate_image(_xml_value(item, "thumbnail", "imgUrl", "image"), metadata)
    counter = culture_info_ingest.OfficialRejectionCounter()
    events, _ = culture_info_ingest.parse_culture_info_events(
        xml_text, source_name=source_name, counter=counter
    )
    records = []
    for event in events:
        image_url = _validate_image(event.thumbnail_url, metadata)
        fields: dict[str, PublicScalar] = {
            "event_id": event.event_id,
            "title_ko": event.title_ko,
            "category": event.event_type,
            "venue_name_ko": event.venue_name_ko,
            "region_name_ko": event.region_name_ko,
            "starts_on": event.starts_on.isoformat() if event.starts_on else None,
            "ends_on": event.ends_on.isoformat() if event.ends_on else None,
            "latitude": event.gps_y,
            "longitude": event.gps_x,
            "image_url": image_url,
        }
        records.append(
            _make_record(
                kind="culture_event",
                source_name=source_name,
                dataset_name=dataset_name,
                source_record_id=event.seq,
                identity_values={"source_record_id": event.seq},
                language="ko",
                category=event.event_type,
                region_name_ko=event.region_name_ko,
                coordinate_precision="place_point"
                if event.gps_x is not None and event.gps_y is not None
                else "none",
                image_rights_status=metadata.image_rights_status,
                metadata=metadata,
                fields=fields,
            )
        )
    return records, counter.total


def _normalize_performance_events(
    payload: object,
    source_name: str,
    dataset_name: str,
    metadata: SourceFixtureMetadata,
) -> tuple[list[NormalizedOfficialRecord], int]:
    xml_text = _text_payload(payload)
    root = _parse_xml_safely(xml_text)
    _assert_safe_xml_items(root, item_path=".//db")
    for item in root.findall(".//db"):
        _validate_image(_xml_value(item, "poster", "image", "imgUrl"), metadata)
    counter = kopis_ingest.OfficialRejectionCounter()
    performances = kopis_ingest.parse_kopis_performances(xml_text, counter=counter)
    records = []
    for performance in performances:
        image_url = _validate_image(performance.poster_url, metadata)
        fields: dict[str, PublicScalar] = {
            "event_id": performance.event_id,
            "title_ko": performance.title_ko,
            "category": performance.genre_name,
            "venue_name_ko": performance.venue_name_ko,
            "region_name_ko": performance.region_name_ko,
            "starts_on": performance.starts_on.isoformat() if performance.starts_on else None,
            "ends_on": performance.ends_on.isoformat() if performance.ends_on else None,
            "image_url": image_url,
            "openrun": performance.openrun,
            "performance_state": performance.performance_state,
        }
        records.append(
            _make_record(
                kind="performance_event",
                source_name=source_name,
                dataset_name=dataset_name,
                source_record_id=performance.mt20id,
                identity_values={"source_record_id": performance.mt20id},
                language="ko",
                category=performance.genre_name,
                region_name_ko=performance.region_name_ko,
                coordinate_precision="none",
                image_rights_status=metadata.image_rights_status,
                metadata=metadata,
                fields=fields,
            )
        )
    return records, counter.total


def _normalize_franchise(
    payload: object,
    source_name: str,
    dataset_name: str,
    metadata: SourceFixtureMetadata,
) -> tuple[list[NormalizedOfficialRecord], int]:
    if not isinstance(payload, Sequence) or isinstance(payload, (str, bytes, bytearray)):
        raise OfficialSourceAdapterError("unsupported_payload_shape")
    rows = []
    for row in payload:
        item = _mapping_payload(row)
        _assert_safe_mapping(item)
        rows.append(dict(item))
    records, skipped = franchise_reference_ingest.parse_brand_stats_items(
        rows,
        year=metadata.source_year or 0,
        source_name=source_name,
    )
    normalized = []
    for brand in records:
        fields: dict[str, PublicScalar] = {
            "brand_id": brand.brand_id,
            "brand_name_ko": brand.brand_name_ko,
            "normalized_brand_name": brand.normalized_brand_name,
            "headquarters_name_ko": brand.headquarters_name_ko,
            "category": brand.business_category,
            "main_product": brand.main_product,
            "franchise_store_count": brand.franchise_store_count,
            "average_sales_amount": brand.average_sales_amount,
            "chain_scale_score": brand.chain_scale_score,
        }
        normalized.append(
            _make_record(
                kind="franchise_reference",
                source_name=source_name,
                dataset_name=dataset_name,
                source_record_id=brand.source_record_id,
                identity_values={"source_record_id": brand.source_record_id},
                language="ko",
                category=brand.business_category,
                region_name_ko=None,
                coordinate_precision="none",
                image_rights_status=metadata.image_rights_status,
                metadata=metadata,
                fields=fields,
            )
        )
    return normalized, skipped


def _normalize_card_spending(
    payload: object,
    source_name: str,
    dataset_name: str,
    metadata: SourceFixtureMetadata,
) -> tuple[list[NormalizedOfficialRecord], int]:
    if not isinstance(payload, Sequence) or isinstance(payload, (str, bytes, bytearray)):
        raise OfficialSourceAdapterError("unsupported_payload_shape")
    region_code_map = dict(metadata.region_code_map)
    area_groups: dict[tuple[Any, ...], dict[str, Any]] = defaultdict(
        lambda: {"spend_amount": None, "transaction_count": None}
    )
    demo_groups: dict[tuple[Any, ...], dict[str, Any]] = defaultdict(
        lambda: {"spend_amount": None, "transaction_count": None}
    )
    rejected = 0
    for row in payload:
        try:
            item = _mapping_payload(row)
            _assert_safe_mapping(item)
            parsed = card_spending_ingest._parse_row(
                normalized=card_spending_ingest._normalize_row(dict(item)),
                source_name=source_name,
                visitor_type=metadata.visitor_type,
                region_code_map=region_code_map,
            )
        except OfficialSourceAdapterError:
            raise
        except Exception as error:
            del error
            parsed = None
        if parsed is None:
            rejected += 1
            continue
        area_key = (
            parsed["month"],
            parsed["region_name_ko"],
            parsed["industry_code"],
            parsed["industry_name_ko"],
            parsed["visitor_type"],
        )
        card_spending_ingest._merge_group(
            area_groups[area_key], parsed["spend_amount"], parsed["transaction_count"]
        )
        if parsed["gender"] or parsed["age_group"]:
            demo_key = (
                parsed["month"],
                parsed["region_name_ko"],
                parsed["industry_code"],
                parsed["gender"],
                parsed["age_group"],
            )
            card_spending_ingest._merge_group(
                demo_groups[demo_key], parsed["spend_amount"], parsed["transaction_count"]
            )

    records = []
    for key, values in sorted(area_groups.items(), key=card_spending_ingest._sortable_group_key):
        month, region_name, industry_code, industry_name, visitor_type = key
        identity = {
            "month": month.isoformat(),
            "region_name_ko": region_name,
            "industry_code": industry_code or "unknown",
            "visitor_type": visitor_type,
        }
        records.append(
            _make_record(
                kind="card_spending_aggregate",
                source_name=source_name,
                dataset_name=dataset_name,
                source_record_id=None,
                identity_values=identity,
                language=None,
                category=industry_code,
                region_name_ko=region_name,
                coordinate_precision="coarse_region",
                image_rights_status=metadata.image_rights_status,
                metadata=metadata,
                fields={
                    "month": month.isoformat(),
                    "region_name_ko": region_name,
                    "industry_code": industry_code,
                    "industry_name_ko": industry_name,
                    "spend_amount": _decimal_text(values["spend_amount"]),
                    "transaction_count": values["transaction_count"],
                    "visitor_type": visitor_type,
                },
            )
        )
    for key, values in sorted(demo_groups.items(), key=card_spending_ingest._sortable_group_key):
        month, region_name, industry_code, gender, age_group = key
        identity = {
            "month": month.isoformat(),
            "region_name_ko": region_name,
            "industry_code": industry_code or "unknown",
            "gender": gender or "unknown",
            "age_group": age_group or "unknown",
        }
        records.append(
            _make_record(
                kind="card_spending_aggregate",
                source_name=source_name,
                dataset_name=dataset_name,
                source_record_id=None,
                identity_values=identity,
                language=None,
                category=industry_code,
                region_name_ko=region_name,
                coordinate_precision="coarse_region",
                image_rights_status=metadata.image_rights_status,
                metadata=metadata,
                fields={
                    "month": month.isoformat(),
                    "region_name_ko": region_name,
                    "industry_code": industry_code,
                    "industry_name_ko": None,
                    "gender": gender,
                    "age_group": age_group,
                    "spend_amount": _decimal_text(values["spend_amount"]),
                    "transaction_count": values["transaction_count"],
                    "visitor_type": metadata.visitor_type,
                },
            )
        )
    return records, rejected


def _make_record(
    *,
    kind: SourceAdapterKind,
    source_name: str,
    dataset_name: str,
    source_record_id: str | None,
    identity_values: Mapping[str, object],
    language: str | None,
    category: str | None,
    region_name_ko: str | None,
    coordinate_precision: CoordinatePrecision,
    image_rights_status: ImageRightsStatus,
    metadata: SourceFixtureMetadata,
    fields: Mapping[str, PublicScalar],
) -> NormalizedOfficialRecord:
    allowed = _ALLOWED_FIELDS[kind]
    if not set(fields).issubset(allowed):
        raise OfficialSourceAdapterError("forbidden_field")
    stable_fields = tuple(sorted(identity_values))
    if not stable_fields or any(not str(value).strip() for value in identity_values.values()):
        raise OfficialSourceAdapterError("missing_stable_identity")
    policy = SourceRecordIdentityPolicy(
        stable_fields=stable_fields,
        dedupe_fields=stable_fields,
    )
    dedupe_key = stable_source_record_identity(
        source_name=source_name,
        dataset_name=dataset_name,
        policy=policy,
        record=identity_values,
    )
    record_id = source_record_id or dedupe_key
    if not isinstance(record_id, str) or not 0 < len(record_id.strip()) <= 256:
        raise OfficialSourceAdapterError("missing_stable_identity")
    public_fields = tuple((key, _public_scalar(value)) for key, value in sorted(fields.items()))
    return NormalizedOfficialRecord(
        kind=kind,
        source_name=source_name,
        dataset_name=dataset_name,
        source_record_id=record_id.strip(),
        dedupe_key=dedupe_key,
        language=language,
        category=_optional_text(category),
        region_name_ko=_optional_text(region_name_ko),
        coverage_scope=metadata.coverage_scope,
        coordinate_precision=coordinate_precision,
        image_rights_status=image_rights_status,
        observed_at=metadata.observed_at,
        source_updated_at=metadata.source_updated_at,
        public_fields=public_fields,
    )


def _finalize(
    *,
    source_name: str,
    dataset_name: str,
    kind: SourceAdapterKind,
    metadata: SourceFixtureMetadata,
    records: Sequence[NormalizedOfficialRecord],
    rejected_record_count: int,
) -> SourceNormalizationResult:
    by_key: dict[str, NormalizedOfficialRecord] = {}
    for record in records:
        by_key.setdefault(record.dedupe_key, record)
    ordered = tuple(by_key[key] for key in sorted(by_key))
    duplicate_count = len(records) - len(ordered)
    reasons: list[NormalizationReason] = []
    if rejected_record_count:
        reasons.append("parser_rejected_record")
    status: NormalizationStatus = "accepted"
    accepted_count: int | None = len(ordered)
    if rejected_record_count:
        status = "incomplete" if ordered else "rejected"
        if not ordered:
            accepted_count = None
    return SourceNormalizationResult(
        source_name=source_name,
        dataset_name=dataset_name,
        kind=kind,
        status=status,
        records=ordered,
        accepted_record_count=accepted_count,
        rejected_record_count=rejected_record_count,
        duplicate_record_count=duplicate_count,
        rejection_reasons=tuple(reasons),
        observed_at=metadata.observed_at,
        source_updated_at=metadata.source_updated_at,
        coverage_scope=metadata.coverage_scope,
        covered_regions=metadata.covered_regions,
        localized_languages=metadata.localized_languages,
        image_rights_status=metadata.image_rights_status,
    )


def _normalize_metadata(metadata: SourceFixtureMetadata) -> SourceFixtureMetadata:
    if metadata.coverage_scope not in {"nationwide", "coarse_region", "unknown"}:
        raise OfficialSourceAdapterError("invalid_metadata")
    if metadata.image_rights_status not in {"verified", "not_permitted", "unknown"}:
        raise OfficialSourceAdapterError("invalid_metadata")
    languages = tuple(
        sorted({str(value).strip().lower() for value in metadata.localized_languages})
    )
    if not languages or not set(languages).issubset({"ko", "en"}):
        raise OfficialSourceAdapterError("unsupported_localization")
    observed_at = _as_utc(metadata.observed_at)
    source_updated_at = _as_utc(metadata.source_updated_at) if metadata.source_updated_at else None
    if source_updated_at and source_updated_at > observed_at:
        raise OfficialSourceAdapterError("invalid_freshness")
    regions = tuple(
        sorted({str(value).strip() for value in metadata.covered_regions if str(value).strip()})
    )
    return SourceFixtureMetadata(
        observed_at=observed_at,
        source_updated_at=source_updated_at,
        coverage_scope=metadata.coverage_scope,
        covered_regions=regions,
        localized_languages=languages,
        image_rights_status=metadata.image_rights_status,
        source_year=metadata.source_year,
        visitor_type=_optional_text(metadata.visitor_type) or "domestic",
        region_code_map=tuple(
            sorted(
                (str(key).strip(), str(value).strip()) for key, value in metadata.region_code_map
            )
        ),
    )


def _dispatch_metadata_check(*, metadata: SourceFixtureMetadata, dataset_name: str) -> None:
    if not dataset_name.strip():
        raise OfficialSourceAdapterError("invalid_metadata")
    if metadata.image_rights_status == "not_permitted":
        raise OfficialSourceAdapterError("image_rights_not_verified")


def _mapping_payload(payload: object) -> Mapping[str, object]:
    if not isinstance(payload, Mapping):
        raise OfficialSourceAdapterError("unsupported_payload_shape")
    return payload


def _text_payload(payload: object) -> str:
    if not isinstance(payload, str) or not payload.strip():
        raise OfficialSourceAdapterError("unsupported_payload_shape")
    return payload


def _parse_xml_safely(xml_text: str) -> ElementTree.Element:
    try:
        return ElementTree.fromstring(xml_text)
    except (ElementTree.ParseError, TypeError, ValueError) as error:
        del error
        raise OfficialSourceAdapterError("malformed_payload") from None


def _assert_safe_mapping(payload: Mapping[str, object]) -> None:
    for key, value in payload.items():
        normalized_key = _normalize_key(key)
        if _contains_forbidden_term(normalized_key):
            raise OfficialSourceAdapterError("forbidden_field")
        if normalized_key in {"coordinateprecision", "locationprecision"} and _normalize_key(
            value
        ) in {"personalprecise", "personalprecision"}:
            raise OfficialSourceAdapterError("unsafe_coordinate_precision")
        if isinstance(value, (Mapping, list, tuple, set)):
            raise OfficialSourceAdapterError("unsupported_payload_shape")
        if isinstance(value, str) and _SECRET_SHAPED_VALUE.search(value):
            raise OfficialSourceAdapterError("forbidden_field")


def _assert_safe_xml_items(root: ElementTree.Element, *, item_path: str = ".//items/item") -> None:
    for item in root.findall(item_path):
        for child in item:
            tag = _normalize_key(child.tag)
            if _contains_forbidden_term(tag):
                raise OfficialSourceAdapterError("forbidden_field")
            if child.text and _SECRET_SHAPED_VALUE.search(child.text):
                raise OfficialSourceAdapterError("forbidden_field")


def _validate_image(raw_value: object, metadata: SourceFixtureMetadata) -> str | None:
    if raw_value is None or not str(raw_value).strip():
        return None
    raw_url = str(raw_value).strip()
    if urlparse(raw_url).scheme.lower() != "https":
        raise OfficialSourceAdapterError("invalid_image_url")
    try:
        validate_image_url(raw_url, ImageUrlPolicy())
    except ValueError as error:
        del error
        raise OfficialSourceAdapterError("invalid_image_url") from None
    normalized = official_image_url_or_none(raw_url)
    if normalized != raw_url:
        raise OfficialSourceAdapterError("invalid_image_url")
    if metadata.image_rights_status != "verified":
        raise OfficialSourceAdapterError("image_rights_not_verified")
    return normalized


def _xml_value(item: ElementTree.Element, *names: str) -> str | None:
    candidates = {_normalize_key(name) for name in names}
    for child in item:
        if _normalize_key(child.tag) in candidates:
            return child.text.strip() if child.text else None
    return None


def _first_value(payload: Mapping[str, object], *names: str) -> object:
    normalized = {_normalize_key(name) for name in names}
    for key, value in payload.items():
        if _normalize_key(key) in normalized:
            return value
    return None


def _rejected(
    *,
    source_name: str,
    reason: NormalizationReason,
    dataset_name: str = "",
    kind: SourceAdapterKind | None = None,
    metadata: SourceFixtureMetadata | None = None,
) -> SourceNormalizationResult:
    observed_at = None
    source_updated_at = None
    coverage_scope: CoverageScope = "unknown"
    covered_regions: tuple[str, ...] = ()
    languages: tuple[str, ...] = ()
    image_rights: ImageRightsStatus = "unknown"
    if metadata is not None:
        try:
            normalized = _normalize_metadata(metadata)
            observed_at = normalized.observed_at
            source_updated_at = normalized.source_updated_at
            coverage_scope = normalized.coverage_scope
            covered_regions = normalized.covered_regions
            languages = normalized.localized_languages
            image_rights = normalized.image_rights_status
        except Exception:
            pass
    return SourceNormalizationResult(
        source_name=source_name,
        dataset_name=dataset_name,
        kind=kind,
        status="rejected",
        records=(),
        accepted_record_count=None,
        rejected_record_count=0,
        duplicate_record_count=0,
        rejection_reasons=(reason,),
        observed_at=observed_at,
        source_updated_at=source_updated_at,
        coverage_scope=coverage_scope,
        covered_regions=covered_regions,
        localized_languages=languages,
        image_rights_status=image_rights,
    )


def _public_scalar(value: object) -> PublicScalar:
    if value is None or isinstance(value, (str, int, float)):
        if isinstance(value, float) and not math.isfinite(value):
            raise OfficialSourceAdapterError("malformed_payload")
        if isinstance(value, str) and _SECRET_SHAPED_VALUE.search(value):
            raise OfficialSourceAdapterError("forbidden_field")
        return value
    if isinstance(value, Decimal):
        return _decimal_text(value)
    raise OfficialSourceAdapterError("forbidden_field")


def _decimal_text(value: Decimal | None) -> str | None:
    return str(value) if value is not None else None


def _normalize_key(value: object) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(value).strip().lower())


def _contains_forbidden_term(value: str) -> bool:
    return any(term in value for term in _FORBIDDEN_FIELD_TERMS)


def _optional_text(value: object) -> str | None:
    if value is None:
        return None
    text = " ".join(str(value).strip().split())
    return text or None


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)
