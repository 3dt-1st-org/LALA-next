from __future__ import annotations

import pytest

from apps.api.app.schemas.planner import DailyPlanRequest
from apps.api.app.services import planner_service


@pytest.mark.parametrize(
    ("place_source", "weather_source", "expected"),
    [
        ("db", "db", "db"),
        ("public_mvp_snapshot", "public_mvp_snapshot", "public_mvp_snapshot"),
        ("db", "unavailable", "mixed"),
        ("unavailable", "db", "mixed"),
        ("db", "public_mvp_snapshot", "mixed"),
        ("public_mvp_snapshot", "unavailable", "mixed"),
        (None, "db", "mixed"),
        ("db", None, "mixed"),
        (None, "public_mvp_snapshot", "mixed"),
        (None, None, "unavailable"),
        ("unavailable", "unavailable", "unavailable"),
        # Neither db nor public_mvp_snapshot collapses to unavailable.
        ("kma+airkorea", "kma+airkorea", "unavailable"),
    ],
)
def test_combined_source_applies_mixing_rules(
    place_source: str | None,
    weather_source: str | None,
    expected: str,
) -> None:
    assert planner_service._combined_source(place_source, weather_source) == expected


@pytest.mark.parametrize(
    ("weather_status", "expected_reason", "expected_action"),
    [
        (
            "good",
            "Weather is suitable, so keep the current route toward 한강공원.",
            "Keep 한강공원 as the primary local stop.",
        ),
        (
            "unknown",
            "Weather data is still pending, so keep 한강공원 as the current option.",
            "Keep 한강공원 while weather data is pending.",
        ),
        (
            "bad",
            "Weather is not ideal; prioritize short-walk or indoor-friendly "
            "options near 한강공원.",
            "Show indoor or short-walk alternatives around 한강공원.",
        ),
        # Any status outside good/unknown hits the not-ideal fallback branch.
        (
            "severe",
            "Weather is not ideal; prioritize short-walk or indoor-friendly "
            "options near 한강공원.",
            "Show indoor or short-walk alternatives around 한강공원.",
        ),
    ],
)
def test_intervention_messaging_branches_on_weather_status(
    weather_status: str,
    expected_reason: str,
    expected_action: str,
) -> None:
    reason = planner_service._intervention_reason(
        weather_status=weather_status,
        candidate_name="한강공원",
    )
    action = planner_service._recommended_action(
        weather_status=weather_status,
        candidate_name="한강공원",
    )

    assert reason == expected_reason
    assert action == expected_action


@pytest.mark.parametrize(
    ("language", "place_candidates", "expected_periods", "expected_titles"),
    [
        ("ko", [], ["afternoon"], ["날씨에 맞춰 조정"]),
        ("en", [], ["afternoon"], ["Adjust by weather"]),
        (
            "ko",
            [{"name": "경복궁"}],
            ["morning", "afternoon"],
            ["첫 장소 추천", "날씨에 맞춰 조정"],
        ),
        (
            "en",
            [{"name": "Gyeongbokgung"}],
            ["morning", "afternoon"],
            ["Start near a landmark", "Adjust by weather"],
        ),
    ],
)
def test_daily_plan_slots_shape_by_language_and_candidates(
    language: str,
    place_candidates: list[dict],
    expected_periods: list[str],
    expected_titles: list[str],
) -> None:
    weather = {"outdoor_status": "good"}

    slots = planner_service._daily_plan_slots(
        place_candidates=place_candidates,
        weather=weather,
        language=language,
    )

    assert [slot["period"] for slot in slots] == expected_periods
    assert [slot["title"] for slot in slots] == expected_titles
    assert slots[-1] == {
        "period": "afternoon",
        "title": expected_titles[-1],
        "weather_hint": "good",
    }
    if place_candidates:
        assert slots[0]["place"] == place_candidates[0]


def test_daily_plan_identity_emits_hash_and_cache_key() -> None:
    request = DailyPlanRequest(lat=37.5665, lng=126.978, radius_m=3000, language="ko")

    identity = planner_service.daily_plan_identity(request, language="ko")

    assert len(identity["request_hash"]) == 64
    assert all(char in "0123456789abcdef" for char in identity["request_hash"])
    assert identity["cache_key"] == f"daily_plan:{identity['request_hash'][:32]}"


def test_daily_plan_identity_differs_by_language() -> None:
    request = DailyPlanRequest(lat=37.5665, lng=126.978, radius_m=3000, language="ko")

    ko_identity = planner_service.daily_plan_identity(request, language="ko")
    en_identity = planner_service.daily_plan_identity(request, language="en")

    assert ko_identity["request_hash"] != en_identity["request_hash"]
    assert ko_identity["cache_key"] != en_identity["cache_key"]


def test_daily_plan_identity_reflects_location_and_radius() -> None:
    base = DailyPlanRequest(lat=37.5665, lng=126.978, radius_m=3000, language="ko")
    other_location = DailyPlanRequest(lat=35.1796, lng=129.0756, radius_m=3000, language="ko")
    other_radius = DailyPlanRequest(lat=37.5665, lng=126.978, radius_m=5000, language="ko")

    base_identity = planner_service.daily_plan_identity(base, language="ko")

    assert (
        planner_service.daily_plan_identity(other_location, language="ko")
        != base_identity
    )
    assert (
        planner_service.daily_plan_identity(other_radius, language="ko") != base_identity
    )


def test_daily_plan_identity_language_none_falls_back_to_request_language() -> None:
    request = DailyPlanRequest(lat=37.5665, lng=126.978, radius_m=3000, language="en")

    fallback = planner_service.daily_plan_identity(request, language=None)
    explicit = planner_service.daily_plan_identity(request, language="en")

    assert fallback == explicit


def test_daily_plan_identity_is_deterministic() -> None:
    request = DailyPlanRequest(lat=37.2636, lng=127.0286, radius_m=5000, language="ko")

    first = planner_service.daily_plan_identity(request, language="ko")
    second = planner_service.daily_plan_identity(request, language="ko")

    assert first == second


def test_daily_plan_combines_weather_and_places_with_correct_sources(
    monkeypatch,
) -> None:
    captured: dict[str, object] = {}
    weather = {
        "source": "db",
        "outdoor_status": "good",
        "temp": "21.4",
        "location": "서울",
    }
    places = {
        "source": "db",
        "places": [{"name": "경복궁", "category": "landmark"}],
    }

    def fake_current_weather(*, lat: float, lng: float) -> dict:
        captured["weather"] = {"lat": lat, "lng": lng}
        return weather

    def fake_list_places(**kwargs: object) -> dict:
        captured["places"] = kwargs
        return places

    monkeypatch.setattr(planner_service, "current_weather", fake_current_weather)
    monkeypatch.setattr(planner_service, "list_places", fake_list_places)

    request = DailyPlanRequest(lat=37.5665, lng=126.978, radius_m=3000, language="ko")
    plan = planner_service.daily_plan(request)

    assert plan["language"] == "ko"
    assert plan["center"] == {"lat": 37.5665, "lng": 126.978}
    assert plan["radius_m"] == 3000
    assert plan["weather"] == weather
    assert plan["source"] == "db"
    assert captured["weather"] == {"lat": 37.5665, "lng": 126.978}
    assert captured["places"] == {
        "lat": 37.5665,
        "lng": 126.978,
        "radius_m": 3000,
        "category": "all",
        "language": "ko",
    }
    assert [slot["period"] for slot in plan["slots"]] == ["morning", "afternoon"]
    assert plan["slots"][0]["place"] == {"name": "경복궁", "category": "landmark"}
    assert plan["slots"][1]["weather_hint"] == "good"
    assert (
        plan["request_hash"]
        == planner_service.daily_plan_identity(request, language="ko")["request_hash"]
    )
    assert plan["cache_key"].startswith("daily_plan:")


def test_daily_plan_normalizes_language_and_translates_slots(monkeypatch) -> None:
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kwargs: {"source": "db", "outdoor_status": "bad"},
    )
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kwargs: {"source": "db", "places": [{"name": "Gyeongbokgung"}]},
    )

    request = DailyPlanRequest(lat=37.5665, lng=126.978, radius_m=3000, language="EN")
    plan = planner_service.daily_plan(request)

    assert plan["language"] == "en"
    assert plan["slots"][0]["title"] == "Start near a landmark"
    assert plan["slots"][1]["title"] == "Adjust by weather"
    assert plan["slots"][1]["weather_hint"] == "bad"


def test_daily_plan_handles_unavailable_sources(monkeypatch) -> None:
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kwargs: {"source": "unavailable", "outdoor_status": "unknown"},
    )
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kwargs: {"source": "unavailable", "places": []},
    )

    request = DailyPlanRequest(lat=37.5665, lng=126.978, radius_m=3000, language="ko")
    plan = planner_service.daily_plan(request)

    assert plan["source"] == "unavailable"
    assert [slot["period"] for slot in plan["slots"]] == ["afternoon"]
    assert plan["slots"][0]["weather_hint"] == "unknown"


def test_intervention_flags_bad_weather_and_keeps_top_place(monkeypatch) -> None:
    captured: dict[str, object] = {}
    weather = {"source": "db", "outdoor_status": "bad"}
    places = {
        "source": "db",
        "places": [{"name": "남산서울타워", "category": "landmark"}],
    }

    def fake_current_weather(*, lat: float, lng: float) -> dict:
        captured["weather"] = {"lat": lat, "lng": lng}
        return weather

    def fake_list_places(**kwargs: object) -> dict:
        captured["places"] = kwargs
        return places

    monkeypatch.setattr(planner_service, "current_weather", fake_current_weather)
    monkeypatch.setattr(planner_service, "list_places", fake_list_places)

    result = planner_service.intervention(lat=37.5665, lng=126.978, radius_m=2000)

    assert result["center"] == {"lat": 37.5665, "lng": 126.978}
    assert result["radius_m"] == 2000
    assert result["should_intervene"] is True
    assert result["place"] == {"name": "남산서울타워", "category": "landmark"}
    assert result["source"] == "db"
    assert result["reason"] == (
        "Weather is not ideal; prioritize short-walk or indoor-friendly "
        "options near 남산서울타워."
    )
    assert result["recommended_action"] == (
        "Show indoor or short-walk alternatives around 남산서울타워."
    )
    assert captured["weather"] == {"lat": 37.5665, "lng": 126.978}
    assert captured["places"] == {
        "lat": 37.5665,
        "lng": 126.978,
        "radius_m": 2000,
        "category": "all",
        "language": "ko",
    }


def test_intervention_skips_when_weather_is_good(monkeypatch) -> None:
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kwargs: {"source": "public_mvp_snapshot", "outdoor_status": "good"},
    )
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kwargs: {
            "source": "public_mvp_snapshot",
            "places": [{"name": "해운대"}],
        },
    )

    result = planner_service.intervention(lat=35.16, lng=129.16, radius_m=1500)

    assert result["should_intervene"] is False
    assert result["source"] == "public_mvp_snapshot"
    assert result["reason"] == (
        "Weather is suitable, so keep the current route toward 해운대."
    )
    assert result["recommended_action"] == "Keep 해운대 as the primary local stop."


def test_intervention_uses_fallback_name_when_no_places(monkeypatch) -> None:
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kwargs: {"source": "db", "outdoor_status": "unknown"},
    )
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kwargs: {"source": "db", "places": []},
    )

    result = planner_service.intervention(lat=37.5665, lng=126.978, radius_m=3000)

    assert result["should_intervene"] is False
    assert result["place"] is None
    assert result["source"] == "db"
    assert result["reason"] == (
        "Weather data is still pending, so keep nearby local places as the current option."
    )
    assert result["recommended_action"] == (
        "Keep nearby local places while weather data is pending."
    )
