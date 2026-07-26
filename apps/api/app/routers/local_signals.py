from __future__ import annotations

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, Request

from apps.api.app.core.auth import (
    RequestIdentity,
    require_client_auth,
    require_logto_identity,
)
from apps.api.app.core.config import get_settings
from apps.api.app.core.metrics import RuntimeMetrics
from apps.api.app.core.rate_limit import enforce_local_signals_rate_limit
from apps.api.app.core.responses import success_envelope
from apps.api.app.schemas.local_signals import (
    LocalSignalCommentCreate,
    LocalSignalDraftCreate,
    LocalSignalKind,
    LocalSignalLanguage,
    LocalSignalPatch,
    LocalSignalReportCreate,
)
from apps.api.app.services.local_signals_service import (
    LocalSignalsRepository,
    LocalSignalsService,
)
from apps.api.app.services.request_identity import request_hash

router = APIRouter(
    prefix="/api/v1/community",
    tags=["local-signals"],
    dependencies=[Depends(require_client_auth)],
)


def get_local_signals_service() -> LocalSignalsService:
    settings = get_settings()
    return LocalSignalsService(LocalSignalsRepository(settings), settings=settings)


def _actor_key(identity: RequestIdentity) -> str:
    if identity.mode == "oauth" and identity.issuer and identity.subject:
        return f"{identity.issuer}:{identity.subject}"
    return "public"


def _record_event(request: Request, event: str) -> None:
    metrics: RuntimeMetrics | None = getattr(request.app.state, "metrics", None)
    if metrics is not None:
        metrics.record_local_signal_event(event)


def _idempotency_key(
    request: Request,
    supplied: str | None,
    payload: dict,
) -> str:
    normalized = (supplied or "").strip()
    if normalized:
        return normalized
    return request_hash({"path": request.url.path, "payload": payload})


def _read_limit(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_client_auth)],
) -> None:
    enforce_local_signals_rate_limit(
        request,
        route_key="local-signals-read",
        actor_key=_actor_key(identity),
        limit_per_minute=120,
    )


@router.get("/signals", dependencies=[Depends(_read_limit)])
def list_signals(
    request: Request,
    language: Annotated[LocalSignalLanguage, Query()] = "ko",
    region: Annotated[str | None, Query(min_length=1, max_length=64)] = None,
    place_id: Annotated[str | None, Query(min_length=1, max_length=128)] = None,
    kind: Annotated[LocalSignalKind | None, Query()] = None,
    sort: Annotated[Literal["recent", "useful"], Query()] = "recent",
    limit: Annotated[int, Query(gt=0, le=50)] = 20,
    cursor: Annotated[str | None, Query(max_length=128)] = None,
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    payload = service.list_public(
        language=language,
        region=region,
        place_id=place_id,
        kind=kind,
        limit=limit,
        cursor=cursor,
        sort=sort,
    )
    _record_event(request, "read")
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.get("/signals/{signal_id}", dependencies=[Depends(_read_limit)])
def get_signal(
    request: Request,
    signal_id: UUID,
    language: Annotated[LocalSignalLanguage, Query()] = "ko",
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    payload = service.get_public(signal_id=signal_id, language=language)
    _record_event(request, "read")
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.get("/places/{place_id}/signals", dependencies=[Depends(_read_limit)])
def list_place_signals(
    request: Request,
    place_id: str,
    language: Annotated[LocalSignalLanguage, Query()] = "ko",
    sort: Annotated[Literal["recent", "useful"], Query()] = "recent",
    limit: Annotated[int, Query(gt=0, le=50)] = 20,
    cursor: Annotated[str | None, Query(max_length=128)] = None,
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    payload = service.list_public(
        language=language,
        region=None,
        place_id=place_id,
        kind=None,
        limit=limit,
        cursor=cursor,
        sort=sort,
    )
    _record_event(request, "read")
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.get("/signals/{signal_id}/comments", dependencies=[Depends(_read_limit)])
def list_signal_comments(
    request: Request,
    signal_id: UUID,
    language: Annotated[LocalSignalLanguage, Query()] = "ko",
    limit: Annotated[int, Query(gt=0, le=50)] = 20,
    cursor: Annotated[str | None, Query(max_length=128)] = None,
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    payload = service.list_comments(
        signal_id=signal_id,
        language=language,
        limit=limit,
        cursor=cursor,
    )
    _record_event(request, "read")
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.post("/signals")
def create_signal(
    request: Request,
    body: LocalSignalDraftCreate,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    enforce_local_signals_rate_limit(
        request,
        route_key="local-signals-create",
        actor_key=_actor_key(identity),
        limit_per_minute=10,
    )
    payload = service.create_draft(
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        values=body.model_dump(),
        idempotency_key=_idempotency_key(request, idempotency_key, body.model_dump(mode="json")),
    )
    _record_event(request, "write")
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.patch("/signals/{signal_id}")
def update_signal(
    request: Request,
    signal_id: UUID,
    body: LocalSignalPatch,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    enforce_local_signals_rate_limit(
        request,
        route_key="local-signals-update",
        actor_key=_actor_key(identity),
        limit_per_minute=20,
    )
    values = body.model_dump(exclude_unset=True, exclude_none=True)
    payload = service.update_draft(
        signal_id=signal_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        values=values,
        idempotency_key=_idempotency_key(request, idempotency_key, values),
    )
    _record_event(request, "write")
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.post("/signals/{signal_id}/submit")
def submit_signal(
    request: Request,
    signal_id: UUID,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    enforce_local_signals_rate_limit(
        request,
        route_key="local-signals-submit",
        actor_key=_actor_key(identity),
        limit_per_minute=5,
    )
    payload = service.submit(
        signal_id=signal_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        idempotency_key=_idempotency_key(request, idempotency_key, {"signal_id": str(signal_id)}),
    )
    _record_event(request, "write")
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.delete("/signals/{signal_id}")
def delete_signal(
    request: Request,
    signal_id: UUID,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    enforce_local_signals_rate_limit(
        request,
        route_key="local-signals-delete",
        actor_key=_actor_key(identity),
        limit_per_minute=10,
    )
    payload = service.delete(
        signal_id=signal_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        idempotency_key=_idempotency_key(request, idempotency_key, {"signal_id": str(signal_id)}),
    )
    _record_event(request, "write")
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.put("/signals/{signal_id}/reactions/{reaction_type}")
def add_reaction(
    request: Request,
    signal_id: UUID,
    reaction_type: Literal["useful", "respectful", "needs_confirmation"],
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    enforce_local_signals_rate_limit(
        request,
        route_key="local-signals-reaction-add",
        actor_key=_actor_key(identity),
        limit_per_minute=60,
    )
    payload = service.set_reaction(
        signal_id=signal_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        reaction_type=reaction_type,
        active=True,
    )
    _record_event(request, "write")
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.delete("/signals/{signal_id}/reactions/{reaction_type}")
def remove_reaction(
    request: Request,
    signal_id: UUID,
    reaction_type: Literal["useful", "respectful", "needs_confirmation"],
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    enforce_local_signals_rate_limit(
        request,
        route_key="local-signals-reaction-remove",
        actor_key=_actor_key(identity),
        limit_per_minute=60,
    )
    payload = service.set_reaction(
        signal_id=signal_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        reaction_type=reaction_type,
        active=False,
    )
    _record_event(request, "write")
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.put("/signals/{signal_id}/save")
def save_signal(
    request: Request,
    signal_id: UUID,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    enforce_local_signals_rate_limit(
        request,
        route_key="local-signals-save-add",
        actor_key=_actor_key(identity),
        limit_per_minute=60,
    )
    payload = service.set_save(
        signal_id=signal_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        active=True,
    )
    _record_event(request, "write")
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.delete("/signals/{signal_id}/save")
def unsave_signal(
    request: Request,
    signal_id: UUID,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    enforce_local_signals_rate_limit(
        request,
        route_key="local-signals-save-remove",
        actor_key=_actor_key(identity),
        limit_per_minute=60,
    )
    payload = service.set_save(
        signal_id=signal_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        active=False,
    )
    _record_event(request, "write")
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.post("/signals/{signal_id}/comments")
def create_comment(
    request: Request,
    signal_id: UUID,
    body: LocalSignalCommentCreate,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    enforce_local_signals_rate_limit(
        request,
        route_key="local-signals-comment",
        actor_key=_actor_key(identity),
        limit_per_minute=20,
    )
    payload = service.create_comment(
        signal_id=signal_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        values=body,
        idempotency_key=_idempotency_key(request, idempotency_key, body.model_dump(mode="json")),
    )
    _record_event(request, "write")
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.post("/signals/{signal_id}/reports")
def report_signal(
    request: Request,
    signal_id: UUID,
    body: LocalSignalReportCreate,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    service: Annotated[LocalSignalsService, Depends(get_local_signals_service)] = None,  # type: ignore[assignment]
) -> dict:
    enforce_local_signals_rate_limit(
        request,
        route_key="local-signals-report",
        actor_key=_actor_key(identity),
        limit_per_minute=5,
    )
    payload = service.create_report(
        signal_id=signal_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        body=body,
        idempotency_key=_idempotency_key(request, idempotency_key, body.model_dump(mode="json")),
    )
    _record_event(request, "report")
    return success_envelope(request=request, data=payload, meta={"source": "db"})
