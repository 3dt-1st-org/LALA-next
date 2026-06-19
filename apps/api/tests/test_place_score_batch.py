from __future__ import annotations

import json
import sys
import types

from apps.api.app.services import place_score_batch
from apps.api.app.tools import run_place_score_batch


def test_place_score_batch_plan_uses_data_dictionary_names(capsys):
    exit_code = run_place_score_batch.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["target"] == "analytics.place_score_snapshots"
    assert "economy.card_spending_area_monthly" in payload["input_relations"]
    assert "culture.events" in payload["input_relations"]
    assert "analytics.place_business_identity" in payload["input_relations"]
    assert payload["db_mutation"] is False


def test_compute_score_snapshots_combines_card_weather_and_culture_signals():
    signals = [
        place_score_batch.PlaceSignal(
            place_id="popular-attraction",
            name_ko="인기 명소",
            category="attraction",
            region_name_ko="수원시",
            is_indoor=False,
            primary_source="tour_api",
            region_spend_amount=900_000,
            region_transaction_count=120,
            card_month="2026-05-01",
            region_place_count=10,
            culture_event_count=4,
            place_event_count=1,
            business_identity_type="unknown",
            small_merchant_fit_score=0.55,
            is_rain_snow=False,
            is_bad_dust=False,
            is_heatwave=False,
            is_coldwave=False,
            is_strong_wind=False,
        ),
        place_score_batch.PlaceSignal(
            place_id="quiet-indoor",
            name_ko="조용한 전시관",
            category="culture_venue",
            region_name_ko="여주시",
            is_indoor=True,
            primary_source="kcisa",
            region_spend_amount=300_000,
            region_transaction_count=40,
            card_month="2026-05-01",
            region_place_count=2,
            culture_event_count=1,
            place_event_count=0,
            business_identity_type="local_small_chain",
            franchise_brand_name="동네전시",
            franchise_match_confidence=0.82,
            chain_scale_score=0.2,
            small_merchant_fit_score=0.76,
            is_rain_snow=True,
            is_bad_dust=False,
            is_heatwave=False,
            is_coldwave=False,
            is_strong_wind=False,
        ),
    ]

    snapshots = place_score_batch.compute_score_snapshots(signals)

    attraction = snapshots[0]
    indoor = snapshots[1]
    assert attraction.local_spending_score == 0.95
    assert attraction.small_merchant_fit_score == 0.55
    assert attraction.weather_fit_score == 0.85
    assert attraction.review_quality_score is None
    assert attraction.culture_relevance_score == 0.91
    assert attraction.accessibility_fit_score == 0.68
    assert attraction.features["input_sources"] == [
        "travel.places",
        "economy.card_spending_area_monthly",
        "culture.events",
        "travel.place_events",
        "analytics.place_business_identity",
        "travel.weather_observations",
    ]
    assert indoor.local_spending_score == 0.35
    assert indoor.demand_dispersion_score > attraction.demand_dispersion_score
    assert indoor.weather_fit_score == 0.9
    assert indoor.small_merchant_fit_score == 0.76
    assert 0 < indoor.final_score <= 1


def test_fetch_place_signals_uses_null_identity_when_relation_is_missing(monkeypatch):
    captured = _install_fake_signal_db(monkeypatch, business_identity_exists=False)

    signals = place_score_batch.fetch_place_signals(
        dsn="postgresql://db.example/lala",
        category="restaurant",
        limit=20,
        connect_timeout=3,
    )

    assert signals[0].small_merchant_fit_score is None
    assert "NULL::text AS business_identity_type" in captured["sql"]
    assert "LEFT JOIN analytics.place_business_identity" not in captured["sql"]


def test_fetch_place_signals_joins_identity_when_relation_exists(monkeypatch):
    captured = _install_fake_signal_db(monkeypatch, business_identity_exists=True)

    signals = place_score_batch.fetch_place_signals(
        dsn="postgresql://db.example/lala",
        category="restaurant",
        limit=20,
        connect_timeout=3,
    )

    assert signals[0].business_identity_type == "local_small_chain"
    assert signals[0].small_merchant_fit_score == 0.76
    assert "LEFT JOIN analytics.place_business_identity" in captured["sql"]


def test_apply_requires_guard_before_reading_db(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.delenv(run_place_score_batch.ALLOW_ENV, raising=False)

    exit_code = run_place_score_batch.main(
        ["--apply", "--confirm", run_place_score_batch.CONFIRM_TEXT]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_place_score_batch.ALLOW_ENV in output
    assert dsn not in output
    assert password not in output


def _install_fake_signal_db(monkeypatch, *, business_identity_exists: bool) -> dict:
    captured: dict[str, object] = {}

    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql, params=None):
            if "to_regclass" in sql:
                captured["relation_check"] = params
                self.last_operation = "relation_check"
                return
            captured["sql"] = sql
            captured["params"] = params
            self.last_operation = "signals"

        def fetchone(self):
            return {"exists": business_identity_exists}

        def fetchall(self):
            return [
                {
                    "place_id": "restaurant-1",
                    "name_ko": "동네국수",
                    "category": "restaurant",
                    "region_name_ko": "수원시",
                    "is_indoor": False,
                    "primary_source": "tour_api",
                    "region_spend_amount": 100000,
                    "region_transaction_count": 10,
                    "card_month": "2026-05-01",
                    "region_place_count": 5,
                    "culture_event_count": 0,
                    "place_event_count": 0,
                    "business_identity_type": (
                        "local_small_chain" if business_identity_exists else None
                    ),
                    "is_franchise": business_identity_exists,
                    "franchise_brand_name": "동네국수" if business_identity_exists else None,
                    "franchise_match_confidence": 0.82 if business_identity_exists else None,
                    "chain_scale_score": 0.2 if business_identity_exists else None,
                    "small_merchant_fit_score": 0.76 if business_identity_exists else None,
                    "is_rain_snow": False,
                    "is_bad_dust": False,
                    "is_heatwave": False,
                    "is_coldwave": False,
                    "is_strong_wind": False,
                }
            ]

    class FakeConnection:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def cursor(self, cursor_factory=None):
            captured["cursor_factory"] = cursor_factory
            return FakeCursor()

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    extras_module = types.ModuleType("psycopg2.extras")
    extras_module.RealDictCursor = object()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)
    monkeypatch.setitem(sys.modules, "psycopg2.extras", extras_module)
    return captured


def test_preview_redacts_dsn_on_execution_error(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)

    def fail(**kwargs):
        raise RuntimeError(f"connection failed for {dsn} password={password}")

    monkeypatch.setattr(run_place_score_batch, "fetch_place_signals", fail)

    exit_code = run_place_score_batch.main(["--preview"])

    output = capsys.readouterr().out
    assert exit_code == 2
    assert "[redacted]" in output
    assert dsn not in output
    assert password not in output
