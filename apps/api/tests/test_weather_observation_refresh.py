from __future__ import annotations

import json
from datetime import datetime

from apps.api.app.services import weather_observation_refresh
from apps.api.app.tools import run_weather_observation_refresh


def test_weather_observation_refresh_plan_is_non_mutating(capsys):
    exit_code = run_weather_observation_refresh.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["live_api_call"] is False
    assert payload["db_mutation"] is False
    assert payload["target"] == "travel.weather_observations"
    assert payload["required_env"] == ["PUBLIC_DATA_SERVICE_KEY"]
    assert payload["apply_required_env"] == ["DB_DSN"]


def test_parse_refresh_target_uses_named_coordinate():
    target = weather_observation_refresh.parse_refresh_target("수원시=37.2636,127.0286")

    assert target.location_name == "수원시"
    assert target.lat == 37.2636
    assert target.lng == 127.0286


def test_weather_payload_to_observation_maps_public_weather_fields():
    target = weather_observation_refresh.WeatherRefreshTarget(
        location_name="수원시",
        lat=37.2636,
        lng=127.0286,
    )

    observation = weather_observation_refresh.weather_payload_to_observation(
        {
            "source": "kma_ultra_srt_ncst+airkorea_sido_realtime",
            "temp": "34.2",
            "icon": "rain",
            "record_time": "2026-06-22T09:00:00+09:00",
            "dust": {
                "pm10": "82",
                "pm25": "22",
                "grade": "bad",
                "pm10_grade": "bad",
                "pm25_grade": "normal",
            },
        },
        target=target,
    )

    assert observation is not None
    assert observation.location_name == "수원시"
    assert observation.temperature_c == 34.2
    assert observation.precipitation_type == "rain"
    assert observation.pm10 == 82.0
    assert observation.pm25 == 22.0
    assert observation.is_rain_snow is True
    assert observation.is_bad_dust is True
    assert observation.is_heatwave is True
    assert observation.is_coldwave is False
    assert observation.observed_at.isoformat() == "2026-06-22T09:00:00+09:00"


def test_refresh_weather_observations_collects_live_observations(monkeypatch):
    target = weather_observation_refresh.WeatherRefreshTarget(
        location_name="서울",
        lat=37.5665,
        lng=126.9780,
    )

    def fake_live_weather(**kwargs):
        assert kwargs["force"] is True
        return {
            "source": "airkorea_sido_realtime",
            "temp": "",
            "icon": "unavailable",
            "record_time": "2026-06-22 09:00",
            "dust": {"pm10": "11", "pm25": "4", "grade": "good"},
        }

    monkeypatch.setattr(
        weather_observation_refresh.weather_service,
        "fetch_live_weather",
        fake_live_weather,
    )

    result = weather_observation_refresh.refresh_weather_observations(
        targets=[target],
        force=True,
    )

    assert len(result.observations) == 1
    assert result.observations[0].location_name == "서울"
    assert result.observations[0].pm10 == 11.0
    assert result.skipped_targets == ()


def test_apply_requires_guard_before_refreshing_weather(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "host=example.postgres.database.azure.com user=user password=" + password
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.delenv(run_weather_observation_refresh.ALLOW_ENV, raising=False)

    def fail_refresh(**kwargs):
        raise AssertionError("refresh should not run before apply guard passes")

    monkeypatch.setattr(run_weather_observation_refresh, "refresh_weather_observations", fail_refresh)

    exit_code = run_weather_observation_refresh.main(
        [
            "--apply",
            "--confirm",
            run_weather_observation_refresh.CONFIRM_TEXT,
            "--target",
            "수원시=37.2636,127.0286",
        ]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_weather_observation_refresh.ALLOW_ENV in output
    assert dsn not in output
    assert password not in output


def test_upsert_weather_observations_inserts_only_new_rows(monkeypatch):
    observation = weather_observation_refresh.WeatherObservation(
        location_name="수원시",
        temperature_c=22.5,
        precipitation_type="none",
        pm10=31.0,
        pm25=12.0,
        is_rain_snow=False,
        is_bad_dust=False,
        is_heatwave=False,
        is_coldwave=False,
        is_strong_wind=False,
        observed_at=datetime.fromisoformat("2026-06-22T09:00:00+09:00"),
        source="kma_ultra_srt_ncst+airkorea_sido_realtime",
    )
    result = weather_observation_refresh.WeatherRefreshResult(
        targets=(
            weather_observation_refresh.WeatherRefreshTarget("수원시", 37.2636, 127.0286),
        ),
        observations=(observation,),
        skipped_targets=(),
    )
    captured: dict[str, object] = {"execute_count": 0}

    class FakeCursor:
        rowcount = 1

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql, params=None):
            captured["sql"] = sql
            captured["params"] = params
            captured["execute_count"] = int(captured["execute_count"]) + 1

    class FakeConnection:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def cursor(self):
            return FakeCursor()

        def commit(self):
            captured["committed"] = True

        def close(self):
            captured["closed"] = True

    class FakePsycopg2:
        @staticmethod
        def connect(dsn, connect_timeout):
            captured["dsn"] = dsn
            captured["connect_timeout"] = connect_timeout
            return FakeConnection()

    monkeypatch.setitem(__import__("sys").modules, "psycopg2", FakePsycopg2)

    apply_result = weather_observation_refresh.upsert_weather_observations(
        dsn="host=db.example dbname=lala",
        result=result,
        connect_timeout=3,
    )

    assert apply_result == {"inserted_rows": 1, "skipped_duplicate_rows": 0}
    assert captured["execute_count"] == 1
    assert "travel.weather_observations" in str(captured["sql"])
    assert captured["params"]["location_name"] == "수원시"
    assert captured["committed"] is True
