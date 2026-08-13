from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field, field_validator


class SavePlaceRequest(BaseModel):
    """Optional body for the idempotent save-place PUT. Source defaults to the
    public MVP snapshot provenance used elsewhere; no coordinates or PII."""

    source: str = Field(default="public_mvp_snapshot")


class SavePlanRequest(BaseModel):
    """Body for the persisted-plan PUT. The plan is the DailyPlanData dict
    produced by the stateless planner; it is stored verbatim and read back
    through a version guard. Validation of the inner plan shape is the
    planner's responsibility, not the persistence layer's."""

    plan: dict[str, Any] = Field(...)


class SlotVisitRequest(BaseModel):
    """Body for the idempotent slot check-in PUT."""

    status: str = Field(default="visited")
    place_id: str | None = Field(default=None)

    @field_validator("status")
    @classmethod
    def _status_must_be_known(cls, value: str) -> str:
        if value not in ("planned", "visited"):
            raise ValueError("status must be 'planned' or 'visited'")
        return value
