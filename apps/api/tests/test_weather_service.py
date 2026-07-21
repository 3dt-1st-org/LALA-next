from __future__ import annotations

import sys
import types
from datetime import datetime
from types import SimpleNamespace

import pytest

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


@pytest.mark.parametrize(
    ("lat", "lng", "expected"),
    [
        (37.5665, 126.9780, "서울"),
        (37.4563, 126.7052, "인천"),
        (35.1796, 129.0756, "부산"),
        (35.8714, 128.6014, "대구"),
        (35.1595, 126.8526, "광주"),
        (36.3504, 127.3845, "대전"),
        (35.5384, 129.3114, "울산"),
        (36.48, 127.289, "세종"),
        (37.2636, 127.0286, "경기"),
        (37.8813, 127.7298, "강원"),
        (36.6424, 127.4890, "충북"),
        (36.6012, 126.6608, "충남"),
        (35.8242, 127.1480, "전북"),
        (34.8118, 126.3922, "전남"),
        (36.5760, 128.5056, "경북"),
        (35.2278, 128.6811, "경남"),
        (33.4996, 126.5312, "제주"),
    ],
)
def test_sido_name_for_coordinate_covers_supported_provinces(
    lat: float,
    lng: float,
    expected: str,
) -> None:
    assert weather_service._sido_name_for_coordinate(lat=lat, lng=lng) == expected


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
        weather_service.db_repository,
        "fetch_nearest_region_labels",
        lambda **kwargs: ["수원시", "Suwon"],
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
    assert kma_request["timeout"] == weather_service.KMA_REQUEST_TIMEOUT_SECONDS
    assert airkorea_request["timeout"] == weather_service.AIRKOREA_REQUEST_TIMEOUT_SECONDS
    assert airkorea_request["params"]["sidoName"] == "경기"
    assert weather["source"] == f"{weather_service.KMA_SOURCE}+{weather_service.AIRKOREA_SOURCE}"
    assert weather["location"] == "종로구"
    assert weather["air_quality_location"] == "종로구"
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
        weather_service.db_repository,
        "fetch_nearest_region_labels",
        lambda **kwargs: [],
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


def test_current_weather_marks_bad_when_air_quality_is_bad(monkeypatch) -> None:
    official_weather = {
        "lat": 37.5665,
        "lng": 126.9780,
        "location": "기상청 격자",
        "temp": "21.4",
        "icon": "partly-cloudy",
        "dust": weather_service.unknown_dust_payload(),
        "forecast": [],
        "outdoor_status": "good",
        "force": False,
        "location_match": True,
        "record_time": "2026-06-21T12:00:00+09:00",
        "source": weather_service.KMA_SOURCE,
    }
    air_quality = {
        "sido_name": "서울",
        "location": "중랑구",
        "record_time": "2026-06-21 12:00",
        "dust": weather_service.build_dust_payload(pm10="121", pm25="48"),
    }
    monkeypatch.setattr(
        weather_service.db_repository,
        "fetch_latest_weather",
        lambda **kwargs: None,
    )
    monkeypatch.setattr(
        weather_service,
        "_fetch_official_weather_pair",
        lambda **kwargs: (official_weather, air_quality),
    )

    weather = weather_service.current_weather(lat=37.5665, lng=126.9780)

    assert weather["source"] == (f"{weather_service.KMA_SOURCE}+{weather_service.AIRKOREA_SOURCE}")
    assert weather["location"] == "중랑구"
    assert weather["dust"]["pm10_grade"] == "bad"
    assert weather["dust"]["pm25_grade"] == "bad"
    assert weather["outdoor_status"] == "bad"


def test_current_weather_merges_airkorea_into_db_weather(monkeypatch) -> None:
    weather_service.clear_official_weather_cache()
    db_weather = {
        "lat": 37.5665,
        "lng": 126.9780,
        "location": "기상청 격자",
        "temp": "24.8",
        "icon": "partly-cloudy",
        "dust": weather_service.unknown_dust_payload(),
        "forecast": [],
        "outdoor_status": "good",
        "force": False,
        "location_match": True,
        "record_time": "2026-06-21T20:00:00+09:00",
        "source": "db",
    }
    air_quality = {
        "sido_name": "서울",
        "location": "중구",
        "record_time": "2026-06-21 21:00",
        "dust": weather_service.build_dust_payload(
            pm10="9",
            pm25="3",
            pm10_grade="1",
            pm25_grade="1",
        ),
    }
    monkeypatch.setattr(
        weather_service.db_repository,
        "fetch_latest_weather",
        lambda **kwargs: dict(db_weather),
    )
    monkeypatch.setattr(
        weather_service,
        "_fetch_airkorea_sido_air_quality",
        lambda **kwargs: dict(air_quality),
    )

    weather = weather_service.current_weather(lat=37.5665, lng=126.9780)

    assert weather["source"] == f"db+{weather_service.AIRKOREA_SOURCE}"
    assert weather["location"] == "중구"
    assert weather["air_quality_location"] == "중구"
    assert weather["air_quality_record_time"] == "2026-06-21 21:00"
    assert weather["dust"]["pm10"] == "9"
    assert weather["dust"]["pm25"] == "3"
    assert weather["dust"]["pm10_grade"] == "good"
    assert weather["dust"]["pm25_grade"] == "good"


def test_current_weather_refreshes_airkorea_even_when_db_has_dust_values(
    monkeypatch,
) -> None:
    db_weather = {
        "lat": 37.5665,
        "lng": 126.9780,
        "location": "기상청 격자",
        "temp": "24.8",
        "icon": "partly-cloudy",
        "dust": weather_service.build_dust_payload(
            pm10="99",
            pm25="44",
            pm10_grade="3",
            pm25_grade="3",
        ),
        "forecast": [],
        "outdoor_status": "bad",
        "force": False,
        "location_match": True,
        "record_time": "2026-06-21T20:00:00+09:00",
        "source": "db",
    }
    air_quality = {
        "sido_name": "서울",
        "location": "중구",
        "record_time": "2026-06-21 21:00",
        "dust": weather_service.build_dust_payload(
            pm10="8",
            pm25="3",
            pm10_grade="1",
            pm25_grade="1",
        ),
    }
    monkeypatch.setattr(
        weather_service.db_repository,
        "fetch_latest_weather",
        lambda **kwargs: dict(db_weather),
    )
    monkeypatch.setattr(
        weather_service,
        "_fetch_airkorea_sido_air_quality",
        lambda **kwargs: dict(air_quality),
    )

    weather = weather_service.current_weather(lat=37.5665, lng=126.9780)

    assert weather["source"] == f"db+{weather_service.AIRKOREA_SOURCE}"
    assert weather["location"] == "중구"
    assert weather["air_quality_location"] == "중구"
    assert weather["air_quality_record_time"] == "2026-06-21 21:00"
    assert weather["dust"]["pm10"] == "8"
    assert weather["dust"]["pm25"] == "3"
    assert weather["dust"]["pm10_grade"] == "good"
    assert weather["dust"]["pm25_grade"] == "good"


def test_airkorea_selection_prefers_station_with_pm10_and_pm25() -> None:
    selected = weather_service._select_airkorea_item(
        [
            {
                "stationName": "중구",
                "pm10Value": "5",
                "pm25Value": "-",
            },
            {
                "stationName": "종로구",
                "pm10Value": "7",
                "pm25Value": "2",
            },
            {
                "stationName": "용산구",
                "pm10Value": "-",
                "pm25Value": "3",
            },
        ]
    )

    assert selected is not None
    assert selected["stationName"] == "종로구"


def test_airkorea_selection_prefers_matching_nearby_station_when_complete() -> None:
    selected = weather_service._select_airkorea_item(
        [
            {
                "stationName": "종로구",
                "pm10Value": "7",
                "pm25Value": "2",
            },
            {
                "stationName": "중랑구",
                "pm10Value": "31",
                "pm25Value": "14",
            },
        ],
        preferred_station_names=["중랑구", "Jungnang-gu"],
    )

    assert selected is not None
    assert selected["stationName"] == "중랑구"


def test_airkorea_selection_keeps_split_dust_before_matching_partial() -> None:
    selected = weather_service._select_airkorea_item(
        [
            {
                "stationName": "중랑구",
                "pm10Value": "31",
                "pm25Value": "-",
            },
            {
                "stationName": "종로구",
                "pm10Value": "7",
                "pm25Value": "2",
            },
        ],
        preferred_station_names=["중랑구"],
    )

    assert selected is not None
    assert selected["stationName"] == "종로구"
