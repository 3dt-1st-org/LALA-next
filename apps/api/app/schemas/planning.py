from __future__ import annotations

import json
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, ValidationInfo, field_validator


class SavePlaceRequest(BaseModel):
    """Optional body for the idempotent save-place PUT. Source defaults to the
    public MVP snapshot provenance used elsewhere; no coordinates or PII."""

    source: str = Field(default="public_mvp_snapshot", max_length=128)


class SavePlanRequest(BaseModel):
    """Body for the persisted-plan PUT. The plan is the DailyPlanData dict
    produced by the stateless planner; it is stored verbatim and read back
    through a version guard. Validation of the inner plan shape is the
    planner's responsibility, not the persistence layer's."""

    plan: dict[str, Any] = Field(...)

    @field_validator("plan", mode="before")
    @classmethod
    def bounded_plan(cls, value: Any) -> Any:
        # Preserve the planner's existing dict contract, including extension
        # fields, while bounding depth, containers, strings and encoded bytes.
        stack = [(value, 0)]
        nodes = 0
        while stack:
            item, depth = stack.pop()
            nodes += 1
            if depth > 12 or nodes > 4096:
                raise ValueError("plan nesting or size exceeds the supported limit")
            if isinstance(item, dict):
                if len(item) > 128:
                    raise ValueError("plan objects may contain at most 128 fields")
                for key, child in item.items():
                    if not isinstance(key, str) or len(key) > 128:
                        raise ValueError("plan field names must be at most 128 characters")
                    stack.append((child, depth + 1))
            elif isinstance(item, list):
                if len(item) > 128:
                    raise ValueError("plan arrays may contain at most 128 items")
                stack.extend((child, depth + 1) for child in item)
            elif isinstance(item, str) and len(item) > 12000:
                raise ValueError("plan text may contain at most 12000 characters")
        try:
            encoded = json.dumps(value, ensure_ascii=False, allow_nan=False).encode()
        except (TypeError, ValueError, RecursionError) as exc:
            raise ValueError("plan must contain finite JSON values") from exc
        if len(encoded) > 128 * 1024:
            raise ValueError("plan must be at most 128 KiB")
        return value


class SlotVisitRequest(BaseModel):
    """Body for the idempotent, user-controlled slot outcome PUT."""

    status: str = Field(default="visited")
    place_id: str | None = Field(default=None, max_length=128)
    reason_code: (
        Literal[
            "closed",
            "weather",
            "crowded",
            "time",
            "transport",
            "changed_mind",
            "other",
        ]
        | None
    ) = Field(default=None)
    use_for_recommendations: bool = Field(default=False)

    @field_validator("status")
    @classmethod
    def _status_must_be_known(cls, value: str) -> str:
        if value not in ("planned", "visited", "not_visited"):
            raise ValueError("status must be 'planned', 'visited', or 'not_visited'")
        return value

    @field_validator("reason_code")
    @classmethod
    def _reason_requires_not_visited(
        cls,
        value: str | None,
        info: ValidationInfo,
    ) -> str | None:
        if value is not None and info.data.get("status") != "not_visited":
            raise ValueError("reason_code is only valid for not_visited")
        return value


class TripPreferenceOverridePayload(BaseModel):
    """Soft conditions that may differ for one trip date.

    Hard dietary and accessibility constraints are intentionally absent, so a
    trip override cannot weaken the account/device defaults.
    """

    model_config = ConfigDict(extra="forbid")

    version: Literal[1] = 1
    companions: (
        list[Literal["solo", "partner", "friends", "family", "children", "senior", "pet"]] | None
    ) = Field(default=None, max_length=7)
    pace: Literal["relaxed", "balanced", "packed"] | None = None
    crowd_tolerance: Literal["quiet", "balanced", "popular"] | None = None
    walking_band: Literal["short", "medium", "long"] | None = None
    indoor_outdoor: Literal["indoor", "balanced", "outdoor"] | None = None
    weather_sensitivity: Literal["low", "medium", "high"] | None = None
    transport_modes: list[Literal["walk", "transit", "taxi", "car", "bicycle"]] | None = Field(
        default=None, max_length=5
    )
    max_wait_minutes: Literal[10, 20, 40, 60] | None = None
    budget_band: Literal["value", "balanced", "special"] | None = None
    day_rhythm: Literal["morning", "daytime", "night"] | None = None
    exclude_closing_soon: bool | None = None

    @field_validator("companions", "transport_modes")
    @classmethod
    def _must_not_repeat_values(cls, value: list[str] | None) -> list[str] | None:
        if value is not None and len(value) != len(set(value)):
            raise ValueError("override lists must not contain duplicates")
        return value


class SaveTripPreferenceOverrideRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    expected_revision: int = Field(ge=0)
    override: TripPreferenceOverridePayload
