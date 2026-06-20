from __future__ import annotations

from typing import Any, Literal

Pollutant = Literal["pm10", "pm25"]

_GRADE_CODE = {
    1: "good",
    2: "normal",
    3: "bad",
    4: "very_bad",
}
_GRADE_KO = {
    1: "좋음",
    2: "보통",
    3: "나쁨",
    4: "매우나쁨",
}


def unknown_dust_payload() -> dict[str, str]:
    return {
        "pm10": "",
        "pm25": "",
        "grade": "unknown",
        "grade_ko": "확인 중",
        "pm10_grade": "unknown",
        "pm10_grade_ko": "확인 중",
        "pm25_grade": "unknown",
        "pm25_grade_ko": "확인 중",
    }


def clean_air_quality_value(value: Any) -> str:
    text = str(value or "").strip()
    if text in {"", "-", "점검중", "통신장애"}:
        return ""
    return text


def build_dust_payload(
    *,
    pm10: Any,
    pm25: Any,
    pm10_grade: Any = None,
    pm25_grade: Any = None,
    fallback_bad: bool = False,
) -> dict[str, str]:
    pm10_value = clean_air_quality_value(pm10)
    pm25_value = clean_air_quality_value(pm25)
    pm10_level = _grade_level(pm10_grade) or _grade_level_from_value(pm10_value, "pm10")
    pm25_level = _grade_level(pm25_grade) or _grade_level_from_value(pm25_value, "pm25")
    levels = [level for level in [pm10_level, pm25_level] if level is not None]
    overall_level = max(levels) if levels else None
    if fallback_bad and (overall_level is None or overall_level < 3):
        overall_level = 3

    return {
        "pm10": pm10_value,
        "pm25": pm25_value,
        "grade": _grade_code(overall_level),
        "grade_ko": _grade_ko(overall_level),
        "pm10_grade": _grade_code(pm10_level),
        "pm10_grade_ko": _grade_ko(pm10_level),
        "pm25_grade": _grade_code(pm25_level),
        "pm25_grade_ko": _grade_ko(pm25_level),
    }


def _grade_level(value: Any) -> int | None:
    try:
        numeric = int(str(value or "").strip())
    except ValueError:
        return None
    if 1 <= numeric <= 4:
        return numeric
    return None


def _grade_level_from_value(value: str, pollutant: Pollutant) -> int | None:
    try:
        numeric = float(value)
    except ValueError:
        return None
    if pollutant == "pm10":
        if numeric <= 30:
            return 1
        if numeric <= 80:
            return 2
        if numeric <= 150:
            return 3
        return 4
    if numeric <= 15:
        return 1
    if numeric <= 35:
        return 2
    if numeric <= 75:
        return 3
    return 4


def _grade_code(level: int | None) -> str:
    return _GRADE_CODE.get(level, "unknown")


def _grade_ko(level: int | None) -> str:
    return _GRADE_KO.get(level, "확인 중")
