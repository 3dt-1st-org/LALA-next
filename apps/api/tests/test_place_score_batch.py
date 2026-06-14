from __future__ import annotations

import json

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
    assert attraction.weather_fit_score == 0.85
    assert attraction.review_quality_score is None
    assert attraction.culture_relevance_score == 0.91
    assert attraction.features["input_sources"] == [
        "travel.places",
        "economy.card_spending_area_monthly",
        "culture.events",
        "travel.place_events",
        "travel.weather_observations",
    ]
    assert indoor.local_spending_score == 0.35
    assert indoor.demand_dispersion_score > attraction.demand_dispersion_score
    assert indoor.weather_fit_score == 0.9
    assert 0 < indoor.final_score <= 1


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
