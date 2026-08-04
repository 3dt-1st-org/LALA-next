from __future__ import annotations

from apps.api.app.services import local_place_enrichment


def test_romanize_place_name_adds_useful_suffix() -> None:
    name = local_place_enrichment.romanize_place_name("시흥오이도박물관")

    assert name == "Siheung Oido Museum"
    assert "Bagmulgwan" not in name
    assert not any("가" <= char <= "힣" for char in name)


def test_romanize_place_name_uses_curated_public_labels() -> None:
    name = local_place_enrichment.romanize_place_name("2025 제7회 BMF(블랙뮤직페스티벌)")

    assert name == "2025 7th BMF Black Music Festival"
    assert "Je7Hoe" not in name


def test_romanize_place_name_handles_event_phrases() -> None:
    name = local_place_enrichment.romanize_place_name("2025 양주관아지에서 만나는 특별한 주말")

    assert name == "2025 Special Weekend at Yangju Gwana Historic Site"
    assert "Yangjugwan-Aji" not in name


def test_romanize_address_uses_gyeonggi_region_dictionary() -> None:
    address = local_place_enrichment.romanize_address("경기도 포천시 신북면 아트밸리로 234")

    assert address
    assert address.startswith("Gyeonggi-do Pocheon-si")
    assert not any("가" <= char <= "힣" for char in address)


def test_romanize_address_uses_seoul_short_alias() -> None:
    address = local_place_enrichment.romanize_address("서울시 종로구 익선동")

    assert address == "Seoul Jongno-gu Igseondong"
    assert "Seoulsi" not in address


def test_romanize_address_supports_non_capital_regions() -> None:
    address = local_place_enrichment.romanize_address("부산광역시 해운대구 우동")

    assert address == "Busan Haeundae-gu Udong"
    assert "부산" not in address


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


def test_build_local_enrichment_infers_region_from_address_when_missing() -> None:
    enrichment = local_place_enrichment.build_local_enrichment(
        {
            "place_id": "tour-api-2946228",
            "name_ko": "익선동 한옥거리",
            "name_en": "Ikseon-dong Hanok Street",
            "address_ko": "서울시 종로구 익선동",
            "address_en": None,
            "region_name_ko": None,
            "region_name_en": None,
        }
    )

    assert enrichment.region_name_en == "Jongno-gu"


def test_build_local_enrichment_can_refresh_local_values() -> None:
    enrichment = local_place_enrichment.build_local_enrichment(
        {
            "place_id": "tour-api-3551014",
            "name_ko": "2025 제7회 BMF(블랙뮤직페스티벌)",
            "name_en": "2025 Je7Hoe Bmf(Beullaegmyujigpeseutibeol)",
            "address_ko": "경기도 의정부시",
            "address_en": "Gyeonggi-do Uijeongbu-si",
            "region_name_ko": "의정부시",
            "region_name_en": "Uijeongbu-si",
        },
        replace_existing=True,
    )

    assert enrichment.name_en == "2025 7th BMF Black Music Festival"


def test_apply_local_enrichments_replace_existing_updates_enrichment(monkeypatch):
    """Verify replace_existing=True updates existing enrichment on conflict."""
    import sys
    from types import SimpleNamespace

    executed: list = []

    class Cursor:
        rowcount = 1

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self):
            return Cursor()

        def commit(self):
            executed.append(("commit", None))

    def connect(dsn, connect_timeout):
        executed.append(("connect", {"dsn": dsn, "connect_timeout": connect_timeout}))
        return Connection()

    class Json:
        def __init__(self, obj):
            self.obj = obj

    extras = SimpleNamespace(Json=Json)
    psycopg2_module = SimpleNamespace(connect=connect, extras=extras)

    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)
    monkeypatch.setitem(sys.modules, "psycopg2.extras", extras)

    enrichment = local_place_enrichment.LocalPlaceEnrichment(
        place_id="test-place-1",
        name_en="Updated Name",
        address_en="Updated Address",
        region_name_en="Updated Region",
        confidence=0.62,
        reason="Test enrichment",
    )

    result = local_place_enrichment.apply_local_enrichments(
        dsn="postgresql://redacted",
        enrichments=[enrichment],
        connect_timeout=5,
        replace_existing=True,
    )

    assert result == 1

    # Find the INSERT INTO travel.place_enrichments statement
    insert_statements = [
        sql for sql, params in executed if "INSERT INTO travel.place_enrichments" in sql
    ]
    assert len(insert_statements) == 1
    insert_sql = insert_statements[0]

    assert "ON CONFLICT (place_id, enrichment_type, prompt_version)" in insert_sql
    assert "DO UPDATE SET" in insert_sql
    assert "name_en = EXCLUDED.name_en" in insert_sql
    assert "address_en = EXCLUDED.address_en" in insert_sql
    assert "region_name_en = EXCLUDED.region_name_en" in insert_sql
