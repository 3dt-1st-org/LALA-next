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
            return (True, True, True, True)

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
    assert "to_regclass('travel.weather_observations')" in captured["sql"]
    assert "to_regclass('travel.docent_scripts')" in captured["sql"]
    assert "to_regclass('analytics.place_score_snapshots')" in captured["sql"]


def test_check_db_status_degrades_when_canonical_relation_is_missing(monkeypatch):
    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql):
            return None

        def fetchone(self):
            return (True, False, True, True)

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
                    "lat": 37.2,
                    "lng": 127.0,
                    "source": "canonical",
                    "updated_at": datetime.now(UTC),
                    "distance_m": 125.2,
                    "local_spending_score": 0.81,
                    "demand_dispersion_score": 0.72,
                    "weather_fit_score": 0.66,
                    "review_quality_score": None,
                    "culture_relevance_score": 0.88,
                    "final_score": 0.775,
                    "formula_version": "local-value-v1",
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
    )

    assert places[0]["place_id"] == "db-place-1"
    assert places[0]["distance_m"] == 125
    assert places[0]["source"] == "db"
    assert places[0]["score"] == {
        "final_score": 0.775,
        "formula_version": "local-value-v1",
        "components": {
            "local_spending_score": 0.81,
            "demand_dispersion_score": 0.72,
            "weather_fit_score": 0.66,
            "review_quality_score": None,
            "culture_relevance_score": 0.88,
        },
        "data_basis": "analytics.place_score_snapshots",
        "features": {"source": "unit-test"},
    }
    assert "FROM analytics.place_score_snapshots" in captured["sql"]
    assert "WHERE distance_m <= %s" in captured["sql"]
    assert "ORDER BY COALESCE(latest_scores.final_score, 0) DESC, distance_m ASC" in captured["sql"]
    assert captured["params"] == (37.2, 127.0, "all", "all", 3000)


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
    assert "WITH nearest_region AS" in captured["sql"]
    assert "ORDER BY location_match_rank ASC, w.record_time DESC" in captured["sql"]
    assert captured["params"] == (37.2, 127.0)


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


def test_remaining_ttl_sec_reports_future_expiry():
    ttl = db_repository._remaining_ttl_sec(datetime.now(UTC) + timedelta(seconds=90))

    assert 0 < ttl <= 90


def test_remaining_ttl_sec_clamps_expired_values():
    ttl = db_repository._remaining_ttl_sec(datetime.now(UTC) - timedelta(seconds=1))

    assert ttl == 0
