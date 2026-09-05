from __future__ import annotations

import asyncio
import json
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import pytest
from fastapi import WebSocketDisconnect

from apps.api.app.core.auth import RequestIdentity, require_client_auth, require_oauth_identity
from apps.api.app.core.config import Settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.routers.community_chat import (
    ConnectionManager,
    manager,
)
from apps.api.app.services.community_chat_service import (
    FANOUT_CHANNEL,
    WS_TICKET_TTL_SECONDS,
    CommunityChatRepository,
    CommunityChatRepositoryUnavailable,
    CommunityChatService,
    canonical_request_hash,
    get_community_chat_service,
)
from apps.api.app.services.community_idempotency import (
    validate_idempotency_key,
)

ROOM_ID = UUID("00000000-0000-0000-0000-000000000010")
OTHER_ROOM_ID = UUID("00000000-0000-0000-0000-000000000099")
MESSAGE_ID = UUID("00000000-0000-0000-0000-000000000011")
AUTHOR_ID = UUID("00000000-0000-0000-0000-000000000012")
MEMBER_USER_ID = UUID("00000000-0000-0000-0000-000000000013")
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


def _room_row(visibility: str = "public") -> dict[str, Any]:
    return {
        "id": ROOM_ID,
        "name": "general",
        "visibility": visibility,
        "created_at": NOW,
    }


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
    manager.reset_delivery_dedup_for_tests()
    yield
    manager._rooms.clear()
    manager.reset_delivery_dedup_for_tests()


# ===========================================================================
# Idempotency helper contract.
# ===========================================================================


def test_canonical_request_hash_is_order_insensitive_and_stable() -> None:
    first = canonical_request_hash({"room_id": "r", "body": "b"})
    second = canonical_request_hash({"body": "b", "room_id": "r"})

    assert first == second
    assert len(first) == 64
    assert first != canonical_request_hash({"room_id": "r", "body": "other"})


def test_validate_idempotency_key_bounds_and_rejects_control_characters() -> None:
    assert validate_idempotency_key(None) is None
    assert validate_idempotency_key("  ok-key-1  ") == "ok-key-1"
    for bad in ("", "   ", "x" * 201, "bad\x00key", "bad\nkey"):
        with pytest.raises(Exception) as exc_info:
            validate_idempotency_key(bad)
        assert getattr(exc_info.value, "code", None) == "IDEMPOTENCY_KEY_INVALID"


# ===========================================================================
# Repository: SQL generation + row shaping (no real database).
# ===========================================================================


def test_list_rooms_filters_by_visibility_and_viewer_membership() -> None:
    repository, executed = _repo([{"count": 1}, _room_row()])

    rows, total = repository.list_rooms(
        limit=20, offset=0, viewer_issuer=ISSUER, viewer_subject=SUBJECT
    )

    assert total == 1
    assert rows == [_room_row()]
    assert "r.visibility = 'public'" in executed[0][0]
    assert "community.chat_room_members" in executed[0][0]
    viewer_params = executed[0][1]
    assert len(viewer_params) == 5
    assert "ORDER BY r.created_at DESC" in executed[1][0]
    assert executed[1][1][-2:] == (20, 0)


def test_create_room_public_records_creator_without_membership_row() -> None:
    repository, executed = _repo([_room_row("public")])

    row = repository.create_room(
        name="general", visibility="public", issuer=ISSUER, subject=SUBJECT
    )

    assert row == _room_row("public")
    sql, params = executed[0]
    assert "INSERT INTO community.chat_rooms" in sql
    assert "visibility" in sql
    assert params == ("general", "public", ISSUER, SUBJECT)
    assert not any("chat_room_members" in sql for sql, _ in executed[1:])


def test_create_room_private_writes_owner_membership_same_transaction() -> None:
    repository, executed = _repo([_room_row("private")])

    repository.create_room(name="secret", visibility="private", issuer=ISSUER, subject=SUBJECT)

    member_sql, member_params = executed[1]
    assert "INSERT INTO community.chat_room_members" in member_sql
    assert "'owner'" in member_sql
    assert member_params[:3] == (str(ROOM_ID), ISSUER, SUBJECT)


def test_room_access_returns_none_for_inaccessible_or_missing() -> None:
    repository, executed = _repo([None])

    assert repository.room_access(room_id=ROOM_ID, viewer_issuer=None, viewer_subject=None) is None
    assert "r.visibility = 'public'" in executed[0][0]


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


def test_create_message_is_access_guarded_and_emits_fanout_notify() -> None:
    repository, executed = _repo([_inserted_message_row(), {"id": AUTHOR_ID}])

    row = repository.create_message(room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT, body="hello")

    assert row["author_user_id"] == AUTHOR_ID
    insert_sql, insert_params = executed[0]
    assert "INSERT INTO community.chat_messages" in insert_sql
    assert "FROM community.chat_rooms r" in insert_sql
    assert "r.visibility = 'public'" in insert_sql
    assert "community.chat_room_members" in insert_sql
    assert insert_params == (
        str(ROOM_ID),
        ISSUER,
        SUBJECT,
        "hello",
        str(ROOM_ID),
        ISSUER,
        ISSUER,
        SUBJECT,
        ISSUER,
        SUBJECT,
    )
    notify_sql, notify_params = executed[2]
    assert "pg_notify" in notify_sql
    assert notify_params[0] == FANOUT_CHANNEL
    payload = json.loads(notify_params[1])
    assert payload == {"room_id": str(ROOM_ID), "message_id": str(MESSAGE_ID)}


def test_create_message_returns_none_when_access_denied() -> None:
    repository, _executed = _repo([None])

    assert (
        repository.create_message(room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT, body="hello")
        is None
    )


def test_create_message_idempotent_created_path_claims_stores_and_notifies() -> None:
    repository, executed = _repo(
        [
            {"idempotency_key": "key-1"},  # claim
            _inserted_message_row(),  # guarded insert
            {"id": AUTHOR_ID},  # author resolve
        ]
    )
    request_hash = canonical_request_hash({"room_id": str(ROOM_ID), "body": "hello"})

    result = repository.create_message_idempotent(
        room_id=ROOM_ID,
        issuer=ISSUER,
        subject=SUBJECT,
        body="hello",
        idempotency_key="key-1",
    )

    assert result["outcome"] == "created"
    assert result["message"]["id"] == str(MESSAGE_ID)
    assert result["message"]["author_user_id"] == str(AUTHOR_ID)
    purge_sql, purge_params = executed[0]
    assert "DELETE FROM community.idempotency_keys" in purge_sql
    assert purge_params == ("community.chat.message.create", ISSUER, SUBJECT)
    claim_sql, claim_params = executed[1]
    assert "ON CONFLICT (scope, actor_issuer, actor_subject, idempotency_key)" in claim_sql
    assert "DO NOTHING" in claim_sql
    assert "'null'::jsonb" in claim_sql
    assert claim_params[4] == request_hash
    assert claim_params[5] == 24 * 60 * 60
    store_sql, store_params = executed[4]
    assert "UPDATE community.idempotency_keys" in store_sql
    assert "SET response_json = %s::jsonb" in store_sql
    assert json.loads(store_params[0])["id"] == str(MESSAGE_ID)
    notify_sql, notify_params = executed[5]
    assert "pg_notify" in notify_sql


def test_create_message_idempotent_replays_committed_response() -> None:
    stored = {
        "id": str(MESSAGE_ID),
        "room_id": str(ROOM_ID),
        "author_user_id": str(AUTHOR_ID),
        "body": "hello",
        "created_at": NOW.isoformat(),
    }
    request_hash = canonical_request_hash({"room_id": str(ROOM_ID), "body": "hello"})
    repository, executed = _repo(
        [
            None,  # claim loses (concurrent winner committed first)
            {"request_hash": request_hash, "response_json": stored},
        ]
    )

    result = repository.create_message_idempotent(
        room_id=ROOM_ID,
        issuer=ISSUER,
        subject=SUBJECT,
        body="hello",
        idempotency_key="key-1",
    )

    assert result["outcome"] == "replayed"
    assert result["message"] == stored
    # No message insert, no notify: the replay must not create anything.
    assert not any("INSERT INTO community.chat_messages" in sql for sql, _ in executed)
    assert not any("pg_notify" in sql for sql, _ in executed)


def test_create_message_idempotent_conflicts_on_different_payload() -> None:
    request_hash = canonical_request_hash({"room_id": str(ROOM_ID), "body": "hello"})
    repository, executed = _repo(
        [
            None,  # claim loses
            {"request_hash": request_hash, "response_json": {}},
        ]
    )

    result = repository.create_message_idempotent(
        room_id=ROOM_ID,
        issuer=ISSUER,
        subject=SUBJECT,
        body="different body",
        idempotency_key="key-1",
    )

    assert result == {"outcome": "conflict", "message": None}
    assert not any("INSERT INTO community.chat_messages" in sql for sql, _ in executed)


def test_create_message_idempotent_denied_path_releases_the_claim() -> None:
    repository, executed = _repo(
        [
            {"idempotency_key": "key-1"},  # claim
            None,  # guarded insert denied (room inaccessible)
        ]
    )

    result = repository.create_message_idempotent(
        room_id=ROOM_ID,
        issuer=ISSUER,
        subject=SUBJECT,
        body="hello",
        idempotency_key="key-1",
    )

    assert result == {"outcome": "denied", "message": None}
    release_sql, release_params = executed[3]
    assert "DELETE FROM community.idempotency_keys" in release_sql
    assert "response_json = 'null'::jsonb" in release_sql
    assert release_params[3] == "key-1"
    assert not any("pg_notify" in sql for sql, _ in executed)


def test_issue_ws_ticket_stores_only_sha256_digest() -> None:
    repository, executed = _repo([{"expires_at": NOW}])

    row = repository.issue_ws_ticket(
        room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT, ttl_seconds=WS_TICKET_TTL_SECONDS
    )

    assert row["ticket"] and len(row["ticket"]) >= 40
    assert row["expires_at"] == NOW
    purge_sql, purge_params = executed[0]
    assert "DELETE FROM community.chat_ws_tickets" in purge_sql
    assert purge_params == (ISSUER, SUBJECT)
    insert_sql, insert_params = executed[1]
    assert "INSERT INTO community.chat_ws_tickets" in insert_sql
    import hashlib

    assert insert_params[0] == hashlib.sha256(row["ticket"].encode()).hexdigest()
    assert len(insert_params[0]) == 64
    assert insert_params[3:] == (SUBJECT, WS_TICKET_TTL_SECONDS)


def test_claim_ws_ticket_single_use_update_and_access_recheck() -> None:
    repository, executed = _repo(
        [
            {"room_id": ROOM_ID, "issuer": ISSUER, "subject": SUBJECT},
            _room_row(),
        ]
    )

    claim = repository.claim_ws_ticket(ticket="raw-ticket", room_id=ROOM_ID)

    assert claim == {"issuer": ISSUER, "subject": SUBJECT}
    claim_sql, claim_params = executed[0]
    assert "UPDATE community.chat_ws_tickets" in claim_sql
    assert "SET used_at = now()" in claim_sql
    assert "used_at IS NULL" in claim_sql
    assert "expires_at > now()" in claim_sql
    assert claim_params[0] != "raw-ticket"  # only the digest is bound
    assert "community.chat_room_members" in executed[1][0]  # access re-check


def test_claim_ws_ticket_rejects_used_expired_or_malformed() -> None:
    repository, _executed = _repo([None])
    assert repository.claim_ws_ticket(ticket="raw", room_id=ROOM_ID) is None

    repository2, _executed2 = _repo(
        [{"room_id": OTHER_ROOM_ID, "issuer": ISSUER, "subject": SUBJECT}]
    )
    assert repository2.claim_ws_ticket(ticket="raw", room_id=ROOM_ID) is None

    repository3, _executed3 = _repo([])
    long_ticket = "x" * 513
    assert repository3.claim_ws_ticket(ticket=long_ticket, room_id=ROOM_ID) is None
    assert repository3.claim_ws_ticket(ticket="", room_id=ROOM_ID) is None


def test_fetch_message_for_fanout_selects_by_id() -> None:
    repository, executed = _repo([_message_row()])

    row = repository.fetch_message_for_fanout(message_id=MESSAGE_ID)

    assert row["id"] == MESSAGE_ID
    assert "WHERE m.id = %s" in executed[0][0]
    assert executed[0][1] == (str(MESSAGE_ID),)


def test_repository_without_dsn_is_unavailable() -> None:
    repository = CommunityChatRepository(Settings(db_dsn=""))

    with pytest.raises(CommunityChatRepositoryUnavailable):
        repository.list_rooms(limit=1, offset=0, viewer_issuer=None, viewer_subject=None)


# ===========================================================================
# Service: error mapping + payload shaping.
# ===========================================================================


class _UnavailableRepository:
    def list_rooms(self, **_: Any) -> tuple[list[dict[str, Any]], int]:
        raise CommunityChatRepositoryUnavailable()

    def create_room(self, **_: Any) -> dict[str, Any]:
        raise CommunityChatRepositoryUnavailable()

    def room_access(self, **_: Any) -> dict[str, Any] | None:
        raise CommunityChatRepositoryUnavailable()

    def add_room_member(self, **_: Any) -> dict[str, Any]:
        raise CommunityChatRepositoryUnavailable()

    def list_messages(self, **_: Any) -> tuple[list[dict[str, Any]], int]:
        raise CommunityChatRepositoryUnavailable()

    def create_message(self, **_: Any) -> dict[str, Any] | None:
        raise CommunityChatRepositoryUnavailable()

    def create_message_idempotent(self, **_: Any) -> dict[str, Any]:
        raise CommunityChatRepositoryUnavailable()

    def issue_ws_ticket(self, **_: Any) -> dict[str, Any]:
        raise CommunityChatRepositoryUnavailable()

    def claim_ws_ticket(self, **_: Any) -> dict[str, Any] | None:
        raise CommunityChatRepositoryUnavailable()

    def fetch_message_for_fanout(self, **_: Any) -> dict[str, Any] | None:
        raise CommunityChatRepositoryUnavailable()


def test_service_maps_repository_unavailability_to_retryable_503() -> None:
    service = CommunityChatService(_UnavailableRepository())

    with pytest.raises(ServiceError) as exc_info:
        service.list_rooms(limit=1, offset=0)

    assert exc_info.value.status_code == 503
    assert exc_info.value.code == "COMMUNITY_CHAT_DB_UNAVAILABLE"
    assert exc_info.value.retryable is True


def test_service_create_message_maps_denied_to_indistinguishable_404() -> None:
    class DeniedRepository(_UnavailableRepository):
        def create_message(self, **_: Any) -> dict[str, Any] | None:
            return None

    service = CommunityChatService(DeniedRepository())

    with pytest.raises(ServiceError) as exc_info:
        service.create_message(room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT, body="hi")

    assert exc_info.value.status_code == 404
    assert exc_info.value.code == "COMMUNITY_CHAT_ROOM_NOT_FOUND"


def test_service_create_message_maps_idempotent_conflict_to_409() -> None:
    class ConflictRepository(_UnavailableRepository):
        def create_message_idempotent(self, **_: Any) -> dict[str, Any]:
            return {"outcome": "conflict", "message": None}

    service = CommunityChatService(ConflictRepository())

    with pytest.raises(ServiceError) as exc_info:
        service.create_message(
            room_id=ROOM_ID,
            issuer=ISSUER,
            subject=SUBJECT,
            body="hi",
            idempotency_key="key",
        )

    assert exc_info.value.status_code == 409
    assert exc_info.value.code == "IDEMPOTENCY_KEY_CONFLICT"
    assert exc_info.value.retryable is False


def test_service_create_message_replays_stored_response_verbatim() -> None:
    stored = {
        "id": str(MESSAGE_ID),
        "room_id": str(ROOM_ID),
        "author_user_id": str(AUTHOR_ID),
        "body": "hello",
        "created_at": NOW.isoformat(),
    }

    class ReplayRepository(_UnavailableRepository):
        def create_message_idempotent(self, **_: Any) -> dict[str, Any]:
            return {"outcome": "replayed", "message": dict(stored)}

    service = CommunityChatService(ReplayRepository())

    payload = service.create_message(
        room_id=ROOM_ID,
        issuer=ISSUER,
        subject=SUBJECT,
        body="hello",
        idempotency_key="key",
    )

    assert payload == stored


def test_service_list_messages_hides_private_rooms_behind_404() -> None:
    class NoAccessRepository(_UnavailableRepository):
        def room_access(self, **_: Any) -> dict[str, Any] | None:
            return None

    service = CommunityChatService(NoAccessRepository())

    with pytest.raises(ServiceError) as exc_info:
        service.list_messages(room_id=ROOM_ID, limit=10, offset=0)

    assert exc_info.value.status_code == 404
    assert exc_info.value.code == "COMMUNITY_CHAT_ROOM_NOT_FOUND"


def test_service_list_messages_returns_messages_for_accessible_room() -> None:
    class AccessRepository(_UnavailableRepository):
        def room_access(self, **_: Any) -> dict[str, Any] | None:
            return _room_row()

        def list_messages(self, **kwargs: Any) -> tuple[list[dict[str, Any]], int]:
            return ([_message_row()], 1)

    service = CommunityChatService(AccessRepository())

    payload = service.list_messages(
        room_id=ROOM_ID, limit=50, offset=0, viewer_issuer=ISSUER, viewer_subject=SUBJECT
    )

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


def test_service_issue_ws_ticket_checks_access_before_minting() -> None:
    class TicketRepository(_UnavailableRepository):
        def __init__(self, room: dict[str, Any] | None) -> None:
            self.room = room
            self.minted = False

        def room_access(self, **_: Any) -> dict[str, Any] | None:
            return self.room

        def issue_ws_ticket(self, **kwargs: Any) -> dict[str, Any]:
            self.minted = True
            return {
                "ticket": "raw-ticket",
                "room_id": str(kwargs["room_id"]),
                "expires_at": NOW,
            }

    denied = TicketRepository(None)
    with pytest.raises(ServiceError) as exc_info:
        CommunityChatService(denied).issue_ws_ticket(
            room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT
        )
    assert exc_info.value.status_code == 404
    assert denied.minted is False

    allowed = TicketRepository(_room_row("private"))
    payload = CommunityChatService(allowed).issue_ws_ticket(
        room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT
    )
    assert payload["ticket"] == "raw-ticket"
    assert payload["room_id"] == str(ROOM_ID)
    assert payload["expires_at"] == NOW.isoformat()


@pytest.mark.parametrize(
    ("outcome", "status", "code"),
    [
        ("missing_room", 404, "COMMUNITY_CHAT_ROOM_NOT_FOUND"),
        ("not_owner", 404, "COMMUNITY_CHAT_ROOM_NOT_FOUND"),
        ("not_private", 422, "COMMUNITY_CHAT_ROOM_NOT_PRIVATE"),
        ("missing_member", 404, "COMMUNITY_CHAT_MEMBER_USER_NOT_FOUND"),
    ],
)
def test_service_add_room_member_maps_governed_outcomes(
    outcome: str, status: int, code: str
) -> None:
    class OutcomeRepository(_UnavailableRepository):
        def add_room_member(self, **_: Any) -> dict[str, Any]:
            return {"outcome": outcome}

    service = CommunityChatService(OutcomeRepository())

    with pytest.raises(ServiceError) as exc_info:
        service.add_room_member(
            room_id=ROOM_ID,
            member_user_id=MEMBER_USER_ID,
            owner_issuer=ISSUER,
            owner_subject=SUBJECT,
        )

    assert exc_info.value.status_code == status
    assert exc_info.value.code == code


def test_service_add_room_member_reports_added_state() -> None:
    class AddedRepository(_UnavailableRepository):
        def add_room_member(self, **_: Any) -> dict[str, Any]:
            return {"outcome": "already_member"}

    payload = CommunityChatService(AddedRepository()).add_room_member(
        room_id=ROOM_ID,
        member_user_id=MEMBER_USER_ID,
        owner_issuer=ISSUER,
        owner_subject=SUBJECT,
    )

    assert payload == {
        "room_id": str(ROOM_ID),
        "member_user_id": str(MEMBER_USER_ID),
        "added": False,
    }


def test_service_shapes_room_payload_with_visibility() -> None:
    class StubRepository(_UnavailableRepository):
        def list_rooms(self, **kwargs: Any) -> tuple[list[dict[str, Any]], int]:
            return ([_room_row("private")], 1)

    payload = CommunityChatService(StubRepository()).list_rooms(limit=1, offset=0)

    assert payload == {
        "count": 1,
        "total": 1,
        "rooms": [
            {
                "id": str(ROOM_ID),
                "name": "general",
                "visibility": "private",
                "created_at": NOW.isoformat(),
            }
        ],
    }


# ===========================================================================
# ConnectionManager: connect / broadcast / dedup / caps (no ASGI stack).
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
        assert cm.actor_connection_count(ISSUER, SUBJECT) == 1

    asyncio.run(run())


def test_connection_manager_broadcast_once_delivers_each_message_exactly_once() -> None:
    async def run() -> None:
        cm = ConnectionManager()
        ws = MockWebSocket()
        await cm.connect(ws, room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT)
        frame = {
            "type": "message",
            "data": {"id": str(MESSAGE_ID), "body": "hello"},
        }

        await cm.broadcast_once(room_id=ROOM_ID, payload=frame)
        await cm.broadcast_once(room_id=ROOM_ID, payload=frame)

        assert ws.sent == [frame]

    asyncio.run(run())


def test_connection_manager_dedup_is_bounded() -> None:
    cm = ConnectionManager()
    for index in range(300):
        assert cm._claim_delivery(f"m{index}") is True
    assert len(cm._recent_id_set) == 256
    assert cm._claim_delivery("m0") is True  # evicted id is re-claimable again
    assert cm._claim_delivery("m299") is False


def test_connection_manager_broadcast_fans_out_to_room_only() -> None:
    async def run() -> None:
        cm = ConnectionManager()
        ws_a = MockWebSocket()
        ws_b = MockWebSocket()
        ws_other = MockWebSocket()
        await cm.connect(ws_a, room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT)
        await cm.connect(ws_b, room_id=ROOM_ID, issuer="https://o", subject="o")
        await cm.connect(ws_other, room_id=OTHER_ROOM_ID, issuer="https://x", subject="x")

        await cm.broadcast(room_id=ROOM_ID, payload={"type": "message", "data": {}})

        assert ws_a.sent == [{"type": "message", "data": {}}]
        assert ws_b.sent == [{"type": "message", "data": {}}]
        assert ws_other.sent == []

    asyncio.run(run())


def test_connection_manager_actor_connection_count_spans_rooms() -> None:
    async def run() -> None:
        cm = ConnectionManager()
        await cm.connect(MockWebSocket(), room_id=ROOM_ID, issuer=ISSUER, subject=SUBJECT)
        await cm.connect(MockWebSocket(), room_id=OTHER_ROOM_ID, issuer=ISSUER, subject=SUBJECT)
        await cm.connect(MockWebSocket(), room_id=ROOM_ID, issuer="https://o", subject="o")

        assert cm.actor_connection_count(ISSUER, SUBJECT) == 2

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


# ===========================================================================
# Router (REST): auth gating + envelope contract.
# ===========================================================================


class FakeChatService:
    def __init__(self) -> None:
        self.created_rooms: list[dict[str, Any]] = []
        self.created_messages: list[dict[str, Any]] = []
        self.issued_tickets: list[UUID] = []
        self.claimed_tickets: list[str] = []
        self.added_members: list[dict[str, Any]] = []
        self.list_rooms_viewers: list[tuple[str | None, str | None]] = []
        self.list_messages_viewers: list[tuple[str | None, str | None]] = []

    def list_rooms(self, **kwargs: Any) -> dict[str, Any]:
        self.list_rooms_viewers.append((kwargs.get("viewer_issuer"), kwargs.get("viewer_subject")))
        return {
            "count": 1,
            "total": 1,
            "rooms": [
                {
                    "id": str(ROOM_ID),
                    "name": "general",
                    "visibility": "public",
                    "created_at": NOW.isoformat(),
                }
            ],
        }

    def create_room(self, **kwargs: Any) -> dict[str, Any]:
        self.created_rooms.append(dict(kwargs))
        return {
            "id": str(ROOM_ID),
            "name": kwargs["name"],
            "visibility": kwargs["visibility"],
            "created_at": NOW.isoformat(),
        }

    def room_access(self, **kwargs: Any) -> dict[str, Any] | None:
        return _room_row()

    def add_room_member(self, **kwargs: Any) -> dict[str, Any]:
        self.added_members.append(dict(kwargs))
        return {
            "room_id": str(kwargs["room_id"]),
            "member_user_id": str(kwargs["member_user_id"]),
            "added": True,
        }

    def list_messages(self, **kwargs: Any) -> dict[str, Any]:
        self.list_messages_viewers.append(
            (kwargs.get("viewer_issuer"), kwargs.get("viewer_subject"))
        )
        return {"count": 0, "total": 0, "messages": []}

    def create_message(self, **kwargs: Any) -> dict[str, Any]:
        self.created_messages.append(dict(kwargs))
        return {
            "id": str(MESSAGE_ID),
            "room_id": str(kwargs["room_id"]),
            "author_user_id": str(AUTHOR_ID),
            "body": kwargs["body"],
            "created_at": NOW.isoformat(),
        }

    def issue_ws_ticket(self, **kwargs: Any) -> dict[str, Any]:
        self.issued_tickets.append(kwargs["room_id"])
        return {
            "room_id": str(kwargs["room_id"]),
            "ticket": "issued-ticket",
            "expires_at": NOW.isoformat(),
        }

    def claim_ws_ticket(self, **kwargs: Any) -> dict[str, Any] | None:
        self.claimed_tickets.append(kwargs["ticket"])
        if kwargs["ticket"] != "valid-ticket":
            return None
        return {"issuer": ISSUER, "subject": SUBJECT}

    def fetch_message_for_fanout(self, **kwargs: Any) -> dict[str, Any] | None:
        return None


def _oauth_identity() -> RequestIdentity:
    return RequestIdentity(mode="oauth", issuer=ISSUER, subject=SUBJECT)


def _guest_identity() -> RequestIdentity:
    return RequestIdentity(mode="public")


def _install_fake_service(client, service: FakeChatService) -> None:
    client.app.dependency_overrides[get_community_chat_service] = lambda: service


def test_list_rooms_is_guest_readable_and_passes_guest_viewer(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_client_auth] = _guest_identity

    response = client.get("/api/v1/community/chat/rooms", headers={"X-API-Key": api_key})

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["error"] is None
    assert body["data"]["count"] == 1
    assert body["data"]["rooms"][0]["visibility"] == "public"
    assert body["meta"]["source"] == "db"
    assert service.list_rooms_viewers == [(None, None)]


def test_list_rooms_passes_verified_oauth_viewer_not_client_claims(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_client_auth] = _oauth_identity

    response = client.get("/api/v1/community/chat/rooms", headers={"X-API-Key": api_key})

    assert response.status_code == 200
    assert service.list_rooms_viewers == [(ISSUER, SUBJECT)]


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


def test_create_room_defaults_to_public_and_records_creator(client, api_key) -> None:
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
    assert data["visibility"] == "public"
    assert service.created_rooms == [
        {
            "name": "travel",
            "visibility": "public",
            "issuer": ISSUER,
            "subject": SUBJECT,
        }
    ]


def test_create_room_accepts_private_visibility(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        "/api/v1/community/chat/rooms",
        headers={"X-API-Key": api_key},
        json={"name": "secret", "visibility": "private"},
    )

    assert response.status_code == 200
    assert response.json()["data"]["visibility"] == "private"
    assert service.created_rooms[0]["visibility"] == "private"


def test_create_room_rejects_unknown_visibility(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        "/api/v1/community/chat/rooms",
        headers={"X-API-Key": api_key},
        json={"name": "bad", "visibility": "hidden"},
    )

    assert response.status_code == 422
    assert service.created_rooms == []


def test_list_messages_returns_envelope_with_viewer_scope(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_client_auth] = _guest_identity

    response = client.get(
        f"/api/v1/community/chat/rooms/{ROOM_ID}/messages",
        headers={"X-API-Key": api_key},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"] == {"count": 0, "total": 0, "messages": []}
    assert body["meta"]["total"] == 0
    assert service.list_messages_viewers == [(None, None)]


def test_rest_send_message_requires_oauth(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)

    response = client.post(
        f"/api/v1/community/chat/rooms/{ROOM_ID}/messages",
        headers={"X-API-Key": api_key},
        json={"body": "hello"},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "USER_AUTH_REQUIRED"
    assert service.created_messages == []


def test_rest_send_message_persists_and_returns_envelope(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        f"/api/v1/community/chat/rooms/{ROOM_ID}/messages",
        headers={"X-API-Key": api_key, "Idempotency-Key": "retry-1"},
        json={"body": "hello"},
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["body"] == "hello"
    assert data["id"] == str(MESSAGE_ID)
    assert service.created_messages == [
        {
            "room_id": ROOM_ID,
            "issuer": ISSUER,
            "subject": SUBJECT,
            "body": "hello",
            "idempotency_key": "retry-1",
        }
    ]


def test_rest_send_message_rejects_malformed_idempotency_key(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        f"/api/v1/community/chat/rooms/{ROOM_ID}/messages",
        headers={"X-API-Key": api_key, "Idempotency-Key": "x" * 201},
        json={"body": "hello"},
    )

    assert response.status_code == 400
    assert response.json()["error"]["code"] == "IDEMPOTENCY_KEY_INVALID"
    assert service.created_messages == []


def test_ws_ticket_requires_oauth_and_room_access(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)

    unauthenticated = client.post(
        f"/api/v1/community/chat/rooms/{ROOM_ID}/ws-ticket",
        headers={"X-API-Key": api_key},
    )
    assert unauthenticated.status_code == 401
    assert service.issued_tickets == []

    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity
    response = client.post(
        f"/api/v1/community/chat/rooms/{ROOM_ID}/ws-ticket",
        headers={"X-API-Key": api_key},
    )
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["ticket"] == "issued-ticket"
    assert data["room_id"] == str(ROOM_ID)
    assert data["expires_at"]
    assert service.issued_tickets == [ROOM_ID]


def test_ws_ticket_denial_is_indistinguishable_from_missing_room(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    def deny(**kwargs: Any) -> dict[str, Any]:
        raise ServiceError(
            status_code=404,
            code="COMMUNITY_CHAT_ROOM_NOT_FOUND",
            message="Chat room was not found.",
            retryable=False,
        )

    service.issue_ws_ticket = deny  # type: ignore[method-assign]
    response = client.post(
        f"/api/v1/community/chat/rooms/{ROOM_ID}/ws-ticket",
        headers={"X-API-Key": api_key},
    )

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "COMMUNITY_CHAT_ROOM_NOT_FOUND"


def test_add_room_member_owner_only_route(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        f"/api/v1/community/chat/rooms/{ROOM_ID}/members",
        headers={"X-API-Key": api_key},
        json={"member_user_id": str(MEMBER_USER_ID)},
    )

    assert response.status_code == 200
    assert response.json()["data"]["added"] is True
    assert service.added_members == [
        {
            "room_id": ROOM_ID,
            "member_user_id": MEMBER_USER_ID,
            "owner_issuer": ISSUER,
            "owner_subject": SUBJECT,
        }
    ]


# ===========================================================================
# Router (WebSocket): ticket handshake + real-time broadcast.
# ===========================================================================


def _ws_url(ticket: str = "valid-ticket") -> str:
    return f"/api/v1/community/chat/rooms/{ROOM_ID}/ws?ticket={ticket}"


def test_ws_rejects_handshake_when_ticket_missing(client, api_key) -> None:
    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(f"/api/v1/community/chat/rooms/{ROOM_ID}/ws") as ws:
            ws.receive_text()
    assert exc.value.code == 1008


def test_ws_rejects_handshake_when_ticket_oversized(client, api_key) -> None:
    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(_ws_url("x" * 513)) as ws:
            ws.receive_text()
    assert exc.value.code == 1008


def test_ws_rejects_handshake_when_ticket_unusable(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)

    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(_ws_url("used-or-expired")) as ws:
            ws.receive_text()

    assert exc.value.code == 1008
    assert service.claimed_tickets == ["used-or-expired"]
    assert manager.room_connection_count(ROOM_ID) == 0


def test_ws_rejects_cross_origin_browser_handshake(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)

    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(_ws_url(), headers={"origin": "https://evil.example"}) as ws:
            ws.receive_text()

    assert exc.value.code == 1008
    # The rejection happened before any ticket claim: authentication-adjacent
    # side effects run only after the origin policy passes.
    assert service.claimed_tickets == []


def test_ws_allows_same_origin_browser_handshake(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)

    with client.websocket_connect(
        _ws_url(), headers={"origin": "http://testserver", "host": "testserver"}
    ) as ws:
        ws.send_text(json.dumps({"body": "hello"}))
        frame = ws.receive_json()

    assert frame["type"] == "message"
    assert service.claimed_tickets == ["valid-ticket"]


def test_ws_close_1013_when_ticket_store_unavailable(client, api_key) -> None:
    service = FakeChatService()

    def unavailable(**kwargs: Any) -> dict[str, Any] | None:
        raise ServiceError(
            status_code=503,
            code="COMMUNITY_CHAT_DB_UNAVAILABLE",
            message="Community chat store is temporarily unavailable.",
            retryable=True,
        )

    service.claim_ws_ticket = unavailable  # type: ignore[method-assign]
    _install_fake_service(client, service)

    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(_ws_url()) as ws:
            ws.receive_text()

    assert exc.value.code == 1013


def test_ws_persists_and_broadcasts_message(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)

    with client.websocket_connect(_ws_url()) as ws:
        ws.send_text(json.dumps({"body": "hello"}))
        frame = ws.receive_json()

    assert frame["type"] == "message"
    assert frame["data"]["body"] == "hello"
    assert frame["data"]["id"] == str(MESSAGE_ID)
    assert service.created_messages == [
        {
            "room_id": ROOM_ID,
            "issuer": ISSUER,
            "subject": SUBJECT,
            "body": "hello",
            "idempotency_key": None,
        }
    ]
    assert manager.room_connection_count(ROOM_ID) == 0


def test_ws_frame_idempotency_key_reaches_the_service(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)

    with client.websocket_connect(_ws_url()) as ws:
        ws.send_text(json.dumps({"body": "hello", "idempotency_key": "frame-key-1"}))
        frame = ws.receive_json()

    assert frame["type"] == "message"
    assert service.created_messages[0]["idempotency_key"] == "frame-key-1"


def test_ws_rejects_oversized_frame_with_bounded_error(client, api_key) -> None:
    service = FakeChatService()
    _install_fake_service(client, service)

    with client.websocket_connect(_ws_url()) as ws:
        ws.send_text(json.dumps({"body": "a" * 9000}))
        frame = ws.receive_json()

    assert frame == {"type": "error", "error": {"code": "FRAME_TOO_LARGE"}}
    assert service.created_messages == []


def test_ws_rejects_malformed_json_with_error_frame(client, api_key) -> None:
    _install_fake_service(client, FakeChatService())

    with client.websocket_connect(_ws_url()) as ws:
        ws.send_text("not-json")
        frame = ws.receive_json()

    assert frame["type"] == "error"
    assert frame["error"]["code"] == "INVALID_JSON"


def test_ws_rejects_empty_body_with_error_frame(client, api_key) -> None:
    _install_fake_service(client, FakeChatService())

    with client.websocket_connect(_ws_url()) as ws:
        ws.send_text(json.dumps({"body": "   "}))
        frame = ws.receive_json()

    assert frame["type"] == "error"
    assert frame["error"]["code"] == "INVALID_MESSAGE"


def test_ws_bounded_idle_timeout_closes_normally(client, api_key, monkeypatch) -> None:
    from apps.api.app.routers import community_chat as chat_router

    monkeypatch.setattr(chat_router, "WS_IDLE_TIMEOUT_SECONDS", 0.05)
    _install_fake_service(client, FakeChatService())

    with pytest.raises(WebSocketDisconnect) as exc:
        with client.websocket_connect(_ws_url()) as ws:
            ws.receive_json()

    assert exc.value.code == 1000


# ===========================================================================
# Fanout bridge: notification handling without a thread or real database.
# ===========================================================================


class FakeFanoutFetcher:
    def __init__(self, message: dict[str, Any] | None) -> None:
        self.message = message
        self.fetched: list[UUID] = []

    def fetch_message_for_fanout(self, *, message_id: UUID) -> dict[str, Any] | None:
        self.fetched.append(message_id)
        return self.message


def _wire_payload() -> dict[str, Any]:
    """Wire-shaped message payload (what the service fetcher returns)."""

    return {
        "id": str(MESSAGE_ID),
        "room_id": str(ROOM_ID),
        "author_user_id": str(AUTHOR_ID),
        "body": "hello",
        "created_at": NOW.isoformat(),
    }


def test_fanout_handle_notification_delivers_committed_message() -> None:
    from apps.api.app.services.community_chat_fanout import ChatFanoutBridge

    scheduled: list[dict[str, Any]] = []
    fetcher = FakeFanoutFetcher(_wire_payload())
    bridge = ChatFanoutBridge(
        fetcher_factory=lambda: fetcher,
        deliver=lambda payload: scheduled.append(payload),
    )
    bridge._schedule_deliver = lambda payload: scheduled.append(payload)  # type: ignore[method-assign]

    result = bridge.handle_notification(
        json.dumps({"room_id": str(ROOM_ID), "message_id": str(MESSAGE_ID)})
    )

    assert result is not None
    assert result["id"] == str(MESSAGE_ID)
    assert fetcher.fetched == [MESSAGE_ID]
    assert scheduled == [_wire_payload()]


def test_fanout_handle_notification_ignores_malformed_payloads() -> None:
    from apps.api.app.services.community_chat_fanout import ChatFanoutBridge

    fetcher = FakeFanoutFetcher(_wire_payload())
    bridge = ChatFanoutBridge(fetcher_factory=lambda: fetcher, deliver=lambda payload: None)

    for payload in (
        "not-json",
        "[]",
        json.dumps({"room_id": "not-a-uuid", "message_id": str(MESSAGE_ID)}),
        json.dumps({"room_id": str(ROOM_ID)}),
    ):
        assert bridge.handle_notification(payload) is None
    assert fetcher.fetched == []


def test_fanout_handle_notification_skips_when_message_or_room_mismatch() -> None:
    from apps.api.app.services.community_chat_fanout import ChatFanoutBridge

    scheduled: list[dict[str, Any]] = []

    class RecordingBridge(ChatFanoutBridge):
        def _schedule_deliver(self, payload: dict[str, Any]) -> None:
            scheduled.append(payload)

    missing = RecordingBridge(
        fetcher_factory=lambda: FakeFanoutFetcher(None), deliver=lambda p: None
    )
    assert (
        missing.handle_notification(
            json.dumps({"room_id": str(ROOM_ID), "message_id": str(MESSAGE_ID)})
        )
        is None
    )

    mismatch_row = dict(_wire_payload(), room_id=str(OTHER_ROOM_ID))
    mismatch = RecordingBridge(
        fetcher_factory=lambda: FakeFanoutFetcher(mismatch_row), deliver=lambda p: None
    )
    assert (
        mismatch.handle_notification(
            json.dumps({"room_id": str(ROOM_ID), "message_id": str(MESSAGE_ID)})
        )
        is None
    )
    assert scheduled == []


def test_fanout_bridge_disabled_without_dsn() -> None:
    from apps.api.app.core.config import Settings
    from apps.api.app.services.community_chat_fanout import fanout_bridge_enabled

    assert fanout_bridge_enabled(Settings(db_dsn="")) is False
    assert fanout_bridge_enabled(Settings(db_dsn=DB_DSN)) is True
