from __future__ import annotations

from contextlib import closing
from dataclasses import dataclass
from datetime import datetime
from typing import Callable
from uuid import UUID

from apps.api.app.core.config import Settings


class IdentityRepositoryUnavailable(RuntimeError):
    """The configured local identity store cannot be reached."""


class PendingDeletionError(RuntimeError):
    """The user is already in the local account-deletion workflow."""


@dataclass(frozen=True)
class LocalUser:
    id: UUID
    issuer: str
    subject: str
    status: str
    created_at: datetime
    last_seen_at: datetime
    deletion_requested_at: datetime | None


class IdentityRepository:
    def __init__(
        self,
        settings: Settings,
        *,
        connect: Callable[..., object] | None = None,
    ) -> None:
        self._settings = settings
        self._connect = connect or _connect

    def provision_user(self, issuer: str, subject: str) -> LocalUser:
        row = self._fetchone(
            """
            INSERT INTO identity.users (issuer, subject)
            VALUES (%s, %s)
            ON CONFLICT (issuer, subject) DO UPDATE
            SET last_seen_at = now()
            WHERE identity.users.status = 'active'
            RETURNING id, issuer, subject, status, created_at, last_seen_at, deletion_requested_at
            """,
            (issuer, subject),
        )
        if row is not None:
            return _local_user_from_row(row)

        existing = self.find_user(issuer, subject)
        if existing is not None and existing.status == "deleting":
            raise PendingDeletionError()
        raise IdentityRepositoryUnavailable()

    def find_user(self, issuer: str, subject: str) -> LocalUser | None:
        row = self._fetchone(
            """
            SELECT id, issuer, subject, status, created_at, last_seen_at, deletion_requested_at
            FROM identity.users
            WHERE issuer = %s AND subject = %s
            """,
            (issuer, subject),
        )
        return _local_user_from_row(row) if row is not None else None

    def mark_user_deleting(self, issuer: str, subject: str) -> LocalUser | None:
        row = self._fetchone(
            """
            UPDATE identity.users
            SET status = 'deleting', deletion_requested_at = COALESCE(deletion_requested_at, now())
            WHERE issuer = %s AND subject = %s
            RETURNING id, issuer, subject, status, created_at, last_seen_at, deletion_requested_at
            """,
            (issuer, subject),
        )
        return _local_user_from_row(row) if row is not None else None

    def delete_local_user(self, issuer: str, subject: str) -> bool:
        row = self._fetchone(
            "DELETE FROM identity.users WHERE issuer = %s AND subject = %s RETURNING id",
            (issuer, subject),
        )
        return row is not None

    def _fetchone(self, sql: str, params: tuple[str, str]) -> tuple | None:
        if not self._settings.db_dsn:
            raise IdentityRepositoryUnavailable()
        try:
            with closing(self._connect(dsn=self._settings.db_dsn, connect_timeout=3)) as conn:
                with conn:
                    with conn.cursor() as cur:
                        cur.execute(sql, params)
                        return cur.fetchone()
        except IdentityRepositoryUnavailable:
            raise
        except Exception as exc:
            raise IdentityRepositoryUnavailable() from exc


def _connect(*, dsn: str, connect_timeout: int):
    try:
        import psycopg2
    except Exception as exc:
        raise IdentityRepositoryUnavailable() from exc
    return psycopg2.connect(dsn, connect_timeout=connect_timeout)


def _local_user_from_row(row: tuple) -> LocalUser:
    return LocalUser(
        id=row[0],
        issuer=row[1],
        subject=row[2],
        status=row[3],
        created_at=row[4],
        last_seen_at=row[5],
        deletion_requested_at=row[6],
    )
