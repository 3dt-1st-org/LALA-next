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
    client = TestClient(create_app())

    response = client.options(
        "/api/v1/places",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "X-API-Key",
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:3000"
    assert "X-API-Key" in response.headers["access-control-allow-headers"]


def test_cors_origin_list_trims_spaces_and_trailing_slashes(monkeypatch):
    monkeypatch.setenv("CORS_ALLOW_ORIGINS", " http://localhost:3000/ ,, https://team.example ")

    settings = Settings.from_env()

    assert settings.cors_allow_origins == ("http://localhost:3000", "https://team.example")
