from __future__ import annotations

from apps.api.app.services import region_catalog


def test_normalize_province_name_ko_accepts_short_aliases() -> None:
    assert region_catalog.normalize_province_name_ko("경기") == "경기도"
    assert region_catalog.normalize_province_name_ko("제주") == "제주특별자치도"


def test_infer_region_name_from_address_supports_nationwide_manual_catalog() -> None:
    assert region_catalog.infer_region_name_from_address("부산광역시 해운대구 우동") == "해운대구"
    assert region_catalog.infer_region_name_from_address("강원특별자치도 춘천시 옥천동") == "춘천시"


def test_infer_region_name_from_text_uses_province_scoped_aliases() -> None:
    assert region_catalog.infer_region_name_from_text("여름 바다 축제 [해운대]", "부산광역시") == "해운대구"
    assert region_catalog.infer_region_name_from_text("강릉 단오제", "강원특별자치도") == "강릉시"


def test_region_name_en_map_can_include_province_aliases() -> None:
    mapping = region_catalog.region_name_en_map(province_names=("부산광역시",), include_provinces=True)

    assert mapping["부산광역시"] == "Busan"
    assert mapping["부산"] == "Busan"
    assert mapping["해운대구"] == "Haeundae-gu"


def test_kopis_signgucodes_follow_region_catalog() -> None:
    assert region_catalog.normalize_kopis_signgucode("경기도") == "41"
    assert region_catalog.normalize_kopis_signgucode("부산") == "26"
    assert region_catalog.kopis_signgucodes(province_names=("서울특별시", "제주")) == ("11", "50")
