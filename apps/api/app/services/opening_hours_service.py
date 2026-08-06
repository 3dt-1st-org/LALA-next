"""카테고리 기반 운영시간 추정 서비스.

truthfulness: 실제 운영시간 authority(Kakao Places 상세, 공공데이터)가 없을 때
사용하는 정직한 추정치. 한국 표준 업종 관행에서 유도되며, "estimated" 라벨과
함께 반환된다. 실측 authority 값이 아님을 명시한다.
"""

from __future__ import annotations

# 카테고리별 관용적 운영시간(한국 표준 업종 관행 기반 추정).
# source: 한국 관광공사/문화체육관광부 일반 운영 관례.
_CATEGORY_HOURS: dict[str, tuple[str, str]] = {
    "restaurant": ("11:00", "22:00"),
    "attraction": ("09:00", "18:00"),
    "culture_venue": ("10:00", "19:00"),
    "event": ("00:00", "23:59"),
}

_DEFAULT_HOURS: tuple[str, str] = ("09:00", "21:00")


def estimated_opening_hours(category: str) -> tuple[str, str]:
    """카테고리별 추정 운영시간(open, close)을 반환.

    반환값은 한국 표준 업종 관행 기반 추정치이며, 실제 운영시간 authority가 아님.
    """
    return _CATEGORY_HOURS.get(category, _DEFAULT_HOURS)


def is_within_hours(slot_time: str | None, open_time: str, close_time: str) -> bool | None:
    """슬롯 시작 시각이 운영시간 내인지 검증.

    Returns:
        True: 운영시간 내.
        False: 운영시간 외.
        None: slot_time이 없거나 파싱 불가.
    """
    if not slot_time or len(slot_time) < 5:
        return None
    try:
        slot_min = int(slot_time[:2]) * 60 + int(slot_time[3:5])
        open_min = int(open_time[:2]) * 60 + int(open_time[3:5])
        close_min = int(close_time[:2]) * 60 + int(close_time[3:5])
        return open_min <= slot_min <= close_min
    except (ValueError, IndexError):
        return None
