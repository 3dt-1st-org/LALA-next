from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

import pytest

from apps.api.app.core.config import Settings
from apps.api.app.services.identity_repository import (
    IdentityRepository,
    PendingDeletionError,
)


USER_ID = UUID("00000000-0000-0000-0000-000000000001")
CREATED_AT = datetime(2026, 7, 10, tzinfo=UTC)


class FakeCursor:
    def __init__(self, rows: list[tuple | None], executed: list[tuple[str, tuple]]) -> None:
        self.rows = rows
        self.executed = executed

    def __enter__(self) -> "FakeCursor":
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

    def __enter__(self) -> "FakeConnection":
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
        connect=lambda **kwargs: FakeConnection([row], executed),
    )

    user = repository.provision_user("https://issuer.example", "subject-1")

    assert user.id == USER_ID
    assert user.status == "active"
    assert len(executed) == 1
    assert "INSERT INTO identity.users" in executed[0][0]
    assert "ON CONFLICT (issuer, subject) DO UPDATE" in executed[0][0]
    assert "last_seen_at = now()" in executed[0][0]
    assert executed[0][1] == ("https://issuer.example", "subject-1")


def test_provision_user_rejects_a_deleting_row_without_reactivating_it() -> None:
    executed: list[tuple[str, tuple]] = []
    deleting_row = (USER_ID, "https://issuer.example", "subject-1", "deleting", CREATED_AT, CREATED_AT, CREATED_AT)
    rows = [None, deleting_row]
    repository = IdentityRepository(
        Settings(db_dsn="postgresql://redacted"),
        connect=lambda **kwargs: FakeConnection(rows, executed),
    )

    with pytest.raises(PendingDeletionError):
        repository.provision_user("https://issuer.example", "subject-1")

    assert "status = 'active'" in executed[0][0]
    assert "SET status" not in executed[0][0]


def test_mark_and_delete_are_retry_safe_for_missing_users() -> None:
    executed: list[tuple[str, tuple]] = []
    repository = IdentityRepository(
        Settings(db_dsn="postgresql://redacted"),
        connect=lambda **kwargs: FakeConnection([None, None], executed),
    )

    assert repository.mark_user_deleting("https://issuer.example", "subject-1") is None
    assert repository.delete_local_user("https://issuer.example", "subject-1") is False
    assert all("INSERT INTO identity.users" not in sql for sql, _ in executed)
