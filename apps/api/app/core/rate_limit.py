from __future__ import annotations

import hashlib
from dataclasses import dataclass
from threading import Lock
from time import monotonic

from fastapi import Request

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ApiError


@dataclass
class _Window:
    started_at: float
    count: int


_WINDOW_SECONDS = 60.0
_windows: dict[tuple[str, str], _Window] = {}
_lock = Lock()


def _window_allows(key: tuple[str, str], limit: int) -> bool:
    """Advance the shared fixed window once and report whether it is still open.

    The in-process window is intentionally a development/test seam. Production
    deployment can replace the ``enforce_*`` seams with the existing
    edge/distributed limiter without changing route contracts.
    """

    now = monotonic()
    with _lock:
        window = _windows.get(key)
        if window is None or now - window.started_at >= _WINDOW_SECONDS:
            _windows[key] = _Window(started_at=now, count=1)
            return True
        window.count += 1
        return window.count <= limit


def _hashed_key(route_key: str, actor_key: str, client_key: str) -> tuple[str, str]:
    # Hashing keeps the in-process key from becoming an accidental observable
    # identity record while preserving per-actor and per-client isolation.
    key_material = f"{route_key}:{actor_key}:{client_key}".encode()
    return (route_key, hashlib.sha256(key_material).hexdigest())


def enforce_public_contest_paid_route_limit(
    request: Request,
    *,
    route_key: str,
    limit_per_minute: int,
) -> None:
    settings = get_settings()
    if not settings.guest_access_enabled:
        return
    if not settings.paid_route_rate_limit_enabled:
        return

    limit = max(1, limit_per_minute)
    key = (route_key, _client_key(request))
    if _window_allows(key, limit):
        return

    raise ApiError(
        status_code=429,
        code="PAID_ROUTE_RATE_LIMITED",
        message="Too many paid feature requests. Please retry shortly.",
        retryable=True,
    )


def enforce_local_signals_rate_limit(
    request: Request,
    *,
    route_key: str,
    actor_key: str,
    limit_per_minute: int,
) -> None:
    limit = max(1, limit_per_minute)
    key = _hashed_key(route_key, actor_key, _client_key(request))
    if _window_allows(key, limit):
        return

    raise ApiError(
        status_code=429,
        code="RATE_LIMITED",
        message="Too many Local Signals requests. Please retry shortly.",
        retryable=True,
    )


def enforce_community_write_rate_limit(
    request: Request,
    *,
    route_key: str,
    actor_key: str,
    limit_per_minute: int,
) -> None:
    """Bounded per-actor/per-client window for authenticated community writes.

    Same replaceable seam and hashed-key discipline as Local Signals, with a
    community-specific error contract. Call only after OAuth identity
    validation so unauthenticated requests never consume an actor window.
    """

    limit = max(1, limit_per_minute)
    key = _hashed_key(route_key, actor_key, _client_key(request))
    if _window_allows(key, limit):
        return

    raise ApiError(
        status_code=429,
        code="COMMUNITY_RATE_LIMITED",
        message="Too many community requests. Please retry shortly.",
        retryable=True,
    )


def enforce_chat_message_rate_limit(
    *,
    route_key: str,
    actor_key: str,
    client_key: str,
    limit_per_minute: int,
) -> None:
    """Bounded per-actor/per-client window for inbound WebSocket chat frames.

    WebSocket frames carry no per-frame ``Request``; callers pass the
    connection's stable client key (resolved once at handshake). Raises the
    same bounded ``ApiError`` contract so the frame handler can emit one
    bounded error frame without echoing message or identity content.
    """

    limit = max(1, limit_per_minute)
    key = _hashed_key(route_key, actor_key, client_key)
    if _window_allows(key, limit):
        return

    raise ApiError(
        status_code=429,
        code="RATE_LIMITED",
        message="Too many chat messages. Please retry shortly.",
        retryable=True,
    )


def _client_key(request: Request) -> str:
    forwarded = (request.headers.get("CF-Connecting-IP") or "").strip()
    if not forwarded:
        forwarded = (request.headers.get("X-Forwarded-For") or "").split(",", 1)[0].strip()
    if forwarded:
        return forwarded
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


def reset_rate_limit_state_for_tests() -> None:
    with _lock:
        _windows.clear()
