from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request, Response

from apps.api.app.core.auth import (
    RequestIdentity,
    require_client_auth,
    require_logto_identity,
)
from apps.api.app.core.config import get_settings
from apps.api.app.core.rate_limit import enforce_public_contest_paid_route_limit
from apps.api.app.core.responses import ensure_request_id, success_envelope
from apps.api.app.schemas.account import AccountDeletionRequest
from apps.api.app.schemas.docent import DocentAudioRequest, DocentScriptRequest
from apps.api.app.schemas.planner import DailyPlanRequest
from apps.api.app.services import docent_service, places_service, planner_service, weather_service
from apps.api.app.services.identity_service import IdentityService, get_identity_service
from apps.api.app.services.logto_management import (
    LogtoManagementClient,
    get_logto_management_client,
)

router = APIRouter(
    prefix="/api/v1",
    tags=["v1"],
    dependencies=[Depends(require_client_auth)],
)


@router.get(
    "/me",
    description=(
        "Returns the local account for an OAuth identity issued by the current configured "
        "LOGTO_ENDPOINT. Legacy OAUTH issuers are not accepted."
    ),
)
def me(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    identity_service: Annotated[IdentityService, Depends(get_identity_service)],
) -> dict:
    user = identity_service.provision_user(identity.issuer or "", identity.subject or "")
    return success_envelope(
        request=request,
        data={
            "user_id": str(user.id),
            "created_at": user.created_at.isoformat(),
            "authenticated": True,
        },
    )


@router.delete(
    "/me",
    status_code=204,
    description=(
        "Deletes the account for an OAuth identity issued by the current configured "
        "LOGTO_ENDPOINT. Legacy OAUTH issuers are not accepted."
    ),
)
def delete_me(
    body: AccountDeletionRequest,
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    identity_service: Annotated[IdentityService, Depends(get_identity_service)],
    management_client: Annotated[
        LogtoManagementClient,
        Depends(get_logto_management_client),
    ],
) -> Response:
    issuer = identity.issuer or ""
    subject = identity.subject or ""
    try:
        identity_service.mark_user_deleting(issuer, subject)
        management_client.delete_user(subject)
        identity_service.finalize_user_deletion(issuer, subject)
    except Exception:
        request.app.state.metrics.record_auth_event("account_deletion_failure")
        raise
    return Response(status_code=204)


@router.get("/places")
def places(
    request: Request,
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    radius_m: int = Query(1000, gt=0, le=50000),
    category: str = Query("all"),
    lang: str = Query("ko"),
    language: str | None = Query(None),
    include_scores: bool = Query(False),
    limit: int = Query(60, gt=0, le=100),
) -> dict:
    selected_language = language or lang
    payload = places_service.list_places(
        lat=lat,
        lng=lng,
        radius_m=radius_m,
        category=category,
        language=selected_language,
        include_scores=include_scores,
        limit=limit,
    )
    return success_envelope(
        request=request, data=payload, meta={"source": payload.get("source", "computed")}
    )


@router.get("/weather")
def weather(
    request: Request,
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    force: bool = Query(False),
) -> dict:
    payload = weather_service.current_weather(lat=lat, lng=lng, force=force)
    return success_envelope(
        request=request, data=payload, meta={"source": payload.get("source", "computed")}
    )


@router.post("/docents/script")
def docent_script(request: Request, body: DocentScriptRequest) -> dict:
    settings = get_settings()
    enforce_public_contest_paid_route_limit(
        request,
        route_key="docents:script",
        limit_per_minute=settings.docent_script_rate_limit_per_minute,
    )
    payload = docent_service.generate_script(body)
    return success_envelope(
        request=request, data=payload, meta={"source": payload.get("source", "computed")}
    )


@router.post(
    "/docents/audio",
    responses={
        200: {
            "description": "Successful MP3 audio response",
            "content": {"audio/mpeg": {"schema": {"type": "string", "format": "binary"}}},
        },
        503: {
            "description": "Live speech synthesis is not configured",
            "content": {"application/json": {"schema": {"type": "object"}}},
        },
    },
)
def docent_audio(request: Request, body: DocentAudioRequest) -> Response:
    settings = get_settings()
    enforce_public_contest_paid_route_limit(
        request,
        route_key="docents:audio",
        limit_per_minute=settings.docent_audio_rate_limit_per_minute,
    )
    audio = docent_service.generate_audio(body)
    identity = docent_service.audio_identity(body)
    return Response(
        content=audio,
        media_type="audio/mpeg",
        headers={
            "X-Request-ID": ensure_request_id(request),
            "X-LALA-Request-Hash": identity["request_hash"],
            "X-LALA-Cache-Key": identity["cache_key"],
        },
    )


@router.post("/plans/daily")
def daily_plan(request: Request, body: DailyPlanRequest) -> dict:
    payload = planner_service.daily_plan(body)
    return success_envelope(
        request=request, data=payload, meta={"source": payload.get("source", "computed")}
    )


@router.get("/plans/intervention")
def intervention(
    request: Request,
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    radius_m: int = Query(10000, gt=0, le=50000),
) -> dict:
    payload = planner_service.intervention(lat=lat, lng=lng, radius_m=radius_m)
    return success_envelope(
        request=request, data=payload, meta={"source": payload.get("source", "computed")}
    )
