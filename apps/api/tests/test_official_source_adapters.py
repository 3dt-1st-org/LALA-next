from __future__ import annotations

import json
from dataclasses import replace
from datetime import UTC, datetime

import pytest

from apps.api.app.services import official_source_adapters as adapters
from apps.api.app.services import tour_api_ingest

OBSERVED_AT = datetime(2026, 7, 28, 0, 0, tzinfo=UTC)


def _metadata(**overrides):
    metadata = adapters.SourceFixtureMetadata(
        observed_at=OBSERVED_AT,
        source_updated_at=datetime(2026, 7, 27, 0, 0, tzinfo=UTC),
        coverage_scope="nationwide",
        covered_regions=("gyeonggi", "seoul"),
        localized_languages=("ko",),
        image_rights_status="verified",
        source_year=2025,
    )
    return replace(metadata, **overrides)


def _tour_item(**overrides):
    return {
        "contentid": "tour-42",
        "contenttypeid": "12",
        "title": "  Synthetic Place  ",
        "addr1": "경기도 수원시 팔달구",
        "areacode": "31",
        "sigungucode": "13",
        "mapx": "127.025",
        "mapy": "37.263",
        "firstimage": "https://tong.visitkorea.or.kr/cms/resource/synthetic.jpg",
        **overrides,
    }


def test_each_source_category_normalizes_through_existing_parsers():
    tour = adapters.normalize_official_source_fixture(
        source_name="tour_api", payload=_tour_item(), metadata=_metadata()
    )
    culture = adapters.normalize_official_source_fixture(
        source_name="kcisa",
        payload="""
        <response><header><resultCode>00</resultCode></header><body><items><item>
          <seq>culture-1</seq><title>문화 행사</title><realmName>전시</realmName>
          <place>수원시미디어센터</place><area>경기</area><sigungu>수원시</sigungu>
          <startDate>20260701</startDate><endDate>20260731</endDate>
          <thumbnail>https://www.culture.go.kr/upload/synthetic.jpg</thumbnail>
          <gpsX>127.025</gpsX><gpsY>37.263</gpsY>
        </item></items></body></response>
        """,
        metadata=_metadata(),
    )
    performance = adapters.normalize_official_source_fixture(
        source_name="kopis",
        payload="""
        <dbs><db><mt20id>performance-1</mt20id><prfnm>공연 행사</prfnm>
          <prfpdfrom>2026.07.01</prfpdfrom><prfpdto>2026.07.02</prfpdto>
          <fcltynm>수원 공연장</fcltynm><poster>https://www.kopis.or.kr/upload/synthetic.jpg</poster>
          <area>경기도</area><genrenm>연극</genrenm>
        </db></dbs>
        """,
        metadata=_metadata(),
    )
    franchise = adapters.normalize_official_source_fixture(
        source_name="fair_trade_commission",
        payload=[
            {
                "yr": "2025",
                "indutyLclasNm": "외식",
                "indutyMlsfcNm": "한식",
                "corpNm": "합법 합성 본사",
                "brandNm": "합성 브랜드",
                "frcsCnt": "4",
                "avrgSlsAmt": "1200",
            }
        ],
        metadata=_metadata(),
    )
    card = adapters.normalize_official_source_fixture(
        source_name="data_portal",
        payload=[
            {
                "기준년월": "202607",
                "시군구명": "수원시",
                "중분류업종코드": "FD01",
                "중분류업종명": "음식점",
                "성연령코드": "F20",
                "매출금액": "1200",
            }
        ],
        metadata=_metadata(),
    )

    assert [result.status for result in (tour, culture, performance, franchise, card)] == [
        "accepted",
        "accepted",
        "accepted",
        "accepted",
        "accepted",
    ]
    assert [result.kind for result in (tour, culture, performance, franchise, card)] == [
        "tourism_place",
        "culture_event",
        "performance_event",
        "franchise_reference",
        "card_spending_aggregate",
    ]
    assert tour.records[0].coordinate_precision == "place_point"
    assert culture.records[0].coordinate_precision == "place_point"
    assert performance.records[0].coordinate_precision == "none"
    assert franchise.records[0].category == "외식 / 한식"
    assert card.records[0].coordinate_precision == "coarse_region"


def test_equivalent_inputs_have_stable_identity_and_deterministic_output():
    first = adapters.normalize_official_source_fixture(
        source_name="tour_api", payload=_tour_item(), metadata=_metadata()
    )
    second = adapters.normalize_official_source_fixture(
        source_name="tour_api",
        payload={
            "mapy": "37.263",
            "firstimage": "https://tong.visitkorea.or.kr/cms/resource/synthetic.jpg",
            "title": "Synthetic Place",
            "contenttypeid": "12",
            "contentid": "tour-42",
            "sigungucode": "13",
            "addr1": "경기도 수원시 팔달구",
            "mapx": "127.025",
            "areacode": "31",
        },
        metadata=_metadata(),
    )

    assert first.to_public_dict() == second.to_public_dict()
    assert first.records[0].dedupe_key == second.records[0].dedupe_key


def test_duplicate_card_rows_are_aggregated_without_inflating_records():
    row = {
        "기준년월": "202607",
        "시군구명": "수원시",
        "중분류업종코드": "FD01",
        "중분류업종명": "음식점",
        "성연령코드": "F20",
        "매출금액": "1200",
    }
    result = adapters.normalize_official_source_fixture(
        source_name="data_portal", payload=[row, dict(row)], metadata=_metadata()
    )

    assert result.status == "accepted"
    assert result.accepted_record_count == 2
    assert {field[0]: field[1] for field in result.records[0].public_fields}[
        "spend_amount"
    ] == "2400"
    assert result.records[0].dedupe_key != result.records[1].dedupe_key


@pytest.mark.parametrize(
    ("source_name", "payload", "reason"),
    [
        ("not_registered", {}, "unknown_source"),
        ("tour_api", {"title": "missing identity"}, "parser_rejected_record"),
        (
            "tour_api",
            _tour_item(firstimage="http://tong.visitkorea.or.kr/cms/resource/x.jpg"),
            "invalid_image_url",
        ),
        (
            "tour_api",
            _tour_item(coordinate_precision="personal_precise"),
            "unsafe_coordinate_precision",
        ),
        ("kcisa", "<response><broken>", "malformed_payload"),
    ],
)
def test_unknown_malformed_and_unsafe_payloads_fail_closed(source_name, payload, reason):
    result = adapters.normalize_official_source_fixture(
        source_name=source_name, payload=payload, metadata=_metadata()
    )

    assert result.status == "rejected"
    assert result.records == ()
    assert result.accepted_record_count is None
    assert reason in result.rejection_reasons


def test_missing_governance_and_localization_or_image_rights_are_not_usable():
    unsupported_language = adapters.normalize_official_source_fixture(
        source_name="tour_api",
        payload=_tour_item(),
        metadata=_metadata(localized_languages=("ja",)),
    )
    unverified_image = adapters.normalize_official_source_fixture(
        source_name="tour_api",
        payload=_tour_item(),
        metadata=_metadata(image_rights_status="unknown"),
    )
    future_update = adapters.normalize_official_source_fixture(
        source_name="tour_api",
        payload=_tour_item(firstimage=None),
        metadata=_metadata(source_updated_at=datetime(2026, 7, 29, tzinfo=UTC)),
    )

    assert unsupported_language.rejection_reasons == ("unsupported_localization",)
    assert unverified_image.rejection_reasons == ("image_rights_not_verified",)
    assert future_update.rejection_reasons == ("invalid_freshness",)


def test_public_projection_contains_no_raw_review_author_provider_or_rag_fields():
    result = adapters.normalize_official_source_fixture(
        source_name="tour_api", payload=_tour_item(), metadata=_metadata()
    )
    payload = result.to_public_dict()
    serialized = json.dumps(payload, ensure_ascii=False).lower()

    assert "review" not in serialized
    assert "author" not in serialized
    assert "provider_payload" not in serialized
    assert "embedding" not in serialized
    assert "prompt" not in serialized
    assert "synthetic raw" not in serialized
    assert "contentid" not in serialized


def test_forbidden_fields_are_rejected_without_invoking_fetch_or_upsert(monkeypatch):
    monkeypatch.setattr(
        tour_api_ingest, "fetch_tour_api_places", lambda **_: pytest.fail("fetch called")
    )
    monkeypatch.setattr(
        tour_api_ingest, "upsert_tour_api_places", lambda **_: pytest.fail("upsert called")
    )
    result = adapters.normalize_official_source_fixture(
        source_name="tour_api",
        payload=_tour_item(author_id="not accepted"),
        metadata=_metadata(),
    )

    assert result.status == "rejected"
    assert result.rejection_reasons == ("forbidden_field",)


@pytest.mark.parametrize("field_name", ["review_body", "author_subject", "provider_payload"])
def test_raw_review_identity_and_provider_payload_fields_are_rejected(field_name):
    result = adapters.normalize_official_source_fixture(
        source_name="tour_api",
        payload=_tour_item(**{field_name: "not accepted"}),
        metadata=_metadata(),
    )

    assert result.status == "rejected"
    assert result.rejection_reasons == ("forbidden_field",)
