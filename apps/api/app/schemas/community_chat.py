from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class ChatRoomCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)


class ChatMessageIn(BaseModel):
    """Inbound WebSocket message body (validated before persistence).

    ``extra="forbid"`` keeps the wire strict: unknown fields are rejected
    instead of silently dropped. Whitespace-only bodies are rejected while
    valid bodies (including boundary lengths) pass through unchanged.
    """

    model_config = ConfigDict(extra="forbid")

    body: str = Field(..., min_length=1, max_length=4000)

    @field_validator("body")
    @classmethod
    def _reject_whitespace_only(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("body must contain non-whitespace content")
        return value


class ChatRoomResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    name: str
    created_at: datetime


class ChatRoomListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    count: int
    rooms: list[ChatRoomResponse]


class ChatMessageResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    room_id: UUID
    author_user_id: UUID | None
    body: str
    created_at: datetime


class ChatMessageListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    count: int
    messages: list[ChatMessageResponse]
