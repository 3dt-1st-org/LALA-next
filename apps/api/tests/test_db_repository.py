from __future__ import annotations

import sys
import types
from datetime import UTC, datetime, timedelta

import pytest

from apps.api.app.services import db_repository


def test_check_db_status_requires_canonical_relations(monkeypatch):
    captured = {}

    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql):
            captured["sql"] = sql

        def fetchone(self):
            return (True, True, True, True, True, True)

    class FakeConnection:
        def cursor(self):
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)

    status = db_repository.check_db_status("postgresql://db.example/lala")

    assert status == "configured"
    assert "to_regclass('travel.public_places')" in captured["sql"]
    assert "to_regclass('travel.place_events')" in captured["sql"]
    assert "to_regclass('travel.weather_observations')" in captured["sql"]
    assert "to_regclass('travel.docent_scripts')" in captured["sql"]
    assert "to_regclass('analytics.place_score_snapshots')" in captured["sql"]
    assert "to_regclass('rag.knowledge_chunks')" in captured["sql"]


def test_check_db_status_degrades_when_canonical_relation_is_missing(monkeypatch):
    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql):
            return None

        def fetchone(self):
            return (True, False, True, True, True, True)

    class FakeConnection:
        def cursor(self):
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)

    status = db_repository.check_db_status("postgresql://db.example/lala")

    assert status == "degraded"


def test_check_identity_schema_status_requires_tombstone_storage_and_unique_keys(
    monkeypatch,
):
    captured = {}

    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql):
            captured["sql"] = sql

        def fetchone(self):
            return (True, True, True, True, True)

    class FakeConnection:
        def cursor(self):
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)

    status = db_repository.check_identity_schema_status("postgresql://db.example/lala")

    assert status == "configured"
    assert "identity.users" in captured["sql"]
    assert "identity.deleted_users" in captured["sql"]
    assert "identity_digest" in captured["sql"]
    assert "pg_constraint" in captured["sql"]


def test_check_identity_schema_status_degrades_without_deleted_users(monkeypatch):
    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql):
            return None

        def fetchone(self):
            return (True, True, False, True, True)

    class FakeConnection:
        def cursor(self):
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)

    assert db_repository.check_identity_schema_status("postgresql://db.example/lala") == "degraded"


def test_check_postgis_status_requires_extension_and_spatial_index(monkeypatch):
    captured = {}

    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql):
            captured["sql"] = sql

        def fetchone(self):
            return (True, True)

    class FakeConnection:
        def cursor(self):
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)

    status = db_repository.check_postgis_status("postgresql://db.example/lala")

    assert status == "configured"
    assert "FROM pg_extension" in captured["sql"]
    assert "extname = 'postgis'" in captured["sql"]
    assert "to_regclass('travel.idx_places_geog_expr')" in captured["sql"]


def test_check_postgis_status_degrades_without_spatial_index(monkeypatch):
    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql):
            return None

        def fetchone(self):
            return (True, False)

    class FakeConnection:
        def cursor(self):
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)

    status = db_repository.check_postgis_status("postgresql://db.example/lala")

    assert status == "degraded"


def test_fetch_places_uses_radius_bound_ranking_query(monkeypatch):
    captured = {}

    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql, params):
            captured["sql"] = sql
            captured["params"] = params

        def fetchall(self):
            return [
                {
                    "place_id": "db-place-1",
                    "name_ko": "DB 장소",
                    "name_en": "DB Place",
                    "category": "event",
                    "address_ko": "DB 주소",
                    "address_en": "DB address",
                    "region_ko": "수원",
                    "region_en": "Suwon",
                    "event_start_date": "2026-06-01",
                    "event_end_date": "2026-08-31",
                    "event_url": "https://example.test/events/db-place-1",
                    "is_ongoing": True,
                    "is_approximate_location": False,
                    "lat": 37.2,
                    "lng": 127.0,
                    "source": "canonical",
                    "updated_at": datetime.now(UTC),
                    "distance_m": 125.2,
                    "local_spending_score": 0.81,
                    "small_merchant_fit_score": 0.57,
                    "demand_dispersion_score": 0.72,
                    "culture_relevance_score": 0.88,
                    "weather_fit_score": 0.66,
                    "review_quality_score": None,
                    "accessibility_fit_score": 0.62,
                    "final_score": 0.775,
                    "formula_version": "local-value-v2",
                    "score_features": {"source": "unit-test"},
                }
            ]

    class FakeConnection:
        def cursor(self, cursor_factory=None):
            captured["cursor_factory"] = cursor_factory
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    extras_module = types.ModuleType("psycopg2.extras")
    extras_module.RealDictCursor = object()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)
    monkeypatch.setitem(sys.modules, "psycopg2.extras", extras_module)
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")

    places = db_repository.fetch_places(
        lat=37.2,
        lng=127.0,
        radius_m=3000,
        category="all",
        language="en",
        include_scores=True,
        limit=80,
    )

    assert places[0]["place_id"] == "db-place-1"
    assert places[0]["distance_m"] == 125
    assert places[0]["source"] == "db"
    assert places[0]["event_start_date"] == "2026-06-01"
    assert places[0]["event_end_date"] == "2026-08-31"
    assert places[0]["event_url"] == "https://example.test/events/db-place-1"
    assert places[0]["is_ongoing"] is True
    assert places[0]["is_approximate_location"] is False
    assert places[0]["score"] == {
        "final_score": 0.775,
        "formula_version": "local-value-v2",
        "components": {
            "local_spending_score": 0.81,
            "small_merchant_fit_score": 0.57,
            "demand_dispersion_score": 0.72,
            "culture_relevance_score": 0.88,
            "weather_fit_score": 0.66,
            "review_quality_score": None,
            "accessibility_fit_score": 0.62,
        },
        "data_basis": "analytics.place_score_snapshots",
        "features": {"source": "unit-test"},
    }
    assert "FROM analytics.place_score_snapshots" in captured["sql"]
    assert "to_jsonb(score_snapshot)->>'small_merchant_fit_score'" in captured["sql"]
    assert "to_jsonb(score_snapshot)->>'accessibility_fit_score'" in captured["sql"]
    assert "FROM travel.place_events" in captured["sql"]
    assert "ST_DWithin(" in captured["sql"]
    assert "ST_Distance(" in captured["sql"]
    assert "AND lat BETWEEN %s AND %s" in captured["sql"]
    assert "AND lng BETWEEN %s AND %s" in captured["sql"]
    assert (
        "ORDER BY FLOOR(distance_m / 500.0) ASC, COALESCE(latest_scores.final_score, 0) DESC, distance_m ASC"
        in captured["sql"]
    )
    assert captured["params"][:4] == (127.0, 37.2, "all", "all")
    assert captured["params"][-2:] == (3000, 80)
    assert len(captured["params"]) == 10


def test_fetch_places_raises_when_configured_db_read_fails(monkeypatch):
    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: (_ for _ in ()).throw(
        RuntimeError("connection failed")
    )
    extras_module = types.ModuleType("psycopg2.extras")
    extras_module.RealDictCursor = object()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)
    monkeypatch.setitem(sys.modules, "psycopg2.extras", extras_module)
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")

    try:
        db_repository.fetch_places(
            lat=37.2,
            lng=127.0,
            radius_m=3000,
            category="all",
            language="ko",
        )
    except db_repository.DatabaseReadError as exc:
        assert str(exc) == "places_query_failed"
    else:
        raise AssertionError("configured DB read failure must not be returned as []")


def test_fetch_latest_weather_prefers_nearest_region_match(monkeypatch):
    captured = {}

    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql, params):
            captured["sql"] = sql
            captured["params"] = params

        def fetchone(self):
            return {
                "location": "수원",
                "temperature": 11.4,
                "precipitation_type": "rain",
                "pm10": 45,
                "pm25": 21,
                "is_rain_snow": True,
                "is_bad_dust": False,
                "is_heatwave": False,
                "is_coldwave": False,
                "is_strong_wind": False,
                "record_time": datetime.now(UTC),
                "location_match_rank": 0,
            }

    class FakeConnection:
        def cursor(self, cursor_factory=None):
            captured["cursor_factory"] = cursor_factory
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    extras_module = types.ModuleType("psycopg2.extras")
    extras_module.RealDictCursor = object()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)
    monkeypatch.setitem(sys.modules, "psycopg2.extras", extras_module)
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")

    weather = db_repository.fetch_latest_weather(lat=37.2, lng=127.0)

    assert weather is not None
    assert weather["location"] == "수원"
    assert weather["icon"] == "rain"
    assert weather["location_match"] is True
    assert weather["dust"]["grade"] == "normal"
    assert weather["dust"]["pm10_grade"] == "normal"
    assert weather["dust"]["pm25_grade"] == "normal"
    assert "WITH query_point AS" in captured["sql"]
    assert "candidate_places AS" in captured["sql"]
    assert ", nearest_region AS" in captured["sql"]
    assert "ST_Distance(" in captured["sql"]
    assert "WHERE lat BETWEEN %s AND %s" in captured["sql"]
    assert "ORDER BY location_match_rank ASC, w.record_time DESC" in captured["sql"]
    assert captured["params"][:2] == (127.0, 37.2)
    assert captured["params"][-2:] == (37.2, 127.0)
    assert len(captured["params"]) == 8


def test_fetch_latest_weather_marks_latest_fallback_without_region_match(monkeypatch):
    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql, params):
            return None

        def fetchone(self):
            return {
                "location": "fallback-station",
                "temperature": 9.8,
                "precipitation_type": None,
                "pm10": 20,
                "pm25": 11,
                "is_rain_snow": False,
                "is_bad_dust": False,
                "is_heatwave": False,
                "is_coldwave": False,
                "is_strong_wind": False,
                "record_time": datetime.now(UTC),
                "location_match_rank": 1,
            }

    class FakeConnection:
        def cursor(self, cursor_factory=None):
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    extras_module = types.ModuleType("psycopg2.extras")
    extras_module.RealDictCursor = object()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)
    monkeypatch.setitem(sys.modules, "psycopg2.extras", extras_module)
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")

    weather = db_repository.fetch_latest_weather(lat=37.2, lng=127.0)

    assert weather is not None
    assert weather["location"] == "fallback-station"
    assert weather["location_match"] is False
    assert weather["outdoor_status"] == "good"
    assert weather["dust"]["pm10_grade"] == "good"
    assert weather["dust"]["pm25_grade"] == "good"


def test_fetch_nearest_region_labels_uses_postgis_distance_order(monkeypatch):
    captured = {}

    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql, params):
            captured["sql"] = sql
            captured["params"] = params

        def fetchall(self):
            return [
                {"region_ko": "중랑구", "region_en": "Jungnang-gu"},
                {"region_ko": "중랑구", "region_en": "Jungnang-gu"},
                {"region_ko": "성북구", "region_en": "Seongbuk-gu"},
            ]

    class FakeConnection:
        def cursor(self, cursor_factory=None):
            captured["cursor_factory"] = cursor_factory
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    extras_module = types.ModuleType("psycopg2.extras")
    extras_module.RealDictCursor = object()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)
    monkeypatch.setitem(sys.modules, "psycopg2.extras", extras_module)
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")

    labels = db_repository.fetch_nearest_region_labels(
        lat=37.5665,
        lng=126.9780,
    )

    assert labels == ["중랑구", "Jungnang-gu", "성북구", "Seongbuk-gu"]
    assert "FROM travel.public_places" in captured["sql"]
    assert "ST_Distance(" in captured["sql"]
    assert "ORDER BY ST_Distance(" in captured["sql"]
    assert captured["params"][:2] == (126.978, 37.5665)
    assert captured["params"][-1] == 8


def test_fetch_docent_knowledge_context_reads_place_rag_chunks(monkeypatch):
    captured = {}

    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql, params):
            captured["sql"] = sql
            captured["params"] = params

        def fetchall(self):
            return [
                {
                    "source_type": "place_profile",
                    "source_id": "place:tour-1",
                    "source_table": "rag.knowledge_chunks",
                    "title_ko": "수원화성",
                    "body_ko": "장소명은 수원화성입니다. 지역 소비와 산책 동선이 함께 연결됩니다.",
                    "body_en": "Suwon Hwaseong connects local spending and a walking route.",
                    "metadata": '{"category":"attraction"}',
                    "content_sha256": "abc123",
                    "updated_at": datetime.now(UTC),
                }
            ]

    class FakeConnection:
        def cursor(self, cursor_factory=None):
            captured["cursor_factory"] = cursor_factory
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    extras_module = types.ModuleType("psycopg2.extras")
    extras_module.RealDictCursor = object()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)
    monkeypatch.setitem(sys.modules, "psycopg2.extras", extras_module)
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")

    context = db_repository.fetch_docent_knowledge_context(place_id=" tour-1 ")

    assert len(context) == 1
    assert context[0]["source_type"] == "place_profile"
    assert context[0]["title_ko"] == "수원화성"
    assert context[0]["metadata"] == {"category": "attraction"}
    assert "FROM rag.knowledge_chunks" in captured["sql"]
    assert "ORDER BY" in captured["sql"]
    assert captured["params"] == ("tour-1", 3)


def test_fetch_docent_place_profile_context_reads_public_place_profile(monkeypatch):
    captured = {}

    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql, params):
            captured["sql"] = sql
            captured["params"] = params

        def fetchone(self):
            return {
                "place_id": "tour-1",
                "name_ko": "서울도서관",
                "name_en": "Seoul Library",
                "category": "culture_venue",
                "address_ko": "서울특별시 중구 세종대로 110",
                "address_en": "110 Sejong-daero, Jung-gu, Seoul",
                "region_ko": "중구",
                "region_en": "Jung-gu",
                "source": "tour_api",
                "updated_at": datetime.now(UTC),
            }

    class FakeConnection:
        def cursor(self, cursor_factory=None):
            captured["cursor_factory"] = cursor_factory
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    extras_module = types.ModuleType("psycopg2.extras")
    extras_module.RealDictCursor = object()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)
    monkeypatch.setitem(sys.modules, "psycopg2.extras", extras_module)
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")

    context = db_repository.fetch_docent_place_profile_context(place_id=" tour-1 ")

    assert len(context) == 1
    profile = context[0]
    assert profile["source_type"] == "place_profile"
    assert profile["source_id"] == "place:tour-1"
    assert profile["source_table"] == "travel.public_places"
    assert profile["title_ko"] == "서울도서관"
    assert "장소명은 서울도서관입니다" in profile["body_ko"]
    assert "카테고리는 문화공간입니다" in profile["body_ko"]
    assert "대표 원천은 tour_api입니다" in profile["body_ko"]
    assert "The place name is Seoul Library." in profile["body_en"]
    assert profile["metadata"]["primary_source"] == "tour_api"
    assert len(profile["content_sha256"]) == 64
    assert "FROM travel.public_places" in captured["sql"]
    assert captured["params"] == ("tour-1",)


def test_remaining_ttl_sec_reports_future_expiry():
    ttl = db_repository._remaining_ttl_sec(datetime.now(UTC) + timedelta(seconds=90))

    assert 0 < ttl <= 90


def test_remaining_ttl_sec_clamps_expired_values():
    ttl = db_repository._remaining_ttl_sec(datetime.now(UTC) - timedelta(seconds=1))

    assert ttl == 0


def test_english_region_resolves_districts_outside_gyeonggi():
    # Why: _english_region must be nationwide, not Gyeonggi-only.
    cases = {
        "해운대구": "Haeundae-gu",  # Busan
        "제주시": "Jeju-si",  # Jeju
        "춘천시": "Chuncheon-si",  # Gangwon
        "여수시": "Yeosu-si",  # Jeollanam-do
        "경주시": "Gyeongju-si",  # Gyeongsangbuk-do
        "수원시": "Suwon-si",  # Gyeonggi (regression)
        "중구": "Jung-gu",  # Seoul (regression)
    }
    for region_ko, expected_en in cases.items():
        assert db_repository._english_region({"region_ko": region_ko}) == expected_en


def test_english_region_falls_back_to_region_en_when_unknown():
    assert (
        db_repository._english_region({"region_ko": "미분류동", "region_en": "Custom"}) == "Custom"
    )
    assert db_repository._english_region({"region_ko": "", "region_en": ""}) is None


def test_english_display_address_names_actual_province_not_gyeonggi():
    # Why: the synthesized English address previously hard-coded "Gyeonggi-do"
    # for every nationwide row; it must name the row's real province.
    busan = db_repository._english_display_address(
        {
            "region_ko": "해운대구",
            "address_ko": "부산광역시 해운대구 해운대로 1",
        }
    )
    assert busan == "Haeundae-gu, Busan"
    assert "Gyeonggi-do" not in busan

    jeju = db_repository._english_display_address(
        {
            "region_ko": "제주시",
            "address_ko": "제주특별자치도 제주시 연동로",
        }
    )
    assert jeju == "Jeju-si, Jeju"

    # Gyeonggi regression: province still derived from the address, not assumed.
    gyeonggi = db_repository._english_display_address(
        {
            "region_ko": "수원시",
            "address_ko": "경기도 수원시 영통구 덕영대로",
        }
    )
    assert gyeonggi == "Suwon-si, Gyeonggi-do"


def test_english_display_address_resolves_province_from_region_only():
    # Why: even without an address, an unambiguous 시/군/구 should resolve to its
    # real province via the region→province catalog (not assume Gyeonggi).
    assert db_repository._english_display_address({"region_ko": "해운대구"}) == "Haeundae-gu, Busan"


def test_english_display_address_never_fabricates_province():
    # Ambiguous region (중구 spans 6 provinces) and empty rows must not be shown
    # under a wrong province; the address stays region-only or empty.
    assert db_repository._english_display_address({"region_ko": "중구"}) == "Jung-gu"
    assert db_repository._english_display_address({}) == ""


# ---------------------------------------------------------------------------
# RAG V1 hybrid grounding seam (maps fused candidates onto the legacy row shape)
# ---------------------------------------------------------------------------


def test_fetch_docent_knowledge_context_hybrid_maps_candidates_to_legacy_shape(monkeypatch):
    from apps.api.app.services import rag_index, rag_retrieval

    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    candidate = rag_index.RagSearchResult(
        source_type="place_profile",
        source_id="place:p1",
        source_table="travel.places",
        title_ko="수원 화성행궁",
        body_ko="수원 화성행궁 본문",
        place_id="p1",
        metadata={"category": "attraction"},
        similarity=0.91,
        embedding_model="local-hash-v1",
        updated_at="2026-07-26T00:00:00+00:00",
        body_en=None,
        content_sha256="sha-p1",
    )
    captured: dict = {}

    def fake_hybrid(**kwargs):
        captured.update(kwargs)
        return [candidate]

    monkeypatch.setattr(rag_retrieval, "fetch_hybrid_candidates", fake_hybrid)

    rows = db_repository.fetch_docent_knowledge_context_hybrid(
        place_id="p1", query="수원 명소", category="attraction", language="ko", top_k=3
    )

    assert len(rows) == 1
    assert rows[0]["source_type"] == "place_profile"
    assert rows[0]["similarity"] == 0.91
    assert rows[0]["content_sha256"] == "sha-p1"
    assert rows[0]["body_ko"] == "수원 화성행궁 본문"
    assert captured["filters"].place_id == "p1"
    # Serving method resolved from settings (local-hash dev/test default).
    assert captured["embedding_method"] == "local-hash"


def test_fetch_docent_knowledge_context_hybrid_returns_empty_without_dsn(monkeypatch):
    monkeypatch.delenv("DB_DSN", raising=False)
    rows = db_repository.fetch_docent_knowledge_context_hybrid(
        place_id="p1", query="수원 명소", top_k=3
    )
    assert rows == []


def test_fetch_docent_knowledge_context_hybrid_returns_empty_on_infra_error(monkeypatch):
    # R5: a DB connection/query fault (psycopg2.Error) is an infrastructure error — it must
    # still degrade safely to [] so the caller falls back to legacy/profile grounding.
    import psycopg2

    from apps.api.app.services import rag_retrieval

    monkeypatch.setenv("DB_DSN", "postgresql://redacted")

    def fake_hybrid(**kwargs):
        raise psycopg2.OperationalError("connection refused")

    monkeypatch.setattr(rag_retrieval, "fetch_hybrid_candidates", fake_hybrid)

    rows = db_repository.fetch_docent_knowledge_context_hybrid(
        place_id="p1", query="수원 명소", top_k=3
    )

    assert rows == []


def test_fetch_docent_knowledge_context_hybrid_propagates_config_error(monkeypatch):
    # R5: a config error (missing live-AI credentials, unsupported embedding method) must not
    # be swallowed into a silent legacy-grounding fallback — it propagates.
    from apps.api.app.services import rag_retrieval

    monkeypatch.setenv("DB_DSN", "postgresql://redacted")

    def fake_hybrid(**kwargs):
        raise RuntimeError("OpenAI embedding requires OPENAI_API_KEY.")

    monkeypatch.setattr(rag_retrieval, "fetch_hybrid_candidates", fake_hybrid)

    with pytest.raises(RuntimeError):
        db_repository.fetch_docent_knowledge_context_hybrid(
            place_id="p1", query="수원 명소", top_k=3
        )


# ---------------------------------------------------------------------------
# Three-signals Lane 1 — internal reason-composer inputs projected from the DB
# (contract §10 Lane 1). `_local_activity_band` is a SQL min-sample gate over the
# score snapshot's features aggregate; `_has_linked_event` is derived from the
# already-joined LATERAL for ALL categories. Both are internal (underscore-prefixed)
# and consumed+stripped by the reason composer (places_service, Lane 2) — never
# serialized as-is.
#
# The band gate runs in SQL (contract §4: the raw aggregate never leaves the DB
# layer), so the unit harness (fake cursor, no live Postgres) verifies the gate at
# the SQL-encoding level — the same way the existing fetch_places test asserts on
# captured["sql"] — plus dict-surfacing through the fake-row path.
# ---------------------------------------------------------------------------


def _install_fake_places_db(monkeypatch, rows):
    """Fake psycopg2 so fetch_places returns `rows` without a live DB.

    Mirrors the harness in test_fetch_places_uses_radius_bound_ranking_query; returns the
    captured {sql, params} dict so callers can assert on the generated projection SQL.
    """
    captured = {}

    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql, params):
            captured["sql"] = sql
            captured["params"] = params

        def fetchall(self):
            return rows

    class FakeConnection:
        def cursor(self, cursor_factory=None):
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    extras_module = types.ModuleType("psycopg2.extras")
    extras_module.RealDictCursor = object()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)
    monkeypatch.setitem(sys.modules, "psycopg2.extras", extras_module)
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    return captured


def _place_row(**overrides):
    row = {
        "place_id": "p1",
        "name_ko": "장소",
        "name_en": "Place",
        "category": "attraction",
        "address_ko": "주소",
        "address_en": "address",
        "region_ko": "수원",
        "region_en": "Suwon",
        "lat": 37.2,
        "lng": 127.0,
        "source": "canonical",
        "updated_at": datetime.now(UTC),
        "distance_m": 100.0,
        "is_approximate_location": False,
        "is_indoor": None,
        "event_start_date": None,
        "event_end_date": None,
        "event_url": None,
        "is_ongoing": None,
        "final_score": None,
        "score_features": {},
        "_local_activity_band": None,
        "_has_linked_event": None,
    }
    row.update(overrides)
    return row


def test_local_activity_band_surfaces_and_stays_score_independent(monkeypatch):
    # include_scores defaults False (the normal path): the band must still project.
    rows = [
        _place_row(place_id="active-place", _local_activity_band="active"),
        _place_row(place_id="quiet-place", _local_activity_band=None),
    ]
    captured = _install_fake_places_db(monkeypatch, rows)

    places = db_repository.fetch_places(
        lat=37.2, lng=127.0, radius_m=3000, category="all", language="ko"
    )

    by_id = {p["place_id"]: p for p in places}
    assert by_id["active-place"]["_local_activity_band"] == "active"
    assert by_id["quiet-place"]["_local_activity_band"] is None
    # Gate is score-independent: band present even though scores are off (score is None).
    assert by_id["active-place"]["score"] is None
    assert "local_activity_band" in captured["sql"]


def test_local_activity_band_gate_boundary_encoded_score_independent():
    # Boundary (contract §4): region_transaction_count >= MIN_SAMPLE -> 'active', else NULL.
    assert db_repository._LOCAL_ACTIVITY_MIN_SAMPLE == 50

    for include_scores in (True, False):
        projection = db_repository._place_score_projection(include_scores=include_scores)
        # Reads the raw features aggregate directly — not the projected `features` alias that the
        # False branch NULLs — so the gate resolves regardless of the score flag.
        assert "(score_snapshot.features->>'region_transaction_count')" in projection
        # Regex guard: a missing/non-numeric count falls through to ELSE NULL, never raises.
        assert "~ '^[0-9]+$'" in projection
        # MIN_SAMPLE boundary encoded as >= 50 (50 active, 49 null).
        assert ">= 50" in projection
        assert "THEN 'active'" in projection
        assert "ELSE NULL" in projection
        assert "AS local_activity_band" in projection


def test_has_linked_event_surfaces_for_non_event_category(monkeypatch):
    rows = [
        _place_row(place_id="attraction-with-event", category="attraction", _has_linked_event=True),
        _place_row(place_id="restaurant-no-event", category="restaurant", _has_linked_event=False),
    ]
    captured = _install_fake_places_db(monkeypatch, rows)

    places = db_repository.fetch_places(
        lat=37.2, lng=127.0, radius_m=3000, category="all", language="ko"
    )

    by_id = {p["place_id"]: p for p in places}
    # A NON-event place with a linked event surfaces the flag (the LATERAL join is all-category).
    assert by_id["attraction-with-event"]["_has_linked_event"] is True
    assert by_id["restaurant-no-event"]["_has_linked_event"] is False
    # Derived from the existing LATERAL for ALL categories — bare IS NOT NULL, no category guard.
    assert "(linked_event.place_id IS NOT NULL) AS _has_linked_event" in captured["sql"]


def test_has_linked_event_does_not_widen_event_field_category_guard(monkeypatch):
    captured = _install_fake_places_db(monkeypatch, [_place_row()])

    db_repository.fetch_places(lat=37.2, lng=127.0, radius_m=3000, category="all", language="ko")
    sql = captured["sql"]

    # The four shared event_* fields stay category='event'-gated — unchanged by Lane 1
    # (zero blast radius into Flutter detail/evidence consumers).
    assert sql.count("ranked_places.category = 'event' AND linked_event.place_id IS NOT NULL") == 4
    # The new internal has_linked_event is projected for ALL categories: its line carries no
    # `ranked_places.category = 'event'` predicate (distinct from the gated event_* CASEs).
    assert "(linked_event.place_id IS NOT NULL) AS _has_linked_event" in sql


# ---------------------------------------------------------------------------
# V1 bounds query (Lane A) — viewport rectangle behind PLACES_VIEWPORT_BOUNDS.
# The rectangle reuses the existing lat/lng BETWEEN prefilter, re-sourced from
# the SW/NE corners, and DROPS the ST_DWithin circle + post-fetch radius gate
# (contract §3 B1 / §7 D2). Flag-off / bounds-absent keeps the circle path
# byte-for-byte (B2/B3).
# ---------------------------------------------------------------------------


def test_fetch_places_bounds_branch_drops_circle_when_flag_on(monkeypatch):
    # B1: flag on + all four bounds -> rectangle SQL (no ST_DWithin); 9 params
    # (radius_m dropped from the param list); min/max sourced directly from SW/NE.
    captured = _install_fake_places_db(monkeypatch, [_place_row()])
    monkeypatch.setenv("LALA_PLACES_VIEWPORT_BOUNDS", "true")

    db_repository.fetch_places(
        lat=37.0,
        lng=127.0,
        radius_m=3000,
        category="all",
        language="ko",
        sw_lat=36.5,
        sw_lng=126.5,
        ne_lat=37.5,
        ne_lng=127.5,
    )

    sql = captured["sql"]
    params = captured["params"]
    # Rectangle prefilter retained; circle predicate dropped.
    assert "AND lat BETWEEN %s AND %s" in sql
    assert "AND lng BETWEEN %s AND %s" in sql
    assert "ST_DWithin(" not in sql
    # ORDER BY / LIMIT unchanged (contract §6: cost ≤ today, cap preserved).
    assert "ORDER BY FLOOR(distance_m / 500.0) ASC" in sql
    assert "LIMIT %s" in sql
    # 9 params (radius_m absent); SW/NE feed the BETWEEN corners directly.
    assert len(params) == 9
    assert params[:4] == (127.0, 37.0, "all", "all")
    assert params[4:8] == (36.5, 37.5, 126.5, 127.5)
    assert params[-1] == 60


def test_fetch_places_bounds_branch_keeps_circle_when_flag_off(monkeypatch):
    # B3: flag off + bounds sent -> bounds IGNORED, the existing circle SQL runs.
    captured = _install_fake_places_db(monkeypatch, [_place_row()])
    monkeypatch.setenv("LALA_PLACES_VIEWPORT_BOUNDS", "false")

    db_repository.fetch_places(
        lat=37.0,
        lng=127.0,
        radius_m=3000,
        category="all",
        language="ko",
        sw_lat=36.5,
        sw_lng=126.5,
        ne_lat=37.5,
        ne_lng=127.5,
    )

    # Identical to the pre-change circle path: ST_DWithin present, 10 params
    # (radius_m + limit tail), bbox still from _coordinate_radius_bounds.
    assert "ST_DWithin(" in captured["sql"]
    assert len(captured["params"]) == 10
    assert captured["params"][-2:] == (3000, 60)


def test_fetch_places_bounds_branch_keeps_circle_when_bounds_absent(monkeypatch):
    # B2: flag on + no bounds -> circle path UNCHANGED.
    captured = _install_fake_places_db(monkeypatch, [_place_row()])
    monkeypatch.setenv("LALA_PLACES_VIEWPORT_BOUNDS", "true")

    db_repository.fetch_places(lat=37.0, lng=127.0, radius_m=3000, category="all", language="ko")

    assert "ST_DWithin(" in captured["sql"]
    assert len(captured["params"]) == 10
    assert captured["params"][-2:] == (3000, 60)


def test_fetch_places_bounds_branch_skips_radius_overshoot_gate(monkeypatch):
    # D2: in bounds mode a place farther than radius_m is NOT dropped (the
    # rectangle is the exact filter); the circle path still drops it post-fetch.
    far_row = _place_row(place_id="far", distance_m=9_000.0)  # > radius_m (3000)
    captured = _install_fake_places_db(monkeypatch, [far_row])

    # Bounds mode: retained despite distance_m > radius_m.
    monkeypatch.setenv("LALA_PLACES_VIEWPORT_BOUNDS", "true")
    places = db_repository.fetch_places(
        lat=37.0,
        lng=127.0,
        radius_m=3000,
        category="all",
        language="ko",
        sw_lat=36.0,
        sw_lng=126.0,
        ne_lat=38.0,
        ne_lng=128.0,
    )
    assert any(p["place_id"] == "far" for p in places)
    assert "ST_DWithin(" not in captured["sql"]

    # Circle mode: the post-fetch `distance_m > radius_m` gate drops the far row.
    monkeypatch.setenv("LALA_PLACES_VIEWPORT_BOUNDS", "false")
    places_circle = db_repository.fetch_places(
        lat=37.0,
        lng=127.0,
        radius_m=3000,
        category="all",
        language="ko",
    )
    assert all(p["place_id"] != "far" for p in places_circle)
    assert "ST_DWithin(" in captured["sql"]
