from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from apps.api.app.core.auth import (
    RequestIdentity,
    require_client_auth,
    require_logto_identity,
)
from apps.api.app.core.errors import ServiceError
from apps.api.app.services.identity_repository import LocalUser
from apps.api.app.services.identity_service import get_identity_service
from apps.api.app.services.logto_management import (
    LogtoManagementUnavailable,
    get_logto_management_client,
)

USER = LocalUser(
    id=UUID("00000000-0000-0000-0000-000000000001"),
    issuer="https://issuer.example",
    subject="user-subject",
    status="active",
    created_at=datetime(2026, 7, 10, tzinfo=UTC),
    last_seen_at=datetime(2026, 7, 10, tzinfo=UTC),
    deletion_requested_at=None,
)


class FakeIdentityService:
    def __init__(self, user: LocalUser | None = USER, *, events: list[str] | None = None) -> None:
        self.user = user
        self.events = events
        self.local_state = "active" if user is not None else "absent"
        self.provisioned: list[tuple[str, str]] = []
        self.marked: list[tuple[str, str]] = []
        self.finalized: list[tuple[str, str]] = []

    def provision_user(self, issuer: str, subject: str) -> LocalUser:
        self.provisioned.append((issuer, subject))
        return USER

    def mark_user_deleting(self, issuer: str, subject: str) -> LocalUser | None:
        if self.events is not None:
            self.events.append("mark")
        if self.user is not None:
            self.local_state = "deleting"
        self.marked.append((issuer, subject))
        return self.user

    def finalize_user_deletion(self, issuer: str, subject: str) -> bool:
        if self.events is not None:
            self.events.append("local-finalize")
        if self.user is not None:
            self.local_state = "deleted"
        self.finalized.append((issuer, subject))
        return self.user is not None


class FakeManagementClient:
    def __init__(self, *, events: list[str] | None = None) -> None:
        self.events = events
        self.deleted_subjects: list[str] = []

    def delete_user(self, subject: str) -> None:
        if self.events is not None:
            self.events.append("external-delete")
        self.deleted_subjects.append(subject)


def _oauth_identity() -> RequestIdentity:
    return RequestIdentity(mode="oauth", issuer="https://issuer.example", subject="user-subject")


def test_me_requires_an_oauth_identity(client, api_key) -> None:
    response = client.get("/api/v1/me", headers={"X-API-Key": api_key})

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "USER_AUTH_REQUIRED"


def test_get_me_provisions_idempotently_and_hides_external_identity(client, api_key) -> None:
    service = FakeIdentityService()
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = lambda: service

    response = client.get("/api/v1/me", headers={"X-API-Key": api_key})

    assert response.status_code == 200
    assert response.json()["data"] == {
        "user_id": str(USER.id),
        "created_at": "2026-07-10T00:00:00+00:00",
        "authenticated": True,
    }
    assert service.provisioned == [("https://issuer.example", "user-subject")]
    assert "issuer.example" not in response.text
    assert "user-subject" not in response.text


def test_me_database_unavailability_is_retryable_and_does_not_leak_identity(
    client, api_key
) -> None:
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity

    response = client.get("/api/v1/me", headers={"X-API-Key": api_key})

    assert response.status_code == 503
    assert response.json()["error"] == {
        "code": "IDENTITY_DB_UNAVAILABLE",
        "message": "Local identity storage is temporarily unavailable.",
        "retryable": True,
    }
    assert "issuer.example" not in response.text
    assert "user-subject" not in response.text


def test_get_me_rejects_a_tombstoned_identity_without_reprovisioning(client, api_key) -> None:
    class TombstonedIdentityService(FakeIdentityService):
        def provision_user(self, issuer: str, subject: str) -> LocalUser:
            raise ServiceError(
                status_code=410,
                code="ACCOUNT_DELETED",
                message="This account has been deleted.",
                retryable=False,
            )

    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = TombstonedIdentityService

    response = client.get("/api/v1/me", headers={"X-API-Key": api_key})

    assert response.status_code == 410
    assert response.json()["error"] == {
        "code": "ACCOUNT_DELETED",
        "message": "This account has been deleted.",
        "retryable": False,
    }
    assert "issuer.example" not in response.text
    assert "user-subject" not in response.text


def test_delete_me_requires_exact_confirmation_without_side_effects(client, api_key) -> None:
    service = FakeIdentityService()
    management = FakeManagementClient()
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = lambda: service
    client.app.dependency_overrides[get_logto_management_client] = lambda: management

    response = client.request(
        "DELETE",
        "/api/v1/me",
        headers={"X-API-Key": api_key},
        json={"confirmation": "delete-my-account-no"},
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"
    assert service.marked == []
    assert management.deleted_subjects == []


def test_delete_me_is_idempotent_when_local_user_is_missing(client, api_key) -> None:
    service = FakeIdentityService(user=None)
    management = FakeManagementClient()
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = lambda: service
    client.app.dependency_overrides[get_logto_management_client] = lambda: management

    response = client.request(
        "DELETE",
        "/api/v1/me",
        headers={"X-API-Key": api_key},
        json={"confirmation": "delete-my-account"},
    )

    assert response.status_code == 204
    assert response.content == b""
    assert service.marked == [("https://issuer.example", "user-subject")]
    assert management.deleted_subjects == ["user-subject"]
    assert service.finalized == [("https://issuer.example", "user-subject")]


def test_delete_me_marks_then_deletes_external_user_before_local_finalize(client, api_key) -> None:
    events: list[str] = []
    service = FakeIdentityService(events=events)
    management = FakeManagementClient(events=events)
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = lambda: service
    client.app.dependency_overrides[get_logto_management_client] = lambda: management

    response = client.request(
        "DELETE",
        "/api/v1/me",
        headers={"X-API-Key": api_key},
        json={"confirmation": "delete-my-account"},
    )

    assert response.status_code == 204
    assert events == ["mark", "external-delete", "local-finalize"]


def test_delete_me_external_failure_keeps_deleting_state_and_skips_local_finalize(
    client, api_key
) -> None:
    events: list[str] = []
    service = FakeIdentityService(events=events)

    class FailingManagementClient(FakeManagementClient):
        def delete_user(self, subject: str) -> None:
            super().delete_user(subject)
            raise LogtoManagementUnavailable()

    management = FailingManagementClient(events=events)
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = lambda: service
    client.app.dependency_overrides[get_logto_management_client] = lambda: management

    response = client.request(
        "DELETE",
        "/api/v1/me",
        headers={"X-API-Key": api_key},
        json={"confirmation": "delete-my-account"},
    )

    assert response.status_code == 503
    assert response.json()["error"]["retryable"] is True
    assert events == ["mark", "external-delete"]
    assert service.local_state == "deleting"
    assert service.finalized == []


def test_delete_me_retry_completes_after_external_failure(client, api_key) -> None:
    events: list[str] = []
    service = FakeIdentityService(events=events)

    class FlakyManagementClient(FakeManagementClient):
        def __init__(self, **kwargs) -> None:
            super().__init__(**kwargs)
            self.failures_remaining = 1

        def delete_user(self, subject: str) -> None:
            super().delete_user(subject)
            if self.failures_remaining:
                self.failures_remaining -= 1
                raise LogtoManagementUnavailable()

    management = FlakyManagementClient(events=events)
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = lambda: service
    client.app.dependency_overrides[get_logto_management_client] = lambda: management
    payload = {"confirmation": "delete-my-account"}

    first_response = client.request(
        "DELETE", "/api/v1/me", headers={"X-API-Key": api_key}, json=payload
    )
    second_response = client.request(
        "DELETE", "/api/v1/me", headers={"X-API-Key": api_key}, json=payload
    )

    assert first_response.status_code == 503
    assert second_response.status_code == 204
    assert events == [
        "mark",
        "external-delete",
        "mark",
        "external-delete",
        "local-finalize",
    ]
    assert service.local_state == "deleted"


def test_delete_me_rejects_legacy_oauth_before_management_receives_subject(
    client,
    monkeypatch,
) -> None:
    management = FakeManagementClient()
    monkeypatch.setenv("LOGTO_ENDPOINT", "https://tenant.logto.app")
    monkeypatch.setenv("LOGTO_API_AUDIENCE", "https://api.lala-next.example")
    client.app.dependency_overrides[require_client_auth] = lambda: RequestIdentity(
        mode="oauth",
        issuer="https://legacy.example/oidc",
        subject="legacy-subject",
    )
    client.app.dependency_overrides[get_logto_management_client] = lambda: management

    response = client.request(
        "DELETE",
        "/api/v1/me",
        json={"confirmation": "delete-my-account"},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "USER_AUTH_REQUIRED"
    assert management.deleted_subjects == []
    assert "legacy-subject" not in response.text


def test_me_rejects_oauth_when_logto_configuration_is_incomplete(client) -> None:
    client.app.dependency_overrides[require_client_auth] = lambda: RequestIdentity(
        mode="oauth",
        issuer="https://legacy.example/oidc",
        subject="legacy-subject",
    )

    response = client.get("/api/v1/me")

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "USER_AUTH_REQUIRED"
    assert "legacy" not in response.text
