from __future__ import annotations

from apps.api.app.services import local_place_enrichment


def test_romanize_place_name_adds_useful_suffix() -> None:
    name = local_place_enrichment.romanize_place_name("시흥오이도박물관")

    assert name
    assert "Museum" in name
    assert not any("가" <= char <= "힣" for char in name)


def test_romanize_address_uses_gyeonggi_region_dictionary() -> None:
    address = local_place_enrichment.romanize_address("경기도 포천시 신북면 아트밸리로 234")

    assert address
    assert address.startswith("Gyeonggi-do Pocheon-si")
    assert not any("가" <= char <= "힣" for char in address)


def test_build_local_enrichment_preserves_existing_values() -> None:
    enrichment = local_place_enrichment.build_local_enrichment(
        {
            "place_id": "tour-api-1",
            "name_ko": "수원화성",
            "name_en": "Suwon Hwaseong",
            "address_ko": "경기도 수원시 팔달구",
            "address_en": None,
            "region_name_ko": "수원시",
            "region_name_en": None,
        }
    )

    assert enrichment.name_en == "Suwon Hwaseong"
    assert enrichment.region_name_en == "Suwon-si"
    assert enrichment.address_en
    assert not any("가" <= char <= "힣" for char in enrichment.address_en)
