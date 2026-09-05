from __future__ import annotations

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, Request

from apps.api.app.core.auth import (
    RequestIdentity,
    require_client_auth,
    require_oauth_identity,
)
from apps.api.app.core.rate_limit import enforce_community_write_rate_limit
from apps.api.app.core.responses import success_envelope
from apps.api.app.schemas.community import (
    CommunityCommentCreate,
    CommunityFollowCreate,
    CommunityPostCreate,
    CommunityReportCreate,
)
from apps.api.app.services.community_idempotency import validate_idempotency_key
from apps.api.app.services.community_service import CommunityService, get_community_service

router = APIRouter(
    prefix="/api/v1/community",
    tags=["community"],
    # ``require_client_auth`` runs once per request and is cached, so GET routes
    # can re-inject the same dependency to read the (optional) viewer identity
    # without a second execution. POST routes layer ``require_oauth_identity``
    # on top to enforce an authenticated author.
    dependencies=[Depends(require_client_auth)],
)

# Documented per-actor/per-client write limits (requests per minute). Reads are
# not throttled at this seam. Enforcement runs inside each handler — i.e. only
# after OAuth identity validation, so unauthenticated 401s never consume an
# actor's window and a rejected request never reaches the service/repository.
POST_CREATE_LIMIT_PER_MINUTE = 10
COMMENT_CREATE_LIMIT_PER_MINUTE = 20
LIKE_TOGGLE_LIMIT_PER_MINUTE = 60
FOLLOW_TOGGLE_LIMIT_PER_MINUTE = 30
REPORT_CREATE_LIMIT_PER_MINUTE = 5


def _actor_key(identity: RequestIdentity) -> str:
    if identity.mode == "oauth" and identity.issuer and identity.subject:
        return f"{identity.issuer}:{identity.subject}"
    return "public"


def _viewer_identity(identity: RequestIdentity) -> tuple[str | None, str | None]:
    if identity.mode == "oauth" and identity.issuer and identity.subject:
        return identity.issuer, identity.subject
    return None, None


@router.get("/posts")
def list_posts(
    request: Request,
    limit: Annotated[int, Query(gt=0, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
    identity: Annotated[RequestIdentity, Depends(require_client_auth)] = None,  # type: ignore[assignment]
    service: Annotated[CommunityService, Depends(get_community_service)] = None,  # type: ignore[assignment]
) -> dict:
    viewer_issuer, viewer_subject = _viewer_identity(identity) if identity else (None, None)
    payload = service.list_posts(
        limit=limit,
        offset=offset,
        viewer_issuer=viewer_issuer,
        viewer_subject=viewer_subject,
    )
    return success_envelope(
        request=request,
        data=payload,
        meta={
            "source": "db",
            "limit": limit,
            "offset": offset,
            "total": payload["total"],
        },
    )


@router.post("/posts")
def create_post(
    request: Request,
    body: CommunityPostCreate,
    identity: Annotated[RequestIdentity, Depends(require_oauth_identity)],
    service: Annotated[CommunityService, Depends(get_community_service)],
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> dict:
    """Create a post; durable-idempotent when ``Idempotency-Key`` is present.

    The key is scoped to the verified actor and this endpoint; the same key
    with the same canonical payload replays the stored response (across
    restarts), a different payload with the same key is a deterministic 409.
    """

    key = validate_idempotency_key(idempotency_key)
    enforce_community_write_rate_limit(
        request,
        route_key="community-post-create",
        actor_key=_actor_key(identity),
        limit_per_minute=POST_CREATE_LIMIT_PER_MINUTE,
    )
    payload = service.create_post(
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        title=body.title,
        body=body.body,
        tags=body.tags or [],
        idempotency_key=key,
    )
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.get("/posts/{post_id}")
def get_post(
    request: Request,
    post_id: UUID,
    identity: Annotated[RequestIdentity, Depends(require_client_auth)] = None,  # type: ignore[assignment]
    service: Annotated[CommunityService, Depends(get_community_service)] = None,  # type: ignore[assignment]
) -> dict:
    viewer_issuer, viewer_subject = _viewer_identity(identity) if identity else (None, None)
    payload = service.get_post(
        post_id=post_id,
        viewer_issuer=viewer_issuer,
        viewer_subject=viewer_subject,
    )
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.get("/posts/{post_id}/comments")
def list_comments(
    request: Request,
    post_id: UUID,
    limit: Annotated[int, Query(gt=0, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
    service: Annotated[CommunityService, Depends(get_community_service)] = None,  # type: ignore[assignment]
) -> dict:
    payload = service.list_comments(post_id=post_id, limit=limit, offset=offset)
    return success_envelope(
        request=request,
        data=payload,
        meta={
            "source": "db",
            "limit": limit,
            "offset": offset,
            "total": payload["total"],
        },
    )


@router.post("/posts/{post_id}/comments")
def create_comment(
    request: Request,
    post_id: UUID,
    body: CommunityCommentCreate,
    identity: Annotated[RequestIdentity, Depends(require_oauth_identity)],
    service: Annotated[CommunityService, Depends(get_community_service)],
) -> dict:
    enforce_community_write_rate_limit(
        request,
        route_key="community-comment-create",
        actor_key=_actor_key(identity),
        limit_per_minute=COMMENT_CREATE_LIMIT_PER_MINUTE,
    )
    payload = service.create_comment(
        post_id=post_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        body=body.body,
    )
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.post("/posts/{post_id}/like")
def toggle_like(
    request: Request,
    post_id: UUID,
    identity: Annotated[RequestIdentity, Depends(require_oauth_identity)],
    service: Annotated[CommunityService, Depends(get_community_service)],
) -> dict:
    enforce_community_write_rate_limit(
        request,
        route_key="community-like-toggle",
        actor_key=_actor_key(identity),
        limit_per_minute=LIKE_TOGGLE_LIMIT_PER_MINUTE,
    )
    payload = service.toggle_like(
        post_id=post_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
    )
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.get("/follows")
def list_follows(
    request: Request,
    limit: Annotated[int, Query(gt=0, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
    identity: Annotated[RequestIdentity, Depends(require_oauth_identity)] = None,  # type: ignore[assignment]
    service: Annotated[CommunityService, Depends(get_community_service)] = None,  # type: ignore[assignment]
) -> dict:
    payload = service.list_follows(
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        limit=limit,
        offset=offset,
    )
    return success_envelope(
        request=request,
        data=payload,
        meta={
            "source": "db",
            "limit": limit,
            "offset": offset,
            "total": payload["total"],
        },
    )


@router.post("/follows")
def toggle_follow(
    request: Request,
    body: CommunityFollowCreate,
    identity: Annotated[RequestIdentity, Depends(require_oauth_identity)],
    service: Annotated[CommunityService, Depends(get_community_service)],
) -> dict:
    enforce_community_write_rate_limit(
        request,
        route_key="community-follow-toggle",
        actor_key=_actor_key(identity),
        limit_per_minute=FOLLOW_TOGGLE_LIMIT_PER_MINUTE,
    )
    payload = service.toggle_follow(
        follower_issuer=identity.issuer or "",
        follower_subject=identity.subject or "",
        followee_user_id=body.followee_user_id,
    )
    return success_envelope(request=request, data=payload, meta={"source": "db"})


@router.post("/posts/{post_id}/reports")
def report_post(
    request: Request,
    post_id: UUID,
    body: CommunityReportCreate,
    identity: Annotated[RequestIdentity, Depends(require_oauth_identity)],
    service: Annotated[CommunityService, Depends(get_community_service)],
) -> dict:
    enforce_community_write_rate_limit(
        request,
        route_key="community-report-create",
        actor_key=_actor_key(identity),
        limit_per_minute=REPORT_CREATE_LIMIT_PER_MINUTE,
    )
    payload = service.report_post(
        post_id=post_id,
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        reason_code=body.reason_code,
    )
    return success_envelope(request=request, data=payload, meta={"source": "db"})
