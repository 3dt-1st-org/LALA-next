from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa

OAUTH_ISSUER = "https://login.microsoftonline.com/test-tenant/v2.0"
OAUTH_AUDIENCE = "api://lala-next-dev"
OAUTH_JWKS_URL = "https://login.microsoftonline.com/test-tenant/discovery/v2.0/keys"
OAUTH_CLIENT_ID = "00000000-0000-0000-0000-000000000000"


def test_readyz_reports_oauth_jwt_auth_without_static_credentials(client, monkeypatch):
    _configure_oauth(monkeypatch)

    response = client.get("/readyz")

    assert response.status_code == 200
    checks = response.json()["data"]["checks"]
    assert checks["client_auth"] == "configured"
    assert checks["client_identity"] == "oauth-configured"
    assert checks["jwt_validation"] == "configured"
    assert checks["api_key"] == "skipped"
    assert checks["bearer_token"] == "skipped"


def test_v1_accepts_valid_oauth_jwt_without_static_credentials(client, monkeypatch):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    _configure_oauth(monkeypatch)
    monkeypatch.setattr(
        "apps.api.app.core.jwt_auth._get_signing_key",
        lambda jwks_url, token: key.public_key(),
    )

    token = _signed_token(key, scopes="access_as_user lala.read")
    response = client.get("/api/v1/places", headers={"Authorization": f"Bearer {token}"})

    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_v1_rejects_oauth_jwt_missing_required_scope(client, monkeypatch):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    _configure_oauth(monkeypatch)
    monkeypatch.setattr(
        "apps.api.app.core.jwt_auth._get_signing_key",
        lambda jwks_url, token: key.public_key(),
    )

    token = _signed_token(key, scopes="weather.read")
    response = client.get("/api/v1/places", headers={"Authorization": f"Bearer {token}"})

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


def test_v1_reports_oauth_jwks_unavailable_as_retryable_auth_dependency(client, monkeypatch):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    _configure_oauth(monkeypatch)

    def fail_get_signing_key(jwks_url: str, token: str) -> object:
        raise RuntimeError("jwks unavailable")

    monkeypatch.setattr("apps.api.app.core.jwt_auth._get_signing_key", fail_get_signing_key)

    token = _signed_token(key)
    response = client.get("/api/v1/places", headers={"Authorization": f"Bearer {token}"})

    assert response.status_code == 503
    body = response.json()
    assert body["error"]["code"] == "CLIENT_AUTH_UNAVAILABLE"
    assert body["error"]["retryable"] is True
    assert "jwks unavailable" not in response.text


def test_static_bearer_token_still_works_when_oauth_jwks_is_unavailable(client, monkeypatch):
    _configure_oauth(monkeypatch)
    monkeypatch.setenv("API_BEARER_TOKEN", "static-transition-token")
    monkeypatch.setattr(
        "apps.api.app.core.jwt_auth._get_signing_key",
        lambda jwks_url, token: (_ for _ in ()).throw(RuntimeError("jwks unavailable")),
    )

    response = client.get(
        "/api/v1/places",
        headers={"Authorization": "Bearer static-transition-token"},
    )

    assert response.status_code == 200
    assert response.json()["ok"] is True


def _configure_oauth(monkeypatch) -> None:
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.delenv("API_BEARER_TOKEN", raising=False)
    monkeypatch.setenv("OAUTH_ISSUER", OAUTH_ISSUER)
    monkeypatch.setenv("OAUTH_AUDIENCE", OAUTH_AUDIENCE)
    monkeypatch.setenv("OAUTH_JWKS_URL", OAUTH_JWKS_URL)
    monkeypatch.setenv("OAUTH_CLIENT_ID", OAUTH_CLIENT_ID)
    monkeypatch.setenv("OAUTH_REQUIRED_SCOPES", "access_as_user")


def _signed_token(
    key,
    *,
    issuer: str = OAUTH_ISSUER,
    audience: str = OAUTH_AUDIENCE,
    scopes: str = "access_as_user",
) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "iss": issuer,
            "aud": audience,
            "sub": "test-user",
            "scp": scopes,
            "iat": now,
            "nbf": now - timedelta(seconds=5),
            "exp": now + timedelta(minutes=10),
        },
        key,
        algorithm="RS256",
        headers={"kid": "test-key"},
    )
