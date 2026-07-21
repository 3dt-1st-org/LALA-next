from __future__ import annotations

import json
import sys
from datetime import UTC, datetime
from types import SimpleNamespace

from apps.api.app.services import weather_observation_refresh
from apps.api.app.tools import run_weather_observation_refresh


def test_weather_refresh_plan_is_guarded_without_live_call(capsys):
    exit_code = run_weather_observation_refresh.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["live_api_call"] is False
    assert payload["db_mutation"] is False
    assert payload["target"] == "travel.weather_observations"
    assert payload["job_name"] == "weather-refresh"
    assert payload["required_env"] == ["PUBLIC_DATA_SERVICE_KEY"]
    assert payload["apply_required_env"] == ["DB_DSN"]


def test_build_weather_observation_maps_kma_airkorea_flags():
    target = weather_observation_refresh.WeatherTarget(
        location_name="수원시",
        lat=37.2636,
        lng=127.0286,
        place_count=25,
    )

    observation = weather_observation_refresh.build_weather_observation(
        target=target,
        official_weather={
            "temp": "24.5",
            "icon": "rain",
            "record_time": "2026-06-23T10:00:00+09:00",
            "source": "kma_ultra_srt_ncst",
            "outdoor_status": "rain",
        },
        air_quality={
            "record_time": "2026-06-23 10:00",
            "dust": {
                "pm10": "82",
                "pm25": "22",
                "pm10_grade": "bad",
                "pm25_grade": "normal",
            },
        },
        collected_at=datetime(2026, 6, 23, 1, 5, tzinfo=UTC),
    )

    assert observation is not None
    assert observation.location_name == "수원시"
    assert observation.temperature_c == 24.5
    assert observation.precipitation_type == "rain"
    assert observation.pm10 == 82
    assert observation.pm25 == 22
    assert observation.is_rain_snow is True
    assert observation.is_bad_dust is True
    assert observation.is_heatwave is False
    assert observation.observed_at == datetime(2026, 6, 23, 1, 0, tzinfo=UTC)
    assert "kma_ultra_srt_ncst" in observation.source_summary
    assert "airkorea" in observation.source_summary


def test_insert_weather_observations_uses_location_observed_idempotency(monkeypatch):
    executed = []
    rowcounts = [1, 0]

    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))
            self.rowcount = rowcounts.pop(0)

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

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))
    observations = (
        weather_observation_refresh.WeatherObservation(
            location_name="수원시",
            temperature_c=24.5,
            precipitation_type="rain",
            pm10=82,
            pm25=22,
            is_rain_snow=True,
            is_bad_dust=True,
            is_heatwave=False,
            is_coldwave=False,
            is_strong_wind=False,
            observed_at=datetime(2026, 6, 23, 1, 0, tzinfo=UTC),
            collected_at=datetime(2026, 6, 23, 1, 5, tzinfo=UTC),
            source_summary="test",
        ),
        weather_observation_refresh.WeatherObservation(
            location_name="서울시",
            temperature_c=25,
            precipitation_type="partly-cloudy",
            pm10=31,
            pm25=13,
            is_rain_snow=False,
            is_bad_dust=False,
            is_heatwave=False,
            is_coldwave=False,
            is_strong_wind=False,
            observed_at=datetime(2026, 6, 23, 1, 0, tzinfo=UTC),
            collected_at=datetime(2026, 6, 23, 1, 5, tzinfo=UTC),
            source_summary="test",
        ),
    )

    inserted = weather_observation_refresh.insert_weather_observations(
        dsn="postgresql://redacted",
        observations=observations,
        connect_timeout=7,
    )

    assert inserted == 1
    assert executed[0] == (
        "connect",
        {"dsn": "postgresql://redacted", "connect_timeout": 7},
    )
    assert "INSERT INTO travel.weather_observations" in executed[1][0]
    assert "WHERE NOT EXISTS" in executed[1][0]
    assert "location_name = %(location_name)s" in executed[1][0]
    assert "observed_at = %(observed_at)s" in executed[1][0]
    assert executed[-1] == ("commit", None)


def test_weather_apply_requires_guard_before_live_calls(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("PUBLIC_DATA_SERVICE_KEY", "public-data-secret")
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.delenv(run_weather_observation_refresh.ALLOW_ENV, raising=False)

    def fail_fetch(**kwargs):
        raise AssertionError("fetch should not be called before guard passes")

    monkeypatch.setattr(run_weather_observation_refresh, "fetch_weather_targets", fail_fetch)

    exit_code = run_weather_observation_refresh.main(
        ["--apply", "--confirm", run_weather_observation_refresh.CONFIRM_TEXT]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_weather_observation_refresh.ALLOW_ENV in output
    assert dsn not in output
    assert password not in output
    assert "public-data-secret" not in output


def test_weather_apply_records_job_run(monkeypatch, capsys):
    monkeypatch.setenv("PUBLIC_DATA_SERVICE_KEY", "public-data-secret")
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(run_weather_observation_refresh.ALLOW_ENV, "1")
    target = weather_observation_refresh.WeatherTarget(
        location_name="수원시",
        lat=37.2636,
        lng=127.0286,
        place_count=25,
    )
    observation = weather_observation_refresh.WeatherObservation(
        location_name="수원시",
        temperature_c=24.5,
        precipitation_type="partly-cloudy",
        pm10=31,
        pm25=13,
        is_rain_snow=False,
        is_bad_dust=False,
        is_heatwave=False,
        is_coldwave=False,
        is_strong_wind=False,
        observed_at=datetime(2026, 6, 23, 1, 0, tzinfo=UTC),
        collected_at=datetime(2026, 6, 23, 1, 5, tzinfo=UTC),
        source_summary="test",
    )
    recorded = []

    monkeypatch.setattr(
        run_weather_observation_refresh,
        "fetch_weather_targets",
        lambda **kwargs: [target],
    )
    monkeypatch.setattr(
        run_weather_observation_refresh,
        "fetch_weather_observations",
        lambda targets: (observation,),
    )
    monkeypatch.setattr(
        run_weather_observation_refresh,
        "insert_weather_observations",
        lambda **kwargs: 1,
    )
    monkeypatch.setattr(
        run_weather_observation_refresh,
        "record_job_run",
        lambda **kwargs: recorded.append(kwargs),
    )

    exit_code = run_weather_observation_refresh.main(
        [
            "--json",
            "--apply",
            "--confirm",
            run_weather_observation_refresh.CONFIRM_TEXT,
            "--limit",
            "1",
        ]
    )
    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "apply"
    assert payload["db_mutation"] is True
    assert payload["job_run_recorded"] is True
    assert payload["result"]["inserted_rows"] == 1
    assert recorded[0]["job_name"] == "weather-refresh"
    assert recorded[0]["status"] == "succeeded"
