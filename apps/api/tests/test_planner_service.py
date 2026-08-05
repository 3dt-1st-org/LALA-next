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
            "Weather is not ideal; prioritize short-walk or indoor-friendly options near 한강공원.",
            "Show indoor or short-walk alternatives around 한강공원.",
        ),
        # Any status outside good/unknown hits the not-ideal fallback branch.
        (
            "severe",
            "Weather is not ideal; prioritize short-walk or indoor-friendly options near 한강공원.",
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
    ("language", "place_candidates", "expected_titles"),
    [
        ("ko", [], ["오전", "점심", "오후", "저녁"]),
        ("en", [], ["Morning", "Lunch", "Afternoon", "Dinner"]),
        ("ko", [{"name": "경복궁"}], ["오전", "점심", "오후", "저녁"]),
        ("en", [{"name": "Gyeongbokgung"}], ["Morning", "Lunch", "Afternoon", "Dinner"]),
    ],
)
def test_daily_plan_slots_shape_by_language_and_candidates(
    language: str,
    place_candidates: list[dict],
    expected_titles: list[str],
) -> None:
    weather = {"outdoor_status": "good"}

    slots = planner_service._daily_plan_slots(
        place_candidates=place_candidates,
        weather=weather,
        language=language,
    )

    # P5A: 항상 4 period 고정 순서.
    assert [slot["period"] for slot in slots] == [
        "morning",
        "lunch",
        "afternoon",
        "dinner",
    ]
    assert [slot["title"] for slot in slots] == expected_titles
    # weather_hint 는 모든 slot 에 전달.
    assert all(slot["weather_hint"] == "good" for slot in slots)
    if place_candidates:
        assert slots[0]["place"] == place_candidates[0]


def _cand(place_id: str, category: str = "attraction") -> dict:
    """A truthful test candidate: real place_id + category, nothing invented."""
    return {"place_id": place_id, "category": category, "name": place_id}


def test_daily_plan_slots_always_emits_exactly_four_periods() -> None:
    weather = {"outdoor_status": "good"}
    for candidates in [
        [],
        [_cand("a")],
        [_cand("a"), _cand("b")],
        [_cand("a"), _cand("b"), _cand("c")],
        [_cand("a"), _cand("b"), _cand("c"), _cand("d")],
        [_cand("a"), _cand("b"), _cand("c"), _cand("d"), _cand("e"), _cand("f")],
    ]:
        slots = planner_service._daily_plan_slots(
            place_candidates=candidates, weather=weather, language="ko"
        )
        assert [s["period"] for s in slots] == [
            "morning",
            "lunch",
            "afternoon",
            "dinner",
        ]
        assert len(slots) == 4


def test_daily_plan_slots_restaurants_prefer_meal_slots() -> None:
    # restaurant 후보는 lunch/dinner 에, non-restaurant 후보는 morning/afternoon 에.
    candidates = [
        _cand("r1", "restaurant"),
        _cand("n1", "attraction"),
        _cand("r2", "restaurant"),
        _cand("n2", "culture_venue"),
    ]
    slots = planner_service._daily_plan_slots(
        place_candidates=candidates, weather={"outdoor_status": "good"}, language="ko"
    )
    by_period = {s["period"]: (s["place"] or {}).get("place_id") for s in slots}

    assert by_period["morning"] == "n1"
    assert by_period["lunch"] == "r1"
    assert by_period["afternoon"] == "n2"
    assert by_period["dinner"] == "r2"


def test_daily_plan_slots_dedupe_no_place_repeats() -> None:
    # 동일 place_id 가 restaurant/non-restaurant 양쪽에 있어도 한 번만 배정.
    candidates = [
        _cand("dup", "attraction"),
        _cand("dup", "restaurant"),
        _cand("uniq", "attraction"),
    ]
    slots = planner_service._daily_plan_slots(
        place_candidates=candidates, weather={"outdoor_status": "good"}, language="ko"
    )
    assigned = [s["place"]["place_id"] for s in slots if s["place"]]

    assert assigned == ["dup", "uniq"]
    assert len(assigned) == len(set(assigned))


def test_daily_plan_slots_partial_fill_honest_unavailable() -> None:
    candidates = [_cand("a", "attraction"), _cand("b", "restaurant")]
    slots = planner_service._daily_plan_slots(
        place_candidates=candidates, weather={"outdoor_status": "good"}, language="ko"
    )
    filled = [s for s in slots if s["place"] is not None]
    unfilled = [s for s in slots if s["place"] is None]

    assert len(filled) == 2
    assert len(unfilled) == 2
    for slot in filled:
        assert slot["unavailable_reason"] is None
        assert slot["recommendation_reason"] is not None
    for slot in unfilled:
        assert slot["unavailable_reason"] == "추천 장소가 부족해요"
        assert slot["recommendation_reason"] is None


def test_daily_plan_slots_empty_all_unavailable() -> None:
    slots = planner_service._daily_plan_slots(
        place_candidates=[], weather={"outdoor_status": "unknown"}, language="en"
    )

    assert len(slots) == 4
    assert all(slot["place"] is None for slot in slots)
    assert all(slot["unavailable_reason"] == "Not enough nearby options" for slot in slots)


def test_daily_plan_slots_authority_fields_null_without_live_data() -> None:
    candidates = [
        _cand("a", "attraction"),
        _cand("b", "restaurant"),
        _cand("c"),
        _cand("d", "restaurant"),
    ]
    slots = planner_service._daily_plan_slots(
        place_candidates=candidates, weather={"outdoor_status": "good"}, language="ko"
    )

    assert len(slots) == 4
    # start_time: 관용적 시간대 시각(추정). opening-hours authority 부재 시에도
    # 표준 관례(09:00/12:00/14:00/18:00)로 제공.
    assert [s["start_time"] for s in slots] == ["09:00", "12:00", "14:00", "18:00"]
    # 첫 slot 은 이전 장소가 없으므로 travel_time = None.
    assert slots[0]["travel_time_from_previous_minutes"] is None
    for slot in slots:
        # authority 부재 → 여전히 null (추정값이 아닌 진짜 authority 필드).
        assert slot["stay_duration_minutes"] is None
        assert slot["opening_hours_valid"] is None
        assert slot["indoor_outdoor"] is None
        assert slot["local_franchise_confidence"] is None
        assert slot["swappable_alternatives"] == []


def test_daily_plan_slots_travel_time_estimated_between_consecutive_places() -> None:
    """Consecutive slots have estimated walking time; first slot is None."""
    from apps.api.app.services.travel_time_service import haversine_distance_m

    # Two places ~1km apart in Seoul.
    candidates = [
        {"place_id": "p1", "category": "attraction", "lat": 37.5665, "lng": 126.9780, "name": "A"},
        {"place_id": "p2", "category": "restaurant", "lat": 37.5745, "lng": 126.9880, "name": "B"},
    ]
    slots = planner_service._daily_plan_slots(
        place_candidates=candidates, weather={"outdoor_status": "good"}, language="ko"
    )

    # morning gets p1, lunch gets p2. travel_time for lunch = Haversine(p1→p2) ÷ 67.
    assert slots[0]["travel_time_from_previous_minutes"] is None
    assert slots[1]["travel_time_from_previous_minutes"] is not None
    expected_distance = haversine_distance_m(37.5665, 126.9780, 37.5745, 126.9880)
    expected_minutes = max(1, round(expected_distance / 67))
    assert slots[1]["travel_time_from_previous_minutes"] == expected_minutes
    # afternoon/dinner have no place → travel_time stays None (no consecutive pair).
    assert slots[2]["travel_time_from_previous_minutes"] is None


def test_daily_plan_slots_ko_en_exclusive_copy() -> None:
    candidates = [_cand("r", "restaurant")]
    ko = planner_service._daily_plan_slots(
        place_candidates=candidates, weather={"outdoor_status": "good"}, language="ko"
    )
    en = planner_service._daily_plan_slots(
        place_candidates=candidates, weather={"outdoor_status": "good"}, language="en"
    )

    assert [s["title"] for s in ko] == ["오전", "점심", "오후", "저녁"]
    assert [s["title"] for s in en] == ["Morning", "Lunch", "Afternoon", "Dinner"]
    # KO·EN 배타: 이유 문구도 각 언어에 맞게, 혼용 없음.
    ko_reason = next(s["recommendation_reason"] for s in ko if s["place"])
    en_reason = next(s["recommendation_reason"] for s in en if s["place"])
    assert ko_reason == "맛집으로 추천해요"
    assert en_reason == "Recommended as a local restaurant"


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

    assert planner_service.daily_plan_identity(other_location, language="ko") != base_identity
    assert planner_service.daily_plan_identity(other_radius, language="ko") != base_identity


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
    assert [slot["period"] for slot in plan["slots"]] == [
        "morning",
        "lunch",
        "afternoon",
        "dinner",
    ]
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
    assert plan["slots"][0]["title"] == "Morning"
    assert plan["slots"][1]["title"] == "Lunch"
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
    assert [slot["period"] for slot in plan["slots"]] == [
        "morning",
        "lunch",
        "afternoon",
        "dinner",
    ]
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
        "Weather is not ideal; prioritize short-walk or indoor-friendly options near 남산서울타워."
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
    assert result["reason"] == ("Weather is suitable, so keep the current route toward 해운대.")
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


def test_intervention_retains_original_and_alternative_slots(monkeypatch) -> None:
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kwargs: {"source": "db", "outdoor_status": "bad"},
    )
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kwargs: {
            "source": "db",
            "places": [{"place_id": "p1", "name": "행궁동 카페", "category": "restaurant"}],
        },
    )

    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)

    # original_slot carries the candidate in the P5A _plan_slot shape.
    assert result["original_slot"]["period"] == "afternoon"
    assert result["original_slot"]["place"]["place_id"] == "p1"
    # alternative_slot is null without indoor/outdoor provenance (honest).
    assert result["alternative_slot"] is None
    # backward-compat: top-level place still present.
    assert result["place"]["place_id"] == "p1"


def test_intervention_trigger_type_reflects_bad_weather(monkeypatch) -> None:
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kwargs: {"source": "db", "outdoor_status": "bad"},
    )
    monkeypatch.setattr(
        planner_service, "list_places", lambda **kwargs: {"source": "db", "places": []}
    )

    bad = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)
    assert bad["trigger_type"] == "bad_weather"
    assert bad["trigger_factors"] == [{"factor": "weather_outdoor_status", "value": "bad"}]

    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kwargs: {"source": "db", "outdoor_status": "good"},
    )
    good = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)
    assert good["trigger_type"] is None
    assert good["trigger_factors"] == []


def test_intervention_distance_comparison_null_without_authority(monkeypatch) -> None:
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kwargs: {"source": "db", "outdoor_status": "bad"},
    )
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kwargs: {
            "source": "db",
            "places": [{"place_id": "p1", "name": "x"}],
        },
    )

    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)

    # travel-time authority absent → honest null (no fabricated comparison).
    assert result["distance_comparison"] is None


def test_intervention_decision_default_pending_not_applied(monkeypatch) -> None:
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kwargs: {"source": "db", "outdoor_status": "bad"},
    )
    monkeypatch.setattr(
        planner_service, "list_places", lambda **kwargs: {"source": "db", "places": []}
    )

    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)

    # contract boundary: API never forces a user decision.
    assert result["user_decision"] == "pending"
    assert result["apply_state"] == "not_applied"
    assert result["history"] == []


def test_intervention_observable_factors_only(monkeypatch) -> None:
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kwargs: {"source": "db", "outdoor_status": "bad"},
    )
    monkeypatch.setattr(
        planner_service, "list_places", lambda **kwargs: {"source": "db", "places": []}
    )

    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)

    factors = result["trigger_factors"]
    # exactly one observable factor; no invented authority factors leak in.
    assert len(factors) == 1
    assert factors[0]["factor"] == "weather_outdoor_status"
    invented = {"air_quality", "closed", "event_ended", "transit_impaired"}
    assert all(factor["factor"] not in invented for factor in factors)


def test_intervention_ko_en_exclusive_reasons(monkeypatch) -> None:
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kwargs: {"source": "db", "outdoor_status": "bad"},
    )
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kwargs: {
            "source": "db",
            "places": [{"place_id": "p1", "name": "행궁동 카페"}],
        },
    )

    ko = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000, language="ko")
    en = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000, language="en")

    # KO·EN reason/action are mutually exclusive.
    assert "날씨가 좋지 않아요" in ko["reason"]
    assert "Weather is not ideal" in en["reason"]
    assert "날씨가 좋지 않아요" not in en["reason"]
    assert "Weather is not ideal" not in ko["reason"]
    # original_slot title follows the selected language only.
    assert ko["original_slot"]["title"] == "오후"
    assert en["original_slot"]["title"] == "Afternoon"
