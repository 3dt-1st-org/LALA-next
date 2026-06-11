from __future__ import annotations

import hmac
from typing import Annotated

from fastapi import Header

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ApiError


def require_client_auth(
    x_api_key: Annotated[str | None, Header(alias="X-API-Key")] = None,
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
) -> None:
    settings = get_settings()
    if not settings.ios_api_key and not settings.api_bearer_token:
        raise ApiError(
            status_code=503,
            code="CLIENT_AUTH_NOT_CONFIGURED",
            message="Client authentication is not configured.",
            retryable=False,
        )

    if settings.ios_api_key and x_api_key:
        if hmac.compare_digest(x_api_key.strip(), settings.ios_api_key):
            return

    bearer_token = _parse_bearer_token(authorization)
    if settings.api_bearer_token and bearer_token:
        if hmac.compare_digest(bearer_token, settings.api_bearer_token):
            return

    raise ApiError(
        status_code=401,
        code="UNAUTHORIZED",
        message="Invalid client credentials.",
        retryable=False,
    )


def _parse_bearer_token(authorization: str | None) -> str:
    if not authorization:
        return ""
    scheme, _, token = authorization.strip().partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        return ""
    return token.strip()
