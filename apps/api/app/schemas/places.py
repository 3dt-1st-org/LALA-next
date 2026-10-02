from __future__ import annotations

import unicodedata
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, field_validator

PLACE_ID_MAX_LENGTH = 128


def validate_place_id(value: str) -> str:
    if not value or not value.strip():
        raise ValueError("place_id must not be blank")
    if len(value) > PLACE_ID_MAX_LENGTH:
        raise ValueError(f"place_id must be at most {PLACE_ID_MAX_LENGTH} characters")
    if any(unicodedata.category(character) == "Cc" for character in value):
        raise ValueError("place_id must not contain control characters")
    return value


class PlaceLookupRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    place_ids: list[Annotated[str, Field(min_length=1, max_length=PLACE_ID_MAX_LENGTH)]] = Field(
        min_length=1, max_length=100
    )

    @field_validator("place_ids")
    @classmethod
    def validate_place_ids(cls, values: list[str]) -> list[str]:
        return [validate_place_id(value) for value in values]
