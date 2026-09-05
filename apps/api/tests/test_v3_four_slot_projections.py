"""V3 four-slot enrichment projections (D2/D3/D4/D5/D6) — PLAN_FULL_SLOTS gated.

Covers the V3-A backend half: per-slot forecast_window / air_quality_bad /
closure_state projections, swappable_alternatives population, the closure-driven
intervention trigger, the estimated_opening_hours schema hoist, and a flag-off
byte-for-byte regression guard. Honest states only — no fabricated weather/AQ.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace

import pytest

from apps.api.app.services import planner_service

# --- flag-toggle helper (mirrors test_places_service._fake_settings pattern) ------------


def _enable_full_slots(monkeypatch, *, enabled: bool = True) -> None:
    monkeypatch.setattr(
        planner_service,
        "get_settings",
        lambda: SimpleNamespace(feature_flags={"PLAN_FULL_SLOTS": enabled}),
    )


# ======================================================================================
# D4 — closure_state projection
# ======================================================================================


@pytest.mark.parametrize(
    ("category", "period", "expected"),
    [
        # morning 09:00: attraction 09-18 → within → open.
        ("attraction", "morning", "open"),
        # morning 09:00: culture_venue 10-19 → before open → closed.
        ("culture_venue", "morning", "closed"),
        # dinner 18:00: attraction 09-18 → 18:00 inclusive → open.
        ("attraction", "dinner", "open"),
    ],
)
def test_closure_state_open_or_closed_from_category_estimate(
    monkeypatch, category, period, expected
) -> None:
    _enable_full_slots(monkeypatch)
    weather = {"outdoor_status": "good", "forecast": [], "dust": {"grade": "good"}}
    slot = planner_service._plan_slot(
        period=period,
        title=period,
        place={"place_id": "p", "category": category, "is_indoor": False},
        weather_hint="good",
        unavailable_reason="x",
        language="en",
        weather=weather,
        full_slots=True,
    )
    assert slot["closure_state"] == expected


def test_closure_state_unknown_when_no_place(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    slot = planner_service._plan_slot(
        period="morning",
        title="Morning",
        place=None,
        weather_hint=None,
        unavailable_reason="none",
        language="en",
        weather={"outdoor_status": "unknown"},
        full_slots=True,
    )
    assert slot["closure_state"] == "unknown"


# ======================================================================================
# D2 — forecast_window projection
# ======================================================================================


def _fcst(hour_kst: int) -> dict:
    # ISO time at the given KST hour; neutral values for temp/icon.
    dt = datetime(2026, 8, 13, hour_kst, 0, tzinfo=timezone(timedelta(hours=9)))
    return {"time": dt.isoformat(), "temp": "20.0", "icon": "partly-cloudy"}


def test_forecast_window_picks_nearest_and_breaks_ties_earliest(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    # Slot morning start = 09:00 KST. 08:00 and 10:00 are equidistant (delta 60);
    # earliest tie-break (contract A4) selects 08:00. 12:00 is farther.
    weather = {
        "outdoor_status": "good",
        "forecast": [_fcst(10), _fcst(8), _fcst(12)],
        "dust": {"grade": "good"},
    }
    slot = planner_service._plan_slot(
        period="morning",
        title="Morning",
        place={"place_id": "p", "category": "attraction"},
        weather_hint="good",
        unavailable_reason="x",
        language="en",
        weather=weather,
        full_slots=True,
    )
    assert slot["forecast_window"] == {
        "time": _fcst(8)["time"],
        "temp": "20.0",
        "icon": "partly-cloudy",
    }


def test_forecast_window_nearest_non_tie(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    # afternoon start = 14:00; 13:00 (delta 60) beats 17:00 (delta 180).
    weather = {
        "outdoor_status": "good",
        "forecast": [_fcst(17), _fcst(13)],
        "dust": {"grade": "good"},
    }
    slot = planner_service._plan_slot(
        period="afternoon",
        title="Afternoon",
        place={"place_id": "p", "category": "attraction"},
        weather_hint="good",
        unavailable_reason="x",
        language="en",
        weather=weather,
        full_slots=True,
    )
    assert slot["forecast_window"]["time"] == _fcst(13)["time"]


def test_forecast_window_null_when_forecast_empty(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    slot = planner_service._plan_slot(
        period="morning",
        title="Morning",
        place={"place_id": "p", "category": "attraction"},
        weather_hint="unknown",
        unavailable_reason="x",
        language="en",
        weather={"outdoor_status": "unknown", "forecast": [], "dust": {"grade": "unknown"}},
        full_slots=True,
    )
    # Honest empty: AirKorea-only / unavailable paths yield no forecast window.
    assert slot["forecast_window"] is None


# ======================================================================================
# D3 — air_quality_bad projection
# ======================================================================================


@pytest.mark.parametrize(
    ("indoor_outdoor", "grade", "expected"),
    [
        # Outdoor slots: bad/very_bad → True, good/normal → False, unknown → None.
        (False, "bad", True),
        (False, "very_bad", True),
        (False, "good", False),
        (False, "normal", False),
        (False, "unknown", None),
        # Indoor slot: AQ is outdoor-relevant only → null even when dust is bad.
        (True, "bad", None),
        (True, "very_bad", None),
    ],
)
def test_air_quality_bad_projects_dust_grade_for_outdoor(
    monkeypatch, indoor_outdoor, grade, expected
) -> None:
    _enable_full_slots(monkeypatch)
    slot = planner_service._plan_slot(
        period="lunch",
        title="Lunch",
        place={"place_id": "p", "category": "attraction", "is_indoor": indoor_outdoor},
        weather_hint="good",
        unavailable_reason="x",
        language="en",
        weather={"outdoor_status": "good", "forecast": [], "dust": {"grade": grade}},
        full_slots=True,
    )
    assert slot["air_quality_bad"] is expected


def test_air_quality_bad_null_when_dust_absent(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    slot = planner_service._plan_slot(
        period="morning",
        title="Morning",
        place={"place_id": "p", "category": "attraction", "is_indoor": False},
        weather_hint="good",
        unavailable_reason="x",
        language="en",
        weather={"outdoor_status": "good", "forecast": []},  # no dust key
        full_slots=True,
    )
    assert slot["air_quality_bad"] is None


# ======================================================================================
# D6 — swappable_alternatives populated from the candidate pool
# ======================================================================================


def _cand(pid: str, category: str = "attraction") -> dict:
    return {"place_id": pid, "category": category, "name": pid}


def test_swappable_alternatives_populated_from_pool_leftovers(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    candidates = [_cand("a"), _cand("b"), _cand("c"), _cand("d"), _cand("e"), _cand("f")]
    slots = planner_service._daily_plan_slots(
        place_candidates=candidates,
        weather={"outdoor_status": "good", "forecast": [], "dust": {"grade": "good"}},
        language="en",
    )
    filled = [s for s in slots if s["place"] is not None]
    leftover_ids = {"e", "f"}
    # Every filled slot offers the same two leftovers (same category, cap not exceeded).
    for slot in filled:
        ids = {p["place_id"] for p in slot["swappable_alternatives"]}
        assert ids == leftover_ids
    # Unfilled slots (none here — 6 candidates for 4 slots) would be honest [].
    assert len(filled) == 4


def test_swappable_alternatives_same_category_preference_then_other(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    # 2 restaurants (→ lunch/dinner) + 5 attractions (→ morning/afternoon + 3 leftovers).
    candidates = [
        _cand("r1", "restaurant"),
        _cand("r2", "restaurant"),
        _cand("n1"),
        _cand("n2"),
        _cand("n3"),
        _cand("n4"),
        _cand("n5"),
    ]
    slots = planner_service._daily_plan_slots(
        place_candidates=candidates,
        weather={"outdoor_status": "good", "forecast": [], "dust": {"grade": "good"}},
        language="en",
    )
    by_period = {s["period"]: s for s in slots}
    morning = by_period["morning"]
    lunch = by_period["lunch"]
    # Morning (attraction): same-category leftovers first.
    assert {p["place_id"] for p in morning["swappable_alternatives"]} == {"n3", "n4", "n5"}
    # Lunch (restaurant): no leftover restaurants → falls back to other-category.
    assert {p["place_id"] for p in lunch["swappable_alternatives"]} == {"n3", "n4", "n5"}


def test_swappable_alternatives_capped_at_three(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    # 4 restaurants + 4 attractions → 4 leftovers after assignment.
    candidates = [
        _cand("r1", "restaurant"),
        _cand("r2", "restaurant"),
        _cand("r3", "restaurant"),
        _cand("r4", "restaurant"),
        _cand("n1"),
        _cand("n2"),
        _cand("n3"),
        _cand("n4"),
    ]
    slots = planner_service._daily_plan_slots(
        place_candidates=candidates,
        weather={"outdoor_status": "good", "forecast": [], "dust": {"grade": "good"}},
        language="en",
    )
    for slot in slots:
        if slot["place"] is not None:
            assert len(slot["swappable_alternatives"]) <= 3


def test_swappable_alternatives_empty_when_pool_exhausted(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    candidates = [_cand("a"), _cand("b")]  # fewer than 4 → no leftovers.
    slots = planner_service._daily_plan_slots(
        place_candidates=candidates,
        weather={"outdoor_status": "good"},
        language="en",
    )
    for slot in slots:
        assert slot["swappable_alternatives"] == []


# ======================================================================================
# D5 — closure-driven intervention trigger
# ======================================================================================


def test_intervention_closure_detected_when_slot_closed(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    # afternoon (14:00) is within every category estimate, so force is_within_hours →
    # False to exercise the closure path end-to-end (offline projection only).
    monkeypatch.setattr(planner_service, "is_within_hours", lambda *a, **k: False)
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kw: {"source": "db", "outdoor_status": "good", "forecast": []},
    )
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kw: {"source": "db", "places": [{"place_id": "p1", "name": "x"}]},
    )
    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)
    assert result["trigger_type"] == "closure_detected"
    assert result["should_intervene"] is True
    assert result["trigger_factors"] == [
        {"factor": "slot_closure_state", "value": "closed", "period": "afternoon"}
    ]


def test_intervention_bad_weather_and_closure_combines_trigger(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    monkeypatch.setattr(planner_service, "is_within_hours", lambda *a, **k: False)
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kw: {
            "source": "db",
            "outdoor_status": "bad",
            "weather_outdoor_status": "bad",
            "forecast": [],
        },
    )
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kw: {"source": "db", "places": [{"place_id": "p1", "name": "x"}]},
    )
    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)
    assert result["trigger_type"] == "bad_weather_and_closure"
    factors = {f["factor"] for f in result["trigger_factors"]}
    assert factors == {"weather_outdoor_status", "slot_closure_state"}
    assert result["should_intervene"] is True


@pytest.mark.parametrize(
    ("is_bad_weather", "is_closure", "expected"),
    [
        (False, False, None),
        (True, False, "bad_weather"),
        (False, True, "closure_detected"),
        (True, True, "bad_weather_and_closure"),
    ],
)
def test_intervention_trigger_type_combination_logic(is_bad_weather, is_closure, expected) -> None:
    assert (
        planner_service._intervention_trigger_type(
            is_bad_weather=is_bad_weather, is_closure=is_closure
        )
        == expected
    )


# ======================================================================================
# Schema — estimated_opening_hours hoist + closed schemas + trigger_factors period
# ======================================================================================


def _exported_schema() -> dict:
    from apps.api.app.tools.export_openapi import export_openapi_schema

    return export_openapi_schema(Path("/tmp/lala-v3-schema-check.json"))


def test_schema_estimated_opening_hours_is_sibling_of_opening_hours_valid() -> None:
    schema = _exported_schema()
    slot_props = schema["components"]["schemas"]["DailyPlanSlot"]["properties"]
    # Hoist fix (§0.3 NEEDS_CODE): estimated_opening_hours must be a top-level property,
    # no longer nested inside opening_hours_valid.
    assert "estimated_opening_hours" in slot_props
    assert "estimated_opening_hours" not in str(slot_props["opening_hours_valid"])


def test_schema_slot_additive_fields_and_closed() -> None:
    schema = _exported_schema()
    slot = schema["components"]["schemas"]["DailyPlanSlot"]
    for field in ("closure_state", "forecast_window", "air_quality_bad"):
        assert field in slot["properties"]
    assert slot["additionalProperties"] is False
    # closure_state enum + forecast_window refs ForecastItem.
    closure = slot["properties"]["closure_state"]["anyOf"][0]
    assert closure["enum"] == ["open", "closed", "unknown"]
    assert slot["properties"]["forecast_window"]["anyOf"][0] == {
        "$ref": "#/components/schemas/ForecastItem"
    }


def test_schema_intervention_closed_and_trigger_factors_period_optional() -> None:
    schema = _exported_schema()
    intervention = schema["components"]["schemas"]["InterventionData"]
    assert intervention["additionalProperties"] is False
    tf_items = intervention["properties"]["trigger_factors"]["items"]
    # period is an additive OPTIONAL property; required stays [factor, value]; still closed.
    assert set(tf_items["properties"]) == {"factor", "value", "period"}
    assert tf_items["required"] == ["factor", "value"]
    assert tf_items["additionalProperties"] is False


# ======================================================================================
# Flag-OFF regression guard — byte-for-byte pre-V3 behavior
# ======================================================================================


_PRE_V3_SLOT_KEYS = {
    "period",
    "title",
    "place",
    "weather_hint",
    "start_time",
    "stay_duration_minutes",
    "travel_time_from_previous_minutes",
    "opening_hours_valid",
    "estimated_opening_hours",
    "indoor_outdoor",
    "recommendation_reason",
    "local_franchise_confidence",
    "swappable_alternatives",
    "unavailable_reason",
}


def test_flag_off_slots_omit_new_keys_and_keep_swappable_empty(monkeypatch) -> None:
    _enable_full_slots(monkeypatch, enabled=False)
    candidates = [_cand("a"), _cand("b"), _cand("c"), _cand("d"), _cand("e"), _cand("f")]
    slots = planner_service._daily_plan_slots(
        place_candidates=candidates,
        weather={
            "outdoor_status": "good",
            "forecast": [_fcst(9)],
            "dust": {"grade": "bad"},
        },
        language="en",
    )
    assert len(slots) == 4
    for slot in slots:
        # No V3 keys leak when the flag is off; key set is exactly pre-V3.
        assert set(slot.keys()) == _PRE_V3_SLOT_KEYS
        assert slot["swappable_alternatives"] == []


def test_flag_off_intervention_trigger_unchanged(monkeypatch) -> None:
    _enable_full_slots(monkeypatch, enabled=False)
    monkeypatch.setattr(planner_service, "is_within_hours", lambda *a, **k: False)
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kw: {"source": "db", "outdoor_status": "good", "forecast": []},
    )
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kw: {"source": "db", "places": [{"place_id": "p1", "name": "x"}]},
    )
    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)
    # Flag off: closure is ignored → pre-V3 weather-only trigger semantics.
    assert result["trigger_type"] is None
    assert result["should_intervene"] is False
    assert result["trigger_factors"] == []
    # original_slot carries no V3 keys.
    assert "closure_state" not in result["original_slot"]


# ======================================================================================
# P4 — closing-soon projection (distinct estimated-hours trigger, D4 sibling)
# ======================================================================================


def test_closing_soon_projected_true_for_dinner_culture_venue(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    # dinner(18:00) × culture_venue(10:00-19:00): 60min before the estimated close →
    # exactly the documented window boundary → closing_soon True (live combo).
    slot = planner_service._plan_slot(
        period="dinner",
        title="Dinner",
        place={"place_id": "p", "category": "culture_venue", "is_indoor": False},
        weather_hint="good",
        unavailable_reason="x",
        language="en",
        weather={"outdoor_status": "good", "forecast": [], "dust": {"grade": "good"}},
        full_slots=True,
    )
    assert slot["closing_soon"] is True
    # Mutually exclusive: closing-soon implies within-hours → open, never closed.
    assert slot["closure_state"] == "open"


def test_closing_soon_false_when_outside_window(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    # afternoon(14:00) × attraction(09:00-18:00): 240min left → outside the window.
    slot = planner_service._plan_slot(
        period="afternoon",
        title="Afternoon",
        place={"place_id": "p", "category": "attraction", "is_indoor": False},
        weather_hint="good",
        unavailable_reason="x",
        language="en",
        weather={"outdoor_status": "good", "forecast": [], "dust": {"grade": "good"}},
        full_slots=True,
    )
    assert slot["closing_soon"] is False
    assert slot["closure_state"] == "open"


@pytest.mark.parametrize(
    "category", ["restaurant", "attraction", "culture_venue", "event", "other"]
)
def test_closing_soon_never_coexists_with_closed_projection(monkeypatch, category) -> None:
    _enable_full_slots(monkeypatch)
    weather = {"outdoor_status": "good", "forecast": [], "dust": {"grade": "good"}}
    for period in ("morning", "lunch", "afternoon", "dinner"):
        slot = planner_service._plan_slot(
            period=period,
            title=period,
            place={"place_id": "p", "category": category, "is_indoor": False},
            weather_hint="good",
            unavailable_reason="x",
            language="en",
            weather=weather,
            full_slots=True,
        )
        # Structural mutual exclusivity across every period × category combination.
        assert not (slot["closing_soon"] is True and slot["closure_state"] == "closed")


def test_closing_soon_null_when_no_place(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    slot = planner_service._plan_slot(
        period="morning",
        title="Morning",
        place=None,
        weather_hint=None,
        unavailable_reason="none",
        language="en",
        weather={"outdoor_status": "unknown"},
        full_slots=True,
    )
    assert slot["closing_soon"] is None
    assert slot["closure_state"] == "unknown"


def _patch_hours(monkeypatch, hours: tuple[str, str]) -> None:
    # 검증자 정정 재현용 estimated-hours seam: _plan_slot 이 쓰는 추정 운영시간을
    # 임의 범위(자정 넘김/파손 포함)로 교체한다. 카테고리 데이터는 건드리지 않는다.
    monkeypatch.setattr(planner_service, "estimated_opening_hours", lambda category: hours)


def test_plan_slot_overnight_2000_0930_morning_open_and_closing_soon(monkeypatch) -> None:
    """검증자 지정 사례의 payload 증명: 20:00-09:30 × morning(09:00).

    09:00은 close(09:30) 이전(익일 측)이므로 운영중이고 마감까지 30분 →
    closure_state="open" + closing_soon=True (closed 와 공존하지 않음).
    """
    _enable_full_slots(monkeypatch)
    _patch_hours(monkeypatch, ("20:00", "09:30"))
    weather = {"outdoor_status": "good", "forecast": [], "dust": {"grade": "good"}}
    morning = planner_service._plan_slot(
        period="morning",
        title="Morning",
        place={"place_id": "p", "category": "attraction", "is_indoor": False},
        weather_hint="good",
        unavailable_reason="x",
        language="en",
        weather=weather,
        full_slots=True,
    )
    assert morning["opening_hours_valid"] is True
    assert morning["closure_state"] == "open"
    assert morning["closing_soon"] is True

    # 같은 범위의 나머지 period 시작(12:00/14:00/18:00)은 open-close 사이 →
    # closed + closing_soon False (상호 배제의 반대편 증명).
    for period in ("lunch", "afternoon", "dinner"):
        slot = planner_service._plan_slot(
            period=period,
            title=period,
            place={"place_id": "p", "category": "attraction", "is_indoor": False},
            weather_hint="good",
            unavailable_reason="x",
            language="en",
            weather=weather,
            full_slots=True,
        )
        assert slot["closure_state"] == "closed", period
        assert slot["closing_soon"] is False, period


def test_plan_slot_overnight_2000_0200_all_periods_closed_not_closing_soon(
    monkeypatch,
) -> None:
    """20:00-02:00: 표준 period 시작(09/12/14/18)은 모두 open-close 사이 →

    closed + closing_soon=False — payload 에서 두 상태가 공존하지 않는다.
    """
    _enable_full_slots(monkeypatch)
    _patch_hours(monkeypatch, ("20:00", "02:00"))
    weather = {"outdoor_status": "good", "forecast": [], "dust": {"grade": "good"}}
    for period in ("morning", "lunch", "afternoon", "dinner"):
        slot = planner_service._plan_slot(
            period=period,
            title=period,
            place={"place_id": "p", "category": "attraction", "is_indoor": False},
            weather_hint="good",
            unavailable_reason="x",
            language="en",
            weather=weather,
            full_slots=True,
        )
        assert slot["closure_state"] == "closed", period
        assert slot["closing_soon"] is False, period


@pytest.mark.parametrize(
    "hours",
    [
        ("2a:00", "22:00"),  # malformed open
        ("11:00", "２2:00"),  # fullwidth digit close
        ("11:000", "22:00"),  # overlong open
        ("24:00", "22:00"),  # out-of-range hour
        ("11:00", "22:60"),  # out-of-range minute
    ],
)
def test_plan_slot_malformed_hours_yield_unknown_not_positive(monkeypatch, hours) -> None:
    """파손된 추정시간은 payload 에서 unknown — 긍정(closing_soon/open) 판정 없음."""
    _enable_full_slots(monkeypatch)
    _patch_hours(monkeypatch, hours)
    slot = planner_service._plan_slot(
        period="afternoon",
        title="Afternoon",
        place={"place_id": "p", "category": "attraction", "is_indoor": False},
        weather_hint="good",
        unavailable_reason="x",
        language="en",
        weather={"outdoor_status": "good", "forecast": [], "dust": {"grade": "good"}},
        full_slots=True,
    )
    assert slot["opening_hours_valid"] is None
    assert slot["closure_state"] == "unknown"
    assert slot["closing_soon"] is None


def _patch_tight_hours(monkeypatch) -> None:
    # Estimated-hours seam: a "tight" category closes at 15:00 so the fixed
    # afternoon(14:00) original slot lands inside the 60min pre-close window;
    # every other category comfortably covers 14:00. Pure offline projection —
    # same pattern the closure tests use for is_within_hours.
    monkeypatch.setattr(
        planner_service,
        "estimated_opening_hours",
        lambda category: ("13:00", "15:00") if category == "tight" else ("09:00", "21:00"),
    )


def _good_weather() -> dict:
    # No weather/AQ provenance keys → both causes unknown; the only trigger can be
    # the estimated-hours cause.
    return {"source": "db", "outdoor_status": "good", "forecast": []}


def test_intervention_closing_soon_emits_distinct_trigger(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    _patch_tight_hours(monkeypatch)
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kw: _good_weather(),
    )
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kw: {
            "source": "db",
            "places": [
                {"place_id": "p1", "name": "x", "category": "tight"},
                {"place_id": "p2", "name": "y", "category": "restaurant"},
            ],
        },
    )
    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)
    assert result["trigger_type"] == "closing_soon"
    assert result["should_intervene"] is True
    assert result["trigger_factors"] == [
        {"factor": "slot_closing_soon", "value": "within_estimated_window", "period": "afternoon"}
    ]
    # Sole estimated-hours cause: reason/action name it, never weather or air quality.
    assert result["reason"] == (
        "This slot is near the estimated closing time for x (estimated hours 13:00-15:00); "
        "the actual opening status needs a check."
    )
    assert result["recommended_action"] == (
        "Check the estimated closing time for x and review other nearby options too."
    )
    assert "Weather" not in result["reason"]
    assert "Air quality" not in result["reason"]
    # Alternative = the other real candidate (p2), distinct from the original.
    assert (result["alternative_slot"] or {}).get("place", {}).get("place_id") == "p2"
    assert result["alternative_slot"]["closing_soon"] is False

    ko = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000, language="ko")
    assert ko["reason"] == (
        "이번 일정 시간은 x의 추정 운영시간(13:00-15:00) 마감에 가까워요. "
        "실제 영업 여부는 확인이 필요해요."
    )
    assert (
        ko["recommended_action"]
        == "x의 추정 마감 시간을 확인하고 근처 다른 옵션도 함께 검토해 보세요."
    )
    assert "날씨" not in ko["reason"]
    assert "미세먼지" not in ko["reason"]


def test_intervention_closing_soon_alternative_honest_null(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    _patch_tight_hours(monkeypatch)
    monkeypatch.setattr(planner_service, "current_weather", lambda **kw: _good_weather())
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kw: {
            "source": "db",
            "places": [{"place_id": "p1", "name": "x", "category": "tight"}],
        },
    )
    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)
    # No second real candidate → honest null; no fixture/demo place is invented.
    assert result["trigger_type"] == "closing_soon"
    assert result["alternative_slot"] is None


def test_intervention_closing_soon_combines_with_bad_weather(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    _patch_tight_hours(monkeypatch)
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kw: {
            "source": "db",
            "outdoor_status": "bad",
            "weather_outdoor_status": "bad",
            "forecast": [],
        },
    )
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kw: {
            "source": "db",
            "places": [{"place_id": "p1", "name": "x", "category": "tight"}],
        },
    )
    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)
    assert result["trigger_type"] == "bad_weather_and_closing_soon"
    assert result["trigger_factors"] == [
        {"factor": "weather_outdoor_status", "value": "bad"},
        {"factor": "slot_closing_soon", "value": "within_estimated_window", "period": "afternoon"},
    ]
    # Combined cause names each actual cause.
    assert result["reason"] == (
        "Weather is not ideal. This slot is near the estimated closing time for x "
        "(estimated hours 13:00-15:00); the actual opening status needs a check."
    )


def test_intervention_closing_soon_combines_with_bad_air_quality(monkeypatch) -> None:
    _enable_full_slots(monkeypatch)
    _patch_tight_hours(monkeypatch)
    monkeypatch.setattr(
        planner_service,
        "current_weather",
        lambda **kw: {
            "source": "db",
            "outdoor_status": "bad",
            "air_quality_outdoor_status": "bad",
            "dust": {"grade": "bad"},
            "forecast": [],
        },
    )
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kw: {
            "source": "db",
            "places": [{"place_id": "p1", "name": "x", "category": "tight"}],
        },
    )
    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)
    assert result["trigger_type"] == "bad_air_quality_and_closing_soon"
    assert [f["factor"] for f in result["trigger_factors"]] == [
        "air_quality_dust_grade",
        "slot_closing_soon",
    ]
    assert result["reason"].startswith(
        "Air quality is poor. This slot is near the estimated closing time"
    )


def test_intervention_closing_soon_flag_off_never_triggers(monkeypatch) -> None:
    _enable_full_slots(monkeypatch, enabled=False)
    _patch_tight_hours(monkeypatch)
    monkeypatch.setattr(planner_service, "current_weather", lambda **kw: _good_weather())
    monkeypatch.setattr(
        planner_service,
        "list_places",
        lambda **kw: {
            "source": "db",
            "places": [{"place_id": "p1", "name": "x", "category": "tight"}],
        },
    )
    result = planner_service.intervention(lat=37.2, lng=127.0, radius_m=2000)
    # Flag off: pre-V3 semantics byte-for-byte — no trigger, no closing_soon key.
    assert result["trigger_type"] is None
    assert result["should_intervene"] is False
    assert result["trigger_factors"] == []
    assert result["alternative_slot"] is None
    assert "closing_soon" not in result["original_slot"]


@pytest.mark.parametrize(
    (
        "is_bad_weather",
        "is_bad_air_quality",
        "is_closure",
        "is_closing_soon",
        "expected",
    ),
    [
        (False, False, False, False, None),
        (False, False, False, True, "closing_soon"),
        (True, False, False, True, "bad_weather_and_closing_soon"),
        (False, True, False, True, "bad_air_quality_and_closing_soon"),
        (True, True, False, True, "bad_weather_and_air_quality_and_closing_soon"),
        # Closure and closing-soon are mutually exclusive by construction; if a
        # degenerate input ever set both, closure deterministically dominates.
        (False, False, True, True, "closure_detected"),
        (True, False, True, True, "bad_weather_and_closure"),
        # Pre-existing rows stay byte-for-byte with is_closing_soon=False.
        (True, False, False, False, "bad_weather"),
        (False, True, False, False, "bad_air_quality"),
        (False, False, True, False, "closure_detected"),
        (True, True, False, False, "bad_weather_and_air_quality"),
        (True, False, True, False, "bad_weather_and_closure"),
        (False, True, True, False, "bad_air_quality_and_closure"),
        (True, True, True, False, "bad_weather_and_air_quality_and_closure"),
    ],
)
def test_intervention_trigger_type_closing_soon_combination_logic(
    is_bad_weather: bool,
    is_bad_air_quality: bool,
    is_closure: bool,
    is_closing_soon: bool,
    expected: str | None,
) -> None:
    assert (
        planner_service._intervention_trigger_type(
            is_bad_weather=is_bad_weather,
            is_closure=is_closure,
            is_bad_air_quality=is_bad_air_quality,
            is_closing_soon=is_closing_soon,
        )
        == expected
    )


def test_schema_slot_closing_soon_additive_bool() -> None:
    schema = _exported_schema()
    slot = schema["components"]["schemas"]["DailyPlanSlot"]
    assert "closing_soon" in slot["properties"]
    prop = slot["properties"]["closing_soon"]
    assert prop["anyOf"] == [{"type": "boolean"}, {"type": "null"}]
    assert slot["additionalProperties"] is False
    # The description keeps the estimated (non-authority) wording.
    assert "estimated" in prop["description"]


def test_schema_intervention_trigger_type_documents_closing_soon() -> None:
    schema = _exported_schema()
    intervention = schema["components"]["schemas"]["InterventionData"]
    description = intervention["properties"]["trigger_type"]["description"]
    for trigger in (
        "closing_soon",
        "bad_weather_and_closing_soon",
        "bad_air_quality_and_closing_soon",
        "bad_weather_and_air_quality_and_closing_soon",
    ):
        assert trigger in description
