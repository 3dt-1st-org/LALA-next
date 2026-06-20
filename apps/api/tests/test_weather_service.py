from __future__ import annotations

import sys
import types
from datetime import datetime
from types import SimpleNamespace

from apps.api.app.services import weather_service


def test_kma_grid_xy_converts_suwon_coordinate() -> None:
    assert weather_service._kma_grid_xy(37.2636, 127.0286) == (61, 120)


def test_latest_kma_base_time_uses_previous_hour_before_publish_window() -> None:
    before_publish = datetime(2026, 6, 19, 0, 22, tzinfo=weather_service.KST)
    after_publish = datetime(2026, 6, 19, 0, 46, tzinfo=weather_service.KST)

    assert (
        weather_service._latest_kma_base_time(before_publish).strftime("%Y%m%d%H%M")
        == "202606182300"
    )
    assert (
        weather_service._latest_kma_base_time(after_publish).strftime("%Y%m%d%H%M")
        == "202606190000"
    )


def test_current_weather_uses_kma_nowcast_when_db_is_empty(monkeypatch) -> None:
    weather_service.clear_official_weather_cache()
    captured: list[dict[str, object]] = []

    class FakeKmaResponse:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict:
            return {
                "response": {
                    "header": {"resultCode": "00", "resultMsg": "NORMAL_SERVICE"},
                    "body": {
                        "items": {
                            "item": [
                                {"category": "PTY", "obsrValue": "0"},
                                {"category": "T1H", "obsrValue": "22.3"},
                                {"category": "REH", "obsrValue": "68"},
                                {"category": "WSD", "obsrValue": "0.3"},
                            ]
                        }
                    },
                }
            }

    class FakeAirKoreaResponse:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict:
            return {
                "response": {
                    "header": {"resultCode": "00", "resultMsg": "NORMAL_CODE"},
                    "body": {
                        "items": [
                            {
                                "stationName": "종로구",
                                "dataTime": "2026-06-18 23:00",
                                "pm10Value": "31",
                                "pm25Value": "14",
                                "pm10Grade": "2",
                                "pm25Grade": "2",
                            }
                        ]
                    },
                }
            }

    def fake_get(url, *, params, timeout):
        captured.append({"url": url, "params": params, "timeout": timeout})
        if url == weather_service.KMA_ULTRA_SHORT_NOWCAST_URL:
            return FakeKmaResponse()
        return FakeAirKoreaResponse()

    fake_requests = types.ModuleType("requests")
    fake_requests.get = fake_get
    monkeypatch.setitem(sys.modules, "requests", fake_requests)
    monkeypatch.setattr(
        weather_service.db_repository, "fetch_latest_weather", lambda **kwargs: None
    )
    monkeypatch.setattr(
        weather_service,
        "get_settings",
        lambda: SimpleNamespace(public_data_service_key="public-data-secret"),
    )
    monkeypatch.setattr(
        weather_service,
        "_latest_kma_base_time",
        lambda: datetime(2026, 6, 18, 23, 0, tzinfo=weather_service.KST),
    )

    weather = weather_service.current_weather(lat=37.2636, lng=127.0286)

    captured_by_url = {item["url"]: item for item in captured}
    kma_request = captured_by_url[weather_service.KMA_ULTRA_SHORT_NOWCAST_URL]
    airkorea_request = captured_by_url[weather_service.AIRKOREA_SIDO_REALTIME_URL]
    assert kma_request["params"] == {
        "serviceKey": "public-data-secret",
        "pageNo": 1,
        "numOfRows": 100,
        "dataType": "JSON",
        "base_date": "20260618",
        "base_time": "2300",
        "nx": 61,
        "ny": 120,
    }
    assert kma_request["timeout"] == 3
    assert airkorea_request["params"]["sidoName"] == "경기"
    assert (
        weather["source"]
        == f"{weather_service.KMA_SOURCE}+{weather_service.AIRKOREA_SOURCE}"
    )
    assert weather["temp"] == "22.3"
    assert weather["icon"] == "partly-cloudy"
    assert weather["outdoor_status"] == "good"
    assert weather["dust"] == {
        "pm10": "31",
        "pm25": "14",
        "grade": "normal",
        "grade_ko": "보통",
        "pm10_grade": "normal",
        "pm10_grade_ko": "보통",
        "pm25_grade": "normal",
        "pm25_grade_ko": "보통",
    }
    assert weather["record_time"] == "2026-06-18T23:00:00+09:00"
    assert len(weather["forecast"]) == 4

    cached_weather = weather_service.current_weather(lat=37.2636, lng=127.0286)

    assert cached_weather["source"] == weather["source"]
    assert cached_weather["dust"] == weather["dust"]
    assert len(captured) == 2


def test_current_weather_reports_unavailable_without_public_data_key(
    monkeypatch,
) -> None:
    weather_service.clear_official_weather_cache()
    monkeypatch.setattr(
        weather_service.db_repository, "fetch_latest_weather", lambda **kwargs: None
    )
    monkeypatch.setattr(
        weather_service,
        "get_settings",
        lambda: SimpleNamespace(public_data_service_key=""),
    )

    weather = weather_service.current_weather(lat=37.2636, lng=127.0286)

    assert weather["source"] == "unavailable"
    assert weather["temp"] == ""
    assert weather["forecast"] == []
    assert weather["dust"]["pm10_grade"] == "unknown"
    assert weather["dust"]["pm25_grade_ko"] == "확인 중"
