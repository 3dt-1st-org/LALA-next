from __future__ import annotations

import logging

import httpx
import pytest

from apps.api.app.core.config import Settings
from apps.api.app.core.observability import configure_logging
from apps.api.app.services.logto_management import (
    LogtoManagementClient,
    LogtoManagementRejected,
    LogtoManagementUnavailable,
)


class FakeResponse:
    def __init__(self, status_code: int, payload: object = None) -> None:
        self.status_code = status_code
        self.payload = payload

    def json(self):
        return self.payload


class FakeClient:
    def __init__(self, responses: list[FakeResponse]) -> None:
        self.responses = responses
        self.calls: list[tuple[str, str, dict]] = []

    def request(self, method: str, url: str, **kwargs) -> FakeResponse:
        self.calls.append((method, url, kwargs))
        return self.responses.pop(0)


def _settings() -> Settings:
    return Settings(
        logto_endpoint="https://tenant.logto.app",
        logto_management_client_id="management-client",
        logto_management_client_secret="management-secret",
    )


def test_management_settings_default_endpoint_and_resolve_secrets_from_key_vault(monkeypatch) -> None:
    monkeypatch.setenv("KEY_VAULT_URL", "https://vault.example")
    monkeypatch.setenv("LOGTO_ENDPOINT", "https://tenant.logto.app")

    def fake_secret(_url: str, name: str) -> str:
        return {
            "logto-management-client-id": "management-client",
            "logto-management-client-secret": "management-secret",
        }.get(name, "")

    monkeypatch.setattr("apps.api.app.core.config.get_secret_if_configured", fake_secret)

    settings = Settings.from_env()

    assert settings.logto_management_endpoint == "https://tenant.logto.app"
    assert settings.logto_management_client_id == "management-client"
    assert settings.logto_management_client_secret == "management-secret"


def test_management_deletion_uses_m2m_and_revokes_first_party_grants_and_sessions() -> None:
    client = FakeClient(
        [
            FakeResponse(200, {"access_token": "sensitive-token"}),
            FakeResponse(200, [{"id": "grant-1"}]),
            FakeResponse(204),
            FakeResponse(200, [{"id": "session-1"}]),
            FakeResponse(204),
            FakeResponse(204),
        ]
    )
    management = LogtoManagementClient(_settings(), client=client)

    management.delete_user("user-subject")

    assert client.calls[0] == (
        "POST",
        "https://tenant.logto.app/oidc/token",
        {
            "data": {
                "grant_type": "client_credentials",
                "resource": "https://tenant.logto.app/api",
                "scope": "all",
            },
            "auth": ("management-client", "management-secret"),
        },
    )
    assert [(method, url) for method, url, _ in client.calls[1:]] == [
        ("GET", "https://tenant.logto.app/api/users/user-subject/grants"),
        ("DELETE", "https://tenant.logto.app/api/users/user-subject/grants/grant-1"),
        ("GET", "https://tenant.logto.app/api/users/user-subject/sessions"),
        ("DELETE", "https://tenant.logto.app/api/users/user-subject/sessions/session-1"),
        ("DELETE", "https://tenant.logto.app/api/users/user-subject"),
    ]
    assert client.calls[1][2]["params"] == {"appType": "firstParty"}
    assert all(call[2].get("headers", {}).get("Authorization") == "Bearer sensitive-token" for call in client.calls[1:])


def test_management_network_failure_is_retryable_and_redacts_token() -> None:
    class FailingClient:
        def request(self, method: str, url: str, **kwargs):
            raise httpx.ConnectError("token=sensitive-token", request=httpx.Request(method, url))

    with pytest.raises(LogtoManagementUnavailable) as exc_info:
        LogtoManagementClient(_settings(), client=FailingClient()).delete_user("user-subject")

    assert exc_info.value.retryable is True
    assert "sensitive-token" not in str(exc_info.value)


@pytest.mark.parametrize(
    ("responses", "expected_calls"),
    (
        (
            [
                FakeResponse(200, {"access_token": "sensitive-token"}),
                FakeResponse(404),
                FakeResponse(200, []),
                FakeResponse(204),
            ],
            [
                ("POST", "https://tenant.logto.app/oidc/token"),
                ("GET", "https://tenant.logto.app/api/users/user-subject/grants"),
                ("GET", "https://tenant.logto.app/api/users/user-subject/sessions"),
                ("DELETE", "https://tenant.logto.app/api/users/user-subject"),
            ],
        ),
        (
            [
                FakeResponse(200, {"access_token": "sensitive-token"}),
                FakeResponse(200, []),
                FakeResponse(404),
                FakeResponse(204),
            ],
            [
                ("POST", "https://tenant.logto.app/oidc/token"),
                ("GET", "https://tenant.logto.app/api/users/user-subject/grants"),
                ("GET", "https://tenant.logto.app/api/users/user-subject/sessions"),
                ("DELETE", "https://tenant.logto.app/api/users/user-subject"),
            ],
        ),
    ),
)
def test_management_optional_collection_404_still_deletes_user(
    responses,
    expected_calls,
) -> None:
    client = FakeClient(responses)

    LogtoManagementClient(_settings(), client=client).delete_user("user-subject")

    assert [(method, url) for method, url, _ in client.calls] == expected_calls


def test_management_user_delete_404_is_an_idempotent_success() -> None:
    client = FakeClient(
        [
            FakeResponse(200, {"access_token": "sensitive-token"}),
            FakeResponse(200, []),
            FakeResponse(200, []),
            FakeResponse(404),
        ]
    )

    LogtoManagementClient(_settings(), client=client).delete_user("user-subject")

    assert [(method, url) for method, url, _ in client.calls] == [
        ("POST", "https://tenant.logto.app/oidc/token"),
        ("GET", "https://tenant.logto.app/api/users/user-subject/grants"),
        ("GET", "https://tenant.logto.app/api/users/user-subject/sessions"),
        ("DELETE", "https://tenant.logto.app/api/users/user-subject"),
    ]


@pytest.mark.parametrize("status_code", (408, 429))
def test_management_transient_http_failures_are_retryable(status_code: int) -> None:
    client = FakeClient(
        [
            FakeResponse(200, {"access_token": "sensitive-token"}),
            FakeResponse(status_code),
        ]
    )

    with pytest.raises(LogtoManagementUnavailable):
        LogtoManagementClient(_settings(), client=client).delete_user("user-subject")


@pytest.mark.parametrize(
    "responses",
    (
        [
            FakeResponse(200, {"access_token": "sensitive-token"}),
            FakeResponse(200, {"unexpected": []}),
        ],
        [
            FakeResponse(200, {"access_token": "sensitive-token"}),
            FakeResponse(200, []),
            FakeResponse(200, {"unexpected": []}),
        ],
    ),
)
def test_management_unexpected_list_payload_is_a_non_retryable_service_error(responses) -> None:
    expected_call_count = len(responses)
    client = FakeClient(responses)

    with pytest.raises(LogtoManagementRejected) as exc_info:
        LogtoManagementClient(_settings(), client=client).delete_user("user-subject")

    assert exc_info.value.retryable is False
    assert len(client.calls) == expected_call_count


def test_management_http_libraries_do_not_log_subject_urls(caplog) -> None:
    subject = "unique-subject-marker"

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/oidc/token":
            return httpx.Response(200, json={"access_token": "sensitive-token"})
        if request.url.path.endswith("/grants"):
            return httpx.Response(200, json=[])
        if request.url.path.endswith("/sessions"):
            return httpx.Response(200, json=[])
        return httpx.Response(204)

    caplog.set_level(logging.INFO)
    configure_logging("INFO")
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        LogtoManagementClient(_settings(), client=client).delete_user(subject)

    assert logging.getLogger("httpx").getEffectiveLevel() >= logging.WARNING
    assert logging.getLogger("httpcore").getEffectiveLevel() >= logging.WARNING
    assert subject not in " ".join(record.getMessage() for record in caplog.records)
