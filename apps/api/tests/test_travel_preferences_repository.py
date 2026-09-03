from __future__ import annotations

import re
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pytest

from apps.api.app.core.config import Settings
from apps.api.app.services.travel_preferences_repository import (
    TravelPreferencesRepository,
    TravelPreferencesRevisionConflict,
)

UPDATED_AT = datetime(2026, 9, 2, tzinfo=UTC)
ROOT = Path(__file__).resolve().parents[3]
PREFERENCES_SQL = ROOT / "sql" / "canonical" / "065_user_travel_preferences.sql"


class _FakeCursor:
    def __init__(self, executed: list, rows: list[Any]) -> None:
        self._executed = executed
        self._rows = rows

    def __enter__(self) -> _FakeCursor:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def execute(self, sql: str, params: Any = None) -> None:
        self._executed.append((sql, params))

    def fetchone(self) -> Any:
        return self._rows.pop(0) if self._rows else None


class _FakeConnection:
    def __init__(self, executed: list, rows: list[Any]) -> None:
        self._executed = executed
        self._rows = rows

    def __enter__(self) -> _FakeConnection:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def cursor(self, cursor_factory: Any = None) -> _FakeCursor:
        return _FakeCursor(self._executed, self._rows)

    def close(self) -> None:
        return None


def _repo(*rows: Any) -> tuple[TravelPreferencesRepository, list]:
    executed: list = []
    queued = list(rows)
    settings = Settings(db_dsn="postgresql://redacted")
    repository = TravelPreferencesRepository(
        settings,
        connect=lambda **_: _FakeConnection(executed, queued),
    )
    return repository, executed


def _record(revision: int = 1) -> dict:
    return {
        "schema_version": 1,
        "revision": revision,
        "payload": {"version": 1, "soft": {}, "hard": {}, "locale": {}},
        "updated_at": UPDATED_AT,
    }


def test_get_is_owner_scoped_and_returns_revisioned_document() -> None:
    repository, executed = _repo(_record(3))

    result = repository.get(issuer="iss-a", subject="sub-a")

    assert result is not None and result.revision == 3
    sql, params = executed[0]
    assert "issuer = %s AND subject = %s" in sql
    assert params == ("iss-a", "sub-a")


def test_first_put_requires_expected_revision_zero_and_inserts_once() -> None:
    repository, executed = _repo(None, _record(1))

    result = repository.put(
        issuer="iss",
        subject="sub",
        expected_revision=0,
        preferences={"version": 1},
    )

    assert result.revision == 1
    assert "FOR UPDATE" in executed[0][0]
    assert "ON CONFLICT" in executed[1][0]
    assert executed[0][1] == ("iss", "sub")


def test_first_put_rejects_nonzero_revision_without_inserting() -> None:
    repository, executed = _repo(None)

    with pytest.raises(TravelPreferencesRevisionConflict):
        repository.put(
            issuer="iss",
            subject="sub",
            expected_revision=2,
            preferences={"version": 1},
        )

    assert len(executed) == 1


def test_update_rejects_stale_revision_before_writing() -> None:
    repository, executed = _repo({"revision": 4})

    with pytest.raises(TravelPreferencesRevisionConflict):
        repository.put(
            issuer="iss",
            subject="sub",
            expected_revision=3,
            preferences={"version": 1},
        )

    assert len(executed) == 1


def test_update_binds_payload_and_owner_without_string_interpolation() -> None:
    repository, executed = _repo({"revision": 4}, _record(5))
    sensitive_marker = "user-declared-ingredient"

    result = repository.put(
        issuer="iss",
        subject="sub",
        expected_revision=4,
        preferences={"version": 1, "hard": {"avoid_ingredients": sensitive_marker}},
    )

    assert result.revision == 5
    sql, params = executed[1]
    assert sensitive_marker not in sql
    assert params[2:] == ("iss", "sub", 4)


def test_preferences_migration_is_additive_owner_scoped_and_cascades_on_account_delete() -> None:
    sql = PREFERENCES_SQL.read_text(encoding="utf-8")

    assert not re.search(r"\b(DROP|TRUNCATE|DELETE\s+FROM)\b", sql, re.IGNORECASE)
    assert "CREATE TABLE IF NOT EXISTS profile.user_travel_preferences" in sql
    assert "REFERENCES identity.users (issuer, subject)" in sql
    assert "ON DELETE CASCADE" in sql
    assert "PRIMARY KEY (issuer, subject)" in sql
    assert "jsonb_typeof(payload) = 'object'" in sql
