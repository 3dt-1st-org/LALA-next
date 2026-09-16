from __future__ import annotations

from fastapi import APIRouter, Depends

from apps.api.app.core.auth import require_client_auth
from apps.api.app.routers import session, v1_planning, v1_public

router = APIRouter(
    prefix="/api/v1",
    tags=["v1"],
    dependencies=[Depends(require_client_auth)],
)

router.include_router(session.router)
router.include_router(v1_public.router)
router.include_router(v1_planning.router)
