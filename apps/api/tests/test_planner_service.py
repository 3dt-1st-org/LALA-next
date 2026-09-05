from __future__ import annotations

from datetime import UTC, datetime
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from apps.api.app.core.errors import ServiceError
from apps.api.app.schemas.planner import DailyPlanRequest
from apps.api.app.services import places_service, planner_service
from apps.api.app.services.request_identity import generation_identity


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
        assert slot["opening_hours_valid"] is not None or slot["place"] is None
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


def test_daily_plan_language_en_localizes_place_reason(monkeypatch) -> None:
    # V7 fix: /plans/daily slots embed the /places reason composer output verbatim
    # (slot.place.reason), so language=en must reach the REAL composer — patch only
    # the db boundary, not list_places, to prove the language threading end-to-end.
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kwargs: {"source": "db", "outdoor_status": "good"},
    )
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: SimpleNamespace(static_snapshot_fallback=False, db_dsn="postgres://test"),
    )
    monkeypatch.setattr(
        places_service.db_repository,
        "fetch_places",
        lambda **kwargs: [
            {
                "place_id": "p1",
                "name": "Nearby spot",
                "category": "attraction",
                "distance_m": 300,
                "source": "db",
                "upstream_source": "tour_api",
            }
        ],
    )
    monkeypatch.setattr(places_service.db_repository, "fetch_latest_weather", lambda **kwargs: {})
    # Freeze the composer clock so the operating-status segment is deterministic.
    fixed = datetime(2026, 8, 13, 12, 0, 0, tzinfo=UTC)

    class _FrozenDateTime(datetime):
        @classmethod
        def now(cls, tz=None):
            return fixed.astimezone(tz) if tz else fixed.replace(tzinfo=None)

    monkeypatch.setattr(places_service, "datetime", _FrozenDateTime)

    request = DailyPlanRequest(lat=37.5665, lng=126.978, radius_m=3000, language="en")
    plan = planner_service.daily_plan(request)

    slot_place = plan["slots"][0]["place"]
    assert slot_place["reason"] == "Open now · Nearby · Korea Tourism Organization data"
    # The slot's own copy stays EN too (no mixed-language dock).
    assert plan["slots"][0]["recommendation_reason"] == "Recommended as a local attraction"


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


def test_intervention_bad_weather_finds_indoor_alternative(monkeypatch):
    """§12.6: bad weather + indoor provenance → alternative_slot populated."""
    places = [
        {"place_id": "p1", "name": "야외 공원", "category": "attraction", "is_indoor": False},
        {"place_id": "p2", "name": "실내 미술관", "category": "culture_venue", "is_indoor": True},
    ]
    monkeypatch.setattr(
        planner_service, "list_places", lambda **kw: {"source": "db", "places": places}
    )
    monkeypatch.setattr(
        planner_service, "current_weather", lambda **kw: {"outdoor_status": "bad", "source": "kma"}
    )

    result = planner_service.intervention(lat=37.5, lng=127.0, radius_m=3000, language="ko")

    assert result["should_intervene"] is True
    assert result["trigger_type"] == "bad_weather"
    alt = result["alternative_slot"]
    assert alt is not None, "indoor alternative should be suggested when weather is bad"
    assert alt["place"]["place_id"] == "p2"
    assert alt["indoor_outdoor"] == "indoor"


def test_intervention_bad_weather_no_indoor_alternative(monkeypatch):
    """§12.6: bad weather + no indoor provenance → alternative_slot None (honest)."""
    places = [
        {"place_id": "p1", "name": "야외 공원", "category": "attraction", "is_indoor": False},
        {"place_id": "p2", "name": "야외 카페", "category": "restaurant", "is_indoor": False},
    ]
    monkeypatch.setattr(
        planner_service, "list_places", lambda **kw: {"source": "db", "places": places}
    )
    monkeypatch.setattr(
        planner_service, "current_weather", lambda **kw: {"outdoor_status": "bad", "source": "kma"}
    )

    result = planner_service.intervention(lat=37.5, lng=127.0, radius_m=3000, language="ko")

    assert result["should_intervene"] is True
    assert result["alternative_slot"] is None, "no indoor provenance → honest null"


def test_intervention_good_weather_no_alternative(monkeypatch):
    """§12.6: good weather → no alternative_slot regardless of indoor availability."""
    places = [
        {"place_id": "p1", "name": "실내 미술관", "category": "culture_venue", "is_indoor": True},
    ]
    monkeypatch.setattr(
        planner_service, "list_places", lambda **kw: {"source": "db", "places": places}
    )
    monkeypatch.setattr(
        planner_service, "current_weather", lambda **kw: {"outdoor_status": "good", "source": "kma"}
    )

    result = planner_service.intervention(lat=37.5, lng=127.0, radius_m=3000, language="ko")

    assert result["should_intervene"] is False
    assert result["alternative_slot"] is None


def test_intervention_excludes_original_from_alternatives(monkeypatch):
    """alternative_slot must not be the same place as original_slot."""
    places = [
        {"place_id": "p1", "name": "미술관 A", "category": "culture_venue", "is_indoor": True},
        {"place_id": "p2", "name": "미술관 B", "category": "culture_venue", "is_indoor": True},
    ]
    monkeypatch.setattr(
        planner_service, "list_places", lambda **kw: {"source": "db", "places": places}
    )
    monkeypatch.setattr(
        planner_service, "current_weather", lambda **kw: {"outdoor_status": "bad", "source": "kma"}
    )

    result = planner_service.intervention(lat=37.5, lng=127.0, radius_m=3000, language="ko")

    alt = result["alternative_slot"]
    assert alt is not None
    assert alt["place"]["place_id"] != result["place"]["place_id"], (
        "alternative must differ from original"
    )


# ---------------------------------------------------------------------------
# D-1: 선택 장소(selected_place_id) 고정 배정 계약.
# ---------------------------------------------------------------------------


def test_daily_plan_slots_pins_selected_restaurant_to_lunch_exactly_once() -> None:
    weather = {"outdoor_status": "good"}
    candidates = [
        _cand("n1", "attraction"),
        _cand("r1", "restaurant"),
        _cand("n2", "culture_venue"),
        _cand("r2", "restaurant"),
        _cand("n3", "attraction"),
    ]
    selected = next(c for c in candidates if c["place_id"] == "r1")

    slots = planner_service._daily_plan_slots(
        place_candidates=candidates,
        weather=weather,
        language="ko",
        selected_place=selected,
    )

    assigned_ids = [slot["place"]["place_id"] for slot in slots if slot["place"]]
    # 정확히 한 번, 식사 슬롯 중 첫 번째(lunch)에 배정.
    assert assigned_ids.count("r1") == 1
    assert slots[1]["period"] == "lunch"
    assert slots[1]["place"]["place_id"] == "r1"
    # 나머지 슬롯은 기존 deterministic 규칙 유지(중복 없음, 4슬롯 유지).
    assert len(slots) == 4
    assert len(set(assigned_ids)) == len(assigned_ids)
    assert slots[0]["place"]["place_id"] == "n1"
    assert slots[2]["place"]["place_id"] == "n2"


def test_daily_plan_slots_pins_selected_non_restaurant_to_morning() -> None:
    weather = {"outdoor_status": "good"}
    candidates = [
        _cand("n1", "attraction"),
        _cand("r1", "restaurant"),
        _cand("n2", "culture_venue"),
        _cand("r2", "restaurant"),
    ]
    selected = next(c for c in candidates if c["place_id"] == "n2")

    slots = planner_service._daily_plan_slots(
        place_candidates=candidates,
        weather=weather,
        language="ko",
        selected_place=selected,
    )

    assigned_ids = [slot["place"]["place_id"] for slot in slots if slot["place"]]
    assert assigned_ids.count("n2") == 1
    assert slots[0]["period"] == "morning"
    assert slots[0]["place"]["place_id"] == "n2"
    # morning 을 차지했어도 나머지 후보는 기존 fallback 규칙대로 배정된다.
    assert slots[1]["place"]["place_id"] == "r1"
    assert slots[2]["place"]["place_id"] == "n1"
    assert slots[3]["place"]["place_id"] == "r2"


def test_daily_plan_slots_selected_place_not_in_swappable_alternatives(
    monkeypatch,
) -> None:
    # swappable_alternatives 는 PLAN_FULL_SLOTS 게이트가 켜져야 채워진다(V3 D6).
    monkeypatch.setattr(
        planner_service,
        "get_settings",
        lambda: SimpleNamespace(feature_flags={"PLAN_FULL_SLOTS": True}),
    )
    weather = {"outdoor_status": "good"}
    candidates = [
        _cand("n1", "attraction"),
        _cand("r1", "restaurant"),
        _cand("n2", "attraction"),
        _cand("r2", "restaurant"),
        _cand("n3", "attraction"),
    ]
    selected = next(c for c in candidates if c["place_id"] == "r1")

    slots = planner_service._daily_plan_slots(
        place_candidates=candidates,
        weather=weather,
        language="ko",
        selected_place=selected,
    )

    alternatives_all = [
        alt["place_id"] for slot in slots for alt in (slot.get("swappable_alternatives") or [])
    ]
    # 게이트가 켜져 leftover 가 존재하며, 고정 장소는 후보에도 남지 않는다.
    assert alternatives_all, "leftover alternatives should be populated"
    assert "r1" not in alternatives_all


def _patch_daily_plan_sources(monkeypatch, places: list[dict]) -> None:
    monkeypatch.setattr(
        planner_service, "list_places", lambda **kw: {"source": "db", "places": places}
    )
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kw: {"outdoor_status": "good", "source": "kma"},
    )


def test_daily_plan_includes_selected_place_once(monkeypatch) -> None:
    places = [
        {"place_id": "p1", "name": "수원화성", "category": "attraction"},
        {"place_id": "p2", "name": "로컬 식당", "category": "restaurant"},
        {"place_id": "p3", "name": "행궁", "category": "attraction"},
        {"place_id": "p4", "name": "카페", "category": "culture_venue"},
    ]
    _patch_daily_plan_sources(monkeypatch, places)

    request = DailyPlanRequest(
        lat=37.5, lng=127.0, radius_m=3000, language="ko", selected_place_id="p2"
    )
    result = planner_service.daily_plan(request)

    assigned = [slot["place"]["place_id"] for slot in result["slots"] if slot["place"]]
    assert assigned.count("p2") == 1
    lunch_slot = next(s for s in result["slots"] if s["period"] == "lunch")
    assert lunch_slot["place"]["place_id"] == "p2"


def test_daily_plan_unresolvable_selected_place_fails_honestly(monkeypatch) -> None:
    _patch_daily_plan_sources(
        monkeypatch,
        [
            {"place_id": "p1", "name": "수원화성", "category": "attraction"},
        ],
    )

    request = DailyPlanRequest(
        lat=37.5, lng=127.0, radius_m=3000, language="ko", selected_place_id="ghost"
    )

    with pytest.raises(ServiceError) as excinfo:
        planner_service.daily_plan(request)

    assert excinfo.value.status_code == 422
    assert excinfo.value.code == "SELECTED_PLACE_UNAVAILABLE"
    assert excinfo.value.message == "선택한 장소를 이 일정에 포함할 수 없어요."
    assert excinfo.value.retryable is False


def test_daily_plan_unresolvable_selected_place_message_localizes(monkeypatch) -> None:
    _patch_daily_plan_sources(monkeypatch, [])

    request = DailyPlanRequest(
        lat=37.5, lng=127.0, radius_m=3000, language="en", selected_place_id="ghost"
    )

    with pytest.raises(ServiceError) as excinfo:
        planner_service.daily_plan(request)

    assert excinfo.value.message == "The selected place cannot be included in this plan."


def test_daily_plan_strips_selected_place_id_whitespace(monkeypatch) -> None:
    _patch_daily_plan_sources(
        monkeypatch,
        [
            {"place_id": "p1", "name": "수원화성", "category": "attraction"},
            {"place_id": "p2", "name": "로컬 식당", "category": "restaurant"},
        ],
    )

    request = DailyPlanRequest(
        lat=37.5, lng=127.0, radius_m=3000, language="ko", selected_place_id="  p2  "
    )
    result = planner_service.daily_plan(request)

    # BeforeValidator 정규화 후 실제 candidate 로 해석된다.
    lunch_slot = next(s for s in result["slots"] if s["period"] == "lunch")
    assert lunch_slot["place"]["place_id"] == "p2"


def test_daily_plan_whitespace_only_selected_place_id_is_rejected() -> None:
    # 거부 계약: 공백 전용 문자열은 미지정이 아니라 VALIDATION_ERROR 이다.
    with pytest.raises(ValidationError):
        DailyPlanRequest(lat=37.5, lng=127.0, radius_m=3000, language="ko", selected_place_id="   ")


def test_daily_plan_identity_preserves_legacy_unpinned_payload_bytes() -> None:
    unpinned = DailyPlanRequest(lat=37.5665, lng=126.978, radius_m=3000, language="ko")

    identity = planner_service.daily_plan_identity(unpinned, language="ko")

    # 기존(D-1 이전) 페이로드를 그대로 재구성해 hash 가 바이트 단위로 같은지 검증한다.
    legacy_payload = {
        "lat": 37.5665,
        "lng": 126.978,
        "radius_m": 3000,
        "language": "ko",
    }
    legacy = generation_identity("daily_plan", legacy_payload)
    assert identity == legacy


def test_daily_plan_identity_distinguishes_selected_place() -> None:
    unpinned = DailyPlanRequest(lat=37.5665, lng=126.978, radius_m=3000, language="ko")
    pinned = DailyPlanRequest(
        lat=37.5665,
        lng=126.978,
        radius_m=3000,
        language="ko",
        selected_place_id="p2",
    )

    unpinned_identity = planner_service.daily_plan_identity(unpinned, language="ko")
    pinned_identity = planner_service.daily_plan_identity(pinned, language="ko")

    assert unpinned_identity["request_hash"] != pinned_identity["request_hash"]
    assert unpinned_identity["cache_key"] != pinned_identity["cache_key"]
    # 서로 다른 고정 장소도 서로 다른 정체성을 갖는다.
    other_pinned = DailyPlanRequest(
        lat=37.5665,
        lng=126.978,
        radius_m=3000,
        language="ko",
        selected_place_id="p3",
    )
    other_identity = planner_service.daily_plan_identity(other_pinned, language="ko")
    assert pinned_identity["request_hash"] != other_identity["request_hash"]


# ---------------------------------------------------------------------------
# CP1: preference_context — grounded effects + honest reporting 계약.
# ---------------------------------------------------------------------------


def test_preference_context_rejects_unknown_and_sensitive_fields() -> None:
    # strict 계약: 알 수 없는 키와 민감 키(알레르겐/식이/PII)는 422 로 거부된다.
    for sensitive in (
        {"allergens": ["nuts"]},
        {"dietary_modes": ["vegan"]},
        {"avoid_ingredients": "고수"},
        {"wheelchair_access": True},
        {"user_id": "u-1"},
        # CP2: 식당 커뮤니케이션 전용 soft 값도 public plan endpoint 로
        # 전송될 수 없다(extra="forbid" 로 거부).
        {"spice_level": "mild"},
        {"order_requests": ["quietTable"]},
    ):
        with pytest.raises(ValidationError):
            DailyPlanRequest(
                lat=37.5,
                lng=127.0,
                preference_context={"indoor_outdoor": "indoor", **sensitive},
            )


def test_preference_context_rejects_invalid_enums_bounds_and_duplicates() -> None:
    for invalid in (
        {"indoor_outdoor": "somewhere"},
        {"weather_sensitivity": "extreme"},
        {"walking_band": "marathon"},
        {"max_one_way_minutes": 45},
        {"budget_band": "luxury"},
        {"food_cuisines": ["italian"]},
        {"food_cuisines": ["korean", "korean"]},
        {"food_cuisines": ["korean", "cafeDessert", "streetFood", "marketFood", "worldCuisine"]},
    ):
        with pytest.raises(ValidationError):
            DailyPlanRequest(lat=37.5, lng=127.0, preference_context=invalid)


def test_preference_context_defaults_reuse_preference_store_bounds() -> None:
    request = DailyPlanRequest(lat=37.5, lng=127.0, preference_context={"indoor_outdoor": "indoor"})

    context = request.preference_context
    assert context is not None
    assert context.weather_sensitivity == "medium"
    assert context.walking_band == "medium"
    assert context.max_one_way_minutes == 30
    assert context.food_cuisines == []
    assert context.budget_band == "balanced"
    assert context.exclude_closing_soon is True


def test_daily_plan_without_preference_context_omits_effects_and_keeps_identity(
    monkeypatch,
) -> None:
    captured = _capture_plan_sources(monkeypatch, [])

    request = DailyPlanRequest(lat=37.5665, lng=126.978, radius_m=3000, language="ko")
    plan = planner_service.daily_plan(request)

    # 컨텍스트 없는 응답은 preference_effects 키 자체가 없다(legacy 형태 보존).
    assert "preference_effects" not in plan
    assert captured["radius_m"] == 3000
    # D-1 과 동일한 방식: 정체성 페이로드가 기존 바이트와 같은지 직접 검증.
    legacy_payload = {
        "lat": 37.5665,
        "lng": 126.978,
        "radius_m": 3000,
        "language": "ko",
    }
    assert plan["request_hash"] == generation_identity("daily_plan", legacy_payload)["request_hash"]
    assert plan["cache_key"] == generation_identity("daily_plan", legacy_payload)["cache_key"]


def test_daily_plan_identity_includes_preference_context_only_when_present(
    monkeypatch,
) -> None:
    _patch_daily_plan_sources(monkeypatch, [])
    base = DailyPlanRequest(lat=37.5, lng=127.0, radius_m=3000, language="ko")
    with_context = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        radius_m=3000,
        language="ko",
        preference_context={"indoor_outdoor": "indoor"},
    )

    base_identity = planner_service.daily_plan_identity(base, language="ko")
    context_identity = planner_service.daily_plan_identity(with_context, language="ko")

    assert base_identity["request_hash"] != context_identity["request_hash"]
    assert context_identity == planner_service.daily_plan_identity(with_context, language="ko")


def _capture_plan_sources(monkeypatch, places: list[dict], outdoor_status: str = "good"):
    captured: dict[str, object] = {}

    def fake_list_places(**kwargs: object) -> dict:
        captured.update(kwargs)
        return {"source": "db", "places": places}

    monkeypatch.setattr(planner_service, "list_places", fake_list_places)
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kw: {"outdoor_status": outdoor_status, "source": "kma"},
    )
    return captured


def test_daily_plan_caps_query_radius_from_max_one_way_minutes(monkeypatch) -> None:
    places = [{"place_id": f"p{i}", "name": f"장소{i}", "category": "attraction"} for i in range(4)]
    captured = _capture_plan_sources(monkeypatch, places)

    request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        radius_m=5000,
        language="ko",
        preference_context={"max_one_way_minutes": 15},
    )
    plan = planner_service.daily_plan(request)

    # 문서화된 도보 추정: 15분 × 67 m/min = 1005m. 요청 반경을 초과하지 않는다.
    assert captured["radius_m"] == 15 * 67
    assert plan["radius_m"] == 5000  # 응답은 요청 에코(요청/유효 구분은 effects 가 진실)
    radius_effect = plan["preference_effects"][0]
    assert radius_effect["field"] == "max_one_way_minutes"
    assert radius_effect["applied"] is True
    assert radius_effect["reason_code"] == "RADIUS_CAPPED_TO_WALKING_TIME"
    assert radius_effect["details"]["requested_radius_m"] == 5000
    assert radius_effect["details"]["effective_radius_m"] == 15 * 67
    assert radius_effect["details"]["effective_one_way_minutes"] == 15
    assert radius_effect["details"]["walking_estimate"] == "haversine_4kmh"
    assert "1005" in radius_effect["explanation"]


def test_daily_plan_radius_cap_attributes_to_walking_band_when_stricter(monkeypatch) -> None:
    captured = _capture_plan_sources(monkeypatch, [])

    request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        radius_m=50000,
        language="ko",
        preference_context={"walking_band": "short", "max_one_way_minutes": 90},
    )
    plan = planner_service.daily_plan(request)

    # 밴드(15분)가 명시 분(90분)보다 작으므로 상한의 근거는 walking_band.
    assert captured["radius_m"] == 15 * 67
    radius_effect = plan["preference_effects"][0]
    assert radius_effect["field"] == "walking_band"
    assert radius_effect["applied"] is True
    assert radius_effect["details"]["source_fields"] == ["walking_band"]


def test_daily_plan_radius_cap_not_binding_reports_honest_reason(monkeypatch) -> None:
    captured = _capture_plan_sources(monkeypatch, [])

    # 기본 컨텍스트(30분 → 2010m)는 요청 반경 1000m를 줄이지 못한다.
    request = DailyPlanRequest(
        lat=37.5, lng=127.0, radius_m=1000, language="ko", preference_context={}
    )
    plan = planner_service.daily_plan(request)

    assert captured["radius_m"] == 1000
    radius_effect = plan["preference_effects"][0]
    assert radius_effect["field"] == "max_one_way_minutes"
    assert radius_effect["applied"] is False
    assert radius_effect["reason_code"] == "RADIUS_CAP_NOT_BINDING"
    assert radius_effect["details"]["effective_radius_m"] == 1000


def test_daily_plan_orders_indoor_first_under_indoor_preference_good_weather(
    monkeypatch,
) -> None:
    places = [
        {"place_id": "out1", "name": "야외 공원", "category": "attraction", "is_indoor": False},
        {"place_id": "in1", "name": "실내 미술관", "category": "culture_venue", "is_indoor": True},
        {"place_id": "out2", "name": "야외 시장", "category": "attraction", "is_indoor": False},
        {"place_id": "in2", "name": "실내 카페", "category": "restaurant", "is_indoor": True},
    ]
    _capture_plan_sources(monkeypatch, places)

    request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        language="ko",
        preference_context={"indoor_outdoor": "indoor"},
    )
    plan = planner_service.daily_plan(request)

    # morning/afternoon 은 non-restaurant 후보 순서를 따른다: in1 → out1 → out2.
    morning_place = plan["slots"][0]["place"]["place_id"]
    afternoon_place = plan["slots"][2]["place"]["place_id"]
    assert morning_place == "in1"
    assert afternoon_place == "out1"
    indoor_effect = plan["preference_effects"][1]
    assert indoor_effect["applied"] is True
    assert indoor_effect["reason_code"] == "INDOOR_ORDERING_APPLIED"
    assert indoor_effect["details"]["ordered_by"] == "preference"
    assert indoor_effect["details"]["preferred"] == "indoor"


def test_daily_plan_orders_outdoor_first_under_outdoor_preference_good_weather(
    monkeypatch,
) -> None:
    places = [
        {"place_id": "in1", "name": "실내 미술관", "category": "attraction", "is_indoor": True},
        {"place_id": "out1", "name": "야외 공원", "category": "culture_venue", "is_indoor": False},
    ]
    _capture_plan_sources(monkeypatch, places)

    request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        language="ko",
        preference_context={"indoor_outdoor": "outdoor", "weather_sensitivity": "high"},
    )
    plan = planner_service.daily_plan(request)

    assert plan["slots"][0]["place"]["place_id"] == "out1"
    indoor_effect = plan["preference_effects"][1]
    assert indoor_effect["applied"] is True
    assert indoor_effect["reason_code"] == "INDOOR_ORDERING_APPLIED"
    assert indoor_effect["details"]["preferred"] == "outdoor"


def test_daily_plan_bad_weather_prefers_indoor_over_outdoor_preference(monkeypatch) -> None:
    places = [
        {"place_id": "out1", "name": "야외 공원", "category": "attraction", "is_indoor": False},
        {"place_id": "in1", "name": "실내 미술관", "category": "culture_venue", "is_indoor": True},
    ]
    _capture_plan_sources(monkeypatch, places, outdoor_status="bad")

    request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        language="ko",
        preference_context={"indoor_outdoor": "outdoor", "weather_sensitivity": "medium"},
    )
    plan = planner_service.daily_plan(request)

    # 안전 우선: 나쁜 날씨 + medium/high 민감도는 outdoor soft 선호를 이긴다.
    assert plan["slots"][0]["place"]["place_id"] == "in1"
    indoor_effect = plan["preference_effects"][1]
    assert indoor_effect["applied"] is True
    assert indoor_effect["reason_code"] == "WEATHER_SAFETY_INDOOR_PRIORITY"
    assert indoor_effect["details"]["ordered_by"] == "weather_safety"
    assert indoor_effect["details"]["weather_outdoor_status"] == "bad"


def test_daily_plan_bad_weather_high_sensitivity_beats_outdoor_preference_too(
    monkeypatch,
) -> None:
    places = [
        {"place_id": "out1", "name": "야외 공원", "category": "attraction", "is_indoor": False},
        {"place_id": "in1", "name": "실내 미술관", "category": "attraction", "is_indoor": True},
    ]
    _capture_plan_sources(monkeypatch, places, outdoor_status="bad")

    request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        language="ko",
        preference_context={"indoor_outdoor": "outdoor", "weather_sensitivity": "high"},
    )
    plan = planner_service.daily_plan(request)

    assert plan["slots"][0]["place"]["place_id"] == "in1"
    assert plan["preference_effects"][1]["reason_code"] == "WEATHER_SAFETY_INDOOR_PRIORITY"


def test_daily_plan_bad_weather_low_sensitivity_keeps_outdoor_preference(monkeypatch) -> None:
    places = [
        {"place_id": "in1", "name": "실내 미술관", "category": "attraction", "is_indoor": True},
        {"place_id": "out1", "name": "야외 공원", "category": "culture_venue", "is_indoor": False},
    ]
    _capture_plan_sources(monkeypatch, places, outdoor_status="bad")

    request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        language="ko",
        preference_context={"indoor_outdoor": "outdoor", "weather_sensitivity": "low"},
    )
    plan = planner_service.daily_plan(request)

    # low 민감도는 안전 오버라이드를 발동하지 않는다(선호가 그대로 유지).
    assert plan["slots"][0]["place"]["place_id"] == "out1"
    assert plan["preference_effects"][1]["reason_code"] == "INDOOR_ORDERING_APPLIED"


def test_daily_plan_unknown_indoor_status_not_treated_as_indoor(monkeypatch) -> None:
    places = [
        {"place_id": "u1", "name": "미확인 장소1", "category": "attraction"},
        {"place_id": "in1", "name": "실내 미술관", "category": "culture_venue", "is_indoor": True},
        {"place_id": "u2", "name": "미확인 장소2", "category": "attraction", "is_indoor": None},
    ]
    _capture_plan_sources(monkeypatch, places)

    request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        language="ko",
        preference_context={"indoor_outdoor": "indoor"},
    )
    plan = planner_service.daily_plan(request)

    # known indoor 먼저, unknown 은 실내로 취급하지 않고 입력 순서대로 뒤에 위치.
    assigned = [slot["place"]["place_id"] for slot in plan["slots"] if slot["place"]]
    assert assigned == ["in1", "u1", "u2"]


def test_daily_plan_all_unknown_indoor_reports_honest_unavailable(monkeypatch) -> None:
    places = [
        {"place_id": "u1", "name": "미확인1", "category": "attraction"},
        {"place_id": "u2", "name": "미확인2", "category": "attraction"},
    ]
    _capture_plan_sources(monkeypatch, places)

    request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        language="ko",
        preference_context={"indoor_outdoor": "indoor"},
    )
    plan = planner_service.daily_plan(request)

    indoor_effect = plan["preference_effects"][1]
    assert indoor_effect["applied"] is False
    assert indoor_effect["reason_code"] == "INDOOR_STATUS_UNAVAILABLE"
    # 순서도 바뀌지 않는다(발명 금지).
    assert plan["slots"][0]["place"]["place_id"] == "u1"


def test_daily_plan_balanced_preference_reports_not_directional(monkeypatch) -> None:
    places = [
        {"place_id": "out1", "name": "야외 공원", "category": "attraction", "is_indoor": False},
        {"place_id": "in1", "name": "실내 미술관", "category": "attraction", "is_indoor": True},
    ]
    _capture_plan_sources(monkeypatch, places)

    request = DailyPlanRequest(
        lat=37.5, lng=127.0, language="ko", preference_context={"indoor_outdoor": "balanced"}
    )
    plan = planner_service.daily_plan(request)

    indoor_effect = plan["preference_effects"][1]
    assert indoor_effect["applied"] is False
    assert indoor_effect["reason_code"] == "INDOOR_ORDERING_NOT_DIRECTIONAL"
    # 중립 선호는 순서를 바꾸지 않는다(기존 배정 규칙 그대로).
    assert plan["slots"][0]["place"]["place_id"] == "out1"


def test_daily_plan_indoor_ordering_no_change_reports_honest_reason(monkeypatch) -> None:
    places = [
        {"place_id": "in1", "name": "실내 미술관", "category": "attraction", "is_indoor": True},
        {"place_id": "out1", "name": "야외 공원", "category": "culture_venue", "is_indoor": False},
    ]
    _capture_plan_sources(monkeypatch, places)

    request = DailyPlanRequest(
        lat=37.5, lng=127.0, language="ko", preference_context={"indoor_outdoor": "indoor"}
    )
    plan = planner_service.daily_plan(request)

    indoor_effect = plan["preference_effects"][1]
    assert indoor_effect["applied"] is False
    assert indoor_effect["reason_code"] == "INDOOR_ORDERING_NO_CHANGE"


def test_preference_effects_report_unsupported_fields_honestly(monkeypatch) -> None:
    _capture_plan_sources(monkeypatch, [])
    request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        language="ko",
        preference_context={
            "food_cuisines": ["korean"],
            "budget_band": "value",
            "exclude_closing_soon": True,
        },
    )
    plan = planner_service.daily_plan(request)

    by_field = {effect["field"]: effect for effect in plan["preference_effects"]}
    assert by_field["food_cuisines"] == {
        "field": "food_cuisines",
        "applied": False,
        "reason_code": "CUISINE_FACET_UNAVAILABLE",
        "explanation": "장소 데이터에 요리 정보가 없어 요리 선호를 반영하지 못했어요.",
    }
    assert by_field["budget_band"]["applied"] is False
    assert by_field["budget_band"]["reason_code"] == "PRICE_FACET_UNAVAILABLE"
    assert by_field["exclude_closing_soon"]["applied"] is False
    assert by_field["exclude_closing_soon"]["reason_code"] == "CLOSING_SOON_FACET_UNAVAILABLE"
    # 정의된 효과는 5개 뿐(안정적 순서), 필터링을 주장하지 않는다.
    assert len(plan["preference_effects"]) == 5


def test_preference_effects_explanations_localize_ko_en(monkeypatch) -> None:
    places = [
        {"place_id": "out1", "name": "야외 공원", "category": "attraction", "is_indoor": False},
        {"place_id": "in1", "name": "실내 미술관", "category": "attraction", "is_indoor": True},
    ]
    _capture_plan_sources(monkeypatch, places)
    ko_request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        language="ko",
        radius_m=5000,
        preference_context={"indoor_outdoor": "indoor", "max_one_way_minutes": 15},
    )
    _capture_plan_sources(monkeypatch, places, outdoor_status="bad")
    en_request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        language="en",
        radius_m=5000,
        preference_context={
            "indoor_outdoor": "outdoor",
            "weather_sensitivity": "medium",
            "max_one_way_minutes": 15,
        },
    )

    ko_plan = planner_service.daily_plan(ko_request)
    en_plan = planner_service.daily_plan(en_request)

    ko_radius = ko_plan["preference_effects"][0]
    en_effects = en_plan["preference_effects"]
    assert "줄였어요" in ko_radius["explanation"]
    assert "Capped the search radius" in en_effects[0]["explanation"]
    assert en_effects[1]["reason_code"] == "WEATHER_SAFETY_INDOOR_PRIORITY"
    assert "Weather is bad" in en_effects[1]["explanation"]


def test_preference_effects_never_leak_raw_or_sensitive_values(monkeypatch) -> None:
    _capture_plan_sources(monkeypatch, [])
    request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        language="ko",
        preference_context={"food_cuisines": ["korean"], "budget_band": "value"},
    )
    plan = planner_service.daily_plan(request)

    serialized = repr(plan["preference_effects"])
    for forbidden in ("korean", "value", "allergen", "dietary", "wheelchair"):
        assert forbidden not in serialized


def test_daily_plan_pins_selected_place_once_with_preference_context(monkeypatch) -> None:
    places = [
        {"place_id": "out1", "name": "야외 공원", "category": "attraction", "is_indoor": False},
        {"place_id": "pin", "name": "고정 맛집", "category": "restaurant", "is_indoor": True},
        {"place_id": "in1", "name": "실내 미술관", "category": "attraction", "is_indoor": True},
        {"place_id": "out2", "name": "야외 시장", "category": "attraction", "is_indoor": False},
    ]
    _capture_plan_sources(monkeypatch, places)

    request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        radius_m=5000,
        language="ko",
        selected_place_id="pin",
        preference_context={"indoor_outdoor": "indoor", "max_one_way_minutes": 15},
    )
    plan = planner_service.daily_plan(request)

    assigned = [slot["place"]["place_id"] for slot in plan["slots"] if slot["place"]]
    assert assigned.count("pin") == 1
    lunch = next(s for s in plan["slots"] if s["period"] == "lunch")
    assert lunch["place"]["place_id"] == "pin"
    # 정렬된 후보 순서도 유지: indoor 우선(morning=in1, afternoon=out1).
    assert plan["slots"][0]["place"]["place_id"] == "in1"
    assert plan["slots"][2]["place"]["place_id"] == "out1"


def test_daily_plan_selected_place_outside_capped_radius_fails_honestly(monkeypatch) -> None:
    # 축소된 유효 반경 안의 후보만 돌려주는 list_places(double): 반경 밖 고정 장소는
    # 유효 후보 집합에 존재할 수 없다 → 기존 정직한 422.
    places_in_cap = [
        {"place_id": "in1", "name": "실내 미술관", "category": "attraction", "is_indoor": True},
    ]

    def fake_list_places(**kwargs: object) -> dict:
        # 캡된 반경 밖 후보는 애초에 반환되지 않는다(실제 쿼리와 동일).
        return {"source": "db", "places": list(places_in_cap)}

    monkeypatch.setattr(planner_service, "list_places", fake_list_places)
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kw: {"outdoor_status": "good", "source": "kma"},
    )

    request = DailyPlanRequest(
        lat=37.5,
        lng=127.0,
        radius_m=5000,
        language="ko",
        selected_place_id="far-pin",
        preference_context={"max_one_way_minutes": 15},
    )

    with pytest.raises(ServiceError) as excinfo:
        planner_service.daily_plan(request)

    assert excinfo.value.status_code == 422
    assert excinfo.value.code == "SELECTED_PLACE_UNAVAILABLE"


# ---------------------------------------------------------------------------
# P4: distinct weather vs air-quality intervention causes.
# ---------------------------------------------------------------------------


def _p4_weather(
    *,
    weather_status: str,
    air_quality_status: str,
    dust_grade: str,
    aggregate: str,
) -> dict:
    """Weather payload with explicit P4 provenance (current_weather shape)."""
    return {
        "source": "kma_ultra_srt_ncst+airkorea_sido_realtime",
        "outdoor_status": aggregate,
        "weather_outdoor_status": weather_status,
        "air_quality_outdoor_status": air_quality_status,
        "dust": {"grade": dust_grade},
        "forecast": [],
    }


def _patch_intervention_sources(
    monkeypatch,
    places: list[dict],
    weather: dict,
) -> None:
    monkeypatch.setattr(
        planner_service, "list_places", lambda **kw: {"source": "db", "places": places}
    )
    monkeypatch.setattr(planner_service, "current_weather", lambda **kw: dict(weather))


def test_intervention_bad_air_quality_only_emits_distinct_trigger(monkeypatch) -> None:
    """AQ sole observed cause → bad_air_quality trigger + AQ factor + AQ copy."""
    _patch_intervention_sources(
        monkeypatch,
        [{"place_id": "p1", "name": "야외 공원", "category": "attraction"}],
        _p4_weather(
            weather_status="good",
            air_quality_status="bad",
            dust_grade="bad",
            aggregate="bad",
        ),
    )

    result = planner_service.intervention(lat=37.5, lng=127.0, radius_m=3000, language="en")

    assert result["should_intervene"] is True
    assert result["trigger_type"] == "bad_air_quality"
    assert result["trigger_factors"] == [{"factor": "air_quality_dust_grade", "value": "bad"}]
    # Cause-correct copy: AQ-only never claims weather.
    assert result["reason"] == (
        "Air quality is poor; prioritize short-walk or indoor-friendly options near 야외 공원."
    )
    assert result["recommended_action"] == (
        "Show indoor or short-walk alternatives around 야외 공원."
    )


def test_intervention_bad_air_quality_very_bad_discloses_observed_grade(
    monkeypatch,
) -> None:
    _patch_intervention_sources(
        monkeypatch,
        [],
        _p4_weather(
            weather_status="unknown",
            air_quality_status="bad",
            dust_grade="very_bad",
            aggregate="bad",
        ),
    )

    result = planner_service.intervention(lat=37.5, lng=127.0, radius_m=3000)

    assert result["trigger_type"] == "bad_air_quality"
    assert result["trigger_factors"] == [{"factor": "air_quality_dust_grade", "value": "very_bad"}]


def test_intervention_bad_air_quality_copy_localizes_ko_en(monkeypatch) -> None:
    _patch_intervention_sources(
        monkeypatch,
        [{"place_id": "p1", "name": "행궁동 카페"}],
        _p4_weather(
            weather_status="good",
            air_quality_status="bad",
            dust_grade="bad",
            aggregate="bad",
        ),
    )

    ko = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000, language="ko")
    en = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000, language="en")

    assert "미세먼지가 나빠요" in ko["reason"]
    assert "Air quality is poor" in en["reason"]
    assert "날씨가 좋지 않아요" not in ko["reason"]
    assert "Weather is not ideal" not in en["reason"]
    assert "Weather is not ideal" not in ko["reason"]
    assert "날씨가 좋지 않아요" not in en["reason"]


def test_intervention_weather_and_air_quality_combine_truthfully(monkeypatch) -> None:
    _patch_intervention_sources(
        monkeypatch,
        [],
        _p4_weather(
            weather_status="bad",
            air_quality_status="bad",
            dust_grade="bad",
            aggregate="bad",
        ),
    )

    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000, language="en")

    assert result["trigger_type"] == "bad_weather_and_air_quality"
    assert result["trigger_factors"] == [
        {"factor": "weather_outdoor_status", "value": "bad"},
        {"factor": "air_quality_dust_grade", "value": "bad"},
    ]
    assert result["reason"].startswith("Weather and air quality are both poor")

    ko = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000, language="ko")
    assert "날씨와 미세먼지가 모두 좋지 않아요" in ko["reason"]


def test_intervention_air_quality_and_closure_combine(monkeypatch) -> None:
    monkeypatch.setattr(
        planner_service,
        "get_settings",
        lambda: SimpleNamespace(feature_flags={"PLAN_FULL_SLOTS": True}),
    )
    monkeypatch.setattr(planner_service, "is_within_hours", lambda *a, **k: False)
    _patch_intervention_sources(
        monkeypatch,
        [{"place_id": "p1", "name": "x"}],
        _p4_weather(
            weather_status="good",
            air_quality_status="bad",
            dust_grade="bad",
            aggregate="bad",
        ),
    )

    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)

    assert result["trigger_type"] == "bad_air_quality_and_closure"
    assert result["trigger_factors"] == [
        {"factor": "air_quality_dust_grade", "value": "bad"},
        {"factor": "slot_closure_state", "value": "closed", "period": "afternoon"},
    ]


def test_intervention_weather_air_quality_and_closure_triple_trigger(monkeypatch) -> None:
    monkeypatch.setattr(
        planner_service,
        "get_settings",
        lambda: SimpleNamespace(feature_flags={"PLAN_FULL_SLOTS": True}),
    )
    monkeypatch.setattr(planner_service, "is_within_hours", lambda *a, **k: False)
    _patch_intervention_sources(
        monkeypatch,
        [{"place_id": "p1", "name": "x"}],
        _p4_weather(
            weather_status="bad",
            air_quality_status="bad",
            dust_grade="bad",
            aggregate="bad",
        ),
    )

    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)

    assert result["trigger_type"] == "bad_weather_and_air_quality_and_closure"
    assert [factor["factor"] for factor in result["trigger_factors"]] == [
        "weather_outdoor_status",
        "air_quality_dust_grade",
        "slot_closure_state",
    ]


@pytest.mark.parametrize(
    ("is_bad_weather", "is_bad_air_quality", "is_closure", "expected"),
    [
        (False, False, False, None),
        (True, False, False, "bad_weather"),
        (False, True, False, "bad_air_quality"),
        (False, False, True, "closure_detected"),
        (True, True, False, "bad_weather_and_air_quality"),
        (True, False, True, "bad_weather_and_closure"),
        (False, True, True, "bad_air_quality_and_closure"),
        (True, True, True, "bad_weather_and_air_quality_and_closure"),
    ],
)
def test_intervention_trigger_type_air_quality_combination_logic(
    is_bad_weather: bool,
    is_bad_air_quality: bool,
    is_closure: bool,
    expected: str | None,
) -> None:
    assert (
        planner_service._intervention_trigger_type(
            is_bad_weather=is_bad_weather,
            is_closure=is_closure,
            is_bad_air_quality=is_bad_air_quality,
        )
        == expected
    )


def test_intervention_unknown_air_quality_does_not_intervene(monkeypatch) -> None:
    """Unknown dust grade / unknown weather → no invented cause, no trigger."""
    _patch_intervention_sources(
        monkeypatch,
        [{"place_id": "p1", "name": "x"}],
        _p4_weather(
            weather_status="unknown",
            air_quality_status="unknown",
            dust_grade="unknown",
            aggregate="unknown",
        ),
    )

    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)

    assert result["should_intervene"] is False
    assert result["trigger_type"] is None
    assert result["trigger_factors"] == []
    assert result["alternative_slot"] is None


def test_intervention_unknown_dust_with_bad_weather_keeps_weather_only(
    monkeypatch,
) -> None:
    _patch_intervention_sources(
        monkeypatch,
        [],
        _p4_weather(
            weather_status="bad",
            air_quality_status="unknown",
            dust_grade="unknown",
            aggregate="bad",
        ),
    )

    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)

    # Unknown AQ is not a cause and never collapses into the weather factor.
    assert result["trigger_type"] == "bad_weather"
    assert result["trigger_factors"] == [{"factor": "weather_outdoor_status", "value": "bad"}]


def test_intervention_bad_air_quality_finds_indoor_alternative(monkeypatch) -> None:
    places = [
        {"place_id": "p1", "name": "야외 공원", "category": "attraction", "is_indoor": False},
        {"place_id": "p2", "name": "실내 미술관", "category": "culture_venue", "is_indoor": True},
    ]
    _patch_intervention_sources(
        monkeypatch,
        places,
        _p4_weather(
            weather_status="good",
            air_quality_status="bad",
            dust_grade="bad",
            aggregate="bad",
        ),
    )

    result = planner_service.intervention(lat=37.5, lng=127.0, radius_m=3000, language="ko")

    assert result["should_intervene"] is True
    alt = result["alternative_slot"]
    assert alt is not None, "adverse AQ should offer an indoor alternative"
    assert alt["place"]["place_id"] == "p2"
    assert alt["indoor_outdoor"] == "indoor"
    assert alt["place"]["place_id"] != result["place"]["place_id"]


def test_intervention_bad_air_quality_no_indoor_alternative_honest_null(
    monkeypatch,
) -> None:
    places = [
        {"place_id": "p1", "name": "야외 공원", "category": "attraction", "is_indoor": False},
        {"place_id": "p2", "name": "야외 카페", "category": "restaurant", "is_indoor": False},
    ]
    _patch_intervention_sources(
        monkeypatch,
        places,
        _p4_weather(
            weather_status="unknown",
            air_quality_status="bad",
            dust_grade="bad",
            aggregate="bad",
        ),
    )

    result = planner_service.intervention(lat=37.5, lng=127.0, radius_m=3000, language="ko")

    assert result["should_intervene"] is True
    assert result["alternative_slot"] is None, "no indoor provenance → honest null"


def test_intervention_good_air_quality_bad_weather_keeps_existing_payload(
    monkeypatch,
) -> None:
    """Weather-only cause keeps the exact pre-P4 bad_weather payload bytes."""
    _patch_intervention_sources(
        monkeypatch,
        [{"place_id": "p1", "name": "남산서울타워", "category": "landmark"}],
        _p4_weather(
            weather_status="bad",
            air_quality_status="good",
            dust_grade="good",
            aggregate="bad",
        ),
    )

    result = planner_service.intervention(lat=37.5665, lng=126.978, radius_m=2000)

    assert result["should_intervene"] is True
    assert result["trigger_type"] == "bad_weather"
    assert result["trigger_factors"] == [{"factor": "weather_outdoor_status", "value": "bad"}]
    assert result["reason"] == (
        "Weather is not ideal; prioritize short-walk or indoor-friendly options near 남산서울타워."
    )
    assert result["recommended_action"] == (
        "Show indoor or short-walk alternatives around 남산서울타워."
    )


def test_intervention_legacy_payload_without_provenance_keeps_bad_weather(
    monkeypatch,
) -> None:
    """Pre-P4 payloads (no provenance keys) keep the aggregate interpretation —
    even a bad dust grade on a legacy payload must not invent an AQ cause."""
    monkeypatch.setattr(planner_service, "list_places", lambda **kw: {"source": "db", "places": []})
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kw: {"source": "db", "outdoor_status": "bad", "dust": {"grade": "bad"}},
    )

    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)

    assert result["should_intervene"] is True
    assert result["trigger_type"] == "bad_weather"
    assert result["trigger_factors"] == [{"factor": "weather_outdoor_status", "value": "bad"}]


@pytest.mark.parametrize(
    ("weather_status", "air_quality_status", "expected_fragment"),
    [
        ("good", "bad", "Air quality is poor"),
        ("unknown", "bad", "Air quality is poor"),
        ("bad", "bad", "Weather and air quality are both poor"),
    ],
)
def test_intervention_reason_air_quality_branches(
    weather_status: str, air_quality_status: str, expected_fragment: str
) -> None:
    reason = planner_service._intervention_reason(
        weather_status=weather_status,
        candidate_name="한강공원",
        air_quality_status=air_quality_status,
    )
    action = planner_service._recommended_action(
        weather_status=weather_status,
        candidate_name="한강공원",
        air_quality_status=air_quality_status,
    )

    assert expected_fragment in reason
    assert action == "Show indoor or short-walk alternatives around 한강공원."
