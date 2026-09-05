import pytest

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


# ---------------------------------------------------------------------------
# 검증자 정정(correction): 공유 strict ASCII HH:MM 파서 + 공유 멤버십 정의.
# 잘못된 구분자/과길이/부호/패딩/전각·Unicode 숫자/시>=24/분>=60 은 절대
# 긍정 판정으로 이어지지 않는다. \d 는 Unicode digit 을 받으므로 [0-9] 만 쓴다.
# ---------------------------------------------------------------------------

_ADVERSARIAL_HHMM = [
    # 잘못된 구분자.
    "11-00",
    "11.00",
    "11/00",
    "11 00",
    "11;00",
    "11：00",  # 전각 콜론
    # 과길이 / 추가 문자.
    "11:000",
    "011:00",
    "11:00:00",
    "11:00 ",
    " 11:00",
    "11:00x",
    "111:00",
    # 부호.
    "+1:00",
    "-9:30",
    "+11:00",
    "-11:00",
    # 공백 패딩 / 짧은 형태(정확한 5자 zero-padded 만 허용).
    " 1:00",
    "1:00",
    "9:30",
    "9:3",
    "1:5",
    # Unicode / 전각 / 비-ASCII 숫자(int() 와 \d 가 받아들이는 것들).
    "１１:００",
    "11:００",
    "１1:00",
    "١١:٠٠",  # Arabic-Indic digits
    "₁₁:₀₀",  # subscript digits
    "١١:00",
    # 시 >= 24 / 분 >= 60 (형식은 HH:MM 이나 범위 밖).
    "24:00",
    "25:00",
    "30:15",
    "99:99",
    "11:60",
    "11:99",
    "00:60",
    "23:60",
    # 빈/구조 불명.
    "",
    ":",
    "::",
    "0000",
    "1100",
    "aa:bb",
    "2a:0b",
]


@pytest.mark.parametrize("bad", _ADVERSARIAL_HHMM)
def test_strict_parser_rejects_adversarial_slot_times(bad: str) -> None:
    # 슬롯 시각이 malformed 이면 두 헬퍼 모두 unknown — 긍정 판정 없음.
    assert is_within_hours(bad, "11:00", "22:00") is None
    assert is_closing_soon(bad, "11:00", "22:00") is None


@pytest.mark.parametrize("bad", _ADVERSARIAL_HHMM)
def test_strict_parser_rejects_adversarial_open_close_hours(bad: str) -> None:
    # open/close 어느 쪽이 malformed 여도 unknown — 긍정 판정 없음.
    # ("21:00"/"11:00"-"22:00" 조합은 원래 closing-soon True 인 경계 값.)
    assert is_within_hours("21:00", bad, "22:00") is None
    assert is_within_hours("21:00", "11:00", bad) is None
    assert is_closing_soon("21:00", bad, "22:00") is None
    assert is_closing_soon("21:00", "11:00", bad) is None


@pytest.mark.parametrize("bad", _ADVERSARIAL_HHMM)
def test_strict_parser_rejects_adversarial_overnight_hours(bad: str) -> None:
    # 자정 넘김 범위에서도 malformed 는 unknown — 긍정 판정 없음.
    assert is_within_hours("21:00", bad, "02:00") is None
    assert is_within_hours("21:00", "20:00", bad) is None
    assert is_closing_soon("01:30", bad, "02:00") is None
    assert is_closing_soon("01:30", "20:00", bad) is None


def test_strict_parser_accepts_exact_ascii_hhmm_boundaries() -> None:
    # 유효한 경계 값은 그대로 받는다(과잉 거부 없음).
    assert is_within_hours("00:00", "00:00", "23:59") is True
    assert is_within_hours("23:59", "00:00", "23:59") is True
    assert is_within_hours("12:00", "00:00", "23:59") is True
    assert is_closing_soon("23:58", "00:00", "23:59") is True


def test_strict_parser_rejects_non_string_slot_time() -> None:
    assert is_within_hours(None, "11:00", "22:00") is None
    assert is_closing_soon(None, "11:00", "22:00") is None


def test_shared_overnight_membership_2000_0200() -> None:
    # 검증자 정정: 두 헬퍼가 동일 멤버십 — 20:00 이후(당일)와 02:00 이전(익일)은
    # 운영중, 그 사이는 운영 외.
    for within_time in ("20:00", "20:01", "23:30", "00:00", "01:30", "02:00"):
        assert is_within_hours(within_time, "20:00", "02:00") is True, within_time
    for outside_time in ("19:59", "02:01", "03:00", "12:00", "19:00"):
        assert is_within_hours(outside_time, "20:00", "02:00") is False, outside_time


def test_shared_membership_open_equal_close_is_unknown_for_both() -> None:
    # open==close(마감 시각 미정의)은 두 헬퍼 모두 unknown.
    assert is_within_hours("10:00", "10:00", "10:00") is None
    assert is_within_hours("12:00", "10:00", "10:00") is None
    assert is_closing_soon("10:00", "10:00", "10:00") is None
    assert is_closing_soon("09:30", "10:00", "10:00") is None


def test_overnight_2000_0930_morning_0900_membership() -> None:
    # 검증자가 명시한 사례: 20:00-09:30 의 morning 09:00.
    assert is_within_hours("09:00", "20:00", "09:30") is True  # close 이전(익일 측)
    assert is_closing_soon("09:00", "20:00", "09:30") is True  # 마감까지 30분
    assert is_closing_soon("08:30", "20:00", "09:30") is True  # 경계 60분 포함
    assert is_closing_soon("08:29", "20:00", "09:30") is False  # 61분
    assert is_within_hours("09:31", "20:00", "09:30") is False  # close 직후
    assert is_closing_soon("09:31", "20:00", "09:30") is False
    assert is_within_hours("19:59", "20:00", "09:30") is False  # open 직전
    assert is_within_hours("20:00", "20:00", "09:30") is True  # open 경계


def _minutes_to_hhmm(minute: int) -> str:
    return f"{minute // 60:02d}:{minute % 60:02d}"


@pytest.mark.parametrize(
    ("open_time", "close_time"),
    [
        ("10:00", "18:00"),  # 주간
        ("20:00", "02:00"),  # 자정 넘김
        ("20:00", "09:30"),  # 자정 넘김(아침 마감)
    ],
)
def test_full_day_closing_soon_implies_within_for_every_valid_minute(
    open_time: str, close_time: str
) -> None:
    # 검증자 정정: 유효한 모든 분에서 closing_soon=True ⇒ is_within_hours=True.
    # 두 헬퍼가 같은 파서/멤버십을 쓰므로 위반 분이 존재하면 실패한다.
    for minute in range(24 * 60):
        slot = _minutes_to_hhmm(minute)
        within = is_within_hours(slot, open_time, close_time)
        soon = is_closing_soon(slot, open_time, close_time)
        assert within is not None, slot
        assert soon is not None, slot
        if soon is True:
            assert within is True, slot
        if within is False:
            assert soon is False, slot


@pytest.mark.parametrize(
    ("open_time", "close_time"),
    [
        ("10:00", "18:00"),
        ("20:00", "02:00"),
        ("20:00", "09:30"),
    ],
)
def test_full_day_closing_soon_matches_documented_window(open_time: str, close_time: str) -> None:
    # 남은 분 정의 자체를 전일 스윕: 운영중인 분에 한해 close 까지의 남은 분이
    # window 이하일 때만 True(경계 포함, close 시각 정각은 남은 분 0 → True).
    open_min = _hhmm_minutes_for_test(open_time)
    close_min = _hhmm_minutes_for_test(close_time)
    assert open_min is not None and close_min is not None
    for minute in range(24 * 60):
        slot = _minutes_to_hhmm(minute)
        soon = is_closing_soon(slot, open_time, close_time)
        within = is_within_hours(slot, open_time, close_time)
        if within is not True:
            assert soon is False, slot
            continue
        remaining = close_min - minute if minute <= close_min else close_min + 24 * 60 - minute
        assert soon is (remaining <= CLOSING_SOON_WINDOW_MINUTES), slot


def _hhmm_minutes_for_test(value: str) -> int:
    return int(value[:2]) * 60 + int(value[3:5])
