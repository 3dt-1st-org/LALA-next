from apps.api.app.services.opening_hours_service import (
    CLOSING_SOON_WINDOW_MINUTES,
    estimated_opening_hours,
    is_closing_soon,
    is_within_hours,
)


def test_restaurant_hours():
    o, c = estimated_opening_hours("restaurant")
    assert o == "11:00" and c == "22:00"


def test_attraction_hours():
    o, c = estimated_opening_hours("attraction")
    assert o == "09:00" and c == "18:00"


def test_culture_venue_hours():
    o, c = estimated_opening_hours("culture_venue")
    assert o == "10:00" and c == "19:00"


def test_default_hours():
    o, c = estimated_opening_hours("unknown")
    assert o == "09:00" and c == "21:00"


def test_within_true():
    assert is_within_hours("12:00", "11:00", "22:00") is True


def test_within_false():
    assert is_within_hours("23:00", "11:00", "22:00") is False


def test_within_edge():
    assert is_within_hours("11:00", "11:00", "22:00") is True


def test_within_none():
    assert is_within_hours(None, "11:00", "22:00") is None


# ---------------------------------------------------------------------------
# P4 closing-soon — bounded, deterministic window from slot start to estimated
# close. Boundary matrix: before-window / in-window / exact-close / after-close.
# ---------------------------------------------------------------------------


def test_closing_soon_window_constant_is_documented_and_bounded() -> None:
    # One named deterministic constant; positive and minute-bounded.
    assert CLOSING_SOON_WINDOW_MINUTES == 60
    assert 0 < CLOSING_SOON_WINDOW_MINUTES <= 24 * 60


def test_closing_soon_before_window_is_false() -> None:
    # 11:00-22:00, window 60 → in-window starts at 21:00. 20:59 is before it.
    assert is_closing_soon("20:59", "11:00", "22:00") is False


def test_closing_soon_window_lower_boundary_is_inclusive() -> None:
    # Exactly close - 60min → inside the window.
    assert is_closing_soon("21:00", "11:00", "22:00") is True


def test_closing_soon_inside_window_is_true() -> None:
    assert is_closing_soon("21:30", "11:00", "22:00") is True


def test_closing_soon_exact_close_is_true_and_within_hours() -> None:
    # is_within_hours treats the exact close minute as within-hours (open), so the
    # remaining-0 case stays closing-soon — never both closed and closing-soon.
    assert is_closing_soon("22:00", "11:00", "22:00") is True
    assert is_within_hours("22:00", "11:00", "22:00") is True


def test_closing_soon_after_close_is_false() -> None:
    assert is_closing_soon("22:01", "11:00", "22:00") is False


def test_closing_soon_before_open_is_false() -> None:
    # Not closing-soon — the place has not opened yet for the day.
    assert is_closing_soon("10:30", "11:00", "22:00") is False


def test_closing_soon_mutually_exclusive_with_closed() -> None:
    # Every minute of the day resolves to at most one of closed / closing-soon.
    for minute in range(0, 24 * 60):
        slot = f"{minute // 60:02d}:{minute % 60:02d}"
        within = is_within_hours(slot, "10:00", "18:00")
        soon = is_closing_soon(slot, "10:00", "18:00")
        if within is True:
            assert soon is not None
        else:
            # Outside hours → closed; closing-soon must never be True there.
            assert soon is False


def test_closing_soon_missing_or_malformed_slot_time_is_unknown() -> None:
    assert is_closing_soon(None, "11:00", "22:00") is None
    assert is_closing_soon("", "11:00", "22:00") is None
    assert is_closing_soon("9x", "11:00", "22:00") is None
    assert is_closing_soon("2a:0b", "11:00", "22:00") is None


def test_closing_soon_malformed_hours_are_unknown() -> None:
    assert is_closing_soon("21:30", "xx:00", "22:00") is None
    assert is_closing_soon("21:30", "11:00", "") is None
    assert is_closing_soon("21:30", "11", "22:00") is None


def test_closing_soon_open_equal_close_is_unknown() -> None:
    # Degenerate 24h-shaped range: no defined closing time → never guess.
    assert is_closing_soon("12:00", "10:00", "10:00") is None


def test_closing_soon_non_positive_window_is_unknown() -> None:
    assert is_closing_soon("21:30", "11:00", "22:00", window_minutes=0) is None
    assert is_closing_soon("21:30", "11:00", "22:00", window_minutes=-5) is None


def test_closing_soon_overnight_range_evening_side() -> None:
    # 20:00-02:00 overnight: 23:00 has 180min left → outside a 60min window.
    assert is_closing_soon("23:00", "20:00", "02:00") is False


def test_closing_soon_overnight_range_next_morning_inside_window() -> None:
    # 01:00 → 60min before the 02:00 close (inclusive lower bound) → True.
    assert is_closing_soon("01:00", "20:00", "02:00") is True
    assert is_closing_soon("01:01", "20:00", "02:00") is True


def test_closing_soon_overnight_range_after_close_is_false() -> None:
    assert is_closing_soon("03:00", "20:00", "02:00") is False
    assert is_closing_soon("19:30", "20:00", "02:00") is False


def test_closing_soon_overnight_exact_close_is_true() -> None:
    assert is_closing_soon("02:00", "20:00", "02:00") is True


def test_closing_soon_real_category_projection_examples() -> None:
    # dinner(18:00) × culture_venue(10:00-19:00) → 60min left → True (live combo).
    assert is_closing_soon("18:00", *estimated_opening_hours("culture_venue")) is True
    # afternoon(14:00) × attraction(09:00-18:00) → 240min left → False.
    assert is_closing_soon("14:00", *estimated_opening_hours("attraction")) is False
    # dinner(18:00) × restaurant(11:00-22:00) → 240min left → False.
    assert is_closing_soon("18:00", *estimated_opening_hours("restaurant")) is False
