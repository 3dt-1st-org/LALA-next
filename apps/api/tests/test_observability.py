from __future__ import annotations

import json
import logging
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from apps.api.app.core.auth import RequestIdentity, require_logto_identity
from apps.api.app.core.errors import ServiceError
from apps.api.app.core.jwt_auth import JwtValidationRejected, JwtValidationUnavailable
from apps.api.app.main import create_app
from apps.api.app.services.identity_service import get_identity_service
from apps.api.app.services.logto_management import (
    LogtoManagementUnavailable,
    get_logto_management_client,
)


def test_request_duration_header_is_returned(client):
    response = client.get("/healthz")

    assert response.status_code == 200
    assert response.headers["X-Request-ID"]
    assert float(response.headers["X-Request-Duration-Ms"]) >= 0


def test_request_logging_omits_auth_headers_and_query_string(
    client,
    auth_headers,
    caplog,
    monkeypatch,
):
    caplog.set_level(logging.INFO, logger="lala_next.api")
    monkeypatch.setenv("API_BEARER_TOKEN", "should-not-be-logged")

    response = client.get(
        "/api/v1/places?lat=37.2&lng=127.0&token=should-not-be-logged",
        headers={
            **auth_headers,
            "Authorization": "Bearer should-not-be-logged",
            "X-Request-ID": "request-log-test",
        },
    )

    assert response.status_code == 200
    records = [
        record
        for record in caplog.records
        if record.name == "lala_next.api" and record.getMessage().startswith("request_completed")
    ]
    assert records
    record = records[-1]
    assert record.request_id == "request-log-test"
    assert record.method == "GET"
    assert record.path == "/api/v1/places"
    assert record.status_code == 200
    assert record.duration_ms >= 0
    rendered = " ".join(record.getMessage() for record in records)
    assert "request_id=request-log-test" in rendered
    assert "method=GET" in rendered
    assert "path=/api/v1/places" in rendered
    assert "status_code=200" in rendered
    assert "should-not-be-logged" not in rendered


def test_optional_jsonl_access_log_is_secret_safe(tmp_path, monkeypatch, api_key):
    access_log_path = tmp_path / "runtime" / "api-access.jsonl"
    monkeypatch.setenv("LALA_ACCESS_LOG_PATH", str(access_log_path))
    client = TestClient(create_app())

    response = client.get(
        "/api/v1/places?lat=37.2&lng=127.0&token=should-not-be-written",
        headers={
            "X-API-Key": api_key,
            "X-Request-ID": "jsonl-log-test",
        },
    )

    assert response.status_code == 200
    lines = access_log_path.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 1
    payload = json.loads(lines[0])
    assert payload["request_id"] == "jsonl-log-test"
    assert payload["method"] == "GET"
    assert payload["path"] == "/api/v1/places"
    assert payload["status_code"] == 200
    assert payload["duration_ms"] >= 0
    assert payload["client_host"]
    assert "should-not-be-written" not in lines[0]
    assert api_key not in lines[0]
    assert "X-API-Key" not in lines[0]
    assert "Authorization" not in lines[0]


def test_unsafe_request_id_header_is_not_logged_or_echoed(client, caplog):
    caplog.set_level(logging.INFO, logger="lala_next.api")
    marker = "super-secret request id"

    response = client.get("/healthz", headers={"X-Request-ID": marker})

    assert response.status_code == 200
    assert response.headers["X-Request-ID"] != marker
    UUID(response.headers["X-Request-ID"])
    body = response.json()
    assert body["meta"]["request_id"] == response.headers["X-Request-ID"]
    assert marker not in response.text

    rendered = " ".join(
        record.getMessage()
        for record in caplog.records
        if record.name == "lala_next.api" and record.getMessage().startswith("request_completed")
    )
    assert marker not in rendered
    assert response.headers["X-Request-ID"] in rendered


def test_metrics_endpoint_is_public_and_omits_query_and_auth_values(
    client,
    auth_headers,
    monkeypatch,
):
    marker = "should-not-be-exported"
    monkeypatch.setenv("API_BEARER_TOKEN", marker)
    response = client.get(
        f"/api/v1/places?lat=37.2&lng=127.0&token={marker}",
        headers={
            **auth_headers,
            "Authorization": f"Bearer {marker}",
            "X-Request-ID": "metrics-test",
        },
    )
    assert response.status_code == 200

    metrics = client.get(f"/metrics?token={marker}")

    assert metrics.status_code == 200
    assert metrics.headers["content-type"].startswith("text/plain")
    body = metrics.text
    assert "lala_next_process_uptime_seconds" in body
    assert "lala_next_http_requests_total" in body
    assert "lala_next_readiness_status" in body
    assert "lala_next_dependency_ready" in body
    assert "lala_next_runtime_mode" in body
    assert 'lala_next_dependency_ready{name="client_auth",status="configured"} 1' in body
    assert 'lala_next_dependency_ready{name="worker_contracts",status="configured"} 1' in body
    assert 'lala_next_runtime_mode{component="overall",mode="degraded"} 1' in body
    assert 'method="GET",path="/api/v1/places",status_code="200",status_class="2xx"' in body
    assert 'path="/metrics"' not in body
    assert marker not in body
    assert "Authorization" not in body
    assert "X-API-Key" not in body

    second_metrics = client.get("/metrics")
    assert 'path="/metrics"' not in second_metrics.text


def test_metrics_records_status_classes_for_errors(client, api_key):
    response = client.get("/api/v1/places", headers={"X-API-Key": "wrong"})
    assert response.status_code == 401

    metrics = client.get("/metrics")

    assert 'method="GET",path="/api/v1/places",status_code="401",status_class="4xx"' in metrics.text


def test_unmatched_paths_are_collapsed_in_logs_and_metrics(client, caplog):
    caplog.set_level(logging.INFO, logger="lala_next.api")

    response = client.get("/missing/should-not-be-path-label?token=should-not-be-exported")
    assert response.status_code == 404

    metrics = client.get("/metrics")
    assert 'path="__unmatched__",status_code="404",status_class="4xx"' in metrics.text
    assert "should-not-be-path-label" not in metrics.text
    assert "should-not-be-exported" not in metrics.text

    rendered = " ".join(
        record.getMessage()
        for record in caplog.records
        if record.name == "lala_next.api" and record.getMessage().startswith("request_completed")
    )
    assert "path=__unmatched__" in rendered
    assert "should-not-be-path-label" not in rendered
    assert "should-not-be-exported" not in rendered


def test_static_operational_paths_are_not_collapsed_to_unmatched(client):
    response = client.get("/openapi.json")
    assert response.status_code == 200

    metrics = client.get("/metrics")

    assert 'method="GET",path="/openapi.json",status_code="200",status_class="2xx"' in metrics.text
    assert 'path="__unmatched__",status_code="200"' not in metrics.text


def test_metrics_exports_readiness_gauges(client, monkeypatch):
    monkeypatch.setattr(
        "apps.api.app.routers.health.build_readiness",
        lambda: {
            "status": "ok",
            "checks": {
                "api_key": "configured",
                "db": "degraded",
                "live_ai": "disabled",
                "live_speech": "enabled",
            },
            "mode": {
                "overall": "degraded",
                "data": "degraded",
                "ai": "disabled",
                "speech": "live-azure",
            },
        },
    )

    metrics = client.get("/metrics")

    assert metrics.status_code == 200
    assert 'lala_next_readiness_status{status="ok"} 1' in metrics.text
    assert 'lala_next_dependency_ready{name="api_key",status="configured"} 1' in metrics.text
    assert 'lala_next_dependency_ready{name="db",status="degraded"} 0' in metrics.text
    assert 'lala_next_dependency_ready{name="live_ai",status="disabled"} 0' in metrics.text
    assert 'lala_next_dependency_ready{name="live_speech",status="enabled"} 1' in metrics.text
    assert 'lala_next_runtime_mode{component="data",mode="degraded"} 1' in metrics.text
    assert 'lala_next_runtime_mode{component="overall",mode="degraded"} 1' in metrics.text
    assert 'lala_next_runtime_mode{component="speech",mode="live-azure"} 1' in metrics.text


def test_metrics_treats_guest_identity_as_ready(client, monkeypatch):
    monkeypatch.setenv("LALA_GUEST_ACCESS", "true")

    body = client.get("/metrics").text

    assert 'lala_next_dependency_ready{name="client_identity",status="guest"} 1' in body


def test_metrics_exports_safe_aggregate_oauth_success_and_jwt_rejection(client, monkeypatch):
    monkeypatch.setenv("OAUTH_ISSUER", "https://issuer.test/oidc")
    monkeypatch.setenv("OAUTH_AUDIENCE", "https://api.test")
    monkeypatch.setenv("OAUTH_JWKS_URL", "https://issuer.test/oidc/jwks")
    raw_token = "raw-token-marker"
    raw_subject = "raw-subject-marker"
    monkeypatch.setattr(
        "apps.api.app.core.auth.validate_oauth_jwt",
        lambda token, settings: {
            "iss": "https://issuer.test/oidc",
            "sub": raw_subject,
        },
    )

    accepted = client.get(
        "/api/v1/places?lat=37.2&lng=127.0",
        headers={"Authorization": f"Bearer {raw_token}"},
    )
    assert accepted.status_code == 200

    def reject_token(token, settings):
        raise JwtValidationRejected()

    monkeypatch.setattr("apps.api.app.core.auth.validate_oauth_jwt", reject_token)
    rejected = client.get(
        "/api/v1/places?lat=37.2&lng=127.0",
        headers={"Authorization": f"Bearer {raw_token}"},
    )
    assert rejected.status_code == 401

    body = client.get("/metrics").text
    assert "lala_next_auth_oauth_success_total 1" in body
    assert "lala_next_auth_jwt_rejection_total 1" in body
    assert raw_token not in body
    assert raw_subject not in body
    assert "issuer.test" not in body


def test_metrics_counts_account_deletion_service_failures_without_identity_labels(
    client,
    monkeypatch,
):
    raw_subject = "deletion-subject-marker"
    monkeypatch.setenv("LALA_GUEST_ACCESS", "true")

    class IdentityService:
        def mark_user_deleting(self, issuer, subject):
            return None

    class FailingManagementClient:
        def delete_user(self, subject):
            raise LogtoManagementUnavailable()

    client.app.dependency_overrides[require_logto_identity] = lambda: RequestIdentity(
        mode="oauth",
        issuer="https://issuer.test/oidc",
        subject=raw_subject,
    )
    client.app.dependency_overrides[get_identity_service] = IdentityService
    client.app.dependency_overrides[get_logto_management_client] = FailingManagementClient

    response = client.request(
        "DELETE",
        "/api/v1/me",
        json={"confirmation": "delete-my-account"},
    )

    assert response.status_code == 503
    body = client.get("/metrics").text
    assert "lala_next_account_deletion_failure_total 1" in body
    assert raw_subject not in body


def test_metrics_does_not_count_jwks_failure_before_deletion_starts(client, monkeypatch):
    monkeypatch.setenv("OAUTH_ISSUER", "https://issuer.test/oidc")
    monkeypatch.setenv("OAUTH_AUDIENCE", "https://api.test")
    monkeypatch.setenv("OAUTH_JWKS_URL", "https://issuer.test/oidc/jwks")

    def unavailable_jwks(token, settings):
        raise JwtValidationUnavailable()

    monkeypatch.setattr("apps.api.app.core.auth.validate_oauth_jwt", unavailable_jwks)

    response = client.request(
        "DELETE",
        "/api/v1/me",
        headers={"Authorization": "Bearer unavailable-jwks-token"},
        json={"confirmation": "delete-my-account"},
    )

    assert response.status_code == 503
    assert "lala_next_account_deletion_failure_total 0" in client.get("/metrics").text


def test_metrics_counts_identity_deletion_stage_failure_once(client, monkeypatch):
    monkeypatch.setenv("LALA_GUEST_ACCESS", "true")

    class FailingIdentityService:
        def mark_user_deleting(self, issuer, subject):
            raise ServiceError(
                status_code=503,
                code="IDENTITY_DB_UNAVAILABLE",
                message="Local identity storage is temporarily unavailable.",
                retryable=True,
            )

    client.app.dependency_overrides[require_logto_identity] = lambda: RequestIdentity(
        mode="oauth",
        issuer="https://issuer.test/oidc",
        subject="identity-failure-subject",
    )
    client.app.dependency_overrides[get_identity_service] = FailingIdentityService

    response = client.request(
        "DELETE",
        "/api/v1/me",
        json={"confirmation": "delete-my-account"},
    )

    assert response.status_code == 503
    assert "lala_next_account_deletion_failure_total 1" in client.get("/metrics").text


def test_metrics_counts_unexpected_deletion_stage_failure_once(client, monkeypatch):
    monkeypatch.setenv("LALA_GUEST_ACCESS", "true")

    class IdentityService:
        def mark_user_deleting(self, issuer, subject):
            return None

    class UnexpectedManagementClient:
        def delete_user(self, subject):
            raise RuntimeError("unexpected deletion failure")

    client.app.dependency_overrides[require_logto_identity] = lambda: RequestIdentity(
        mode="oauth",
        issuer="https://issuer.test/oidc",
        subject="unexpected-failure-subject",
    )
    client.app.dependency_overrides[get_identity_service] = IdentityService
    client.app.dependency_overrides[get_logto_management_client] = UnexpectedManagementClient

    with pytest.raises(RuntimeError, match="unexpected deletion failure"):
        client.request(
            "DELETE",
            "/api/v1/me",
            json={"confirmation": "delete-my-account"},
        )

    assert "lala_next_account_deletion_failure_total 1" in client.get("/metrics").text
