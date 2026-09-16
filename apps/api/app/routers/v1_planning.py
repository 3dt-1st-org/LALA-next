from __future__ import annotations

from datetime import date
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Query, Request

from apps.api.app.core.auth import RequestIdentity, require_logto_identity
from apps.api.app.core.errors import ServiceError
from apps.api.app.core.responses import success_envelope
from apps.api.app.schemas.planning import (
    SavePlaceRequest,
    SavePlanRequest,
    SaveTripPreferenceOverrideRequest,
    SlotVisitRequest,
)
from apps.api.app.services.planning_repository import (
    PlanningRepository,
    TripPreferenceOverrideRevisionConflict,
    get_planning_repository,
)

router = APIRouter()

# V5-A planning action endpoints. Auth-scoped to the caller via require_logto_identity
# and every repository query is bound to the caller's (issuer, subject), so a user can
# never read or write another user's saves, plans, or visits (A6). Honest empty: a
# missing plan reads as null, missing saves/visits as [] (D9), never a 500.


@router.get("/me/saved-places")
def list_saved_places(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    repository: Annotated[PlanningRepository, Depends(get_planning_repository)],
) -> dict:
    items = repository.list_saved_places(
        issuer=identity.issuer or "", subject=identity.subject or ""
    )
    return success_envelope(request=request, data={"items": items}, meta={"source": "db"})


@router.put("/me/saved-places/{place_id}")
def save_place(
    request: Request,
    place_id: str,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    repository: Annotated[PlanningRepository, Depends(get_planning_repository)],
    body: SavePlaceRequest | None = None,
) -> dict:
    source = (body.source if body else None) or "public_mvp_snapshot"
    result = repository.set_saved_place(
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        place_id=place_id,
        source=source,
        active=True,
    )
    return success_envelope(request=request, data=result, meta={"source": "db"})


@router.delete("/me/saved-places/{place_id}")
def unsave_place(
    request: Request,
    place_id: str,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    repository: Annotated[PlanningRepository, Depends(get_planning_repository)],
) -> dict:
    result = repository.set_saved_place(
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        place_id=place_id,
        source="public_mvp_snapshot",
        active=False,
    )
    return success_envelope(request=request, data=result, meta={"source": "db"})


@router.get("/me/plans")
def list_persisted_plans(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    repository: Annotated[PlanningRepository, Depends(get_planning_repository)],
    before: Annotated[date | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
) -> dict:
    items = repository.list_plans(
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        before=before,
        limit=limit,
    )
    return success_envelope(request=request, data={"items": items}, meta={"source": "db"})


@router.put("/me/plans/{plan_date}")
def save_persisted_plan(
    request: Request,
    plan_date: date,
    body: SavePlanRequest,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    repository: Annotated[PlanningRepository, Depends(get_planning_repository)],
) -> dict:
    result = repository.save_plan(
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        plan_date=plan_date,
        envelope=body.plan,
    )
    return success_envelope(request=request, data=result, meta={"source": "db"})


@router.get("/me/plans/{plan_date}")
def load_persisted_plan(
    request: Request,
    plan_date: date,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    repository: Annotated[PlanningRepository, Depends(get_planning_repository)],
) -> dict:
    # None when absent, corrupt, or version-mismatched: honest null, never a throw (D8/D9).
    result = repository.load_plan(
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        plan_date=plan_date,
    )
    return success_envelope(
        request=request,
        data=result,
        meta={"source": "db" if result is not None else "unavailable"},
    )


@router.delete("/me/plans/{plan_date}")
def delete_persisted_plan(
    request: Request,
    plan_date: date,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    repository: Annotated[PlanningRepository, Depends(get_planning_repository)],
) -> dict:
    result = repository.delete_plan(
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        plan_date=plan_date,
    )
    return success_envelope(request=request, data=result, meta={"source": "db"})


@router.get("/me/plans/{plan_date}/preferences")
def get_trip_preference_override(
    request: Request,
    plan_date: date,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    repository: Annotated[PlanningRepository, Depends(get_planning_repository)],
) -> dict:
    result = repository.get_trip_preference_override(
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        plan_date=plan_date,
    )
    return success_envelope(
        request=request,
        data=result,
        meta={"source": "db" if result is not None else "unavailable"},
    )


@router.put("/me/plans/{plan_date}/preferences")
def put_trip_preference_override(
    request: Request,
    plan_date: date,
    body: SaveTripPreferenceOverrideRequest,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    repository: Annotated[PlanningRepository, Depends(get_planning_repository)],
) -> dict:
    try:
        result = repository.put_trip_preference_override(
            issuer=identity.issuer or "",
            subject=identity.subject or "",
            plan_date=plan_date,
            expected_revision=body.expected_revision,
            payload=body.override.model_dump(mode="json", exclude_none=True),
        )
    except TripPreferenceOverrideRevisionConflict as exc:
        raise ServiceError(
            status_code=409,
            code="TRIP_PREFERENCES_REVISION_CONFLICT",
            message="Trip preferences changed on another device.",
            retryable=False,
        ) from exc
    return success_envelope(request=request, data=result, meta={"source": "db"})


@router.delete("/me/plans/{plan_date}/preferences")
def delete_trip_preference_override(
    request: Request,
    plan_date: date,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    repository: Annotated[PlanningRepository, Depends(get_planning_repository)],
) -> dict:
    result = repository.delete_trip_preference_override(
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        plan_date=plan_date,
    )
    return success_envelope(request=request, data=result, meta={"source": "db"})


@router.get("/me/plans/{plan_date}/visits")
def list_slot_visits(
    request: Request,
    plan_date: date,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    repository: Annotated[PlanningRepository, Depends(get_planning_repository)],
) -> dict:
    items = repository.list_slot_visits(
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        plan_date=plan_date,
    )
    return success_envelope(request=request, data={"items": items}, meta={"source": "db"})


@router.put("/me/plans/{plan_date}/visits/{slot_period}")
def check_in_slot(
    request: Request,
    plan_date: date,
    slot_period: Literal["morning", "lunch", "afternoon", "dinner"],
    body: SlotVisitRequest,
    identity: Annotated[RequestIdentity, Depends(require_logto_identity)],
    repository: Annotated[PlanningRepository, Depends(get_planning_repository)],
) -> dict:
    result = repository.set_slot_visit(
        issuer=identity.issuer or "",
        subject=identity.subject or "",
        plan_date=plan_date,
        slot_period=slot_period,
        place_id=body.place_id,
        status=body.status,
        reason_code=body.reason_code,
        use_for_recommendations=body.use_for_recommendations,
    )
    return success_envelope(request=request, data=result, meta={"source": "db"})
