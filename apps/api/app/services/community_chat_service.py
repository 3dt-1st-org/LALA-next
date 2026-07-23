from __future__ import annotations

from collections.abc import Callable, Iterator
from contextlib import closing, contextmanager
from typing import Any
from uuid import UUID

from apps.api.app.core.config import Settings, get_settings
from apps.api.app.core.errors import ServiceError


class CommunityChatRepositoryUnavailable(RuntimeError):
    """The configured community chat store cannot be reached."""


class CommunityChatRepository:
    """psycopg2-backed community chat data access.

    ``connect`` is injectable so unit tests can drive the SQL with a fake
    connection (same pattern as ``CommunityRepository``).
    """

    def __init__(
        self,
        settings: Settings,
        *,
        connect: Callable[..., object] | None = None,
    ) -> None:
        self._settings = settings
        self._connect = connect or _connect

    def list_rooms(self, *, limit: int, offset: int) -> tuple[list[dict[str, Any]], int]:
        sql = """
            SELECT id, name, created_at
            FROM community.chat_rooms
            ORDER BY created_at DESC, id DESC
            LIMIT %s OFFSET %s
        """
        total_sql = "SELECT count(*)::int FROM community.chat_rooms"
        with self._cursor() as cur:
            cur.execute(total_sql)
            total = int(cur.fetchone()["count"])  # type: ignore[index]
            cur.execute(sql, (limit, offset))
            rows = list(cur.fetchall())
        return rows, total

    def create_room(self, *, name: str) -> dict[str, Any]:
        sql = """
            INSERT INTO community.chat_rooms (name)
            VALUES (%s)
            RETURNING id, name, created_at
        """
        with self._cursor() as cur:
            cur.execute(sql, (name,))
            row = cur.fetchone()
        assert row is not None  # RETURNING always yields one row on insert.
        return row

    def room_exists(self, *, room_id: UUID) -> bool:
        sql = "SELECT 1 FROM community.chat_rooms WHERE id = %s"
        with self._cursor() as cur:
            cur.execute(sql, (str(room_id),))
            return cur.fetchone() is not None

    def list_messages(
        self, *, room_id: UUID, limit: int, offset: int
    ) -> tuple[list[dict[str, Any]], int]:
        sql = """
            SELECT
                m.id,
                m.room_id,
                m.author_issuer,
                m.author_subject,
                m.body,
                m.created_at,
                u.id AS author_user_id
            FROM community.chat_messages m
            JOIN identity.users u
              ON u.issuer = m.author_issuer AND u.subject = m.author_subject
            WHERE m.room_id = %s
            ORDER BY m.created_at ASC, m.id ASC
            LIMIT %s OFFSET %s
        """
        total_sql = "SELECT count(*)::int FROM community.chat_messages WHERE room_id = %s"
        with self._cursor() as cur:
            cur.execute(total_sql, (str(room_id),))
            total = int(cur.fetchone()["count"])  # type: ignore[index]
            cur.execute(sql, (str(room_id), limit, offset))
            rows = list(cur.fetchall())
        return rows, total

    def create_message(
        self,
        *,
        room_id: UUID,
        issuer: str,
        subject: str,
        body: str,
    ) -> dict[str, Any] | None:
        sql = """
            INSERT INTO community.chat_messages
                (room_id, author_issuer, author_subject, body)
            SELECT %s, %s, %s, %s
            FROM community.chat_rooms
            WHERE id = %s
            RETURNING
                id,
                room_id,
                author_issuer,
                author_subject,
                body,
                created_at
        """
        with self._cursor() as cur:
            cur.execute(sql, (str(room_id), issuer, subject, body, str(room_id)))
            row = cur.fetchone()
        if row is None:
            return None
        with self._cursor() as cur:
            cur.execute(
                "SELECT id AS author_user_id FROM identity.users "
                "WHERE issuer = %s AND subject = %s",
                (issuer, subject),
            )
            identity_row = cur.fetchone()
        row["author_user_id"] = identity_row["id"] if identity_row else None  # type: ignore[index]
        return row

    @contextmanager
    def _cursor(self) -> Iterator[Any]:
        if not self._settings.db_dsn:
            raise CommunityChatRepositoryUnavailable()
        try:
            from psycopg2.extras import RealDictCursor
        except Exception as exc:
            raise CommunityChatRepositoryUnavailable() from exc
        try:
            with closing(self._connect(dsn=self._settings.db_dsn, connect_timeout=3)) as conn:
                with conn:
                    with conn.cursor(cursor_factory=RealDictCursor) as cur:
                        yield cur
        except CommunityChatRepositoryUnavailable:
            raise
        except Exception as exc:
            raise CommunityChatRepositoryUnavailable() from exc


def _connect(*, dsn: str, connect_timeout: int):
    try:
        import psycopg2
    except Exception as exc:
        raise CommunityChatRepositoryUnavailable() from exc
    return psycopg2.connect(dsn, connect_timeout=connect_timeout)


class CommunityChatService:
    """Thin orchestration layer that shapes repository rows and maps DB errors."""

    def __init__(self, repository: CommunityChatRepository) -> None:
        self._repository = repository

    def list_rooms(self, *, limit: int, offset: int) -> dict[str, Any]:
        try:
            rows, total = self._repository.list_rooms(limit=limit, offset=offset)
        except CommunityChatRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        return {
            "count": len(rows),
            "total": total,
            "rooms": [_room_payload(row) for row in rows],
        }

    def create_room(self, *, name: str) -> dict[str, Any]:
        try:
            row = self._repository.create_room(name=name)
        except CommunityChatRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        return _room_payload(row)

    def room_exists(self, *, room_id: UUID) -> bool:
        try:
            return self._repository.room_exists(room_id=room_id)
        except CommunityChatRepositoryUnavailable as exc:
            raise _database_unavailable() from exc

    def list_messages(self, *, room_id: UUID, limit: int, offset: int) -> dict[str, Any]:
        try:
            rows, total = self._repository.list_messages(
                room_id=room_id, limit=limit, offset=offset
            )
        except CommunityChatRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        return {
            "count": len(rows),
            "total": total,
            "messages": [_message_payload(row) for row in rows],
        }

    def create_message(
        self,
        *,
        room_id: UUID,
        issuer: str,
        subject: str,
        body: str,
    ) -> dict[str, Any]:
        try:
            row = self._repository.create_message(
                room_id=room_id, issuer=issuer, subject=subject, body=body
            )
        except CommunityChatRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if row is None:
            raise _not_found("COMMUNITY_CHAT_ROOM_NOT_FOUND", "Chat room was not found.")
        return _message_payload(row)


def get_community_chat_service() -> CommunityChatService:
    return CommunityChatService(CommunityChatRepository(get_settings()))


def _room_payload(row: dict[str, Any]) -> dict[str, Any]:
    created_at = row.get("created_at")
    return {
        "id": str(row["id"]),
        "name": row["name"],
        "created_at": created_at.isoformat() if created_at else None,
    }


def _message_payload(row: dict[str, Any]) -> dict[str, Any]:
    created_at = row.get("created_at")
    author_user_id = row.get("author_user_id")
    return {
        "id": str(row["id"]),
        "room_id": str(row["room_id"]),
        "author_user_id": str(author_user_id) if author_user_id is not None else None,
        "body": row["body"],
        "created_at": created_at.isoformat() if created_at else None,
    }


def _database_unavailable() -> ServiceError:
    return ServiceError(
        status_code=503,
        code="COMMUNITY_CHAT_DB_UNAVAILABLE",
        message="Community chat store is temporarily unavailable.",
        retryable=True,
    )


def _not_found(code: str, message: str) -> ServiceError:
    return ServiceError(
        status_code=404,
        code=code,
        message=message,
        retryable=False,
    )
