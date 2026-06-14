from __future__ import annotations

from fastapi.testclient import TestClient

from apps.api.app.core.config import Settings
from apps.api.app.main import create_app


def test_cors_is_disabled_by_default(client):
    response = client.options(
        "/api/v1/places",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "X-API-Key",
        },
    )

    assert "access-control-allow-origin" not in response.headers


def test_cors_allows_configured_flutter_web_origin(monkeypatch):
    monkeypatch.setenv("CORS_ALLOW_ORIGINS", "http://localhost:3000, http://127.0.0.1:3000/")
    monkeypatch.setenv("IOS_API_KEY", "cors-test-key")
    client = TestClient(create_app())

    preflight = client.options(
        "/api/v1/places",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "Authorization, X-API-Key",
        },
    )

    response = client.get(
        "/api/v1/places",
        headers={
            "Origin": "http://localhost:3000",
            "X-API-Key": "cors-test-key",
        },
    )

    assert preflight.status_code == 200
    assert preflight.headers["access-control-allow-origin"] == "http://localhost:3000"
    assert "Authorization" in preflight.headers["access-control-allow-headers"]
    assert "X-API-Key" in preflight.headers["access-control-allow-headers"]
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:3000"
    assert "X-Request-ID" in response.headers["access-control-expose-headers"]
    assert "X-Request-Duration-Ms" in response.headers["access-control-expose-headers"]


def test_cors_origin_list_trims_spaces_and_trailing_slashes(monkeypatch):
    monkeypatch.setenv("CORS_ALLOW_ORIGINS", " http://localhost:3000/ ,, https://team.example ")

    settings = Settings.from_env()

    assert settings.cors_allow_origins == ("http://localhost:3000", "https://team.example")


def test_cors_origin_list_can_load_from_lala_key_vault(monkeypatch):
    monkeypatch.delenv("CORS_ALLOW_ORIGINS", raising=False)
    monkeypatch.setenv("KEY_VAULT_URL", "https://lala-next-kv-27db5e.vault.azure.net/")

    def fake_secret(key_vault_url: str, secret_name: str) -> str:
        if secret_name == "cors-allow-origins":
            return " https://web.example/ , http://localhost:3000 "
        return ""

    monkeypatch.setattr("apps.api.app.core.config.get_secret_if_configured", fake_secret)

    settings = Settings.from_env()

    assert settings.cors_allow_origins == ("https://web.example", "http://localhost:3000")
