from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import threading
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any
from uuid import UUID

from apps.api.app.core.config import Settings, get_settings
from apps.api.app.services.community_chat_service import FANOUT_CHANNEL

logger = logging.getLogger(__name__)

# Bounded reconnect backoff for the listener thread (seconds).
_RECONNECT_BACKOFF_SECONDS = (1, 2, 4, 8, 15, 30, 60)
_SELECT_TIMEOUT_SECONDS = 15.0


@dataclass
class _ListenerGeneration:
    """State owned by exactly one listener thread.

    Nothing here is shared across generations: the old thread's ``finally``
    only mutates its own generation, so a late wind-down can never clear a
    successor's connection, stop event or event loop. ``terminated`` is set
    by the owning thread itself when it has fully exited (its connection
    closed by the same thread), which is the only signal ``stop`` trusts.
    """

    thread: threading.Thread
    stop: threading.Event
    loop: asyncio.AbstractEventLoop
    terminated: threading.Event = field(default_factory=threading.Event)
    connection: Any = None


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

    Lifecycle ownership rules (deterministically regression-tested):

    * There is at most one listener thread per bridge. ``start`` is a no-op
      while a healthy generation is serving and *refuses* (returns ``False``)
      while a previous generation is still winding down — confirmed
      termination is required before a restart.
    * Each generation owns its connection, stop event, event loop and
      delivery scheduling; a stale generation can neither deliver after being
      replaced nor mutate the successor's state.
    * The owning thread closes its own connection in its own ``finally``.
      ``stop`` only asks it to leave (stop event + advisory ``cancel()``) and
      then waits a bounded time for ``terminated``; ``connection.cancel()``
      aborts a server round trip but is *not* guaranteed to interrupt a
      locally blocked ``select``, so on timeout the generation is retained
      (not force-closed, not replaced) and simply refuses restarts until the
      thread itself confirms exit.
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
        self._generation: _ListenerGeneration | None = None
        self._lifecycle_lock = threading.Lock()

    # -- Lifecycle -----------------------------------------------------------

    @property
    def running(self) -> bool:
        generation = self._generation
        return (
            generation is not None and generation.thread.is_alive() and not generation.stop.is_set()
        )

    @property
    def winding_down(self) -> bool:
        generation = self._generation
        return generation is not None and generation.thread.is_alive() and generation.stop.is_set()

    def start(self, loop: asyncio.AbstractEventLoop) -> bool:
        """Start one listener generation.

        Returns ``True`` when a generation is serving (existing or freshly
        started) and ``False`` when a previous generation is still winding
        down — in that case no thread is spawned and the caller may retry
        once the old generation confirms termination. Callers must only
        invoke this when a database is configured: without ``DB_DSN`` the
        bridge stays off and WebSocket delivery degrades to same-instance
        only (documented in the P7 runbook).
        """

        with self._lifecycle_lock:
            generation = self._generation
            if generation is not None and generation.thread.is_alive():
                # Already serving: no second listener. Winding down: refuse —
                # restart only after the old generation confirms termination.
                return not generation.stop.is_set()
            # Build the generation object first so the thread closes over the
            # exact object stored on the bridge (identity-checked delivery).
            new_generation = _ListenerGeneration(
                thread=None,  # type: ignore[arg-type]
                stop=threading.Event(),
                loop=loop,
            )
            thread = threading.Thread(
                target=self._listen_loop,
                args=(new_generation,),
                name="community-chat-fanout-bridge",
                daemon=True,
            )
            new_generation.thread = thread
            self._generation = new_generation
            thread.start()
            return True

    def stop(self, timeout: float = 3.0) -> bool:
        """Bounded shutdown of the current generation.

        Sets the generation-owned stop event and issues an advisory
        ``connection.cancel()`` (safe from this thread; may not interrupt a
        locally blocked ``select``). Waits up to ``timeout`` for the owning
        thread to confirm its own termination — the thread closes its own
        connection, so this side never closes a connection it does not own.
        Returns ``True`` when termination was confirmed within ``timeout``.
        On timeout the generation is retained untouched: it keeps ownership
        of its connection and refuses restarts (``start`` returns ``False``)
        until the thread itself exits; bounded callers are never blocked
        waiting for that to happen.
        """

        with self._lifecycle_lock:
            generation = self._generation
        if generation is None:
            return True
        generation.stop.set()
        connection = generation.connection
        if connection is not None:
            with contextlib.suppress(Exception):
                connection.cancel()
        confirmed = generation.terminated.wait(timeout=timeout)
        if confirmed:
            with self._lifecycle_lock:
                if self._generation is generation:
                    self._generation = None
        return confirmed

    # -- Notification handling (unit-testable without a thread) -------------

    def handle_notification(
        self,
        payload_json: str,
        *,
        generation: _ListenerGeneration | None = None,
    ) -> dict[str, Any] | None:
        """Parse one NOTIFY payload and schedule local delivery.

        ``generation`` is the listener the notification came from (``None``
        means "the current one"). A stale generation — replaced or stopped —
        never delivers. Returns the fetched message payload (for
        tests/diagnostics) or ``None`` when the payload is malformed, the
        listener is gone, or the message is no longer readable. Never raises:
        a bad notification only skips delivery.
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
        current = self._generation
        if generation is not None and current is not generation:
            return None  # stale generation: never deliver after replacement
        if current is None:
            return None  # no listener: delivery is honestly skipped
        try:
            fetcher = self._fetcher_factory()
            message = fetcher.fetch_message_for_fanout(message_id=UUID(message_id))
        except Exception:
            # Exception-safe fetch: a transient store error skips this
            # delivery without killing the listener loop. The exception text
            # can embed connection details, so it is not logged.
            return None
        if message is None:
            return None
        fetched = message if isinstance(message, dict) else dict(message)
        if str(fetched.get("room_id")) != room_id:
            return None
        self._schedule_deliver(current, fetched)
        return fetched

    def _schedule_deliver(self, generation: _ListenerGeneration, payload: dict[str, Any]) -> None:
        # Re-checked at schedule time: the generation may have been replaced
        # or stopped while the fetch was in flight.
        if self._generation is not generation or generation.stop.is_set():
            return
        loop = generation.loop
        if loop is None or loop.is_closed():
            return
        asyncio.run_coroutine_threadsafe(self._deliver(payload), loop)

    # -- Listener thread -----------------------------------------------------

    def _listen_loop(self, generation: _ListenerGeneration) -> None:
        try:
            reconnect_attempt = 0
            while not generation.stop.is_set():
                connection = None
                try:
                    connection = self._open_listener_connection()
                    generation.connection = connection
                    reconnect_attempt = 0
                    self._drain_notifications(generation, connection)
                except Exception:
                    # Content-free: the durable store is unaffected; delivery
                    # resumes when the listener reconnects. Exception details
                    # (DSN/payload) are deliberately not logged.
                    logger.warning("community chat fanout listener disconnected; retrying")
                finally:
                    generation.connection = None
                    if connection is not None:
                        with contextlib.suppress(Exception):
                            connection.close()
                if generation.stop.is_set():
                    break
                delay = _RECONNECT_BACKOFF_SECONDS[
                    min(reconnect_attempt, len(_RECONNECT_BACKOFF_SECONDS) - 1)
                ]
                reconnect_attempt += 1
                generation.stop.wait(delay)
        finally:
            generation.terminated.set()

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

    def _drain_notifications(self, generation: _ListenerGeneration, connection) -> None:
        import select

        while not generation.stop.is_set():
            ready, _, _ = select.select([connection], [], [], _SELECT_TIMEOUT_SECONDS)
            if not ready:
                continue
            connection.poll()
            while connection.notifies:
                notification = connection.notifies.pop(0)
                self.handle_notification(notification.payload, generation=generation)


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
