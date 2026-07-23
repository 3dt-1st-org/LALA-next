from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ChatRoomCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)


class ChatMessageIn(BaseModel):
    """Inbound WebSocket message body (parsed before persistence)."""

    body: str = Field(..., min_length=1, max_length=4000)


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
