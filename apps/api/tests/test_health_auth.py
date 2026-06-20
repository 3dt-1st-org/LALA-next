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
    monkeypatch.delenv("API_BEARER_TOKEN", raising=False)
    monkeypatch.delenv("OAUTH_ISSUER", raising=False)
    monkeypatch.delenv("OAUTH_AUDIENCE", raising=False)
    monkeypatch.delenv("OAUTH_JWKS_URL", raising=False)
    monkeypatch.delenv("OAUTH_CLIENT_ID", raising=False)
    monkeypatch.delenv("OAUTH_REQUIRED_SCOPES", raising=False)
    monkeypatch.delenv("DB_DSN", raising=False)

    response = client.get("/readyz")

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["status"] == "degraded"
    assert body["data"]["checks"]["client_auth"] == "missing"
    assert body["data"]["checks"]["client_identity"] == "missing"
    assert body["data"]["checks"]["public_data_service_key"] == "skipped"
    assert body["data"]["checks"]["worker_contracts"] == "configured"
    assert body["data"]["mode"] == {
        "overall": "degraded",
        "data": "unavailable",
        "ai": "disabled",
        "speech": "disabled",
        "worker": "dry-run",
    }


def test_metrics_is_public(client):
    response = client.get("/metrics")

    assert response.status_code == 200
    assert "text/plain" in response.headers["content-type"]
    assert "lala_next_process_uptime_seconds" in response.text


def test_readyz_accepts_bearer_token_as_client_auth(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.setenv("API_BEARER_TOKEN", "test-bearer-token")
    monkeypatch.delenv("OAUTH_ISSUER", raising=False)
    monkeypatch.delenv("OAUTH_AUDIENCE", raising=False)
    monkeypatch.delenv("OAUTH_JWKS_URL", raising=False)
    monkeypatch.delenv("OAUTH_CLIENT_ID", raising=False)
    monkeypatch.delenv("OAUTH_REQUIRED_SCOPES", raising=False)
    monkeypatch.delenv("DB_DSN", raising=False)

    response = client.get("/readyz")

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["checks"]["client_auth"] == "configured"
    assert body["data"]["checks"]["client_identity"] == "static"
    assert body["data"]["checks"]["api_key"] == "skipped"
    assert body["data"]["checks"]["bearer_token"] == "configured"
    assert body["data"]["checks"]["public_data_service_key"] == "skipped"


def test_readyz_reports_static_snapshot_fallback(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.delenv("API_BEARER_TOKEN", raising=False)
    monkeypatch.delenv("OAUTH_ISSUER", raising=False)
    monkeypatch.delenv("OAUTH_AUDIENCE", raising=False)
    monkeypatch.delenv("OAUTH_JWKS_URL", raising=False)
    monkeypatch.delenv("OAUTH_CLIENT_ID", raising=False)
    monkeypatch.delenv("OAUTH_REQUIRED_SCOPES", raising=False)
    monkeypatch.setenv("LALA_STATIC_SNAPSHOT_FALLBACK", "true")

    response = client.get("/readyz")

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["status"] == "ok"
    checks = data["checks"]
    assert checks["client_auth"] == "snapshot-fallback"
    assert checks["client_identity"] == "snapshot-fallback"
    assert checks["static_snapshot_fallback"] == "enabled"
    assert checks["public_data_snapshot"] == "configured"
    assert response.json()["data"]["mode"] == {
        "overall": "public-cache",
        "data": "public-cache",
        "ai": "disabled",
        "speech": "disabled",
        "worker": "dry-run",
    }


def test_legacy_public_demo_mode_env_alias_is_ignored(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.delenv("API_BEARER_TOKEN", raising=False)
    monkeypatch.delenv("LALA_STATIC_SNAPSHOT_FALLBACK", raising=False)
    monkeypatch.setenv("LALA_PUBLIC_DEMO_MODE", "true")

    response = client.get("/readyz")

    assert response.status_code == 200
    checks = response.json()["data"]["checks"]
    assert checks["client_auth"] == "missing"
    assert checks["client_identity"] == "missing"
    assert checks["static_snapshot_fallback"] == "disabled"


def test_readyz_reports_public_contest_access(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.delenv("API_BEARER_TOKEN", raising=False)
    monkeypatch.delenv("OAUTH_ISSUER", raising=False)
    monkeypatch.delenv("OAUTH_AUDIENCE", raising=False)
    monkeypatch.delenv("OAUTH_JWKS_URL", raising=False)
    monkeypatch.delenv("OAUTH_CLIENT_ID", raising=False)
    monkeypatch.delenv("OAUTH_REQUIRED_SCOPES", raising=False)
    monkeypatch.delenv("DB_DSN", raising=False)
    monkeypatch.setenv("LALA_PUBLIC_CONTEST_ACCESS", "true")

    response = client.get("/readyz")

    assert response.status_code == 200
    data = response.json()["data"]
    checks = data["checks"]
    assert checks["client_auth"] == "public-contest"
    assert checks["client_identity"] == "public-contest"
    assert checks["public_contest_access"] == "enabled"
    assert checks["static_snapshot_fallback"] == "disabled"
    assert data["status"] == "degraded"
    assert data["mode"]["data"] == "unavailable"


def test_readyz_reports_oauth_identity_rollout_configuration(client, monkeypatch):
    monkeypatch.setenv("API_BEARER_TOKEN", "test-bearer-token")
    monkeypatch.setenv("OAUTH_ISSUER", "https://login.microsoftonline.com/tenant/v2.0")
    monkeypatch.setenv("OAUTH_AUDIENCE", "api://lala-next-dev")
    monkeypatch.setenv("OAUTH_JWKS_URL", "https://login.microsoftonline.com/tenant/discovery/v2.0/keys")
    monkeypatch.setenv("OAUTH_CLIENT_ID", "00000000-0000-0000-0000-000000000000")
    monkeypatch.setenv("OAUTH_REQUIRED_SCOPES", "access_as_user,lala.read")

    response = client.get("/readyz")

    assert response.status_code == 200
    checks = response.json()["data"]["checks"]
    assert checks["client_identity"] == "transition"
    assert checks["oauth_issuer"] == "configured"
    assert checks["oauth_audience"] == "configured"
    assert checks["oauth_jwks_url"] == "configured"
    assert checks["oauth_client_id"] == "configured"
    assert checks["oauth_required_scopes"] == "configured"
    assert checks["jwt_validation"] == "configured"


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
    assert body["data"]["mode"]["data"] == "degraded"
    assert body["data"]["mode"]["overall"] == "degraded"


def test_readyz_reports_db_backed_and_live_azure_runtime_modes(client, monkeypatch):
    monkeypatch.setenv("API_BEARER_TOKEN", "test-bearer-token")
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.setenv("AZURE_OPENAI_ENDPOINT", "https://aoai.example.test")
    monkeypatch.setenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4o-mini")
    monkeypatch.setenv("AZURE_OPENAI_KEY", "test-openai-key")
    monkeypatch.setenv("LALA_ENABLE_LIVE_SPEECH", "true")
    monkeypatch.setenv("AZURE_SPEECH_REGION", "koreacentral")
    monkeypatch.setenv("AZURE_SPEECH_KEY", "test-speech-key")
    monkeypatch.setattr(
        "apps.api.app.core.readiness.db_repository.check_db_status",
        lambda dsn: "configured",
    )

    response = client.get("/readyz")

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["status"] == "ok"
    assert body["data"]["checks"]["db"] == "configured"
    assert body["data"]["checks"]["client_identity"] == "static"
    assert body["data"]["checks"]["live_ai"] == "enabled"
    assert body["data"]["checks"]["live_speech"] == "enabled"
    assert body["data"]["mode"] == {
        "overall": "live-azure",
        "data": "db-backed",
        "ai": "live-azure",
        "speech": "live-azure",
        "worker": "dry-run",
    }


def test_readyz_reports_ok_for_db_backed_runtime_with_disabled_live_options(client, monkeypatch):
    monkeypatch.setenv("API_BEARER_TOKEN", "test-bearer-token")
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    monkeypatch.setattr(
        "apps.api.app.core.readiness.db_repository.check_db_status",
        lambda dsn: "configured",
    )

    response = client.get("/readyz")

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["status"] == "ok"
    assert body["data"]["checks"]["live_ai"] == "disabled"
    assert body["data"]["checks"]["live_speech"] == "disabled"
    assert body["data"]["mode"] == {
        "overall": "db-backed",
        "data": "db-backed",
        "ai": "disabled",
        "speech": "disabled",
        "worker": "dry-run",
    }


def test_readyz_reports_worker_contract_registry_failure(client, monkeypatch):
    def fail_list_worker_jobs():
        raise RuntimeError("worker registry unavailable")

    monkeypatch.setattr(
        "apps.api.app.core.readiness.worker_contracts.list_worker_jobs",
        fail_list_worker_jobs,
    )

    response = client.get("/readyz")

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["status"] == "degraded"
    assert body["data"]["checks"]["worker_contracts"] == "degraded"


def test_v1_requires_configured_client_auth(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.delenv("API_BEARER_TOKEN", raising=False)
    monkeypatch.delenv("OAUTH_ISSUER", raising=False)
    monkeypatch.delenv("OAUTH_AUDIENCE", raising=False)
    monkeypatch.delenv("OAUTH_JWKS_URL", raising=False)
    monkeypatch.delenv("OAUTH_CLIENT_ID", raising=False)
    monkeypatch.delenv("OAUTH_REQUIRED_SCOPES", raising=False)

    response = client.get("/api/v1/places")

    assert response.status_code == 503
    body = response.json()
    assert body["ok"] is False
    assert body["error"]["code"] == "CLIENT_AUTH_NOT_CONFIGURED"


def test_v1_accepts_unauthenticated_static_snapshot_fallback_request(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.delenv("API_BEARER_TOKEN", raising=False)
    monkeypatch.delenv("OAUTH_ISSUER", raising=False)
    monkeypatch.delenv("OAUTH_AUDIENCE", raising=False)
    monkeypatch.delenv("OAUTH_JWKS_URL", raising=False)
    monkeypatch.delenv("OAUTH_CLIENT_ID", raising=False)
    monkeypatch.delenv("OAUTH_REQUIRED_SCOPES", raising=False)
    monkeypatch.setenv("LALA_STATIC_SNAPSHOT_FALLBACK", "true")

    response = client.get("/api/v1/places?lat=37.2636&lng=127.0286&radius_m=50000")

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["source"] == "public_mvp_snapshot"
    assert body["data"]["places"][0]["score"] is None

    response_with_scores = client.get(
        "/api/v1/places?lat=37.2636&lng=127.0286&radius_m=50000&include_scores=true"
    )

    assert response_with_scores.status_code == 200
    body_with_scores = response_with_scores.json()
    assert body_with_scores["data"]["places"][0]["score"]["data_basis"] == "public_mvp_snapshot"


def test_v1_accepts_unauthenticated_public_contest_request(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.delenv("API_BEARER_TOKEN", raising=False)
    monkeypatch.delenv("OAUTH_ISSUER", raising=False)
    monkeypatch.delenv("OAUTH_AUDIENCE", raising=False)
    monkeypatch.delenv("OAUTH_JWKS_URL", raising=False)
    monkeypatch.delenv("OAUTH_CLIENT_ID", raising=False)
    monkeypatch.delenv("OAUTH_REQUIRED_SCOPES", raising=False)
    monkeypatch.setenv("LALA_PUBLIC_CONTEST_ACCESS", "true")

    response = client.get("/api/v1/places?lat=37.2636&lng=127.0286&radius_m=50000")

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True


def test_v1_requires_present_credentials_when_oauth_is_configured(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.delenv("API_BEARER_TOKEN", raising=False)
    monkeypatch.setenv("OAUTH_ISSUER", "https://login.microsoftonline.com/tenant/v2.0")
    monkeypatch.setenv("OAUTH_AUDIENCE", "api://lala-next-dev")
    monkeypatch.setenv("OAUTH_JWKS_URL", "https://login.microsoftonline.com/tenant/discovery/v2.0/keys")
    monkeypatch.setenv("OAUTH_CLIENT_ID", "00000000-0000-0000-0000-000000000000")
    monkeypatch.setenv("OAUTH_REQUIRED_SCOPES", "access_as_user")

    response = client.get("/api/v1/places")

    assert response.status_code == 401
    body = response.json()
    assert body["ok"] is False
    assert body["error"]["code"] == "UNAUTHORIZED"


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


def test_v1_accepts_valid_api_key_with_edge_whitespace(client, api_key):
    response = client.get("/api/v1/places", headers={"X-API-Key": f"  {api_key}  "})

    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_v1_rejects_oversized_api_key_header(client, api_key):
    oversized = "x" * 4097

    response = client.get("/api/v1/places", headers={"X-API-Key": oversized})

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


def test_v1_accepts_valid_bearer_token(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.setenv("API_BEARER_TOKEN", "test-bearer-token")

    response = client.get(
        "/api/v1/places",
        headers={"Authorization": "Bearer test-bearer-token"},
    )

    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_v1_accepts_valid_bearer_token_with_edge_whitespace(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.setenv("API_BEARER_TOKEN", "test-bearer-token")

    response = client.get(
        "/api/v1/places",
        headers={"Authorization": "  Bearer   test-bearer-token  "},
    )

    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_v1_rejects_invalid_bearer_token(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.setenv("API_BEARER_TOKEN", "test-bearer-token")

    response = client.get(
        "/api/v1/places",
        headers={"Authorization": "Bearer wrong-token"},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


def test_v1_rejects_bearer_token_with_internal_whitespace(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.setenv("API_BEARER_TOKEN", "test-bearer-token")

    response = client.get(
        "/api/v1/places",
        headers={"Authorization": "Bearer test bearer token"},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


def test_v1_rejects_oversized_bearer_header(client, monkeypatch):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.setenv("API_BEARER_TOKEN", "test-bearer-token")

    response = client.get(
        "/api/v1/places",
        headers={"Authorization": "Bearer " + ("x" * 4097)},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"
