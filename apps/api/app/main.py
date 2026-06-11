from __future__ import annotations

from time import perf_counter

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ApiError
from apps.api.app.core.metrics import RuntimeMetrics, route_path_from_scope
from apps.api.app.core.observability import configure_logging, request_log_extra
from apps.api.app.core.responses import error_envelope, ensure_request_id
from apps.api.app.routers.health import router as health_router
from apps.api.app.routers.v1 import router as v1_router


def create_app() -> FastAPI:
    settings = get_settings()
    logger = configure_logging(settings.log_level)
    app = FastAPI(
        title="LALA-next Public API",
        version=settings.app_version,
        description="FastAPI edge for the Flutter-facing LALA-next contract.",
    )
    app.state.metrics = RuntimeMetrics()
    if settings.cors_allow_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=list(settings.cors_allow_origins),
            allow_methods=["GET", "POST", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type", "X-API-Key", "X-Request-ID"],
            expose_headers=["X-Request-ID", "X-Request-Duration-Ms"],
            max_age=600,
        )

    @app.middleware("http")
    async def request_id_middleware(request: Request, call_next):
        request_id = ensure_request_id(request)
        started_at = perf_counter()
        response = await call_next(request)
        duration_ms = round((perf_counter() - started_at) * 1000, 2)
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Request-Duration-Ms"] = f"{duration_ms:.2f}"
        metric_path = route_path_from_scope(request.scope)
        if metric_path != "/metrics":
            app.state.metrics.record_request(
                method=request.method,
                path=metric_path,
                status_code=response.status_code,
                duration_ms=duration_ms,
            )
        client_host = request.client.host if request.client else ""
        logger.info(
            (
                "request_completed request_id=%s method=%s path=%s "
                "status_code=%s duration_ms=%.2f client_host=%s"
            ),
            request_id,
            request.method,
            metric_path,
            response.status_code,
            duration_ms,
            client_host,
            extra=request_log_extra(
                request_id=request_id,
                method=request.method,
                path=metric_path,
                status_code=response.status_code,
                duration_ms=duration_ms,
                client_host=client_host,
            ),
        )
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
