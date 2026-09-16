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
    """Bounded no-DB fallback; configured databases use shared admission."""

    now = monotonic()
    with _lock:
        for expired_key, item in list(_windows.items()):
            if now - item.started_at >= _WINDOW_SECONDS:
                del _windows[expired_key]
        if key not in _windows and len(_windows) >= min(
            4096, max(1, get_settings().paid_memory_max_entries)
        ):
            return False
        window = _windows.get(key)
        if window is None or now - window.started_at >= _WINDOW_SECONDS:
            _windows[key] = _Window(started_at=now, count=1)
            return True
        window.count += 1
        return window.count <= limit


def _hashed_key(route_key: str, actor_key: str, client_key: str) -> tuple[str, str]:
    # Hashing keeps the in-process key from becoming an accidental observable
    # identity record. Authenticated budgets never depend on the peer address.
    key_material = f"{route_key}:{actor_key}".encode()
    return (route_key, hashlib.sha256(key_material).hexdigest())


def _admit(key: tuple[str, str], limit: int) -> bool:
    if get_settings().db_dsn:
        from apps.api.app.services.paid_cost_control import enforce_db_window

        return enforce_db_window(":".join(key), max(1, limit))
    return _window_allows(key, max(1, limit))


def enforce_public_contest_paid_route_limit(
    request: Request,
    *,
    route_key: str,
    limit_per_minute: int,
) -> None:
    from apps.api.app.core.auth import require_client_auth
    from apps.api.app.services.paid_cost_control import paid_actor

    identity = getattr(request.state, "identity", None)
    if identity is None:
        identity = require_client_auth(
            x_api_key=request.headers.get("X-API-Key"),
            authorization=request.headers.get("Authorization"),
            request=request,
        )
    actor = (
        f"oauth:{identity.issuer}:{identity.subject}"
        if identity.mode == "oauth"
        else "static"
        if identity.mode == "static"
        else f"public:{_client_key(request)}"
    )
    paid_actor.set(actor)
    key = _hashed_key(route_key, actor, "")
    if _admit(key, limit_per_minute):
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
    if _admit(key, limit):
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
    """Bounded per-actor window for authenticated community writes.

    Same shared storage and hashed-key discipline as Local Signals, with a
    community-specific error contract. Call only after OAuth identity
    validation so unauthenticated requests never consume an actor window.
    """

    limit = max(1, limit_per_minute)
    key = _hashed_key(route_key, actor_key, _client_key(request))
    if _admit(key, limit):
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
    """Bounded per-actor window for inbound WebSocket chat frames.

    WebSocket frames carry no per-frame ``Request``; callers pass the
    connection's client key for compatibility; admission keys use only the
    authenticated actor. Raises the
    same bounded ``ApiError`` contract so the frame handler can emit one
    bounded error frame without echoing message or identity content.
    """

    limit = max(1, limit_per_minute)
    key = _hashed_key(route_key, actor_key, client_key)
    if _admit(key, limit):
        return

    raise ApiError(
        status_code=429,
        code="RATE_LIMITED",
        message="Too many chat messages. Please retry shortly.",
        retryable=True,
    )


def _client_key(request: Request) -> str:
    # Only the ASGI peer is trusted. Proxy header trust belongs to a separately
    # configured ingress, never to arbitrary HTTP CF/XFF header values.
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


def reset_rate_limit_state_for_tests() -> None:
    with _lock:
        _windows.clear()
