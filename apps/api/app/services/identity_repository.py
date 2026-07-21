from __future__ import annotations

from collections.abc import Callable, Iterator
from contextlib import closing, contextmanager
from dataclasses import dataclass
from datetime import datetime
from hashlib import sha256
from typing import Any
from uuid import UUID

from apps.api.app.core.config import Settings


class IdentityRepositoryUnavailable(RuntimeError):
    """The configured local identity store cannot be reached."""


class PendingDeletionError(RuntimeError):
    """The user is already in the local account-deletion workflow."""


class DeletedIdentityError(RuntimeError):
    """The user identity has a persistent local deletion tombstone."""


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
        digest = _identity_digest(issuer, subject)
        with self._cursor() as cur:
            _lock_identity(cur, digest)
            cur.execute(
                "SELECT 1 FROM identity.deleted_users WHERE identity_digest = %s",
                (digest,),
            )
            if cur.fetchone() is not None:
                raise DeletedIdentityError()

            cur.execute(
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
            row = cur.fetchone()
            if row is not None:
                return _local_user_from_row(row)

            cur.execute(
                """
                SELECT id, issuer, subject, status, created_at, last_seen_at, deletion_requested_at
                FROM identity.users
                WHERE issuer = %s AND subject = %s
                """,
                (issuer, subject),
            )
            existing_row = cur.fetchone()
            if existing_row is not None and _local_user_from_row(existing_row).status == "deleting":
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

    def finalize_user_deletion(self, issuer: str, subject: str) -> bool:
        digest = _identity_digest(issuer, subject)
        with self._cursor() as cur:
            _lock_identity(cur, digest)
            cur.execute(
                "DELETE FROM identity.users WHERE issuer = %s AND subject = %s RETURNING id",
                (issuer, subject),
            )
            deleted = cur.fetchone() is not None
            cur.execute(
                """
                INSERT INTO identity.deleted_users (identity_digest)
                VALUES (%s)
                ON CONFLICT (identity_digest) DO NOTHING
                """,
                (digest,),
            )
            return deleted

    def _fetchone(self, sql: str, params: tuple[str, str]) -> tuple | None:
        with self._cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()

    @contextmanager
    def _cursor(self) -> Iterator[Any]:
        if not self._settings.db_dsn:
            raise IdentityRepositoryUnavailable()
        try:
            with closing(self._connect(dsn=self._settings.db_dsn, connect_timeout=3)) as conn:
                with conn:
                    with conn.cursor() as cur:
                        yield cur
        except (DeletedIdentityError, IdentityRepositoryUnavailable, PendingDeletionError):
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


def _identity_digest(issuer: str, subject: str) -> bytes:
    return sha256(issuer.encode("utf-8") + b"\0" + subject.encode("utf-8")).digest()


def _lock_identity(cur: Any, digest: bytes) -> None:
    lock_key = int.from_bytes(digest[:8], byteorder="big", signed=True)
    cur.execute("SELECT pg_advisory_xact_lock(%s)", (lock_key,))
