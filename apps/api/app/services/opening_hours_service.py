"""카테고리 기반 운영시간 추정 서비스.

truthfulness: 실제 운영시간 authority(Kakao Places 상세, 공공데이터)가 없을 때
사용하는 정직한 추정치. 한국 표준 업종 관행에서 유도되며, "estimated" 라벨과
함께 반환된다. 실측 authority 값이 아님을 명시한다.
"""

from __future__ import annotations

import re

# 카테고리별 관용적 운영시간(한국 표준 업종 관행 기반 추정).
# source: 한국 관광공사/문화체육관광부 일반 운영 관례.
_CATEGORY_HOURS: dict[str, tuple[str, str]] = {
    "restaurant": ("11:00", "22:00"),
    "attraction": ("09:00", "18:00"),
    "culture_venue": ("10:00", "19:00"),
    "event": ("00:00", "23:59"),
}

_DEFAULT_HOURS: tuple[str, str] = ("09:00", "21:00")

_MINUTES_PER_DAY = 24 * 60

# 검증자 정정: 정확한 ASCII "HH:MM" 만 받는 공유 파서. 길이 5, index 2 콜론,
# ASCII 숫자만([0-9] 문자 클래스 — \d 는 Unicode 숫자도 받으므로 쓰지 않는다),
# 시 00-23, 분 00-59. 잘못된 구분자/과길이/부호/공백 패딩/전각 digit/범위 밖은
# 모두 파싱 실패(None)이며 절대 긍정 판정으로 이어지지 않는다.
_HHMM_PATTERN = re.compile(r"([0-9]{2}):([0-9]{2})")

# P4 closing-soon: 슬롯 시작 시각부터 "추정 마감 시각"까지의 거리가 이 window(분)
# 이하일 때만 closing-soon으로 판정한다. 결정론적·문서화된 bounded window이며
# 실측 authority가 아니라 카테고리 추정 운영시간의 투영임을 전제로 한다.
# 예: dinner(18:00) 슬롯 × culture_venue(10:00-19:00) → 마감까지 60분 → True.
CLOSING_SOON_WINDOW_MINUTES = 60


def estimated_opening_hours(category: str) -> tuple[str, str]:
    """카테고리별 추정 운영시간(open, close)을 반환.

    반환값은 한국 표준 업종 관행 기반 추정치이며, 실제 운영시간 authority가 아님.
    """
    return _CATEGORY_HOURS.get(category, _DEFAULT_HOURS)


def _hhmm_minutes(value: str | None) -> int | None:
    r"""정확한 ASCII "HH:MM" 만 분 값으로 변환(공유 strict 파서).

    그 외 모든 표현(잘못된 구분자, 과길이, 부호, 공백 패딩, 전각/Unicode 숫자,
    시 >= 24, 분 >= 60, 빈 값, 비문자열)은 None. int() 슬라이싱과 \d 는
    Unicode digit/부호/공백을 받아들이므로 사용하지 않는다.
    """
    if not isinstance(value, str):
        return None
    matched = _HHMM_PATTERN.fullmatch(value)
    if matched is None:
        return None
    hour = int(matched.group(1))
    minute = int(matched.group(2))
    if hour > 23 or minute > 59:
        return None
    return hour * 60 + minute


def _within_minutes(slot_min: int, open_min: int, close_min: int) -> bool | None:
    """is_within_hours/is_closing_soon 이 공유하는 운영중 멤버십 정의.

    - 주간(open < close): open 이상 close 이하.
    - 자정 넘김(close < open, 예: 20:00-02:00): 당일 open 시각 이후 또는
      (익일) close 시각 이전.
    - open == close: 마감 시각이 정의되지 않는 퇴화 범위 → None(unknown).
    """
    if open_min == close_min:
        return None
    if close_min > open_min:
        return open_min <= slot_min <= close_min
    return slot_min >= open_min or slot_min <= close_min


def is_within_hours(slot_time: str | None, open_time: str, close_time: str) -> bool | None:
    """슬롯 시작 시각이 운영시간 내인지 검증.

    멤버십 정의는 _within_minutes(자정 넘김 지원, open==close 는 unknown)이고
    파서는 _hhmm_minutes(strict ASCII HH:MM) — is_closing_soon 과 동일하다.

    Returns:
        True: 운영시간 내.
        False: 운영시간 외.
        None: 값 파싱 불가/누락 또는 open==close(unknown).
    """
    slot_min = _hhmm_minutes(slot_time)
    open_min = _hhmm_minutes(open_time)
    close_min = _hhmm_minutes(close_time)
    if slot_min is None or open_min is None or close_min is None:
        return None
    return _within_minutes(slot_min, open_min, close_min)


def is_closing_soon(
    slot_time: str | None,
    open_time: str,
    close_time: str,
    window_minutes: int = CLOSING_SOON_WINDOW_MINUTES,
) -> bool | None:
    """슬롯 시작 시각이 추정 마감 window 안에 들어오는지 검증(estimated, authority 아님).

    결정론적 정의:
        - 운영시간 내(_within_minutes — is_within_hours 와 동일 정의)이면서 추정
          마감까지 남은 분이 window_minutes 이하 → True. 마감 시각 딱 그 순간(남은
          분 0)도 True다(멤버십이 마감 시각을 포함하므로 closed와 상호 배제 유지).
        - 운영시간 밖(영업 전/마감 후)이거나 마감까지 window보다 이름 → False.
        - 값 파싱 불가/누락(strict 파서), open==close(마감 시각 미정의),
          window_minutes <= 0 → None (추측 금지, unknown).

    자정 넘김 범위(close < open, 예: 20:00-02:00)는 당일 오픈 이후 또는 익일
    마감 이전을 운영중로 본다. closing_soon=True는 항상 공유 멤버십의 운영시간
    내에서만 나오므로 is_within_hours=True를 함축하고 closure_state="closed"와
    구조적으로 공존하지 않는다.

    Returns:
        True: 마감 임박 window 안(운영중).
        False: window 밖(영업 전/마감 후/여유 있음).
        None: 판단 불가(unknown).
    """
    if window_minutes <= 0:
        return None
    slot_min = _hhmm_minutes(slot_time)
    open_min = _hhmm_minutes(open_time)
    close_min = _hhmm_minutes(close_time)
    if slot_min is None or open_min is None or close_min is None:
        return None
    within = _within_minutes(slot_min, open_min, close_min)
    if within is None:
        return None
    if not within:
        return False
    remaining = (
        close_min - slot_min if slot_min <= close_min else close_min + _MINUTES_PER_DAY - slot_min
    )
    return remaining <= window_minutes
