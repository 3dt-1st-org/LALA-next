from __future__ import annotations

from functools import lru_cache
from typing import Any

import jwt
from jwt import PyJWKClient, PyJWTError
from jwt.exceptions import PyJWKClientConnectionError, PyJWKClientError

from apps.api.app.core.config import Settings

JWT_ALGORITHMS = ("RS256",)
JWT_LEEWAY_SECONDS = 60
JWKS_FETCH_TIMEOUT_SECONDS = 5


class JwtValidationRejected(Exception):
    """Raised when a presented JWT is structurally valid but not acceptable."""


class JwtValidationUnavailable(Exception):
    """Raised when configured JWT validation cannot access required key material."""


def is_oauth_jwt_validation_configured(settings: Settings) -> bool:
    return bool(
        settings.oauth_issuer
        and settings.oauth_audience
        and settings.oauth_jwks_url
    )


def validate_oauth_jwt(token: str, settings: Settings) -> dict[str, Any]:
    if not is_oauth_jwt_validation_configured(settings):
        raise JwtValidationUnavailable("OAuth JWT validation is not configured.")

    try:
        signing_key = _get_signing_key(settings.oauth_jwks_url, token)
    except PyJWKClientConnectionError as exc:
        raise JwtValidationUnavailable("OAuth signing keys are unavailable.") from exc
    except PyJWKClientError as exc:
        raise JwtValidationRejected("OAuth signing key is not accepted.") from exc
    except Exception as exc:  # pragma: no cover - exact network exceptions vary.
        raise JwtValidationUnavailable("OAuth signing keys are unavailable.") from exc

    try:
        payload = jwt.decode(
            token,
            signing_key,
            algorithms=list(JWT_ALGORITHMS),
            audience=settings.oauth_audience,
            issuer=settings.oauth_issuer,
            leeway=JWT_LEEWAY_SECONDS,
            options={"require": ["exp", "iss", "aud", "sub"]},
        )
    except PyJWTError as exc:
        raise JwtValidationRejected("OAuth JWT validation failed.") from exc

    subject = payload.get("sub")
    if not isinstance(subject, str) or not subject.strip():
        raise JwtValidationRejected("OAuth JWT is missing a valid subject.")

    if not _has_required_scope(payload, settings.oauth_required_scopes):
        raise JwtValidationRejected("OAuth JWT is missing required scope.")

    return payload


def _get_signing_key(jwks_url: str, token: str) -> Any:
    return _jwk_client(jwks_url).get_signing_key_from_jwt(token).key


@lru_cache(maxsize=16)
def _jwk_client(jwks_url: str) -> PyJWKClient:
    return PyJWKClient(
        jwks_url,
        cache_keys=True,
        max_cached_keys=16,
        cache_jwk_set=True,
        lifespan=300,
        timeout=JWKS_FETCH_TIMEOUT_SECONDS,
    )


def _has_required_scope(payload: dict[str, Any], required_scopes: tuple[str, ...]) -> bool:
    token_scopes = set(_token_scopes(payload))
    return all(scope in token_scopes for scope in required_scopes)


def _token_scopes(payload: dict[str, Any]) -> tuple[str, ...]:
    scopes: list[str] = []
    scope = payload.get("scope")
    if isinstance(scope, str):
        scopes.extend(value for value in scope.split() if value)
    scp = payload.get("scp")
    if isinstance(scp, str):
        scopes.extend(scope for scope in scp.split() if scope)
    roles = payload.get("roles")
    if isinstance(roles, list):
        scopes.extend(role for role in roles if isinstance(role, str) and role)
    return tuple(scopes)
