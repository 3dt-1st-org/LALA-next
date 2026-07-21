from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

import pytest

from apps.api.app.core.config import Settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.services.identity_repository import (
    DeletedIdentityError,
    IdentityRepository,
    PendingDeletionError,
)
from apps.api.app.services.identity_service import IdentityService

USER_ID = UUID("00000000-0000-0000-0000-000000000001")
CREATED_AT = datetime(2026, 7, 10, tzinfo=UTC)


class FakeCursor:
    def __init__(self, rows: list[tuple | None], executed: list[tuple[str, tuple]]) -> None:
        self.rows = rows
        self.executed = executed

    def __enter__(self) -> FakeCursor:
        return self

    def __exit__(self, *args) -> None:
        return None

    def execute(self, sql: str, params: tuple) -> None:
        self.executed.append((sql, params))

    def fetchone(self) -> tuple | None:
        return self.rows.pop(0)


class FakeConnection:
    def __init__(self, rows: list[tuple | None], executed: list[tuple[str, tuple]]) -> None:
        self.rows = rows
        self.executed = executed

    def __enter__(self) -> FakeConnection:
        return self

    def __exit__(self, *args) -> None:
        return None

    def cursor(self) -> FakeCursor:
        return FakeCursor(self.rows, self.executed)

    def close(self) -> None:
        return None


def test_provision_user_uses_atomic_upsert_and_returns_existing_user() -> None:
    executed: list[tuple[str, tuple]] = []
    row = (USER_ID, "https://issuer.example", "subject-1", "active", CREATED_AT, CREATED_AT, None)
    repository = IdentityRepository(
        Settings(db_dsn="postgresql://redacted"),
        connect=lambda **kwargs: FakeConnection([None, row], executed),
    )

    user = repository.provision_user("https://issuer.example", "subject-1")

    assert user.id == USER_ID
    assert user.status == "active"
    assert len(executed) == 3
    assert "pg_advisory_xact_lock" in executed[0][0]
    assert "FROM identity.deleted_users" in executed[1][0]
    assert "INSERT INTO identity.users" in executed[2][0]
    assert "ON CONFLICT (issuer, subject) DO UPDATE" in executed[2][0]
    assert "last_seen_at = now()" in executed[2][0]
    assert executed[2][1] == ("https://issuer.example", "subject-1")


def test_provision_user_rejects_a_deleting_row_without_reactivating_it() -> None:
    executed: list[tuple[str, tuple]] = []
    deleting_row = (
        USER_ID,
        "https://issuer.example",
        "subject-1",
        "deleting",
        CREATED_AT,
        CREATED_AT,
        CREATED_AT,
    )
    rows = [None, None, deleting_row]
    repository = IdentityRepository(
        Settings(db_dsn="postgresql://redacted"),
        connect=lambda **kwargs: FakeConnection(rows, executed),
    )

    with pytest.raises(PendingDeletionError):
        repository.provision_user("https://issuer.example", "subject-1")

    assert "status = 'active'" in executed[2][0]
    assert "SET status" not in executed[2][0]


def test_provision_user_rejects_tombstoned_identity_before_upsert() -> None:
    executed: list[tuple[str, tuple]] = []
    repository = IdentityRepository(
        Settings(db_dsn="postgresql://redacted"),
        connect=lambda **kwargs: FakeConnection([(1,)], executed),
    )

    with pytest.raises(DeletedIdentityError):
        repository.provision_user("https://issuer.example", "subject-1")

    assert "pg_advisory_xact_lock" in executed[0][0]
    assert "FROM identity.deleted_users" in executed[1][0]
    assert all("INSERT INTO identity.users" not in sql for sql, _ in executed)


def test_finalize_user_deletion_atomically_removes_user_and_inserts_digest_tombstone() -> None:
    executed: list[tuple[str, tuple]] = []
    connect_calls: list[dict] = []

    def connect(**kwargs):
        connect_calls.append(kwargs)
        return FakeConnection([(USER_ID,)], executed)

    repository = IdentityRepository(
        Settings(db_dsn="postgresql://redacted"),
        connect=connect,
    )

    assert repository.finalize_user_deletion("https://issuer.example", "subject-1") is True

    assert len(connect_calls) == 1
    assert "pg_advisory_xact_lock" in executed[0][0]
    assert "DELETE FROM identity.users" in executed[1][0]
    assert "INSERT INTO identity.deleted_users" in executed[2][0]
    assert "ON CONFLICT (identity_digest) DO NOTHING" in executed[2][0]
    digest = executed[2][1][0]
    assert isinstance(digest, bytes)
    assert len(digest) == 32
    assert b"issuer.example" not in digest
    assert b"subject-1" not in digest
    expected_lock_key = int.from_bytes(digest[:8], byteorder="big", signed=True)
    assert executed[0][1] == (expected_lock_key,)


def test_finalize_user_deletion_is_idempotent_when_local_user_is_missing() -> None:
    executed: list[tuple[str, tuple]] = []
    repository = IdentityRepository(
        Settings(db_dsn="postgresql://redacted"),
        connect=lambda **kwargs: FakeConnection([None], executed),
    )

    assert repository.finalize_user_deletion("https://issuer.example", "subject-1") is False

    assert "INSERT INTO identity.deleted_users" in executed[-1][0]


def test_mark_and_delete_are_retry_safe_for_missing_users() -> None:
    executed: list[tuple[str, tuple]] = []
    repository = IdentityRepository(
        Settings(db_dsn="postgresql://redacted"),
        connect=lambda **kwargs: FakeConnection([None, None], executed),
    )

    assert repository.mark_user_deleting("https://issuer.example", "subject-1") is None
    assert repository.finalize_user_deletion("https://issuer.example", "subject-1") is False
    assert all("INSERT INTO identity.users" not in sql for sql, _ in executed)


def test_identity_service_returns_safe_gone_error_for_tombstoned_identity() -> None:
    class DeletedRepository:
        def provision_user(self, issuer: str, subject: str):
            raise DeletedIdentityError()

    with pytest.raises(ServiceError) as exc_info:
        IdentityService(DeletedRepository()).provision_user(
            "https://issuer.example",
            "subject-1",
        )

    assert exc_info.value.status_code == 410
    assert exc_info.value.code == "ACCOUNT_DELETED"
    assert exc_info.value.retryable is False
    assert "issuer.example" not in str(exc_info.value)
    assert "subject-1" not in str(exc_info.value)
