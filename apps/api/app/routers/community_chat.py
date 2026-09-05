from __future__ import annotations

import asyncio
import json
from collections import deque
from dataclasses import dataclass
from typing import Annotated
from urllib.parse import urlsplit
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, Request, WebSocket, WebSocketDisconnect
from pydantic import ValidationError

from apps.api.app.core.auth import (
    RequestIdentity,
    require_client_auth,
    require_oauth_identity,
)
from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ApiError, ServiceError
from apps.api.app.core.rate_limit import (
    enforce_chat_message_rate_limit,
    enforce_community_write_rate_limit,
)
from apps.api.app.core.responses import success_envelope
from apps.api.app.schemas.community_chat import (
    ChatMessageCreate,
    ChatMessageIn,
    ChatRoomCreate,
    ChatRoomMemberAdd,
)
from apps.api.app.services.community_chat_fanout import (
    fanout_bridge_enabled,
    get_fanout_bridge,
)
from apps.api.app.services.community_chat_service import (
    CommunityChatService,
    get_community_chat_service,
)
from apps.api.app.services.community_idempotency import validate_idempotency_key

router = APIRouter(
    prefix="/api/v1/community/chat",
    tags=["community-chat"],
    # NOTE: no router-level ``require_client_auth`` dependency — it would also
    # gate the WebSocket handshake (which authenticates via a short-lived
    # single-use ticket claimed in the database instead of headers). Each HTTP
    # route declares the dependency itself.
)

# Documented per-actor/per-client write limits (requests/messages per minute).
# Reads are not throttled at this seam. Room creation and ticket issuance are
# enforced inside the handler (after OAuth identity validation); WebSocket
# frames are validated with ``ChatMessageIn`` and throttled per actor+client
# before persistence, so a rejected frame never reaches the service/repository
# or the broadcast.
ROOM_CREATE_LIMIT_PER_MINUTE = 5
CHAT_MESSAGE_LIMIT_PER_MINUTE = 30
CHAT_MESSAGE_REST_LIMIT_PER_MINUTE = 30
WS_TICKET_LIMIT_PER_MINUTE = 30
MEMBER_ADD_LIMIT_PER_MINUTE = 20

# Durable WebSocket handshake contract (see P7 devlog/runbook):
#   * bearer tokens are never accepted on the WebSocket URL — the client
#     exchanges its OAuth bearer for a short-lived single-use ticket over REST
#     (``POST /rooms/{room_id}/ws-ticket``) and the ticket is claimed with one
#     atomic database UPDATE before the socket is accepted;
#   * browsers send ``Origin`` on every handshake: absent Origin (native
#     clients) is allowed, an Origin must match the request host (same-origin)
#     or the configured CORS allowlist;
#   * frames, frame rate and connection lifetime are bounded.
MAX_FRAME_BYTES = 8192
WS_IDLE_TIMEOUT_SECONDS = 600
MAX_CONNECTIONS_PER_ROOM = 200
MAX_WS_CONNECTIONS_PER_ACTOR = 8
_TICKET_MAX_LENGTH = 512
# Delivery-dedup bound: ids of messages already broadcast on this process.
# Bounded memory; Postgres stays the durable truth for history.
_RECENT_DELIVERY_IDS = 256

# Bounded, content-free help text for rejected frames: states the wire contract
# without echoing any part of the rejected payload.
_INVALID_BODY_HELP = "Message must be a JSON object with a body of 1-4000 characters."


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

    @property
    def actor_key(self) -> str:
        return f"{self.issuer}:{self.subject}"


class ConnectionManager:
    """In-memory registry of active WebSocket clients keyed by room.

    A single instance is shared across all chat-room WebSocket endpoints so a
    message persisted in one handler fans out to every connected client in the
    same room. Cross-instance fanout is carried by Postgres NOTIFY (see
    ``community_chat_fanout``); this registry only ever describes the local
    process and is never represented as cross-instance delivery.

    ``broadcast_once`` deduplicates by message id so the local fast path and
    the NOTIFY path never deliver the same committed message twice to local
    sockets.
    """

    def __init__(self) -> None:
        self._rooms: dict[UUID, list[_Connection]] = {}
        self._recent_ids: deque[str] = deque()
        self._recent_id_set: set[str] = set()

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

    async def broadcast_once(
        self,
        *,
        room_id: UUID,
        payload: dict,
        exclude: WebSocket | None = None,
    ) -> None:
        """Deliver a message frame to local sockets unless already delivered."""

        message_id = payload.get("data", {}).get("id") if isinstance(payload, dict) else None
        if isinstance(message_id, str) and not self._claim_delivery(message_id):
            return
        await self.broadcast(room_id=room_id, payload=payload, exclude=exclude)

    def _claim_delivery(self, message_id: str) -> bool:
        # Runs on the event loop only (called before any await), so plain
        # mutation is race-free; the NOTIFY path is scheduled onto the same
        # loop by the fanout bridge.
        if message_id in self._recent_id_set:
            return False
        if len(self._recent_ids) >= _RECENT_DELIVERY_IDS:
            self._recent_id_set.discard(self._recent_ids.popleft())
        self._recent_ids.append(message_id)
        self._recent_id_set.add(message_id)
        return True

    def room_connection_count(self, room_id: UUID) -> int:
        return len(self._rooms.get(room_id, []))

    def actor_connection_count(self, issuer: str, subject: str) -> int:
        actor_key = f"{issuer}:{subject}"
        return sum(
            1
            for connections in self._rooms.values()
            for connection in connections
            if connection.actor_key == actor_key
        )

    def reset_delivery_dedup_for_tests(self) -> None:
        self._recent_ids.clear()
        self._recent_id_set.clear()


manager = ConnectionManager()


async def _deliver_fanout_payload(payload: dict) -> None:
    await manager.broadcast_once(
        room_id=UUID(payload["room_id"]),
        payload={"type": "message", "data": payload},
    )


def _ensure_fanout_bridge() -> None:
    """Start the Postgres LISTEN/NOTIFY bridge once per process.

    No-op without ``DB_DSN`` (unit tests, offline dev): delivery then covers
    only sockets on this instance, REST reads stay authoritative, and the
    degradation is documented in the P7 runbook rather than claimed as
    cross-instance delivery.
    """

    if not fanout_bridge_enabled():
        return
    bridge = get_fanout_bridge(_deliver_fanout_payload)
    if not bridge.running:
        bridge.start(asyncio.get_running_loop())


def _actor_key(issuer: str, subject: str) -> str:
    return f"{issuer}:{subject}"


def _ws_client_key(websocket: WebSocket) -> str:
    client = websocket.client
    if client and client.host:
        return client.host
    return "unknown"


def _viewer_identity(identity: RequestIdentity | None) -> tuple[str | None, str | None]:
    if identity and identity.mode == "oauth" and identity.issuer and identity.subject:
        return identity.issuer, identity.subject
    return None, None


def _origin_allowed(websocket: WebSocket) -> bool:
    """Allowed-origin policy for the browser WebSocket handshake.

    Native clients send no ``Origin`` and pass. A browser handshake must be
    same-origin (Origin host == Host header) or match the deployment's CORS
    allowlist exactly; anything else is rejected before the socket is
    accepted. The policy intentionally adds no new configuration surface.
    """

    origin = (websocket.headers.get("origin") or "").strip()
    if not origin:
        return True
    host = (websocket.headers.get("host") or "").strip().lower()
    origin_host = urlsplit(origin).netloc.lower()
    if origin_host and origin_host == host:
        return True
    for allowed in get_settings().cors_allow_origins or ():
        if allowed.strip().lower().rstrip("/") == origin.lower().rstrip("/"):
            return True
    return False


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
    viewer_issuer, viewer_subject = _viewer_identity(identity)
    payload = service.list_rooms(
        limit=limit,
        offset=offset,
        viewer_issuer=viewer_issuer,
        viewer_subject=viewer_subject,
    )
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
    enforce_community_write_rate_limit(
        request,
        route_key="community-chat-room-create",
        actor_key=_actor_key(identity.issuer or "", identity.subject or ""),
        limit_per_minute=ROOM_CREATE_LIMIT_PER_MINUTE,
    )
    payload = service.create_room(
        name=body.name,
        visibility=body.visibility,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
    )
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.post("/rooms/{room_id}/members")
def add_room_member(
    request: Request,
    room_id: UUID,
    body: ChatRoomMemberAdd,
    identity: Annotated[RequestIdentity, Depends(require_oauth_identity)],
    service: Annotated[CommunityChatService, Depends(get_community_chat_service)],
) -> dict:
    enforce_community_write_rate_limit(
        request,
        route_key="community-chat-member-add",
        actor_key=_actor_key(identity.issuer or "", identity.subject or ""),
        limit_per_minute=MEMBER_ADD_LIMIT_PER_MINUTE,
    )
    payload = service.add_room_member(
        room_id=room_id,
        member_user_id=body.member_user_id,
        owner_issuer=identity.issuer or "",
        owner_subject=identity.subject or "",
    )
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
    viewer_issuer, viewer_subject = _viewer_identity(identity)
    payload = service.list_messages(
        room_id=room_id,
        limit=limit,
        offset=offset,
        viewer_issuer=viewer_issuer,
        viewer_subject=viewer_subject,
    )
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


@router.post("/rooms/{room_id}/ws-ticket")
def create_ws_ticket(
    request: Request,
    room_id: UUID,
    identity: Annotated[RequestIdentity, Depends(require_oauth_identity)],
    service: Annotated[CommunityChatService, Depends(get_community_chat_service)],
) -> dict:
    """Exchange the verified OAuth bearer for a one-shot handshake ticket.

    The response is the only place the raw ticket exists; the database stores
    only its sha256 digest. Re-issuing is cheap and rate-limited per actor.
    """

    enforce_community_write_rate_limit(
        request,
        route_key="community-chat-ws-ticket",
        actor_key=_actor_key(identity.issuer or "", identity.subject or ""),
        limit_per_minute=WS_TICKET_LIMIT_PER_MINUTE,
    )
    payload = service.issue_ws_ticket(
        room_id=room_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
    )
    return success_envelope(
        request=request,
        data=payload,
        meta={"source": "db", "expires_in_seconds": 60},
    )


@router.post("/rooms/{room_id}/messages")
async def create_message(
    request: Request,
    room_id: UUID,
    body: ChatMessageCreate,
    identity: Annotated[RequestIdentity, Depends(require_oauth_identity)],
    service: Annotated[CommunityChatService, Depends(get_community_chat_service)],
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> dict:
    """REST chat send: durable-idempotent retry fallback for the WebSocket.

    ``Idempotency-Key`` (optional, 1-200 chars): the same key with the same
    canonical payload replays the stored response after crash/restart; the
    same key with a different payload is a deterministic 409.
    """

    key = validate_idempotency_key(idempotency_key)
    enforce_community_write_rate_limit(
        request,
        route_key="community-chat-message-rest",
        actor_key=_actor_key(identity.issuer or "", identity.subject or ""),
        limit_per_minute=CHAT_MESSAGE_REST_LIMIT_PER_MINUTE,
    )
    payload = service.create_message(
        room_id=room_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        body=body.body,
        idempotency_key=key,
    )
    await manager.broadcast_once(
        room_id=room_id,
        payload={"type": "message", "data": payload},
    )
    return success_envelope(request=request, data=payload, meta={"source": "db"})


# ---------------------------------------------------------------------------
# WebSocket route (real-time chat).
# ---------------------------------------------------------------------------


@router.websocket("/rooms/{room_id}/ws")
async def chat_room_ws(
    websocket: WebSocket,
    room_id: UUID,
    ticket: str | None = None,
    service: Annotated[CommunityChatService, Depends(get_community_chat_service)] = None,  # type: ignore[assignment]
) -> None:
    """Ticket-authenticated real-time chat socket.

    Authentication happens strictly before any side effect beyond the atomic
    single-use ticket claim itself: origin policy, ticket claim (database
    UPDATE), room binding and access re-check all run before ``accept()``. A
    rejected handshake is a content-free 1008/1013 close that does not reveal
    whether the room exists.
    """

    if not ticket or len(ticket) > _TICKET_MAX_LENGTH:
        await websocket.close(code=1008)
        return
    if not _origin_allowed(websocket):
        await websocket.close(code=1008)
        return
    active_service = service or get_community_chat_service()
    try:
        claim = active_service.claim_ws_ticket(ticket=ticket, room_id=room_id)
    except ServiceError:
        # Store unavailable: ask the client to retry shortly (REST fallback).
        await websocket.close(code=1013)
        return
    if claim is None:
        await websocket.close(code=1008)
        return
    issuer = claim["issuer"]
    subject = claim["subject"]
    if manager.actor_connection_count(issuer, subject) >= MAX_WS_CONNECTIONS_PER_ACTOR:
        await websocket.close(code=1013)
        return
    if manager.room_connection_count(room_id) >= MAX_CONNECTIONS_PER_ROOM:
        await websocket.close(code=1013)
        return

    await manager.connect(websocket, room_id=room_id, issuer=issuer, subject=subject)
    _ensure_fanout_bridge()
    client_key = _ws_client_key(websocket)
    try:
        while True:
            try:
                raw = await asyncio.wait_for(
                    websocket.receive_text(), timeout=WS_IDLE_TIMEOUT_SECONDS
                )
            except TimeoutError:
                # Bounded resource lifetime: idle sockets close normally and
                # clients reconnect with a fresh ticket.
                await websocket.close(code=1000)
                return
            await _handle_chat_message(
                websocket=websocket,
                room_id=room_id,
                issuer=issuer,
                subject=subject,
                client_key=client_key,
                raw=raw,
                service=active_service,
            )
    except WebSocketDisconnect:
        pass
    finally:
        manager.disconnect(websocket, room_id)


async def _handle_chat_message(
    *,
    websocket: WebSocket,
    room_id: UUID,
    issuer: str,
    subject: str,
    client_key: str,
    raw: str,
    service: CommunityChatService | None,
) -> None:
    """Parse, validate, throttle, persist, and broadcast one inbound frame.

    Every rejection path answers with exactly one bounded error frame that
    never echoes message, ticket, or identity content, and never persists or
    broadcasts the rejected payload. The connection stays open afterwards.
    """

    if len(raw.encode("utf-8", errors="replace")) > MAX_FRAME_BYTES:
        await websocket.send_json({"type": "error", "error": {"code": "FRAME_TOO_LARGE"}})
        return

    try:
        parsed = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        await websocket.send_json({"type": "error", "error": {"code": "INVALID_JSON"}})
        return

    if not isinstance(parsed, dict):
        await websocket.send_json(
            {"type": "error", "error": {"code": "INVALID_MESSAGE", "message": _INVALID_BODY_HELP}}
        )
        return

    try:
        message = ChatMessageIn.model_validate(parsed)
    except ValidationError:
        await websocket.send_json(
            {"type": "error", "error": {"code": "INVALID_MESSAGE", "message": _INVALID_BODY_HELP}}
        )
        return

    try:
        enforce_chat_message_rate_limit(
            route_key="community-chat-message",
            actor_key=_actor_key(issuer, subject),
            client_key=client_key,
            limit_per_minute=CHAT_MESSAGE_LIMIT_PER_MINUTE,
        )
    except ApiError as exc:
        await websocket.send_json(
            {"type": "error", "error": {"code": exc.code, "message": exc.message}}
        )
        return

    active_service = service or get_community_chat_service()
    try:
        payload = active_service.create_message(
            room_id=room_id,
            issuer=issuer,
            subject=subject,
            body=message.body,
            idempotency_key=message.idempotency_key,
        )
    except ServiceError as exc:
        await websocket.send_json(
            {"type": "error", "error": {"code": exc.code, "message": exc.message}}
        )
        return

    await manager.broadcast_once(room_id=room_id, payload={"type": "message", "data": payload})
