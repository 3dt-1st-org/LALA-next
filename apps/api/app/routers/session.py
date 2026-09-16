from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Request, Response

from apps.api.app.core.account_context import CurrentAccountContext
from apps.api.app.core.auth import (
    RequestIdentity,
    require_current_account_context,
    require_logto_identity,
)
from apps.api.app.core.responses import success_envelope
from apps.api.app.schemas.account import AccountDeletionRequest
from apps.api.app.schemas.preferences import SaveTravelPreferencesRequest
from apps.api.app.services.identity_service import IdentityService, get_identity_service
from apps.api.app.services.logto_management import (
    LogtoManagementClient,
    get_logto_management_client,
)
from apps.api.app.services.travel_preferences_service import (
    TravelPreferencesService,
    get_travel_preferences_service,
)

router = APIRouter()


@router.get(
    "/me",
    description=(
        "Returns the local account for an OAuth identity issued by the current configured "
        "LOGTO_ENDPOINT. Legacy OAUTH issuers are not accepted."
    ),
)
def me(
    request: Request,
    account: Annotated[CurrentAccountContext, Depends(require_current_account_context)],
) -> dict:
    user = account.user
    return success_envelope(
        request=request,
        data={
            "user_id": str(user.id),
            "created_at": user.created_at.isoformat(),
            "authenticated": True,
        },
    )


@router.get(
    "/me/preferences",
    description=(
        "Returns the caller's LALA-owned travel preferences. Logto claims never store "
        "preference or dietary-constraint data."
    ),
)
def get_travel_preferences(
    request: Request,
    account: Annotated[CurrentAccountContext, Depends(require_current_account_context)],
    preferences_service: Annotated[
        TravelPreferencesService,
        Depends(get_travel_preferences_service),
    ],
) -> dict:
    record = preferences_service.get(issuer=account.issuer, subject=account.subject)
    data = None
    if record is not None:
        data = {
            "preferences": record.preferences,
            "revision": record.revision,
            "updated_at": record.updated_at.isoformat(),
        }
    return success_envelope(
        request=request,
        data=data,
        meta={"source": "db" if record is not None else "unavailable"},
    )


@router.put(
    "/me/preferences",
    description=(
        "Creates or replaces the caller's validated travel preferences using an "
        "optimistic revision guard."
    ),
)
def put_travel_preferences(
    body: SaveTravelPreferencesRequest,
    request: Request,
    account: Annotated[CurrentAccountContext, Depends(require_current_account_context)],
    preferences_service: Annotated[
        TravelPreferencesService,
        Depends(get_travel_preferences_service),
    ],
) -> dict:
    record = preferences_service.put(
        issuer=account.issuer,
        subject=account.subject,
        expected_revision=body.expected_revision,
        preferences=body.preferences.model_dump(mode="json"),
    )
    return success_envelope(
        request=request,
        data={
            "preferences": record.preferences,
            "revision": record.revision,
            "updated_at": record.updated_at.isoformat(),
        },
        meta={"source": "db"},
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
        identity_service.delete_account(issuer, subject, management_client)
    except Exception:
        request.app.state.metrics.record_auth_event("account_deletion_failure")
        raise
    return Response(status_code=204)
