from __future__ import annotations

import hmac
import ipaddress
import os
from threading import Lock
from time import monotonic

from fastapi import APIRouter, Request, Response
from fastapi.responses import PlainTextResponse

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ApiError
from apps.api.app.core.metrics import render_prometheus
from apps.api.app.core.readiness import build_readiness
from apps.api.app.core.responses import success_envelope

router = APIRouter(tags=["operations"])
_readiness_lock = Lock()


def _cached_readiness(request: Request) -> dict:
    settings = get_settings()
    with _readiness_lock:
        cached = getattr(request.app.state, "readiness_cache", None)
        if cached is not None and cached[0] == settings and monotonic() < cached[1]:
            return cached[2]
        result = build_readiness()
        request.app.state.readiness_cache = (settings, monotonic() + 2, result)
        return result


@router.get("/healthz")
def healthz(request: Request) -> dict:
    settings = get_settings()
    return success_envelope(
        request=request,
        data={
            "status": "ok",
            "service": "lala-next-api",
            "version": settings.app_version,
        },
    )


@router.get("/readyz")
def readyz(request: Request, response: Response) -> dict:
    readiness = _cached_readiness(request)
    response.status_code = 200 if readiness["status"] == "ok" else 503
    return success_envelope(request=request, data=readiness)


@router.get("/metrics", response_class=PlainTextResponse)
def metrics(request: Request) -> PlainTextResponse:
    if get_settings().runtime_profile in {"api", "worker"}:
        expected = os.getenv("LALA_METRICS_TOKEN", "")
        supplied = request.headers.get("Authorization", "")
        try:
            local = bool(request.client and ipaddress.ip_address(request.client.host).is_loopback)
        except ValueError:
            local = False
        if not local and not (expected and hmac.compare_digest(supplied, f"Bearer {expected}")):
            raise ApiError(
                status_code=403, code="METRICS_FORBIDDEN", message="Metrics access denied."
            )
    return PlainTextResponse(
        render_prometheus(request.app.state.metrics, readiness=_cached_readiness(request)),
        media_type="text/plain; version=0.0.4; charset=utf-8",
    )
