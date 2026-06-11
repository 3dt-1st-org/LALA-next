from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ApiError
from apps.api.app.core.responses import error_envelope, ensure_request_id
from apps.api.app.routers.health import router as health_router
from apps.api.app.routers.v1 import router as v1_router


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="LALA-next Public API",
        version=settings.app_version,
        description="FastAPI edge for the Flutter-facing LALA-next contract.",
    )
    if settings.cors_allow_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=list(settings.cors_allow_origins),
            allow_methods=["GET", "POST", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type", "X-API-Key", "X-Request-ID"],
            expose_headers=["X-Request-ID"],
            max_age=600,
        )

    @app.middleware("http")
    async def request_id_middleware(request: Request, call_next):
        ensure_request_id(request)
        response = await call_next(request)
        response.headers["X-Request-ID"] = request.state.request_id
        return response

    @app.exception_handler(ApiError)
    async def api_error_handler(request: Request, exc: ApiError):
        return JSONResponse(
            status_code=exc.status_code,
            content=error_envelope(
                request=request,
                code=exc.code,
                message=exc.message,
                retryable=exc.retryable,
            ),
        )

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(request: Request, exc: RequestValidationError):
        return JSONResponse(
            status_code=422,
            content=error_envelope(
                request=request,
                code="VALIDATION_ERROR",
                message="Request validation failed.",
                retryable=False,
                details=exc.errors(),
            ),
        )

    app.include_router(health_router)
    app.include_router(v1_router)
    return app


app = create_app()
