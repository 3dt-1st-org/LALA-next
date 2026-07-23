from __future__ import annotations

import asyncio
import json
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import pytest
from fastapi import WebSocketDisconnect

from apps.api.app.core.auth import RequestIdentity, require_oauth_identity
from apps.api.app.core.config import Settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.core.jwt_auth import JwtValidationRejected
from apps.api.app.routers.community_chat import (
    ConnectionManager,
    _identity_from_token,
    manager,
)
from apps.api.app.services.community_chat_service import (
    CommunityChatRepository,
    CommunityChatRepositoryUnavailable,
    CommunityChatService,
    get_community_chat_service,
)

ROOM_ID = UUID("00000000-0000-0000-0000-000000000010")
MESSAGE_ID = UUID("00000000-0000-0000-0000-000000000011")
AUTHOR_ID = UUID("00000000-0000-0000-0000-000000000012")
NOW = datetime(2026, 7, 23, tzinfo=UTC)
ISSUER = "https://issuer.example"
SUBJECT = "user-subject"
DB_DSN = "postgresql://redacted"


# ---------------------------------------------------------------------------
# Test doubles for psycopg2 (same shape as test_community.py).
# ---------------------------------------------------------------------------


class FakeCursor:
    def __init__(self, rows: list[Any], executed: list[tuple[str, Any]]) -> None:
        self._rows = rows
        self._executed = executed

    def __enter__(self) -> FakeCursor:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def execute(self, sql: str, params: Any = None) -> None:
        self._executed.append((sql, params))

    def fetchone(self) -> Any:
        return self._rows.pop(0) if self._rows else None

    def fetchall(self) -> list[Any]:
        items = list(self._rows)
        self._rows.clear()
        return items


class FakeConnection:
    def __init__(self, rows: list[Any], executed: list[tuple[str, Any]]) -> None:
        self._rows = rows
        self._executed = executed

    def __enter__(self) -> FakeConnection:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def cursor(self, cursor_factory: Any = None) -> FakeCursor:
        return FakeCursor(self._rows, self._executed)

    def close(self) -> None:
        return None


def _repo(rows: list[Any]) -> tuple[CommunityChatRepository, list[tuple[str, Any]]]:
    executed: list[tuple[str, Any]] = []
    repository = CommunityChatRepository(
        Settings(db_dsn=DB_DSN),
        connect=lambda **kwargs: FakeConnection(rows, executed),
    )
    return repository, executed


def _room_row() -> dict[str, Any]:
    return {"id": ROOM_ID, "name": "general", "created_at": NOW}


def _message_row() -> dict[str, Any]:
    return {
        "id": MESSAGE_ID,
        "room_id": ROOM_ID,
        "author_issuer": ISSUER,
        "author_subject": SUBJECT,
        "body": "hello",
        "created_at": NOW,
        "author_user_id": AUTHOR_ID,
    }


def _inserted_message_row() -> dict[str, Any]:
    """Row returned by INSERT ... RETURNING (no author_user_id yet)."""
    return {
        "id": MESSAGE_ID,
        "room_id": ROOM_ID,
        "author_issuer": ISSUER,
        "author_subject": SUBJECT,
        "body": "hello",
        "created_at": NOW,
    }


@pytest.fixture(autouse=True)
def _reset_connection_manager() -> None:
    manager._rooms.clear()
    yield
    manager._rooms.clear()


# ===========================================================================
# Repository: SQL generation + row shaping (no real database).
# ===========================================================================


def test_list_rooms_emits_count_then_paginated_query() -> None:
    repository, executed = _repo([{"count": 1}, _room_row()])

    rows, total = repository.list_rooms(limit=20, offset=0)

    assert total == 1
    assert rows == [_room_row()]
    assert "count(*)" in executed[0][0]
    assert "FROM community.chat_rooms" in executed[0][0]
    assert "FROM community.chat_rooms" in executed[1][0]
    assert "ORDER BY created_at DESC" in executed[1][0]
    assert executed[1][1] == (20, 0)


def test_create_room_inserts_name_and_returns_row() -> None:
    repository, executed = _repo([_room_row()])

    row = repository.create_room(name="general")

    assert row == _room_row()
    sql, params = executed[0]
    assert "INSERT INTO community.chat_rooms" in sql
    assert params == ("general",)


def test_room_exists_returns_true_when_row_present() -> None:
    repository, _executed = _repo([{"?column?": 1}])

    assert repository.room_exists(room_id=ROOM_ID) is True


def test_room_exists_returns_false_when_missing() -> None:
    repository, _executed = _repo([None])

    assert repository.room_exists(room_id=ROOM_ID) is False


def test_list_messages_emits_count_then_paginated_query() -> None:
    repository, executed = _repo([{"count": 1}, _message_row()])

    rows, total = repository.list_messages(room_id=ROOM_ID, limit=50, offset=0)

    assert total == 1
    assert rows == [_message_row()]
    assert executed[0][1] == (str(ROOM_ID),)
    assert "FROM community.chat_messages m" in executed[1][0]
    assert "JOIN identity.users u" in executed[1][0]
    assert "WHERE m.room_id = %s" in executed[1][0]
    assert executed[1][1] == (str(ROOM_ID), 50, 0)


def test_create_message_resolves_author_identity_across_two_cursors() -> None:
    repository, executed = _repo([_inserted_message_row(), {"id": AUTHOR_ID}])

    row = repository.create_message(room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT, body="hello")

    assert row["body"] == "hello"
    assert row["author_user_id"] == AUTHOR_ID
    assert "INSERT INTO community.chat_messages" in executed[0][0]
    assert "FROM community.chat_rooms" in executed[0][0]
    assert "FROM identity.users" in executed[1][0]


def test_create_message_returns_none_when_room_missing() -> None:
    repository, _executed = _repo([None])

    assert (
        repository.create_message(room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT, body="hello")
        is None
    )


def test_repository_without_dsn_is_unavailable() -> None:
    repository = CommunityChatRepository(Settings(db_dsn=""))

    with pytest.raises(CommunityChatRepositoryUnavailable):
        repository.list_rooms(limit=1, offset=0)


# ===========================================================================
# Service: error mapping + payload shaping.
# ===========================================================================


class _UnavailableRepository:
    def list_rooms(self, **_: Any) -> tuple[list[dict[str, Any]], int]:
        raise CommunityChatRepositoryUnavailable()

    def create_room(self, **_: Any) -> dict[str, Any]:
        raise CommunityChatRepositoryUnavailable()

    def room_exists(self, **_: Any) -> bool:
        raise CommunityChatRepositoryUnavailable()

    def list_messages(self, **_: Any) -> tuple[list[dict[str, Any]], int]:
        raise CommunityChatRepositoryUnavailable()

    def create_message(self, **_: Any) -> dict[str, Any] | None:
        raise CommunityChatRepositoryUnavailable()


def test_service_maps_repository_unavailability_to_retryable_503() -> None:
    service = CommunityChatService(_UnavailableRepository())

    with pytest.raises(ServiceError) as exc_info:
        service.list_rooms(limit=1, offset=0)

    assert exc_info.value.status_code == 503
    assert exc_info.value.code == "COMMUNITY_CHAT_DB_UNAVAILABLE"
    assert exc_info.value.retryable is True


def test_service_create_message_maps_missing_room_to_404() -> None:
    class MissingRepository(_UnavailableRepository):
        def create_message(self, **_: Any) -> dict[str, Any] | None:
            return None

    service = CommunityChatService(MissingRepository())

    with pytest.raises(ServiceError) as exc_info:
        service.create_message(room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT, body="hi")

    assert exc_info.value.status_code == 404
    assert exc_info.value.code == "COMMUNITY_CHAT_ROOM_NOT_FOUND"


def test_service_shapes_room_payload() -> None:
    class StubRepository(_UnavailableRepository):
        def list_rooms(self, **kwargs: Any) -> tuple[list[dict[str, Any]], int]:
            return ([_room_row()], 1)

    service = CommunityChatService(StubRepository())

    payload = service.list_rooms(limit=1, offset=0)

    assert payload == {
        "count": 1,
        "total": 1,
        "rooms": [
            {
                "id": str(ROOM_ID),
                "name": "general",
                "created_at": NOW.isoformat(),
            }
        ],
    }


def test_service_shapes_message_payload() -> None:
    class StubRepository(_UnavailableRepository):
        def list_messages(self, **kwargs: Any) -> tuple[list[dict[str, Any]], int]:
            return ([_message_row()], 1)

    service = CommunityChatService(StubRepository())

    payload = service.list_messages(room_id=ROOM_ID, limit=50, offset=0)

    assert payload == {
        "count": 1,
        "total": 1,
        "messages": [
            {
                "id": str(MESSAGE_ID),
                "room_id": str(ROOM_ID),
                "author_user_id": str(AUTHOR_ID),
                "body": "hello",
                "created_at": NOW.isoformat(),
            }
        ],
    }


# ===========================================================================
# ConnectionManager: connect / broadcast / disconnect (no ASGI stack).
# ===========================================================================


class MockWebSocket:
    def __init__(self) -> None:
        self.sent: list[dict] = []
        self.accepted = False
        self.send_should_fail = False

    async def accept(self) -> None:
        self.accepted = True

    async def send_json(self, payload: dict) -> None:
        if self.send_should_fail:
            raise RuntimeError("connection lost")
        self.sent.append(payload)

    async def close(self, code: int = 1000) -> None:  # pragma: no cover - not used in unit tests
        return None


def test_connection_manager_connect_accepts_and_tracks_per_room() -> None:
    async def run() -> None:
        cm = ConnectionManager()
        ws = MockWebSocket()
        await cm.connect(ws, room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT)

        assert ws.accepted is True
        assert cm.room_connection_count(ROOM_ID) == 1

    asyncio.run(run())


def test_connection_manager_broadcast_fans_out_to_room_only() -> None:
    other_room = UUID("00000000-0000-0000-0000-000000000099")

    async def run() -> None:
        cm = ConnectionManager()
        ws_a = MockWebSocket()
        ws_b = MockWebSocket()
        ws_other = MockWebSocket()
        await cm.connect(ws_a, room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT)
        await cm.connect(ws_b, room_id=ROOM_ID, issuer="https://o", subject="o")
        await cm.connect(ws_other, room_id=other_room, issuer="https://x", subject="x")

        await cm.broadcast(room_id=ROOM_ID, payload={"type": "message", "data": {}})

        assert ws_a.sent == [{"type": "message", "data": {}}]
        assert ws_b.sent == [{"type": "message", "data": {}}]
        assert ws_other.sent == []

    asyncio.run(run())


def test_connection_manager_broadcast_excludes_sender() -> None:
    async def run() -> None:
        cm = ConnectionManager()
        ws_sender = MockWebSocket()
        ws_other = MockWebSocket()
        await cm.connect(ws_sender, room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT)
        await cm.connect(ws_other, room_id=ROOM_ID, issuer="https://o", subject="o")

        await cm.broadcast(
            room_id=ROOM_ID,
            payload={"type": "message"},
            exclude=ws_sender,
        )

        assert ws_sender.sent == []
        assert ws_other.sent == [{"type": "message"}]

    asyncio.run(run())


def test_connection_manager_disconnect_removes_client_and_prunes_empty_room() -> None:
    async def run() -> None:
        cm = ConnectionManager()
        ws = MockWebSocket()
        await cm.connect(ws, room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT)
        assert cm.room_connection_count(ROOM_ID) == 1

        cm.disconnect(ws, ROOM_ID)
        assert cm.room_connection_count(ROOM_ID) == 0

    asyncio.run(run())


def test_connection_manager_broadcast_evicts_dead_clients() -> None:
    async def run() -> None:
        cm = ConnectionManager()
        ws_dead = MockWebSocket()
        ws_dead.send_should_fail = True
        ws_alive = MockWebSocket()
        await cm.connect(ws_dead, room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT)
        await cm.connect(ws_alive, room_id=ROOM_ID, issuer="https://o", subject="o")

        await cm.broadcast(room_id=ROOM_ID, payload={"type": "message"})

        assert ws_alive.sent == [{"type": "message"}]
        assert cm.room_connection_count(ROOM_ID) == 1

    asyncio.run(run())


def test_identity_from_token_rejects_missing_token() -> None:
    with pytest.raises(JwtValidationRejected):
        _identity_from_token(None, Settings())


# ===========================================================================
# Router (REST): auth gating + envelope contract.
# ===========================================================================


class FakeChatService:
    def __init__(self) -> None:
        self.created_rooms: list[str] = []
        self.created_messages: list[tuple[UUID, str, str, str]] = []

    def list_rooms(self, **kwargs: Any) -> dict[str, Any]:
        return {
            "count": 1,
            "total": 1,
            "rooms": [
                {
                    "id": str(ROOM_ID),
                    "name": "general",
                    "created_at": NOW.isoformat(),
                }
            ],
        }

    def create_room(self, **kwargs: Any) -> dict[str, Any]:
        self.created_rooms.append(kwargs["name"])
        return {
            "id": str(ROOM_ID),
            "name": kwargs["name"],
            "created_at": NOW.isoformat(),
        }

    def room_exists(self, **kwargs: Any) -> bool:
        return True

    def list_messages(self, **kwargs: Any) -> dict[str, Any]:
        return {"count": 0, "total": 0, "messages": []}

    def create_message(self, **kwargs: Any) -> dict[str, Any]:
        self.created_messages.append(
            (kwargs["room_id"], kwargs["issuer"], kwargs["subject"], kwargs["body"])
        )
        return {
            "id": str(MESSAGE_ID),
            "room_id": str(kwargs["room_id"]),
            "author_user_id": str(AUTHOR_ID),
            "body": kwargs["body"],
            "created_at": NOW.isoformat(),
        }


def _oauth_identity() -> RequestIdentity:
    return RequestIdentity(mode="oauth", issuer=ISSUER, subject=SUBJECT)


def _install_fake_service(client, service: FakeChatService) -> None:
    client.app.dependency_overrides[get_community_chat_service] = lambda: service


def test_list_rooms_is_guest_readable_and_returns_envelope(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)

    response = client.get("/api/v1/community/chat/rooms", headers={"X-API-Key": api_key})

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["error"] is None
    assert body["data"]["count"] == 1
    assert body["data"]["rooms"][0]["name"] == "general"
    assert body["meta"]["source"] == "db"
    assert body["meta"]["total"] == 1
    assert "request_id" in body["meta"]


def test_create_room_requires_oauth_identity(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)

    response = client.post(
        "/api/v1/community/chat/rooms",
        headers={"X-API-Key": api_key},
        json={"name": "general"},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "USER_AUTH_REQUIRED"
    assert service.created_rooms == []


def test_create_room_with_oauth_creates_and_returns_envelope(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        "/api/v1/community/chat/rooms",
        headers={"X-API-Key": api_key},
        json={"name": "travel"},
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["name"] == "travel"
    assert service.created_rooms == ["travel"]


def test_list_messages_returns_envelope(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)

    response = client.get(
        f"/api/v1/community/chat/rooms/{ROOM_ID}/messages",
        headers={"X-API-Key": api_key},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"] == {"count": 0, "total": 0, "messages": []}
    assert body["meta"]["total"] == 0


# ===========================================================================
# Router (WebSocket): handshake auth + real-time broadcast.
# ===========================================================================


def test_ws_rejects_handshake_when_token_missing(client, api_key, monkeypatch) -> None:
    # Without OAUTH_* configured, validate_oauth_jwt raises JwtValidationUnavailable
    # which the handler maps to a 1008 close.
    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(f"/api/v1/community/chat/rooms/{ROOM_ID}/ws") as ws:
            ws.receive_text()
    assert exc.value.code == 1008


def test_ws_persists_and_broadcasts_message(client, api_key, monkeypatch) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)
    monkeypatch.setattr(
        "apps.api.app.routers.community_chat._identity_from_token",
        lambda token, settings: (ISSUER, SUBJECT),
    )

    with client.websocket_connect(f"/api/v1/community/chat/rooms/{ROOM_ID}/ws?token=valid") as ws:
        ws.send_text(json.dumps({"body": "hello"}))
        frame = ws.receive_json()

    assert frame["type"] == "message"
    assert frame["data"]["body"] == "hello"
    assert frame["data"]["id"] == str(MESSAGE_ID)
    assert service.created_messages == [(ROOM_ID, ISSUER, SUBJECT, "hello")]
    # The sender is disconnected when the context manager closes the socket.
    assert manager.room_connection_count(ROOM_ID) == 0


def test_ws_rejects_malformed_json_with_error_frame(client, api_key, monkeypatch) -> None:
    _install_fake_service(client, FakeChatService())
    monkeypatch.setattr(
        "apps.api.app.routers.community_chat._identity_from_token",
        lambda token, settings: (ISSUER, SUBJECT),
    )

    with client.websocket_connect(f"/api/v1/community/chat/rooms/{ROOM_ID}/ws?token=valid") as ws:
        ws.send_text("not-json")
        frame = ws.receive_json()

    assert frame["type"] == "error"
    assert frame["error"]["code"] == "INVALID_JSON"


def test_ws_rejects_empty_body_with_error_frame(client, api_key, monkeypatch) -> None:
    _install_fake_service(client, FakeChatService())
    monkeypatch.setattr(
        "apps.api.app.routers.community_chat._identity_from_token",
        lambda token, settings: (ISSUER, SUBJECT),
    )

    with client.websocket_connect(f"/api/v1/community/chat/rooms/{ROOM_ID}/ws?token=valid") as ws:
        ws.send_text(json.dumps({"body": "   "}))
        frame = ws.receive_json()

    assert frame["type"] == "error"
    assert frame["error"]["code"] == "INVALID_MESSAGE"
