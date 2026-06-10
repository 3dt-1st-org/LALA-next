from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class DocentScriptRequest(BaseModel):
    place_id: str = Field(min_length=1)
    category: Literal["attraction", "restaurant", "event"]
    language: Literal["ko", "en"] = "ko"
    mode: Literal["brief", "standard", "deep"] = "brief"


class DocentAudioRequest(BaseModel):
    script: str = Field(min_length=1)
    language: Literal["ko", "en"] = "ko"

