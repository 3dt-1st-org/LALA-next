from __future__ import annotations

from pydantic import BaseModel, field_validator

from apps.api.app.services.normalization import normalize_language


class DailyPlanRequest(BaseModel):
    lat: float = 37.2636
    lng: float = 127.0286
    language: str = "ko"

    @field_validator("language")
    @classmethod
    def normalize_plan_language(cls, value: str) -> str:
        return normalize_language(value)
