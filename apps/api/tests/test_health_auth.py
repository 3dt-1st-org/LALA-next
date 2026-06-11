from __future__ import annotations


def test_healthz_is_public(client):
    response = client.get("/healthz")

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["status"] == "ok"
    assert body["meta"]["request_id"]


def test_readyz_reports_degraded_without_required_env(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.delenv("DB_DSN", raising=False)

    response = client.get("/readyz")

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["status"] == "degraded"
    assert body["data"]["checks"]["api_key"] == "missing"


def test_readyz_reports_db_degraded_when_probe_fails(client, monkeypatch):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    monkeypatch.setattr(
        "apps.api.app.core.readiness.db_repository.check_db_status",
        lambda dsn: "degraded",
    )

    response = client.get("/readyz")

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["status"] == "degraded"
    assert body["data"]["checks"]["db"] == "degraded"


def test_v1_requires_configured_api_key(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)

    response = client.get("/api/v1/places")

    assert response.status_code == 503
    body = response.json()
    assert body["ok"] is False
    assert body["error"]["code"] == "API_KEY_NOT_CONFIGURED"


def test_v1_rejects_invalid_api_key(client, api_key):
    response = client.get("/api/v1/places", headers={"X-API-Key": "wrong"})

    assert response.status_code == 401
    body = response.json()
    assert body["ok"] is False
    assert body["error"]["code"] == "UNAUTHORIZED"


def test_v1_accepts_valid_api_key(client, auth_headers):
    response = client.get("/api/v1/places", headers=auth_headers)

    assert response.status_code == 200
    assert response.json()["ok"] is True
