from __future__ import annotations

import asyncio
import contextlib
from collections import deque
from collections.abc import Awaitable, Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from functools import partial
from threading import BoundedSemaphore
from uuid import UUID

from fastapi import WebSocket, WebSocketDisconnect

from apps.api.app.core.errors import ServiceError
from apps.api.app.services.community_chat_fanout import (
    fanout_bridge_enabled,
    get_fanout_bridge,
)
from apps.api.app.services.community_chat_service import get_community_chat_service

DB_WORK_CAPACITY = 16
SEND_TIMEOUT_SECONDS = 2.0
MAX_PENDING_BROADCASTS = 32
RECENT_DELIVERY_IDS = 256

_db_work_slots = BoundedSemaphore(DB_WORK_CAPACITY)
_db_executor = ThreadPoolExecutor(max_workers=DB_WORK_CAPACITY, thread_name_prefix="chat-db")


async def run_db(function, **kwargs):
    # Admission happens before submitting work: no unbounded executor queue.
    if not _db_work_slots.acquire(blocking=False):
        raise ServiceError(
            status_code=503,
            code="DATABASE_UNAVAILABLE",
            message="Chat is busy. Please retry.",
            retryable=True,
        )
    try:
        future = _db_executor.submit(partial(function, **kwargs))
    except BaseException:
        _db_work_slots.release()
        raise
    # Cancellation of the caller must not release a still-running DB worker slot.
    future.add_done_callback(lambda _: _db_work_slots.release())
    return await asyncio.shield(asyncio.wrap_future(future))


async def send_json(websocket, payload):
    try:
        await asyncio.wait_for(websocket.send_json(payload), SEND_TIMEOUT_SECONDS)
    except TimeoutError:
        with contextlib.suppress(Exception):
            await asyncio.wait_for(websocket.close(code=1013), SEND_TIMEOUT_SECONDS)
        raise WebSocketDisconnect(code=1013) from None


@dataclass
class _Connection:
    websocket: WebSocket
    room_id: UUID
    issuer: str
    subject: str
    sending: asyncio.Lock = field(default_factory=asyncio.Lock)

    @property
    def actor_key(self) -> str:
        return f"{self.issuer}:{self.subject}"


class ConnectionManager:
    """In-memory registry of active WebSocket clients keyed by room."""

    def __init__(self) -> None:
        self._pending_broadcasts = 0
        self._rooms: dict[UUID, list[_Connection]] = {}
        self._recent_ids: deque[str] = deque()
        self._recent_id_set: set[str] = set()
        self._access_verifier: (
            Callable[[UUID, list[tuple[str, str]]], Awaitable[set[str]]] | None
        ) = None

    def attach_access_verifier(
        self,
        verifier: Callable[[UUID, list[tuple[str, str]]], Awaitable[set[str]]],
    ) -> None:
        self._access_verifier = verifier

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
        if not connections:
            return
        if self._pending_broadcasts >= MAX_PENDING_BROADCASTS:
            return  # Durable history is the recovery path under overload.
        self._pending_broadcasts += 1
        try:
            allowed = await self._resolve_allowed_actors(room_id, connections)
            if allowed is None:
                return

            async def deliver(connection):
                if exclude is not None and connection.websocket is exclude:
                    return
                if connection.sending.locked():
                    self.disconnect(connection.websocket, room_id)
                    with contextlib.suppress(Exception):
                        await asyncio.wait_for(
                            connection.websocket.close(code=1013), SEND_TIMEOUT_SECONDS
                        )
                    return
                async with connection.sending:
                    try:
                        if connection.actor_key not in allowed:
                            self.disconnect(connection.websocket, room_id)
                            await asyncio.wait_for(
                                connection.websocket.close(code=1008), SEND_TIMEOUT_SECONDS
                            )
                        else:
                            await send_json(connection.websocket, payload)
                    except Exception:
                        self.disconnect(connection.websocket, room_id)

            await asyncio.gather(*(deliver(connection) for connection in connections))
        finally:
            self._pending_broadcasts -= 1

    async def _resolve_allowed_actors(
        self,
        room_id: UUID,
        connections: list[_Connection],
    ) -> frozenset[str] | None:
        verifier = self._access_verifier
        if verifier is None:
            return None
        actors = sorted({(c.issuer, c.subject) for c in connections})
        try:
            allowed = await verifier(room_id, actors)
        except Exception:
            return None
        return frozenset(allowed)

    async def broadcast_once(
        self,
        *,
        room_id: UUID,
        payload: dict,
        exclude: WebSocket | None = None,
    ) -> None:
        message_id = payload.get("data", {}).get("id") if isinstance(payload, dict) else None
        if isinstance(message_id, str) and not self._claim_delivery(message_id):
            return
        await self.broadcast(room_id=room_id, payload=payload, exclude=exclude)

    def _claim_delivery(self, message_id: str) -> bool:
        if message_id in self._recent_id_set:
            return False
        if len(self._recent_ids) >= RECENT_DELIVERY_IDS:
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


async def verify_room_access_for_actors(
    room_id: UUID,
    actors: list[tuple[str, str]],
) -> set[str]:
    service = get_community_chat_service()
    return await run_db(service.authorized_actors, room_id=room_id, actors=actors)


manager.attach_access_verifier(verify_room_access_for_actors)


async def deliver_fanout_payload(payload: dict) -> None:
    await manager.broadcast_once(
        room_id=UUID(payload["room_id"]),
        payload={"type": "message", "data": payload},
    )


def ensure_fanout_bridge() -> None:
    """Start the Postgres LISTEN/NOTIFY bridge once per process."""

    if not fanout_bridge_enabled():
        return
    bridge = get_fanout_bridge(deliver_fanout_payload)
    if not bridge.running:
        bridge.start(asyncio.get_running_loop())
