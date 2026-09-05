from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

ChatRoomVisibility = Literal["public", "private"]


class ChatRoomCreate(BaseModel):
    """Room creation request.

    ``visibility`` defaults to ``public`` so existing callers keep the
    established public-room semantics. A private room is recorded with its
    verified creator and an explicit owner membership row (server-side).
    """

    model_config = ConfigDict(extra="forbid")

    name: str = Field(..., min_length=1, max_length=120)
    visibility: ChatRoomVisibility = "public"


class ChatMessageIn(BaseModel):
    """Inbound WebSocket message body (validated before persistence).

    ``extra="forbid"`` keeps the wire strict: unknown fields are rejected
    instead of silently dropped. Whitespace-only bodies are rejected while
    valid bodies (including boundary lengths) pass through unchanged.
    ``idempotency_key`` is optional: when present, a retry of the same key
    with the same body replays the original message instead of duplicating
    it (durable across restarts); a different body with the same key is a
    deterministic conflict. It never contributes to identity.
    """

    model_config = ConfigDict(extra="forbid")

    body: str = Field(..., min_length=1, max_length=4000)
    idempotency_key: str | None = Field(None, min_length=1, max_length=200)

    @field_validator("body")
    @classmethod
    def _reject_whitespace_only(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("body must contain non-whitespace content")
        return value


class ChatMessageCreate(BaseModel):
    """REST chat message send body (REST fallback for the WebSocket path).

    The retry identity is the ``Idempotency-Key`` header, not any body field,
    so retries replay the exact same request envelope.
    """

    model_config = ConfigDict(extra="forbid")

    body: str = Field(..., min_length=1, max_length=4000)

    @field_validator("body")
    @classmethod
    def _reject_whitespace_only(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("body must contain non-whitespace content")
        return value


class ChatRoomMemberAdd(BaseModel):
    """Owner-only membership grant addressed by the internal user UUID.

    The wire never carries issuer/subject pairs (same policy as follows):
    the server resolves ``member_user_id`` against ``identity.users``.
    """

    model_config = ConfigDict(extra="forbid")

    member_user_id: UUID


class ChatWsTicketResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    room_id: UUID
    ticket: str
    expires_at: datetime


class ChatRoomResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    name: str
    visibility: ChatRoomVisibility
    created_at: datetime


class ChatRoomListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    count: int
    total: int
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
    total: int
    messages: list[ChatMessageResponse]
