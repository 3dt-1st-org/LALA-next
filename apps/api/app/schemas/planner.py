from __future__ import annotations

from typing import Annotated

from pydantic import BaseModel, BeforeValidator, Field, field_validator

from apps.api.app.services.normalization import normalize_language


def _strip_selected_place_id(value: object) -> object:
    # BeforeValidator: min_length 검증 전에 공백을 정규화한다. "  p2  " → "p2",
    # 공백 전용 문자열 → "" (→ min_length 위반 = 명확한 422 거부 계약).
    if isinstance(value, str):
        return value.strip()
    return value


class DailyPlanRequest(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)
    radius_m: int = Field(3000, gt=0, le=50000)
    language: str = "ko"
    # D-1: 선택된 대표 장소(카노니컬 place_id). 없으면 기존 비지정 플랜과 동일.
    # 거부 계약: null/생략 = 미지정, 공백 전용/빈 문자열 = VALIDATION_ERROR(422).
    selected_place_id: Annotated[str | None, BeforeValidator(_strip_selected_place_id)] = Field(
        None, min_length=1, max_length=128
    )

    @field_validator("language")
    @classmethod
    def normalize_plan_language(cls, value: str) -> str:
        return normalize_language(value)
