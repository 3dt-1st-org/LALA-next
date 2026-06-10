from __future__ import annotations

from pydantic import BaseModel


class DailyPlanRequest(BaseModel):
    lat: float = 37.2636
    lng: float = 127.0286
    language: str = "ko"

