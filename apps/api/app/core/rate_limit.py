from __future__ import annotations

from dataclasses import dataclass
from time import monotonic
from threading import Lock

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


def enforce_public_contest_paid_route_limit(
    request: Request,
    *,
    route_key: str,
    limit_per_minute: int,
) -> None:
    settings = get_settings()
    if not settings.public_contest_access:
        return
    if not settings.paid_route_rate_limit_enabled:
        return

    limit = max(1, limit_per_minute)
    client_key = _client_key(request)
    now = monotonic()
    key = (route_key, client_key)
    with _lock:
        window = _windows.get(key)
        if window is None or now - window.started_at >= _WINDOW_SECONDS:
            _windows[key] = _Window(started_at=now, count=1)
            return
        window.count += 1
        if window.count <= limit:
            return

    raise ApiError(
        status_code=429,
        code="PAID_ROUTE_RATE_LIMITED",
        message="Too many paid feature requests. Please retry shortly.",
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
