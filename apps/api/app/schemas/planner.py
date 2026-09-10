from __future__ import annotations

from typing import Annotated

from pydantic import BaseModel, BeforeValidator, ConfigDict, Field, field_validator

from apps.api.app.schemas.preferences import (
    BudgetBand,
    FoodCuisine,
    IndoorOutdoorPreference,
    MaxOneWayMinutes,
    WalkingBand,
    WeatherSensitivity,
)
from apps.api.app.services.normalization import normalize_language


def _strip_selected_place_id(value: object) -> object:
    # BeforeValidator: min_length 검증 전에 공백을 정규화한다. "  p2  " → "p2",
    # 공백 전용 문자열 → "" (→ min_length 위반 = 명확한 422 거부 계약).
    if isinstance(value, str):
        return value.strip()
    return value


class PlanPreferenceContext(BaseModel):
    """CP1: 일정 생성에 반영할 수 있는 비민감 soft 선호 값만 담는다.

    계약 경계(중요): 이 객체는 public plan endpoint 로 전송 가능한 값만 허용한다.
    알레르겐·식이·기피 식재료·이동약성/접근성 선언·인증 클레임·PII·계정 식별자는
    필드로 존재할 수 없다(extra="forbid" 로 알 수 없는 키도 거부). 값 집합과
    상한은 TravelPreferenceSoft 와 같은 소스(schemas/preferences.py)를 재사용한다.
    CP2: 맵기(spice_level)와 주문 요청(order_requests)도 여기에 올 수 없다 —
    식당 커뮤니케이션 전용 soft 값으로 public plan endpoint 로 절대 전송되지 않는다.
    """

    model_config = ConfigDict(extra="forbid")

    indoor_outdoor: IndoorOutdoorPreference = "balanced"
    weather_sensitivity: WeatherSensitivity = "medium"
    walking_band: WalkingBand = "medium"
    max_one_way_minutes: MaxOneWayMinutes = 30
    food_cuisines: list[FoodCuisine] = Field(default_factory=list, max_length=4)
    budget_band: BudgetBand = "balanced"
    exclude_closing_soon: bool = True

    @field_validator("food_cuisines")
    @classmethod
    def _must_not_repeat_values(cls, value: list[str]) -> list[str]:
        if len(value) != len(set(value)):
            raise ValueError("preference context lists must not contain duplicates")
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
    # CP1: 선호 컨텍스트. 없으면(None) 기존 요청 직렬화·정체성·응답 형태가
    # 바이트 단위로 보존된다. 있으면 grounded effect 만 반영하고 그 결과를
    # preference_effects 로 정직하게 보고한다.
    preference_context: PlanPreferenceContext | None = None

    @field_validator("language")
    @classmethod
    def normalize_plan_language(cls, value: str) -> str:
        return normalize_language(value)
