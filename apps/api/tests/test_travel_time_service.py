"""travel_time_service Haversine 추정 검증."""

from apps.api.app.services.travel_time_service import (
    estimate_walking_minutes,
    haversine_distance_m,
    period_start_time,
)


def test_haversine_known_distance() -> None:
    # 서울역 ~ 강남역 직선거리 약 9-10km.
    d = haversine_distance_m(37.5563, 126.9724, 37.4979, 127.0276)
    assert 8000 <= d <= 12000


def test_haversine_same_point_zero() -> None:
    assert haversine_distance_m(37.5, 127.0, 37.5, 127.0) == 0


def test_estimate_walking_minutes_reasonable() -> None:
    # ~1km → 약 15분 (1000m ÷ 67 m/min).
    minutes = estimate_walking_minutes(37.5665, 126.9780, 37.5745, 126.9880)
    assert minutes is not None
    assert 5 <= minutes <= 30


def test_estimate_walking_same_point_zero() -> None:
    assert estimate_walking_minutes(37.5, 127.0, 37.5, 127.0) == 0


def test_estimate_walking_invalid_coords_none() -> None:
    assert estimate_walking_minutes(0, 0, 37.5, 127.0) is None


def test_period_start_times() -> None:
    assert period_start_time("morning") == "09:00"
    assert period_start_time("lunch") == "12:00"
    assert period_start_time("afternoon") == "14:00"
    assert period_start_time("dinner") == "18:00"
    assert period_start_time("unknown") is None
