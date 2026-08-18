from __future__ import annotations

import sys
import types

import pytest

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


def test_romanize_place_name_uses_jungmyeongjeon_label() -> None:
    name = local_place_enrichment.romanize_place_name("중명전")

    assert name == "Jungmyeongjeon"
    assert "Myeongjeongjeon" not in name
    assert "Jeon Hall" not in name


def test_romanize_place_name_uses_hanbat_education_museum_label() -> None:
    name = local_place_enrichment.romanize_place_name("한밭교육박물관")

    assert name == "Hanbat Education Museum"
    assert "Hanhat" not in name


def test_build_local_enrichment_refresh_replaces_wrong_production_labels() -> None:
    # Why: these mirror the confirmed wrong travel.places.name_en rows that the
    # targeted repair mode regenerates from curated entries.
    jungmyeongjeon = local_place_enrichment.build_local_enrichment(
        {
            "place_id": "tour-api-1017547",
            "name_ko": "중명전",
            "name_en": "Myeongjeongjeon Hall",
            "address_ko": "서울시 중구 덕수궁길 11",
            "address_en": "Seoul Jung-gu Deoksugung-gil 11",
            "region_name_ko": "중구",
            "region_name_en": "Jung-gu",
        },
        replace_existing=True,
    )
    hanbat = local_place_enrichment.build_local_enrichment(
        {
            "place_id": "tour-api-130420",
            "name_ko": "한밭교육박물관",
            "name_en": "Daejeon Hanhat Education Museum",
            "address_ko": "대전광역시 서구 둔산로 111",
            "address_en": "Daejeon Seo-gu",
            "region_name_ko": "서구",
            "region_name_en": "Seo-gu",
        },
        replace_existing=True,
    )

    assert jungmyeongjeon.place_id == "tour-api-1017547"
    assert jungmyeongjeon.name_en == "Jungmyeongjeon"
    assert hanbat.place_id == "tour-api-130420"
    assert hanbat.name_en == "Hanbat Education Museum"


def _targeted_production_rows() -> list[dict[str, object]]:
    return [
        {
            "place_id": "tour-api-1017547",
            "name_ko": "중명전",
            "name_en": "Myeongjeongjeon Hall",
            "address_ko": "서울시 중구 덕수궁길 11",
            "address_en": "11 Deoksugung-gil, Jung-gu, Seoul",
            "region_name_ko": "중구",
            "region_name_en": "Jung-gu",
        },
        {
            "place_id": "tour-api-130420",
            "name_ko": "한밭교육박물관",
            "name_en": "Daejeon Hanhat Education Museum",
            "address_ko": "대전광역시 서구 둔산로 111",
            "address_en": "111 Dunsan-ro, Seo-gu, Daejeon",
            "region_name_ko": "서구",
            "region_name_en": "Seo-gu",
        },
    ]


def test_build_targeted_name_en_enrichment_touches_name_only() -> None:
    enrichment = local_place_enrichment.build_targeted_name_en_enrichment(
        _targeted_production_rows()[0]
    )

    assert enrichment.place_id == "tour-api-1017547"
    assert enrichment.name_en == "Jungmyeongjeon"
    # Why: targeted repair is bounded to name_en; existing address/region stay untouched.
    assert enrichment.address_en is None
    assert enrichment.region_name_en is None


def test_targeted_rows_error_accepts_curated_targets() -> None:
    rows = _targeted_production_rows()

    assert (
        local_place_enrichment.targeted_rows_error(rows, ["tour-api-1017547", "tour-api-130420"])
        == ""
    )


def test_targeted_rows_error_refuses_missing_duplicate_and_uncurated() -> None:
    rows = _targeted_production_rows()

    missing = local_place_enrichment.targeted_rows_error(rows, ["tour-api-999999"])
    assert "tour-api-999999" in missing
    assert "was not found" in missing

    uncurated_row = {**rows[0], "name_ko": "새 이름 없는 곳"}
    uncurated = local_place_enrichment.targeted_rows_error([uncurated_row], ["tour-api-1017547"])
    assert "curated" in uncurated

    duplicated = local_place_enrichment.targeted_rows_error(
        [rows[0], dict(rows[0])], ["tour-api-1017547"]
    )
    assert "more than one row" in duplicated


def test_fetch_targeted_places_queries_exact_ids_only(monkeypatch) -> None:
    executed = []

    class Cursor:
        def __init__(self) -> None:
            self.results = [
                {"place_id": "tour-api-130420", "name_ko": "한밭교육박물관"},
                {"place_id": "tour-api-1017547", "name_ko": "중명전"},
            ]

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))
            return None

        def fetchall(self):
            return self.results

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self, cursor_factory=None):
            return Cursor()

    fake_psycopg2 = types.ModuleType("psycopg2")
    fake_extras = types.ModuleType("psycopg2.extras")
    fake_extras.RealDictCursor = object
    fake_psycopg2.extras = fake_extras
    fake_psycopg2.connect = lambda dsn, connect_timeout: Connection()
    monkeypatch.setitem(sys.modules, "psycopg2", fake_psycopg2)
    monkeypatch.setitem(sys.modules, "psycopg2.extras", fake_extras)

    rows = local_place_enrichment.fetch_targeted_places(
        dsn="postgresql://redacted",
        place_ids=["tour-api-1017547", "tour-api-130420"],
        connect_timeout=5,
    )

    sql, params = executed[0]
    # Why: the contract is an exact-ID fetch, never a broad candidate set filtered later.
    assert "ANY(%s)" in sql
    assert "LIMIT" not in sql
    assert params == (["tour-api-1017547", "tour-api-130420"],)
    assert len(rows) == 2


def _targeted_apply_connection(rowcounts: list[int], executed: list, actions: list):
    class Cursor:
        def __init__(self) -> None:
            self._rowcounts = list(rowcounts)
            self.rowcount = 0

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))
            if self._rowcounts:
                self.rowcount = self._rowcounts.pop(0)

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            if exc_type is not None:
                actions.append("rollback")
            return None

        def cursor(self, cursor_factory=None):
            return Cursor()

        def commit(self):
            actions.append("commit")

        def rollback(self):
            actions.append("rollback")

    return Connection()


def test_apply_targeted_updates_only_name_en_in_one_transaction(monkeypatch) -> None:
    executed: list = []
    actions: list = []
    connection = _targeted_apply_connection([1, 1, 1, 1], executed, actions)
    fake_psycopg2 = types.ModuleType("psycopg2")
    fake_psycopg2.connect = lambda dsn, connect_timeout: connection
    monkeypatch.setitem(sys.modules, "psycopg2", fake_psycopg2)

    rows = _targeted_production_rows()
    enrichments = [local_place_enrichment.build_targeted_name_en_enrichment(row) for row in rows]

    updated = local_place_enrichment.apply_targeted_local_enrichments(
        dsn="postgresql://redacted",
        enrichments=enrichments,
        expected_name_ko={"tour-api-1017547": "중명전", "tour-api-130420": "한밭교육박물관"},
        connect_timeout=5,
    )

    update_statements = [(sql, params) for sql, params in executed if "UPDATE travel.places" in sql]
    insert_statements = [(sql, params) for sql, params in executed if "place_enrichments" in sql]
    assert updated == 2
    assert len(update_statements) == 2
    assert len(insert_statements) == 2
    # Why: bounded repair must not touch address_en/region_name_en.
    for sql, _params in update_statements:
        assert "name_en = %(name_en)s" in sql
        assert "address_en" not in sql
        assert "region_name_en" not in sql
        assert "name_ko = %(name_ko)s" in sql
    insert_sql, _ = insert_statements[0]
    # History rows for targeted repair carry only the corrected name_en.
    assert "%(name_en)s" in insert_sql
    assert "%(address_en)s" not in insert_sql
    assert "%(region_name_en)s" not in insert_sql
    # Update precedes its history insert per target, and exactly one commit commits the run.
    first_update_index = executed.index(update_statements[0])
    first_insert_index = executed.index(insert_statements[0])
    assert first_update_index < first_insert_index
    assert actions == ["commit"]


def test_apply_targeted_rolls_back_whole_run_when_target_changed(monkeypatch) -> None:
    executed: list = []
    actions: list = []
    # Why: first target updates fine, second target's name_ko changed concurrently (rowcount 0).
    connection = _targeted_apply_connection([1, 1, 0], executed, actions)
    fake_psycopg2 = types.ModuleType("psycopg2")
    fake_psycopg2.connect = lambda dsn, connect_timeout: connection
    monkeypatch.setitem(sys.modules, "psycopg2", fake_psycopg2)

    rows = _targeted_production_rows()
    enrichments = [local_place_enrichment.build_targeted_name_en_enrichment(row) for row in rows]

    with pytest.raises(local_place_enrichment.TargetedPlaceChangedError) as excinfo:
        local_place_enrichment.apply_targeted_local_enrichments(
            dsn="postgresql://redacted",
            enrichments=enrichments,
            expected_name_ko={"tour-api-1017547": "중명전", "tour-api-130420": "한밭교육박물관"},
            connect_timeout=5,
        )

    assert "tour-api-130420" in str(excinfo.value)
    assert actions == ["rollback"]
    assert "commit" not in actions
