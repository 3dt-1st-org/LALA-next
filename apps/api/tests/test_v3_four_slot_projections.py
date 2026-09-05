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
