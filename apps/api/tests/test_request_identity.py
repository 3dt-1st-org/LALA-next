from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from apps.api.app.core.auth import (
    RequestIdentity,
    require_client_auth,
    require_logto_identity,
)
from apps.api.app.core.config import Settings
from apps.api.app.core.errors import ApiError
from apps.api.app.core.jwt_auth import is_oauth_jwt_validation_configured

LOGTO_ENDPOINT = "https://lala-test.logto.app"
LOGTO_ISSUER = f"{LOGTO_ENDPOINT}/oidc"
LOGTO_JWKS_URL = f"{LOGTO_ISSUER}/jwks"
LOGTO_API_AUDIENCE = "https://api.lala-next.example"


def test_logto_settings_are_canonical_and_derive_jwt_validation_values(monkeypatch):
    monkeypatch.setenv("LOGTO_ENDPOINT", LOGTO_ENDPOINT)
    monkeypatch.setenv("LOGTO_API_AUDIENCE", LOGTO_API_AUDIENCE)
    monkeypatch.setenv("OAUTH_ISSUER", "https://legacy.example/issuer")
    monkeypatch.setenv("OAUTH_AUDIENCE", "legacy-audience")
    monkeypatch.setenv("OAUTH_JWKS_URL", "https://legacy.example/jwks")

    settings = Settings.from_env()

    assert settings.logto_endpoint == LOGTO_ENDPOINT
    assert settings.logto_api_audience == LOGTO_API_AUDIENCE
    assert settings.oauth_issuer == LOGTO_ISSUER
    assert settings.oauth_audience == LOGTO_API_AUDIENCE
    assert settings.oauth_jwks_url == LOGTO_JWKS_URL
    assert is_oauth_jwt_validation_configured(settings) is True


def test_unsafe_logto_endpoint_preserves_legacy_oauth_validation_settings(monkeypatch):
    monkeypatch.setenv("LOGTO_ENDPOINT", "http://unsafe-logto.example")
    monkeypatch.setenv("LOGTO_API_AUDIENCE", LOGTO_API_AUDIENCE)
    monkeypatch.setenv("OAUTH_ISSUER", "https://legacy.example/issuer")
    monkeypatch.setenv("OAUTH_AUDIENCE", "legacy-audience")
    monkeypatch.setenv("OAUTH_JWKS_URL", "https://legacy.example/jwks")

    settings = Settings.from_env()

    assert settings.oauth_issuer == "https://legacy.example/issuer"
    assert settings.oauth_audience == "legacy-audience"
    assert settings.oauth_jwks_url == "https://legacy.example/jwks"


def test_missing_logto_audience_preserves_legacy_oauth_validation_settings(monkeypatch):
    monkeypatch.setenv("LOGTO_ENDPOINT", LOGTO_ENDPOINT)
    monkeypatch.delenv("LOGTO_API_AUDIENCE", raising=False)
    monkeypatch.setenv("OAUTH_ISSUER", "https://legacy.example/issuer")
    monkeypatch.setenv("OAUTH_AUDIENCE", "legacy-audience")
    monkeypatch.setenv("OAUTH_JWKS_URL", "https://legacy.example/jwks")

    settings = Settings.from_env()

    assert settings.oauth_issuer == "https://legacy.example/issuer"
    assert settings.oauth_audience == "legacy-audience"
    assert settings.oauth_jwks_url == "https://legacy.example/jwks"


@pytest.mark.parametrize(
    ("method", "path", "payload"),
    (
        ("get", "/api/v1/places?lat=37.2&lng=127.0", None),
        ("get", "/api/v1/weather?lat=37.2&lng=127.0", None),
        (
            "post",
            "/api/v1/docents/script",
            {
                "place_id": "guest-place",
                "place_name": "Guest Place",
                "category": "attraction",
            },
        ),
        (
            "post",
            "/api/v1/plans/daily",
            {"lat": 37.2, "lng": 127.0},
        ),
    ),
)
def test_guest_access_keeps_existing_tourism_routes_available(
    client,
    monkeypatch,
    method,
    path,
    payload,
):
    monkeypatch.setenv("LALA_GUEST_ACCESS", "true")

    response = client.request(method, path, json=payload)

    assert response.status_code == 200
    assert response.json()["ok"] is True


@pytest.mark.parametrize(
    "headers",
    (
        {"Authorization": "Token malformed"},
        {"Authorization": "Bearer malformed token"},
        {"X-API-Key": "wrong"},
    ),
)
def test_guest_access_rejects_each_presented_invalid_credential(client, monkeypatch, headers):
    monkeypatch.setenv("LALA_GUEST_ACCESS", "true")

    response = client.get("/api/v1/places?lat=37.2&lng=127.0", headers=headers)

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


def test_guest_access_rejects_malformed_bearer_when_api_key_is_valid(client, monkeypatch):
    monkeypatch.setenv("LALA_GUEST_ACCESS", "true")
    monkeypatch.setenv("IOS_API_KEY", "static-transition-key")

    response = client.get(
        "/api/v1/places?lat=37.2&lng=127.0",
        headers={
            "Authorization": "Token malformed",
            "X-API-Key": "static-transition-key",
        },
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


def test_static_transition_credentials_return_static_request_identity(monkeypatch):
    monkeypatch.setenv("IOS_API_KEY", "static-transition-key")

    identity = require_client_auth(x_api_key="static-transition-key")

    assert identity.mode == "static"
    assert identity.issuer is None
    assert identity.subject is None


def test_oauth_identity_returns_validated_issuer_and_subject(monkeypatch):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    _configure_logto(monkeypatch)
    monkeypatch.setattr(
        "apps.api.app.core.jwt_auth._get_signing_key",
        lambda jwks_url, token: key.public_key(),
    )

    identity = require_client_auth(authorization=f"Bearer {_signed_token(key)}")

    assert identity.mode == "oauth"
    assert identity.issuer == LOGTO_ISSUER
    assert identity.subject == "logto-user-subject"


def test_logto_identity_requires_current_canonical_endpoint_issuer() -> None:
    settings = Settings(
        logto_endpoint=f"{LOGTO_ENDPOINT}/",
        logto_api_audience=LOGTO_API_AUDIENCE,
    )

    identity = require_logto_identity(
        identity=RequestIdentity(
            mode="oauth",
            issuer=LOGTO_ISSUER,
            subject="logto-user-subject",
        ),
        settings=settings,
    )

    assert identity.issuer == LOGTO_ISSUER


@pytest.mark.parametrize(
    "settings",
    (
        Settings(
            logto_endpoint=LOGTO_ENDPOINT,
            logto_api_audience=LOGTO_API_AUDIENCE,
        ),
        Settings(logto_endpoint=LOGTO_ENDPOINT),
        Settings(logto_api_audience=LOGTO_API_AUDIENCE),
    ),
)
def test_logto_identity_rejects_legacy_or_incomplete_configuration(settings) -> None:
    with pytest.raises(ApiError) as exc_info:
        require_logto_identity(
            identity=RequestIdentity(
                mode="oauth",
                issuer="https://legacy.example/oidc",
                subject="legacy-subject",
            ),
            settings=settings,
        )

    assert exc_info.value.status_code == 401
    assert exc_info.value.code == "USER_AUTH_REQUIRED"
    assert "legacy" not in str(exc_info.value)


def test_oauth_validation_does_not_require_scopes_when_none_are_configured(client, monkeypatch):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    _configure_logto(monkeypatch)
    monkeypatch.delenv("OAUTH_REQUIRED_SCOPES", raising=False)
    monkeypatch.setattr(
        "apps.api.app.core.jwt_auth._get_signing_key",
        lambda jwks_url, token: key.public_key(),
    )

    response = client.get(
        "/api/v1/places?lat=37.2&lng=127.0",
        headers={"Authorization": f"Bearer {_signed_token(key, scope='')}"},
    )

    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_oauth_scope_claim_is_enforced_when_configured(client, monkeypatch):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    _configure_logto(monkeypatch)
    monkeypatch.setenv("OAUTH_REQUIRED_SCOPES", "lala.read")
    monkeypatch.setattr(
        "apps.api.app.core.jwt_auth._get_signing_key",
        lambda jwks_url, token: key.public_key(),
    )

    response = client.get(
        "/api/v1/places?lat=37.2&lng=127.0",
        headers={"Authorization": f"Bearer {_signed_token(key, scope='lala.read')}"},
    )

    assert response.status_code == 200
    assert response.json()["ok"] is True


def _configure_logto(monkeypatch) -> None:
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.delenv("API_BEARER_TOKEN", raising=False)
    monkeypatch.setenv("LOGTO_ENDPOINT", LOGTO_ENDPOINT)
    monkeypatch.setenv("LOGTO_API_AUDIENCE", LOGTO_API_AUDIENCE)


def _signed_token(key, *, scope: str = "") -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "iss": LOGTO_ISSUER,
            "aud": LOGTO_API_AUDIENCE,
            "sub": "logto-user-subject",
            "scope": scope,
            "iat": now,
            "nbf": now - timedelta(seconds=5),
            "exp": now + timedelta(minutes=10),
        },
        key,
        algorithm="RS256",
        headers={"kid": "test-key"},
    )
