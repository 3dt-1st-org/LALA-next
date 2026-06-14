from __future__ import annotations

import hmac
from hashlib import sha256
from typing import Annotated

from fastapi import Header

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ApiError
from apps.api.app.core.jwt_auth import (
    JwtValidationRejected,
    JwtValidationUnavailable,
    is_oauth_jwt_validation_configured,
    validate_oauth_jwt,
)

MAX_CLIENT_AUTH_VALUE_BYTES = 4096


def require_client_auth(
    x_api_key: Annotated[str | None, Header(alias="X-API-Key")] = None,
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
) -> None:
    settings = get_settings()
    jwt_validation_configured = is_oauth_jwt_validation_configured(settings)
    if not settings.ios_api_key and not settings.api_bearer_token and not jwt_validation_configured:
        raise ApiError(
            status_code=503,
            code="CLIENT_AUTH_NOT_CONFIGURED",
            message="Client authentication is not configured.",
            retryable=False,
        )

    api_key = _normalize_header_value(x_api_key)
    if settings.ios_api_key and api_key:
        if _constant_time_secret_match(api_key, settings.ios_api_key):
            return

    bearer_token = _parse_bearer_token(authorization)
    if settings.api_bearer_token and bearer_token:
        if _constant_time_secret_match(bearer_token, settings.api_bearer_token):
            return

    if jwt_validation_configured and bearer_token:
        try:
            validate_oauth_jwt(bearer_token, settings)
            return
        except JwtValidationRejected:
            pass
        except JwtValidationUnavailable as exc:
            raise ApiError(
                status_code=503,
                code="CLIENT_AUTH_UNAVAILABLE",
                message="Client token validation is temporarily unavailable.",
                retryable=True,
            ) from exc

    raise ApiError(
        status_code=401,
        code="UNAUTHORIZED",
        message="Invalid client credentials.",
        retryable=False,
    )


def _parse_bearer_token(authorization: str | None) -> str:
    value = _normalize_header_value(authorization)
    if not value:
        return ""
    scheme, separator, token = value.partition(" ")
    token = token.strip()
    if scheme.lower() != "bearer" or not separator or not token:
        return ""
    if any(character.isspace() for character in token):
        return ""
    return token


def _normalize_header_value(value: str | None) -> str:
    if not value:
        return ""
    normalized = value.strip()
    if not normalized:
        return ""
    if len(normalized.encode("utf-8")) > MAX_CLIENT_AUTH_VALUE_BYTES:
        return ""
    return normalized


def _constant_time_secret_match(provided: str, expected: str) -> bool:
    if not provided or not expected:
        return False
    provided_digest = sha256(provided.encode("utf-8")).digest()
    expected_digest = sha256(expected.encode("utf-8")).digest()
    return hmac.compare_digest(provided_digest, expected_digest)
