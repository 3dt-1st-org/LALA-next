from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import PlainTextResponse

from apps.api.app.core.config import get_settings
from apps.api.app.core.metrics import render_prometheus
from apps.api.app.core.readiness import build_readiness
from apps.api.app.core.responses import success_envelope

router = APIRouter(tags=["operations"])


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
def readyz(request: Request) -> dict:
    readiness = build_readiness()
    return success_envelope(request=request, data=readiness)


@router.get("/metrics", response_class=PlainTextResponse)
def metrics(request: Request) -> PlainTextResponse:
    return PlainTextResponse(
        render_prometheus(request.app.state.metrics, readiness=build_readiness()),
        media_type="text/plain; version=0.0.4; charset=utf-8",
    )
