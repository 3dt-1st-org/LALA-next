from __future__ import annotations

import sys
import types
from datetime import UTC, datetime, timedelta

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
