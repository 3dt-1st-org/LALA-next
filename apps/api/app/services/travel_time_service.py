"""Haversine 기반 도보 이동 시간 추정 서비스.

truthfulness: 외부 routing API(travel-time authority)가 없을 때 사용하는
정직한 추정치. Haversine 직선거리 ÷ 보행 속도(4 km/h ≈ 67 m/min)로 계산하며,
결과는 "estimated" 라벨과 함께 반환된다. 실측 authority 값이 아님을 명시한다.
"""

from __future__ import annotations

import math

from apps.api.app.core.config import get_settings

# Earth radius in meters (WGS-84 mean radius).
_EARTH_RADIUS_M = 6_371_000.0

# Average walking speed: 4 km/h ≈ 66.67 m/min. Rounded for readability.
_WALKING_SPEED_M_PER_MIN = 67

# Conventional daily-plan start times (not authority-derived; standard meal/period convention).
_PERIOD_START_TIMES: dict[str, str] = {
    "morning": "09:00",
    "lunch": "12:00",
    "afternoon": "14:00",
    "dinner": "18:00",
}


def haversine_distance_m(lat1: float, lng1: float, lat2: float, lng2: float) -> int:
    """두 좌표 간 Haversine 직선거리(m)를 정수로 반환."""
    r_lat1, r_lat2 = math.radians(lat1), math.radians(lat2)
    d_lat = math.radians(lat2 - lat1)
    d_lng = math.radians(lng2 - lng1)
    a = math.sin(d_lat / 2) ** 2 + math.cos(r_lat1) * math.cos(r_lat2) * math.sin(d_lng / 2) ** 2
    c = 2 * math.asin(math.sqrt(a))
    return int(round(_EARTH_RADIUS_M * c))


def estimate_walking_minutes(lat1: float, lng1: float, lat2: float, lng2: float) -> int | None:
    """직선거리 기반 도보 이동 시간 추정(분). 좌표가 유효하지 않으면 None.

    반환값은 추정치이며 실측 authority(travel-time API)가 아님.
    거리 ÷ 67 m/min(≈ 4 km/h 보행 속도)로 계산한다.
    """
    if lat1 == 0 and lng1 == 0 or lat2 == 0 and lng2 == 0:
        return None
    if lat1 == lat2 and lng1 == lng2:
        return 0
    distance_m = haversine_distance_m(lat1, lng1, lat2, lng2)
    minutes = distance_m / _WALKING_SPEED_M_PER_MIN
    return max(1, int(round(minutes)))


def walking_distance_m(minutes: int) -> int:
    """도보 이동 시간(분) → 추정 직선거리(m). 문서화된 추정치(4 km/h ≈ 67 m/min)의
    역산. CP1 선호 반경 상한이 이 한 곳의 추정치를 사용하도록 하는 공개 표면."""
    return int(minutes * _WALKING_SPEED_M_PER_MIN)


def period_start_time(period: str) -> str | None:
    """관용적 일정 시작 시각(morning 09:00 / lunch 12:00 / afternoon 14:00 / dinner 18:00).

    이 값은 표준 식사/시간대 관례에서 유도된 추정 시작 시각이며,
    opening-hours authority가 확보되면 실제 운영시간 기반으로 교체된다.
    """
    return _PERIOD_START_TIMES.get(period)


def live_routing_enabled() -> bool:
    """V5-C routing-seam flag read (mirrors speech_service.live_speech_enabled).

    The flag gates the FUTURE Directions hook only; it never enables a live call in
    V5. Default off keeps the Haversine estimate as the sole travel-time signal.
    """
    return bool(get_settings().enable_live_routing)


def resolve_travel_time_authority_minutes(
    lat1: float, lng1: float, lat2: float, lng2: float
) -> int | None:
    """V5-C routing seam: authoritative Directions ETA, or honest null.

    This is the travel-time AUTHORITY surface (Kakao/Naver Directions), distinct from
    the Haversine ESTIMATE (`estimate_walking_minutes`) which stays byte-for-byte.

    - Flag OFF (default) -> None. The Haversine estimate stands alone; no authority.
    - Flag ON -> still None in V5. Real Kakao/Naver Directions are BLOCKED_EXTERNAL /
      V7 (contract §3a); the hook is present but the Directions invocation never fires,
      so the authority stays honestly null rather than guessing a route/ETA.

    The V7 call site is the marked branch below. It must ship no network/paid call in V5.
    """
    if not live_routing_enabled():
        return None
    # --- V7 boundary (BLOCKED_EXTERNAL in V5) -------------------------------------
    # When live routing lands, the Kakao/Naver Directions request goes here. It is
    # intentionally a no-op in V5: returning None keeps the authority honest and proves
    # no outbound HTTP/paid call ships on any V5 path regardless of the flag state.
    return None
