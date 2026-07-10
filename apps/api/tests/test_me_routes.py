from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from apps.api.app.core.auth import RequestIdentity, require_oauth_identity
from apps.api.app.services.identity_repository import LocalUser
from apps.api.app.services.identity_service import get_identity_service
from apps.api.app.services.logto_management import get_logto_management_client


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
    def __init__(self, user: LocalUser | None = USER) -> None:
        self.user = user
        self.provisioned: list[tuple[str, str]] = []
        self.marked: list[tuple[str, str]] = []
        self.deleted: list[tuple[str, str]] = []

    def provision_user(self, issuer: str, subject: str) -> LocalUser:
        self.provisioned.append((issuer, subject))
        return USER

    def mark_user_deleting(self, issuer: str, subject: str) -> LocalUser | None:
        self.marked.append((issuer, subject))
        return self.user

    def delete_local_user(self, issuer: str, subject: str) -> bool:
        self.deleted.append((issuer, subject))
        return self.user is not None


class FakeManagementClient:
    def __init__(self) -> None:
        self.deleted_subjects: list[str] = []

    def delete_user(self, subject: str) -> None:
        self.deleted_subjects.append(subject)


def _oauth_identity() -> RequestIdentity:
    return RequestIdentity(mode="oauth", issuer="https://issuer.example", subject="user-subject")


def test_me_requires_an_oauth_identity(client, api_key) -> None:
    response = client.get("/api/v1/me", headers={"X-API-Key": api_key})

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "USER_AUTH_REQUIRED"


def test_get_me_provisions_idempotently_and_hides_external_identity(client, api_key) -> None:
    service = FakeIdentityService()
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity
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


def test_me_database_unavailability_is_retryable_and_does_not_leak_identity(client, api_key) -> None:
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.get("/api/v1/me", headers={"X-API-Key": api_key})

    assert response.status_code == 503
    assert response.json()["error"] == {
        "code": "IDENTITY_DB_UNAVAILABLE",
        "message": "Local identity storage is temporarily unavailable.",
        "retryable": True,
    }
    assert "issuer.example" not in response.text
    assert "user-subject" not in response.text


def test_delete_me_requires_exact_confirmation_without_side_effects(client, api_key) -> None:
    service = FakeIdentityService()
    management = FakeManagementClient()
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity
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
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity
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
    assert management.deleted_subjects == []
    assert service.deleted == []
