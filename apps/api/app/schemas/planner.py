from __future__ import annotations

from pydantic import BaseModel, Field, field_validator

from apps.api.app.services.normalization import normalize_language


class DailyPlanRequest(BaseModel):
    lat: float = Field(37.2636, ge=-90, le=90)
    lng: float = Field(127.0286, ge=-180, le=180)
    radius_m: int = Field(50000, gt=0, le=50000)
    language: str = "ko"

    @field_validator("language")
    @classmethod
    def normalize_plan_language(cls, value: str) -> str:
        return normalize_language(value)
