from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import threading
from collections.abc import Callable
from typing import Any
from uuid import UUID

from apps.api.app.core.config import Settings, get_settings
from apps.api.app.services.community_chat_service import FANOUT_CHANNEL

logger = logging.getLogger(__name__)

# Bounded reconnect backoff for the listener thread (seconds).
_RECONNECT_BACKOFF_SECONDS = (1, 2, 4, 8, 15, 30, 60)
_SELECT_TIMEOUT_SECONDS = 15.0


class ChatFanoutBridge:
    """Cross-instance chat fanout over Postgres LISTEN/NOTIFY.

    The writing instance emits ``pg_notify`` in the message transaction (see
    ``community_chat_service``); every API instance that holds WebSocket
    clients runs one listener connection. On notification the message row is
    fetched from Postgres (the durable truth) and delivered to the local room
    sockets on the event loop that started the bridge.

    Honest scope: this is delivery plumbing on top of the durable store. If a
    listener is down, cross-instance delivery pauses until it reconnects; the
    messages remain committed and readable through the REST history endpoint,
    and clients recover by refreshing history on reconnect.
    """

    def __init__(
        self,
        *,
        fetcher_factory: Callable[[], Any],
        deliver: Callable[[dict[str, Any]], Any],
        channel: str = FANOUT_CHANNEL,
    ) -> None:
        self._fetcher_factory = fetcher_factory
        self._deliver = deliver
        self._channel = channel
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._stop = threading.Event()

    # -- Lifecycle -----------------------------------------------------------

    @property
    def running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def start(self, loop: asyncio.AbstractEventLoop) -> bool:
        """Start the listener thread once; returns whether it is running.

        Callers must only invoke this when a database is configured: without
        ``DB_DSN`` the bridge stays off and WebSocket delivery degrades to
        same-instance only (documented in the P7 runbook).
        """

        if self.running:
            return True
        self._stop.clear()
        self._loop = loop
        thread = threading.Thread(
            target=self._listen_loop,
            name="community-chat-fanout-bridge",
            daemon=True,
        )
        self._thread = thread
        thread.start()
        return True

    def stop(self, timeout: float = 1.0) -> None:
        self._stop.set()
        thread = self._thread
        if thread is not None and thread.is_alive():
            thread.join(timeout=timeout)
        self._thread = None
        self._loop = None

    # -- Notification handling (unit-testable without a thread) -------------

    def handle_notification(self, payload_json: str) -> dict[str, Any] | None:
        """Parse one NOTIFY payload and schedule local delivery.

        Returns the fetched message payload (for tests/diagnostics) or
        ``None`` when the payload is malformed or the message is no longer
        readable. Never raises: a bad notification only skips delivery.
        """

        try:
            payload = json.loads(payload_json)
        except (json.JSONDecodeError, TypeError):
            return None
        if not isinstance(payload, dict):
            return None
        room_id = payload.get("room_id")
        message_id = payload.get("message_id")
        if not isinstance(room_id, str) or not isinstance(message_id, str):
            return None
        try:
            UUID(room_id)
            UUID(message_id)
        except ValueError:
            return None
        fetcher = self._fetcher_factory()
        message = fetcher.fetch_message_for_fanout(message_id=UUID(message_id))
        if message is None:
            return None
        fetched = message if isinstance(message, dict) else dict(message)
        if str(fetched.get("room_id")) != room_id:
            return None
        self._schedule_deliver(fetched)
        return fetched

    def _schedule_deliver(self, payload: dict[str, Any]) -> None:
        loop = self._loop
        if loop is None or loop.is_closed():
            return
        asyncio.run_coroutine_threadsafe(self._deliver(payload), loop)

    # -- Listener thread -----------------------------------------------------

    def _listen_loop(self) -> None:
        reconnect_attempt = 0
        while not self._stop.is_set():
            connection = None
            try:
                connection = self._open_listener_connection()
                reconnect_attempt = 0
                self._drain_notifications(connection)
            except Exception:
                # Content-free: the durable store is unaffected; delivery
                # resumes when the listener reconnects.
                logger.warning("community chat fanout listener disconnected; retrying")
            finally:
                if connection is not None:
                    with contextlib.suppress(Exception):
                        connection.close()
            if self._stop.is_set():
                break
            delay = _RECONNECT_BACKOFF_SECONDS[
                min(reconnect_attempt, len(_RECONNECT_BACKOFF_SECONDS) - 1)
            ]
            reconnect_attempt += 1
            self._stop.wait(delay)

    def _open_listener_connection(self):
        import psycopg2

        settings = get_settings()
        if not settings.db_dsn:
            raise RuntimeError("fanout bridge requires DB_DSN")
        connection = psycopg2.connect(settings.db_dsn, connect_timeout=3)
        connection.autocommit = True
        with connection.cursor() as cur:
            cur.execute(f"LISTEN {self._channel}")
        return connection

    def _drain_notifications(self, connection) -> None:
        import select

        while not self._stop.is_set():
            ready, _, _ = select.select([connection], [], [], _SELECT_TIMEOUT_SECONDS)
            if not ready:
                continue
            connection.poll()
            while connection.notifies:
                notification = connection.notifies.pop(0)
                self.handle_notification(notification.payload)


_default_bridge: ChatFanoutBridge | None = None
_default_bridge_lock = threading.Lock()


def get_fanout_bridge(deliver: Callable[[dict[str, Any]], Any]) -> ChatFanoutBridge:
    """Process-wide bridge singleton wired to the given async deliverer.

    The default fetcher goes through ``CommunityChatService`` so scheduled
    payloads are the wire-shaped message dicts (string ids/ISO timestamps),
    never raw driver rows, and store unavailability degrades to a skip.
    """

    global _default_bridge
    with _default_bridge_lock:
        if _default_bridge is None:
            from apps.api.app.services.community_chat_service import (
                get_community_chat_service,
            )

            _default_bridge = ChatFanoutBridge(
                fetcher_factory=get_community_chat_service,
                deliver=deliver,
            )
        return _default_bridge


def fanout_bridge_enabled(settings: Settings | None = None) -> bool:
    resolved = settings or get_settings()
    return bool(resolved.db_dsn)


def reset_fanout_bridge_for_tests() -> None:
    global _default_bridge
    with _default_bridge_lock:
        if _default_bridge is not None:
            _default_bridge.stop()
        _default_bridge = None
