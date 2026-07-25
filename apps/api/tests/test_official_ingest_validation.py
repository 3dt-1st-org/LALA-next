"""Focused tests for official-source coordinate validation + rejection counters."""

from __future__ import annotations

from apps.api.app.services import official_ingest_validation as validation


def test_valid_korean_coordinate_is_returned():
    # Suwon city hall area.
    assert validation.validate_official_coordinate(37.2636, 127.0286) == (37.2636, 127.0286)


def test_null_island_sentinel_is_dropped():
    assert validation.validate_official_coordinate(0, 0) is None
    assert validation.validate_official_coordinate(0.0, 0.0) is None


def test_out_of_range_latitude_is_dropped():
    assert validation.validate_official_coordinate(999.0, 127.0) is None
    assert validation.validate_official_coordinate(-91.0, 127.0) is None


def test_out_of_range_longitude_is_dropped():
    assert validation.validate_official_coordinate(37.0, 999.0) is None
    assert validation.validate_official_coordinate(37.0, -181.0) is None


def test_non_numeric_coordinate_is_dropped():
    assert validation.validate_official_coordinate("abc", "def") is None
    assert validation.validate_official_coordinate(None, None) is None
    assert validation.validate_official_coordinate("", "") is None


def test_rejection_counter_sums_and_summarizes_with_bounded_reason():
    counter = validation.OfficialRejectionCounter()
    assert counter.total == 0
    assert counter.summary_reason() is None

    counter.add("invalid_coordinate")
    counter.add("invalid_coordinate")
    counter.add("invalid_date")

    assert counter.total == 3
    assert counter.counts() == {"invalid_coordinate": 2, "invalid_date": 1}
    summary = counter.summary_reason()
    assert summary is not None
    assert "invalid_coordinate=2" in summary
    assert "invalid_date=1" in summary


def test_rejection_counter_summary_is_stable_and_contains_no_raw_text():
    counter = validation.OfficialRejectionCounter()
    counter.add("unmapped_category")
    counter.add("invalid_image_url")
    summary = counter.summary_reason()
    assert summary is not None
    # Fixed labels only; the counter never receives raw row content.
    assert "unmapped_category=1" in summary
    assert "invalid_image_url=1" in summary
