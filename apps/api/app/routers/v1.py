from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Request, Response

from apps.api.app.core.auth import require_client_auth
from apps.api.app.core.responses import ensure_request_id, success_envelope
from apps.api.app.schemas.docent import DocentAudioRequest, DocentScriptRequest
from apps.api.app.schemas.planner import DailyPlanRequest
from apps.api.app.services import docent_service, planner_service, places_service, weather_service

router = APIRouter(
    prefix="/api/v1",
    tags=["v1"],
    dependencies=[Depends(require_client_auth)],
)


@router.get("/places")
def places(
    request: Request,
    lat: float = Query(37.2636, ge=-90, le=90),
    lng: float = Query(127.0286, ge=-180, le=180),
    radius_m: int = Query(1000, gt=0, le=50000),
    category: str = Query("all"),
    lang: str = Query("ko"),
    language: str | None = Query(None),
    include_scores: bool = Query(False),
) -> dict:
    selected_language = language or lang
    payload = places_service.list_places(
        lat=lat,
        lng=lng,
        radius_m=radius_m,
        category=category,
        language=selected_language,
        include_scores=include_scores,
    )
    return success_envelope(request=request, data=payload, meta={"source": payload.get("source", "computed")})


@router.get("/weather")
def weather(
    request: Request,
    lat: float = Query(37.2636, ge=-90, le=90),
    lng: float = Query(127.0286, ge=-180, le=180),
    force: bool = Query(False),
) -> dict:
    payload = weather_service.current_weather(lat=lat, lng=lng, force=force)
    return success_envelope(request=request, data=payload, meta={"source": payload.get("source", "computed")})


@router.post("/docents/script")
def docent_script(request: Request, body: DocentScriptRequest) -> dict:
    payload = docent_service.generate_script(body)
    return success_envelope(request=request, data=payload, meta={"source": payload.get("source", "computed")})


@router.post(
    "/docents/audio",
    responses={
        200: {
            "description": "Successful MP3 audio response",
            "content": {"audio/mpeg": {"schema": {"type": "string", "format": "binary"}}},
        }
    },
)
def docent_audio(request: Request, body: DocentAudioRequest) -> Response:
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
    return success_envelope(request=request, data=payload, meta={"source": payload.get("source", "computed")})


@router.get("/plans/intervention")
def intervention(
    request: Request,
    lat: float = Query(37.2636, ge=-90, le=90),
    lng: float = Query(127.0286, ge=-180, le=180),
    radius_m: int = Query(10000, gt=0, le=50000),
) -> dict:
    payload = planner_service.intervention(lat=lat, lng=lng, radius_m=radius_m)
    return success_envelope(request=request, data=payload, meta={"source": payload.get("source", "computed")})
