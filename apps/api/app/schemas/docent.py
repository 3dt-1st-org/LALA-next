from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator

from apps.api.app.services.normalization import normalize_docent_mode, normalize_language


class DocentScriptRequest(BaseModel):
    place_id: str = Field(min_length=1)
    category: Literal["attraction", "restaurant", "event", "culture_venue"]
    language: str = "ko"
    mode: str = "brief"

    @field_validator("place_id")
    @classmethod
    def place_id_must_not_be_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("place_id is required")
        return value

    @field_validator("language")
    @classmethod
    def normalize_script_language(cls, value: str) -> str:
        return normalize_language(value)

    @field_validator("mode")
    @classmethod
    def normalize_mode(cls, value: str) -> str:
        return normalize_docent_mode(value)


class DocentAudioRequest(BaseModel):
    script: str = Field(min_length=1)
    language: str = "ko"

    @field_validator("script")
    @classmethod
    def script_must_not_be_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("script is required")
        return value

    @field_validator("language")
    @classmethod
    def normalize_audio_language(cls, value: str) -> str:
        return normalize_language(value)
