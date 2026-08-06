from apps.api.app.services.opening_hours_service import (
    estimated_opening_hours,
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
