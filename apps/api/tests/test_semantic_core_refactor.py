from __future__ import annotations

import asyncio
import threading
from datetime import UTC, datetime
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from fastapi import Request
from fastapi.testclient import TestClient

from apps.api.app.core.auth import require_logto_identity
from apps.api.app.core.config import Settings
from apps.api.app.main import create_app
from apps.api.app.routers import community_chat as chat_router
from apps.api.app.services import community_chat_realtime as realtime
from apps.api.app.services.identity_repository import LocalUser
from apps.api.app.services.identity_service import get_identity_service
from apps.api.app.services.travel_preferences_service import get_travel_preferences_service


class CountingIdentityService:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []
        self.user = LocalUser(
            id=UUID("00000000-0000-0000-0000-000000000321"),
            issuer="https://tenant.example/oidc",
            subject="subject-1",
            status="active",
            created_at=datetime(2026, 9, 16, tzinfo=UTC),
            last_seen_at=datetime(2026, 9, 16, tzinfo=UTC),
            deletion_requested_at=None,
        )

    def provision_user(self, issuer: str, subject: str) -> LocalUser:
        self.calls.append((issuer, subject))
        return self.user


class EmptyPreferencesService:
    def get(self, *, issuer: str, subject: str):
        return None


def _logto_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LOGTO_ENDPOINT", "https://tenant.example")
    monkeypatch.setenv("LOGTO_API_AUDIENCE", "https://api.example")
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.delenv("API_BEARER_TOKEN", raising=False)


def test_current_account_context_provisions_once_for_account_handlers(monkeypatch) -> None:
    _logto_env(monkeypatch)
    monkeypatch.setattr(
        "apps.api.app.core.auth.validate_oauth_jwt",
        lambda token, settings: {
            "iss": "https://tenant.example/oidc",
            "sub": "subject-1",
        },
    )
    service = CountingIdentityService()
    app = create_app()
    app.dependency_overrides[get_identity_service] = lambda: service
    app.dependency_overrides[get_travel_preferences_service] = lambda: EmptyPreferencesService()

    with TestClient(app) as client:
        me = client.get("/api/v1/me", headers={"Authorization": "Bearer token"})
        preferences = client.get(
            "/api/v1/me/preferences",
            headers={"Authorization": "Bearer token"},
        )

    assert me.status_code == 200
    assert preferences.status_code == 200
    assert service.calls == [
        ("https://tenant.example/oidc", "subject-1"),
        ("https://tenant.example/oidc", "subject-1"),
    ]


def test_delete_logto_dependency_still_skips_provision_for_retry(monkeypatch) -> None:
    def delete_me():
        pass

    service = CountingIdentityService()
    identity = chat_router.RequestIdentity(
        mode="oauth",
        issuer="https://tenant.example/oidc",
        subject="subject-1",
    )
    result = require_logto_identity(
        identity,
        Settings(logto_endpoint="https://tenant.example", logto_api_audience="api"),
        Request({"type": "http", "method": "DELETE", "route": SimpleNamespace(endpoint=delete_me)}),
        service,
    )

    assert result == identity
    assert service.calls == []


def test_openapi_account_contract_is_portable_and_oauth_only() -> None:
    schema = create_app().openapi()
    get_me = schema["paths"]["/api/v1/me"]["get"]
    delete_me = schema["paths"]["/api/v1/me"]["delete"]

    assert get_me["operationId"] == "me_api_v1_me_get"
    assert delete_me["operationId"] == "delete_me_api_v1_me_delete"
    assert get_me["security"] == [{"OAuthBearerAuth": []}]
    assert delete_me["security"] == [{"OAuthBearerAuth": []}]
    assert get_me["x-lala-auth-required"] is True
    assert get_me["x-lala-timeout-seconds"] == 12
    assert "409" in get_me["responses"]
    assert "410" in get_me["responses"]
    assert "409" not in delete_me["responses"]
    for operation in (get_me, delete_me):
        header_names = {
            parameter.get("name")
            for parameter in operation.get("parameters", [])
            if parameter.get("in") == "header"
        }
        assert "Authorization" not in header_names
        assert "X-API-Key" not in header_names


def test_split_v1_routes_preserve_focused_operation_contracts() -> None:
    paths = create_app().openapi()["paths"]

    expected = {
        ("/api/v1/places", "get"): ("places_api_v1_places_get", ["v1"]),
        ("/api/v1/docents/audio", "post"): ("docent_audio_api_v1_docents_audio_post", ["v1"]),
        ("/api/v1/plans/daily", "post"): ("daily_plan_api_v1_plans_daily_post", ["v1"]),
        ("/api/v1/me/preferences", "get"): (
            "get_travel_preferences_api_v1_me_preferences_get",
            ["v1"],
        ),
        ("/api/v1/me/plans/{plan_date}/visits/{slot_period}", "put"): (
            "check_in_slot_api_v1_me_plans__plan_date__visits__slot_period__put",
            ["v1"],
        ),
        ("/api/v1/community/chat/rooms/{room_id}/messages", "post"): (
            "create_message_api_v1_community_chat_rooms__room_id__messages_post",
            ["community-chat"],
        ),
    }
    for (path, method), (operation_id, tags) in expected.items():
        operation = paths[path][method]
        assert operation["operationId"] == operation_id
        assert operation["tags"] == tags

    assert paths["/api/v1/places"]["get"]["security"] == [
        {},
        {"BearerAuth": []},
        {"MigrationApiKey": []},
    ]
    assert paths["/api/v1/me/preferences"]["get"]["security"] == [{"OAuthBearerAuth": []}]
    assert (
        paths["/api/v1/community/chat/rooms/{room_id}/messages"]["post"]["responses"]["429"][
            "description"
        ]
        == "The community write rate limit was exceeded."
    )


def test_realtime_db_capacity_state_is_owned_by_service(monkeypatch) -> None:
    slots = threading.BoundedSemaphore(1)
    monkeypatch.setattr(realtime, "_db_work_slots", slots)

    async def run() -> None:
        entered = threading.Event()
        release = threading.Event()

        def slow() -> None:
            entered.set()
            release.wait(2)

        task = asyncio.create_task(chat_router._run_db(slow))
        try:
            while not entered.is_set():
                await asyncio.sleep(0.001)
            with pytest.raises(chat_router.ServiceError):
                await realtime.run_db(lambda: None)
            task.cancel()
            with pytest.raises(asyncio.CancelledError):
                await task
        finally:
            release.set()

    try:
        asyncio.run(run())
    finally:
        for _ in range(100):
            if slots.acquire(blocking=False):
                slots.release()
                break
            threading.Event().wait(0.005)
        else:
            pytest.fail("worker slot was not returned")


def test_realtime_state_is_not_copied_by_router_after_refactor() -> None:
    assert not hasattr(chat_router, "manager")
    assert not hasattr(chat_router, "ConnectionManager")
    assert not hasattr(chat_router, "_db_work_slots")
    room_id = uuid4()
    assert realtime.manager.room_connection_count(room_id) == 0
