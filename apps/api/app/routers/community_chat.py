from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, WebSocket, WebSocketDisconnect

from apps.api.app.core.auth import (
    RequestIdentity,
    require_client_auth,
    require_oauth_identity,
)
from apps.api.app.core.config import Settings, get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.core.jwt_auth import (
    JwtValidationRejected,
    JwtValidationUnavailable,
    validate_oauth_jwt,
)
from apps.api.app.core.responses import success_envelope
from apps.api.app.schemas.community_chat import ChatRoomCreate
from apps.api.app.services.community_chat_service import (
    CommunityChatService,
    get_community_chat_service,
)

router = APIRouter(
    prefix="/api/v1/community/chat",
    tags=["community-chat"],
    # NOTE: no router-level ``require_client_auth`` dependency — it would also
    # gate the WebSocket handshake (which authenticates via a ``?token=`` query
    # param instead of headers). Each HTTP route declares the dependency itself.
)


# ---------------------------------------------------------------------------
# WebSocket connection management (in-memory, room-scoped).
# Ported from GEOND_OPIc ``_ConnectionManager`` with per-room fan-out.
# ---------------------------------------------------------------------------


@dataclass
class _Connection:
    websocket: WebSocket
    room_id: UUID
    issuer: str
    subject: str


class ConnectionManager:
    """In-memory registry of active WebSocket clients keyed by room.

    A single instance is shared across all chat-room WebSocket endpoints so a
    message persisted in one handler fans out to every connected client in the
    same room.
    """

    def __init__(self) -> None:
        self._rooms: dict[UUID, list[_Connection]] = {}

    async def connect(
        self,
        websocket: WebSocket,
        *,
        room_id: UUID,
        issuer: str,
        subject: str,
    ) -> None:
        await websocket.accept()
        self._rooms.setdefault(room_id, []).append(_Connection(websocket, room_id, issuer, subject))

    def disconnect(self, websocket: WebSocket, room_id: UUID) -> None:
        connections = self._rooms.get(room_id)
        if not connections:
            return
        remaining = [c for c in connections if c.websocket is not websocket]
        if remaining:
            self._rooms[room_id] = remaining
        else:
            self._rooms.pop(room_id, None)

    async def broadcast(
        self,
        *,
        room_id: UUID,
        payload: dict,
        exclude: WebSocket | None = None,
    ) -> None:
        connections = list(self._rooms.get(room_id, []))
        dead: list[_Connection] = []
        for connection in connections:
            if exclude is not None and connection.websocket is exclude:
                continue
            try:
                await connection.websocket.send_json(payload)
            except Exception:
                dead.append(connection)
        for connection in dead:
            self.disconnect(connection.websocket, room_id)

    def room_connection_count(self, room_id: UUID) -> int:
        return len(self._rooms.get(room_id, []))


manager = ConnectionManager()


# ---------------------------------------------------------------------------
# WebSocket authentication helper (token via query param).
# ---------------------------------------------------------------------------


def _identity_from_token(token: str | None, settings: Settings) -> tuple[str, str]:
    """Validate an OAuth bearer token passed as a query parameter.

    Browsers cannot set custom headers on the WebSocket handshake, so the OAuth
    token is forwarded via ``?token=``. Returns ``(issuer, subject)``.
    """
    if not token:
        raise JwtValidationRejected("OAuth token query parameter is required.")
    payload = validate_oauth_jwt(token, settings)
    issuer = payload.get("iss")
    subject = payload.get("sub")
    if not isinstance(issuer, str) or not isinstance(subject, str):
        raise JwtValidationRejected("OAuth token is missing identity claims.")
    return issuer, subject


# ---------------------------------------------------------------------------
# REST routes.
# ---------------------------------------------------------------------------


@router.get("/rooms")
def list_rooms(
    request: Request,
    limit: Annotated[int, Query(gt=0, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
    identity: Annotated[RequestIdentity, Depends(require_client_auth)] = None,  # type: ignore[assignment]
    service: Annotated[CommunityChatService, Depends(get_community_chat_service)] = None,  # type: ignore[assignment]
) -> dict:
    payload = service.list_rooms(limit=limit, offset=offset)
    return success_envelope(
        request=request,
        data=payload,
        meta={
            "source": "db",
            "limit": limit,
            "offset": offset,
            "total": payload["total"],
        },
    )


@router.post("/rooms")
def create_room(
    request: Request,
    body: ChatRoomCreate,
    identity: Annotated[RequestIdentity, Depends(require_oauth_identity)],
    service: Annotated[CommunityChatService, Depends(get_community_chat_service)],
) -> dict:
    payload = service.create_room(name=body.name)
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.get("/rooms/{room_id}/messages")
def list_messages(
    request: Request,
    room_id: UUID,
    limit: Annotated[int, Query(gt=0, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
    identity: Annotated[RequestIdentity, Depends(require_client_auth)] = None,  # type: ignore[assignment]
    service: Annotated[CommunityChatService, Depends(get_community_chat_service)] = None,  # type: ignore[assignment]
) -> dict:
    payload = service.list_messages(room_id=room_id, limit=limit, offset=offset)
    return success_envelope(
        request=request,
        data=payload,
        meta={
            "source": "db",
            "limit": limit,
            "offset": offset,
            "total": payload["total"],
        },
    )


# ---------------------------------------------------------------------------
# WebSocket route (real-time chat).
# ---------------------------------------------------------------------------


@router.websocket("/rooms/{room_id}/ws")
async def chat_room_ws(
    websocket: WebSocket,
    room_id: UUID,
    token: str | None = None,
    service: Annotated[CommunityChatService, Depends(get_community_chat_service)] = None,  # type: ignore[assignment]
) -> None:
    settings = get_settings()
    try:
        issuer, subject = _identity_from_token(token, settings)
    except (JwtValidationRejected, JwtValidationUnavailable):
        # Reject the handshake before accepting (1008 = policy violation).
        await websocket.close(code=1008)
        return

    await manager.connect(websocket, room_id=room_id, issuer=issuer, subject=subject)
    try:
        while True:
            raw = await websocket.receive_text()
            await _handle_chat_message(
                websocket=websocket,
                room_id=room_id,
                issuer=issuer,
                subject=subject,
                raw=raw,
                service=service,
            )
    except WebSocketDisconnect:
        manager.disconnect(websocket, room_id)


async def _handle_chat_message(
    *,
    websocket: WebSocket,
    room_id: UUID,
    issuer: str,
    subject: str,
    raw: str,
    service: CommunityChatService | None,
) -> None:
    """Parse an inbound text frame, persist it, and broadcast to the room."""
    try:
        parsed = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        await websocket.send_json({"type": "error", "error": {"code": "INVALID_JSON"}})
        return

    body_text = parsed.get("body") if isinstance(parsed, dict) else None
    if not isinstance(body_text, str) or not body_text.strip():
        await websocket.send_json(
            {"type": "error", "error": {"code": "INVALID_MESSAGE", "message": "body is required"}}
        )
        return

    active_service = service or get_community_chat_service()
    try:
        payload = active_service.create_message(
            room_id=room_id,
            issuer=issuer,
            subject=subject,
            body=body_text,
        )
    except ServiceError as exc:
        await websocket.send_json(
            {"type": "error", "error": {"code": exc.code, "message": exc.message}}
        )
        return

    await manager.broadcast(room_id=room_id, payload={"type": "message", "data": payload})
