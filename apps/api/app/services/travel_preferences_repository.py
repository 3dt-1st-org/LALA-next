from __future__ import annotations

from collections.abc import Callable, Iterator
from contextlib import closing, contextmanager
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from apps.api.app.core.config import Settings, get_settings

TRAVEL_PREFERENCES_SCHEMA_VERSION = 1


class TravelPreferencesRepositoryUnavailable(RuntimeError):
    """The account preference store cannot be reached or trusted."""


class TravelPreferencesRevisionConflict(RuntimeError):
    """The caller tried to overwrite a newer preference document."""


@dataclass(frozen=True)
class TravelPreferencesRecord:
    preferences: dict[str, Any]
    revision: int
    updated_at: datetime


class TravelPreferencesRepository:
    def __init__(
        self,
        settings: Settings,
        *,
        connect: Callable[..., object] | None = None,
    ) -> None:
        self._settings = settings
        self._connect = connect or _connect

    def get(self, *, issuer: str, subject: str) -> TravelPreferencesRecord | None:
        with self._cursor() as cur:
            cur.execute(
                """
                SELECT schema_version, revision, payload, updated_at
                FROM profile.user_travel_preferences
                WHERE issuer = %s AND subject = %s
                """,
                (issuer, subject),
            )
            row = cur.fetchone()
        return _record_from_row(row)

    def put(
        self,
        *,
        issuer: str,
        subject: str,
        expected_revision: int,
        preferences: dict[str, Any],
    ) -> TravelPreferencesRecord:
        with self._cursor() as cur:
            cur.execute(
                """
                SELECT revision
                FROM profile.user_travel_preferences
                WHERE issuer = %s AND subject = %s
                FOR UPDATE
                """,
                (issuer, subject),
            )
            existing = cur.fetchone()
            if existing is None:
                if expected_revision != 0:
                    raise TravelPreferencesRevisionConflict()
                cur.execute(
                    """
                    INSERT INTO profile.user_travel_preferences
                        (issuer, subject, schema_version, revision, payload)
                    VALUES (%s, %s, %s, 1, %s)
                    ON CONFLICT (issuer, subject) DO NOTHING
                    RETURNING schema_version, revision, payload, updated_at
                    """,
                    (
                        issuer,
                        subject,
                        TRAVEL_PREFERENCES_SCHEMA_VERSION,
                        _as_json(preferences),
                    ),
                )
                inserted = cur.fetchone()
                if inserted is None:
                    raise TravelPreferencesRevisionConflict()
                return _required_record(inserted)

            current_revision = int(existing["revision"])
            if current_revision != expected_revision:
                raise TravelPreferencesRevisionConflict()
            cur.execute(
                """
                UPDATE profile.user_travel_preferences
                SET schema_version = %s,
                    revision = revision + 1,
                    payload = %s,
                    updated_at = now()
                WHERE issuer = %s AND subject = %s AND revision = %s
                RETURNING schema_version, revision, payload, updated_at
                """,
                (
                    TRAVEL_PREFERENCES_SCHEMA_VERSION,
                    _as_json(preferences),
                    issuer,
                    subject,
                    expected_revision,
                ),
            )
            updated = cur.fetchone()
            if updated is None:
                raise TravelPreferencesRevisionConflict()
            return _required_record(updated)

    @contextmanager
    def _cursor(self) -> Iterator[Any]:
        if not self._settings.db_dsn:
            raise TravelPreferencesRepositoryUnavailable()
        try:
            from psycopg2.extras import RealDictCursor
        except Exception as exc:  # pragma: no cover - optional in minimal runtime
            raise TravelPreferencesRepositoryUnavailable() from exc
        try:
            with closing(self._connect(dsn=self._settings.db_dsn, connect_timeout=3)) as conn:
                with conn:
                    with conn.cursor(cursor_factory=RealDictCursor) as cur:
                        yield cur
        except (TravelPreferencesRepositoryUnavailable, TravelPreferencesRevisionConflict):
            raise
        except Exception as exc:  # pragma: no cover - DB-specific failure
            raise TravelPreferencesRepositoryUnavailable() from exc


def get_travel_preferences_repository() -> TravelPreferencesRepository:
    return TravelPreferencesRepository(get_settings())


def _connect(*, dsn: str, connect_timeout: int) -> object:
    try:
        import psycopg2
    except Exception as exc:  # pragma: no cover
        raise TravelPreferencesRepositoryUnavailable() from exc
    return psycopg2.connect(dsn, connect_timeout=connect_timeout)


def _as_json(value: dict[str, Any]) -> Any:
    from psycopg2.extras import Json

    return Json(value)


def _record_from_row(row: Any) -> TravelPreferencesRecord | None:
    if row is None:
        return None
    return _required_record(row)


def _required_record(row: Any) -> TravelPreferencesRecord:
    payload = row.get("payload")
    if (
        row.get("schema_version") != TRAVEL_PREFERENCES_SCHEMA_VERSION
        or not isinstance(payload, dict)
        or not isinstance(row.get("revision"), int)
        or row.get("updated_at") is None
    ):
        raise TravelPreferencesRepositoryUnavailable()
    return TravelPreferencesRecord(
        preferences=payload,
        revision=row["revision"],
        updated_at=row["updated_at"],
    )
