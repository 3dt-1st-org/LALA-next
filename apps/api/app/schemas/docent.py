from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator

from apps.api.app.services.normalization import normalize_docent_mode, normalize_language


class DocentScriptRequest(BaseModel):
    place_id: str = Field(min_length=1, max_length=128)
    place_name: str | None = Field(default=None, max_length=512)
    address: str | None = Field(default=None, max_length=512)
    region_ko: str | None = Field(default=None, max_length=512)
    region_en: str | None = Field(default=None, max_length=512)
    distance_m: int | None = Field(default=None, ge=0)
    source: str | None = Field(default=None, max_length=512)
    upstream_source: str | None = Field(default=None, max_length=512)
    final_score: float | None = Field(default=None, ge=0, le=1)
    local_spending_score: float | None = Field(default=None, ge=0, le=1)
    small_merchant_fit_score: float | None = Field(default=None, ge=0, le=1)
    demand_dispersion_score: float | None = Field(default=None, ge=0, le=1)
    weather_fit_score: float | None = Field(default=None, ge=0, le=1)
    culture_relevance_score: float | None = Field(default=None, ge=0, le=1)
    weather_temp: str | None = Field(default=None, max_length=512)
    weather_icon: str | None = Field(default=None, max_length=512)
    weather_outdoor_status: str | None = Field(default=None, max_length=512)
    dust_grade: str | None = Field(default=None, max_length=512)
    dust_pm10: str | None = Field(default=None, max_length=512)
    dust_pm25: str | None = Field(default=None, max_length=512)
    dust_pm10_grade: str | None = Field(default=None, max_length=512)
    dust_pm25_grade: str | None = Field(default=None, max_length=512)
    category: Literal["attraction", "restaurant", "event", "culture_venue"]
    language: str = Field(default="ko", max_length=16)
    mode: str = Field(default="brief", max_length=16)

    @field_validator("place_id")
    @classmethod
    def place_id_must_not_be_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("place_id is required")
        return value

    @field_validator(
        "place_name",
        "address",
        "region_ko",
        "region_en",
        "source",
        "upstream_source",
        "weather_temp",
        "weather_icon",
        "weather_outdoor_status",
        "dust_grade",
        "dust_pm10",
        "dust_pm25",
        "dust_pm10_grade",
        "dust_pm25_grade",
    )
    @classmethod
    def normalize_optional_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None

    @field_validator("language")
    @classmethod
    def normalize_script_language(cls, value: str) -> str:
        return normalize_language(value)

    @field_validator("mode")
    @classmethod
    def normalize_mode(cls, value: str) -> str:
        return normalize_docent_mode(value)


class DocentAudioRequest(BaseModel):
    script: str = Field(min_length=1, max_length=12000)
    language: str = Field(default="ko", max_length=16)

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
