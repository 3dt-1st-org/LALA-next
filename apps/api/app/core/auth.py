from __future__ import annotations

import hmac
from dataclasses import dataclass
from hashlib import sha256
from typing import Annotated, Literal

from fastapi import Depends, Header, Request

from apps.api.app.core.config import Settings, get_settings
from apps.api.app.core.errors import ApiError
from apps.api.app.core.jwt_auth import (
    JwtValidationRejected,
    JwtValidationUnavailable,
    is_oauth_jwt_validation_configured,
    validate_oauth_jwt,
)

MAX_CLIENT_AUTH_VALUE_BYTES = 4096


@dataclass(frozen=True)
class RequestIdentity:
    mode: Literal["public", "static", "oauth"]
    issuer: str | None = None
    subject: str | None = None


def require_client_auth(
    x_api_key: Annotated[str | None, Header(alias="X-API-Key")] = None,
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
    request: Request = None,
) -> RequestIdentity:
    settings = get_settings()
    jwt_validation_configured = is_oauth_jwt_validation_configured(settings)
    api_key = _normalize_header_value(x_api_key)
    authorization_value = _normalize_header_value(authorization)
    identity: RequestIdentity | None = None

    if x_api_key is not None:
        if not api_key or not settings.ios_api_key:
            raise _unauthorized()
        if not _constant_time_secret_match(api_key, settings.ios_api_key):
            raise _unauthorized()
        identity = RequestIdentity(mode="static")

    if authorization is not None:
        bearer_token = _parse_bearer_token(authorization_value)
        if not bearer_token:
            raise _unauthorized()
        if settings.api_bearer_token and _constant_time_secret_match(
            bearer_token,
            settings.api_bearer_token,
        ):
            identity = RequestIdentity(mode="static")
        elif jwt_validation_configured:
            identity = _oauth_identity(bearer_token, settings, request=request)
        else:
            raise _unauthorized()

    if identity is not None:
        return identity

    if settings.guest_access_enabled or settings.static_snapshot_fallback:
        return RequestIdentity(mode="public")

    if not settings.ios_api_key and not settings.api_bearer_token and not jwt_validation_configured:
        raise ApiError(
            status_code=503,
            code="CLIENT_AUTH_NOT_CONFIGURED",
            message="Client authentication is not configured.",
            retryable=False,
        )
    raise _unauthorized()


def _oauth_identity(
    token: str,
    settings: Settings,
    *,
    request: Request | None = None,
) -> RequestIdentity:
    try:
        payload = validate_oauth_jwt(token, settings)
    except JwtValidationRejected as exc:
        _record_auth_event(request, "jwt_rejection")
        raise _unauthorized() from exc
    except JwtValidationUnavailable as exc:
        raise ApiError(
            status_code=503,
            code="CLIENT_AUTH_UNAVAILABLE",
            message="Client token validation is temporarily unavailable.",
            retryable=True,
        ) from exc

    issuer = payload.get("iss")
    subject = payload.get("sub")
    if not isinstance(issuer, str) or not isinstance(subject, str):
        _record_auth_event(request, "jwt_rejection")
        raise _unauthorized()
    _record_auth_event(request, "oauth_success")
    return RequestIdentity(mode="oauth", issuer=issuer, subject=subject)


def _record_auth_event(request: Request | None, name: str) -> None:
    if request is None:
        return
    metrics = getattr(request.app.state, "metrics", None)
    if metrics is not None:
        metrics.record_auth_event(name)


def require_oauth_identity(
    identity: Annotated[RequestIdentity, Depends(require_client_auth)],
) -> RequestIdentity:
    if identity.mode == "oauth" and identity.issuer and identity.subject:
        return identity
    raise ApiError(
        status_code=401,
        code="USER_AUTH_REQUIRED",
        message="OAuth user authentication is required.",
        retryable=False,
    )


def _unauthorized() -> ApiError:
    return ApiError(
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
