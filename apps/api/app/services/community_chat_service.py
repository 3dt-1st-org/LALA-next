from __future__ import annotations

import hashlib
import json
import secrets
from collections.abc import Callable, Iterator
from contextlib import closing, contextmanager
from typing import Any
from uuid import UUID

from apps.api.app.core.config import Settings, get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.services.community_idempotency import canonical_request_hash

# Durable control constants (documented in docs/devlogs P7 runbook).
IDEMPOTENCY_TTL_SECONDS = 24 * 60 * 60
IDEMPOTENCY_SCOPE_CHAT_MESSAGE = "community.chat.message.create"
WS_TICKET_TTL_SECONDS = 60
FANOUT_CHANNEL = "community_chat_fanout"


class CommunityChatRepositoryUnavailable(RuntimeError):
    """The configured community chat store cannot be reached."""


# SQL fragment: viewer can access public rooms, plus private rooms they own
# or hold an explicit membership row for. ``%s`` bind order below is
# (viewer_issuer, viewer_issuer, viewer_subject, viewer_issuer, viewer_subject).
_ROOM_ACCESS_SQL = """
    (
        r.visibility = 'public'
        OR (
            %s IS NOT NULL
            AND (
                (r.created_by_issuer = %s AND r.created_by_subject = %s)
                OR EXISTS (
                    SELECT 1
                    FROM community.chat_room_members m
                    WHERE m.room_id = r.id
                      AND m.issuer = %s
                      AND m.subject = %s
                )
            )
        )
    )
"""


def _access_params(viewer_issuer: str | None, viewer_subject: str | None) -> tuple:
    viewer = viewer_issuer or None
    return (viewer, viewer, viewer_subject or None, viewer, viewer_subject or None)


class CommunityChatRepository:
    """psycopg2-backed community chat data access.

    ``connect`` is injectable so unit tests can drive the SQL with a fake
    connection (same pattern as ``CommunityRepository``).

    Durable guarantees implemented here:
      * visibility/membership-guarded reads and writes (private existence
        never leaks: denial is indistinguishable from a missing room);
      * idempotent message creation claimed through the
        ``community.idempotency_keys`` primary key inside one transaction, so
        concurrent same-key writers serialize in Postgres, replays survive
        restarts, and business failures never burn the key;
      * single-use WebSocket tickets claimed with one atomic UPDATE;
      * Postgres NOTIFY fanout emitted in the same transaction as the
        committed message.
    """

    def __init__(
        self,
        settings: Settings,
        *,
        connect: Callable[..., object] | None = None,
    ) -> None:
        self._settings = settings
        self._connect = connect or _connect

    # -- Reads ---------------------------------------------------------------

    def list_rooms(
        self,
        *,
        limit: int,
        offset: int,
        viewer_issuer: str | None,
        viewer_subject: str | None,
    ) -> tuple[list[dict[str, Any]], int]:
        access = _ROOM_ACCESS_SQL
        params = _access_params(viewer_issuer, viewer_subject)
        sql = f"""
            SELECT r.id, r.name, r.visibility, r.created_at
            FROM community.chat_rooms r
            WHERE {access}
            ORDER BY r.created_at DESC, r.id DESC
            LIMIT %s OFFSET %s
        """
        total_sql = f"""
            SELECT count(*)::int FROM community.chat_rooms r WHERE {access}
        """
        with self._cursor() as cur:
            cur.execute(total_sql, params)
            total = int(cur.fetchone()["count"])  # type: ignore[index]
            cur.execute(sql, (*params, limit, offset))
            rows = list(cur.fetchall())
        return rows, total

    def room_access(
        self,
        *,
        room_id: UUID,
        viewer_issuer: str | None,
        viewer_subject: str | None,
    ) -> dict[str, Any] | None:
        """Return the room row when the viewer may access it, else ``None``.

        ``None`` covers both missing rooms and private rooms the viewer does
        not own/is not a member of: callers map both to the same 404 so
        private existence cannot be probed.
        """

        sql = f"""
            SELECT r.id, r.name, r.visibility, r.created_at
            FROM community.chat_rooms r
            WHERE r.id = %s AND {_ROOM_ACCESS_SQL}
        """
        params = (str(room_id), *_access_params(viewer_issuer, viewer_subject))
        with self._cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()

    def list_messages(
        self,
        *,
        room_id: UUID,
        limit: int,
        offset: int,
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

    def fetch_message_for_fanout(self, *, message_id: UUID) -> dict[str, Any] | None:
        """Load one message row (with author uuid) for local re-broadcast."""

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
            WHERE m.id = %s
        """
        with self._cursor() as cur:
            cur.execute(sql, (str(message_id),))
            return cur.fetchone()

    # -- Writes --------------------------------------------------------------

    def create_room(
        self,
        *,
        name: str,
        visibility: str,
        issuer: str,
        subject: str,
    ) -> dict[str, Any]:
        """Create a room; private rooms also record the owner membership row.

        Both writes share one transaction: a private room without its owner
        membership can never be committed.
        """

        insert_sql = """
            INSERT INTO community.chat_rooms
                (name, visibility, created_by_issuer, created_by_subject)
            VALUES (%s, %s, %s, %s)
            RETURNING id, name, visibility, created_at
        """
        member_sql = """
            INSERT INTO community.chat_room_members (room_id, issuer, subject, role)
            VALUES (%s, %s, %s, 'owner')
            ON CONFLICT DO NOTHING
        """
        with self._cursor() as cur:
            cur.execute(insert_sql, (name, visibility, issuer, subject))
            row = cur.fetchone()
            assert row is not None  # RETURNING always yields one row on insert.
            if visibility == "private":
                cur.execute(member_sql, (str(row["id"]), issuer, subject))
        return row

    def add_room_member(
        self,
        *,
        room_id: UUID,
        member_user_id: UUID,
        owner_issuer: str,
        owner_subject: str,
    ) -> dict[str, Any]:
        """Owner-only explicit membership grant for a private room.

        Outcomes (decided in SQL order, all inside one transaction):
        ``missing_room`` (also covers non-accessible private rooms),
        ``not_owner``, ``not_private``, ``missing_member``,
        ``already_member`` and ``added``.
        """

        room_sql = """
            SELECT id, visibility, created_by_issuer, created_by_subject
            FROM community.chat_rooms
            WHERE id = %s
        """
        member_sql = "SELECT issuer, subject FROM identity.users WHERE id = %s"
        insert_sql = """
            INSERT INTO community.chat_room_members (room_id, issuer, subject)
            VALUES (%s, %s, %s)
            ON CONFLICT DO NOTHING
            RETURNING room_id
        """
        with self._cursor() as cur:
            cur.execute(room_sql, (str(room_id),))
            room = cur.fetchone()
            if room is None:
                return {"outcome": "missing_room"}
            if (
                room["created_by_issuer"] != owner_issuer
                or room["created_by_subject"] != owner_subject
            ):
                return {"outcome": "not_owner"}
            if room["visibility"] != "private":
                return {"outcome": "not_private"}
            cur.execute(member_sql, (str(member_user_id),))
            member = cur.fetchone()
            if member is None:
                return {"outcome": "missing_member"}
            cur.execute(
                insert_sql,
                (str(room_id), member["issuer"], member["subject"]),
            )
            added = cur.fetchone() is not None
        return {"outcome": "added" if added else "already_member"}

    def create_message(
        self,
        *,
        room_id: UUID,
        issuer: str,
        subject: str,
        body: str,
    ) -> dict[str, Any] | None:
        """Visibility/membership-guarded message insert (non-idempotent path)."""

        insert_sql = f"""
            INSERT INTO community.chat_messages
                (room_id, author_issuer, author_subject, body)
            SELECT %s, %s, %s, %s
            FROM community.chat_rooms r
            WHERE r.id = %s AND {_ROOM_ACCESS_SQL}
            RETURNING
                id,
                room_id,
                author_issuer,
                author_subject,
                body,
                created_at
        """
        access = _access_params(issuer, subject)
        with self._cursor() as cur:
            cur.execute(
                insert_sql,
                (str(room_id), issuer, subject, body, str(room_id), *access),
            )
            row = cur.fetchone()
            if row is None:
                return None
            row["author_user_id"] = self._resolve_author_user_id(cur, issuer, subject)
            _emit_fanout_notify(cur, room_id=row["room_id"], message_id=row["id"])
        return row

    def create_message_idempotent(
        self,
        *,
        room_id: UUID,
        issuer: str,
        subject: str,
        body: str,
        idempotency_key: str,
    ) -> dict[str, Any]:
        """Durable idempotent message creation.

        One transaction: claim the key (placeholder response), run the guarded
        insert, store the real response, emit fanout. Concurrent writers with
        the same key serialize on the primary key; the loser replays the
        committed response or is rejected as a payload conflict. Business
        failures (room inaccessible) roll the claim back so the key is not
        burned. Returns ``{"outcome": ..., "message": ...}``.
        """

        request_hash = canonical_request_hash({"room_id": str(room_id), "body": body})
        claim_sql = """
            INSERT INTO community.idempotency_keys
                (scope, actor_issuer, actor_subject, idempotency_key,
                 request_hash, response_json, status_code, expires_at)
            VALUES (%s, %s, %s, %s, %s, 'null'::jsonb, 200,
                    now() + make_interval(secs => %s))
            ON CONFLICT (scope, actor_issuer, actor_subject, idempotency_key)
                DO NOTHING
            RETURNING idempotency_key
        """
        existing_sql = """
            SELECT request_hash, response_json
            FROM community.idempotency_keys
            WHERE scope = %s AND actor_issuer = %s AND actor_subject = %s
              AND idempotency_key = %s
        """
        purge_sql = """
            DELETE FROM community.idempotency_keys
            WHERE scope = %s AND expires_at < now()
        """
        store_sql = """
            UPDATE community.idempotency_keys
            SET response_json = %s::jsonb
            WHERE scope = %s AND actor_issuer = %s AND actor_subject = %s
              AND idempotency_key = %s
        """
        release_sql = """
            DELETE FROM community.idempotency_keys
            WHERE scope = %s AND actor_issuer = %s AND actor_subject = %s
              AND idempotency_key = %s AND response_json = 'null'::jsonb
        """
        insert_sql = f"""
            INSERT INTO community.chat_messages
                (room_id, author_issuer, author_subject, body)
            SELECT %s, %s, %s, %s
            FROM community.chat_rooms r
            WHERE r.id = %s AND {_ROOM_ACCESS_SQL}
            RETURNING
                id,
                room_id,
                author_issuer,
                author_subject,
                body,
                created_at
        """
        access = _access_params(issuer, subject)
        with self._cursor() as cur:
            cur.execute(purge_sql, (IDEMPOTENCY_SCOPE_CHAT_MESSAGE,))
            cur.execute(
                claim_sql,
                (
                    IDEMPOTENCY_SCOPE_CHAT_MESSAGE,
                    issuer,
                    subject,
                    idempotency_key,
                    request_hash,
                    IDEMPOTENCY_TTL_SECONDS,
                ),
            )
            claimed = cur.fetchone() is not None
            if not claimed:
                cur.execute(
                    existing_sql,
                    (IDEMPOTENCY_SCOPE_CHAT_MESSAGE, issuer, subject, idempotency_key),
                )
                existing = cur.fetchone()
                if existing is None:
                    # Unobservable by design (claims never commit without a
                    # response); treat as a transient store inconsistency.
                    raise CommunityChatRepositoryUnavailable()
                if existing["request_hash"] != request_hash:
                    return {"outcome": "conflict", "message": None}
                response = existing["response_json"]
                if response is None:
                    raise CommunityChatRepositoryUnavailable()
                return {"outcome": "replayed", "message": dict(response)}
            cur.execute(
                insert_sql,
                (str(room_id), issuer, subject, body, str(room_id), *access),
            )
            row = cur.fetchone()
            if row is None:
                # Business failure: release the claim so a retry after the
                # room becomes accessible (or the typo is fixed) still works.
                cur.execute(
                    release_sql,
                    (IDEMPOTENCY_SCOPE_CHAT_MESSAGE, issuer, subject, idempotency_key),
                )
                return {"outcome": "denied", "message": None}
            row["author_user_id"] = self._resolve_author_user_id(cur, issuer, subject)
            payload = _message_payload(row)
            cur.execute(
                store_sql,
                (
                    json.dumps(payload),
                    IDEMPOTENCY_SCOPE_CHAT_MESSAGE,
                    issuer,
                    subject,
                    idempotency_key,
                ),
            )
            _emit_fanout_notify(cur, room_id=row["room_id"], message_id=row["id"])
            return {"outcome": "created", "message": payload}

    # -- WebSocket tickets ---------------------------------------------------

    def issue_ws_ticket(
        self,
        *,
        room_id: UUID,
        issuer: str,
        subject: str,
        ttl_seconds: int = WS_TICKET_TTL_SECONDS,
    ) -> dict[str, Any]:
        """Mint a short-lived single-use handshake ticket.

        Only the sha256 digest is stored. Expired rows for this actor are
        purged in the same transaction to keep the table bounded.
        """

        purge_sql = """
            DELETE FROM community.chat_ws_tickets
            WHERE expires_at < now()
        """
        insert_sql = """
            INSERT INTO community.chat_ws_tickets
                (ticket_hash, room_id, issuer, subject, expires_at)
            VALUES (%s, %s, %s, %s, now() + make_interval(secs => %s))
            RETURNING expires_at
        """
        ticket = secrets.token_urlsafe(32)
        ticket_hash = hashlib.sha256(ticket.encode("utf-8")).hexdigest()
        with self._cursor() as cur:
            cur.execute(purge_sql)
            cur.execute(
                insert_sql,
                (ticket_hash, str(room_id), issuer, subject, ttl_seconds),
            )
            row = cur.fetchone()
            assert row is not None  # RETURNING always yields one row on insert.
        return {
            "ticket": ticket,
            "room_id": str(room_id),
            "expires_at": row["expires_at"],
        }

    def claim_ws_ticket(
        self,
        *,
        ticket: str,
        room_id: UUID,
    ) -> dict[str, Any] | None:
        """Atomically claim a ticket and return the verified actor identity.

        The single UPDATE is the concurrency truth: exactly one handshake can
        consume a ticket across all instances. Returns ``None`` for missing,
        expired, already-used, or room-mismatched tickets, and for tickets
        whose actor no longer has room access (re-checked at claim time).
        """

        claim_sql = """
            UPDATE community.chat_ws_tickets
            SET used_at = now()
            WHERE ticket_hash = %s
              AND used_at IS NULL
              AND expires_at > now()
            RETURNING room_id, issuer, subject
        """
        if not ticket or len(ticket) > 512:
            return None
        ticket_hash = hashlib.sha256(ticket.encode("utf-8")).hexdigest()
        with self._cursor() as cur:
            cur.execute(claim_sql, (ticket_hash,))
            row = cur.fetchone()
            if row is None:
                return None
            if str(row["room_id"]) != str(room_id):
                return None
            access_sql = f"""
                SELECT r.id, r.name, r.visibility, r.created_at
                FROM community.chat_rooms r
                WHERE r.id = %s AND {_ROOM_ACCESS_SQL}
            """
            access = _access_params(row["issuer"], row["subject"])
            cur.execute(access_sql, (str(room_id), *access))
            if cur.fetchone() is None:
                return None
            return {"issuer": row["issuer"], "subject": row["subject"]}

    # -- Plumbing ------------------------------------------------------------

    @staticmethod
    def _resolve_author_user_id(cur: Any, issuer: str, subject: str) -> Any:
        cur.execute(
            "SELECT id AS author_user_id FROM identity.users WHERE issuer = %s AND subject = %s",
            (issuer, subject),
        )
        identity_row = cur.fetchone()
        return identity_row["id"] if identity_row else None

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


def _emit_fanout_notify(cur: Any, *, room_id: Any, message_id: Any = None) -> None:
    """Emit the cross-instance fanout notification inside the open transaction.

    ``pg_notify`` fires exactly when the surrounding transaction commits, so a
    delivered notification always corresponds to a committed message. The
    payload carries ids only (never message content) to stay far below the
    8000-byte NOTIFY payload limit.
    """

    payload = {"room_id": str(room_id)}
    if message_id is not None:
        payload["message_id"] = str(message_id)
    cur.execute(
        "SELECT pg_notify(%s, %s)",
        (FANOUT_CHANNEL, json.dumps(payload, separators=(",", ":"))),
    )


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

    def list_rooms(
        self,
        *,
        limit: int,
        offset: int,
        viewer_issuer: str | None = None,
        viewer_subject: str | None = None,
    ) -> dict[str, Any]:
        try:
            rows, total = self._repository.list_rooms(
                limit=limit,
                offset=offset,
                viewer_issuer=viewer_issuer,
                viewer_subject=viewer_subject,
            )
        except CommunityChatRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        return {
            "count": len(rows),
            "total": total,
            "rooms": [_room_payload(row) for row in rows],
        }

    def create_room(
        self,
        *,
        name: str,
        visibility: str,
        issuer: str,
        subject: str,
    ) -> dict[str, Any]:
        if visibility == "private" and not (issuer and subject):
            # Defense in depth: a private room always records an owner anchor.
            # Unreachable through the REST router (OAuth required); documented
            # account-deletion lifecycle (creator SET NULL) lives in 068.
            raise ServiceError(
                status_code=422,
                code="COMMUNITY_CHAT_ROOM_CREATOR_REQUIRED",
                message="A private room requires a verified creator.",
                retryable=False,
            )
        try:
            row = self._repository.create_room(
                name=name, visibility=visibility, issuer=issuer, subject=subject
            )
        except CommunityChatRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        return _room_payload(row)

    def room_access(
        self,
        *,
        room_id: UUID,
        viewer_issuer: str | None = None,
        viewer_subject: str | None = None,
    ) -> dict[str, Any] | None:
        try:
            return self._repository.room_access(
                room_id=room_id,
                viewer_issuer=viewer_issuer,
                viewer_subject=viewer_subject,
            )
        except CommunityChatRepositoryUnavailable as exc:
            raise _database_unavailable() from exc

    def add_room_member(
        self,
        *,
        room_id: UUID,
        member_user_id: UUID,
        owner_issuer: str,
        owner_subject: str,
    ) -> dict[str, Any]:
        try:
            outcome = self._repository.add_room_member(
                room_id=room_id,
                member_user_id=member_user_id,
                owner_issuer=owner_issuer,
                owner_subject=owner_subject,
            )
        except CommunityChatRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        result = outcome["outcome"]
        if result == "missing_room":
            # Same 404 as an unknown room: private existence must not leak.
            raise _not_found("COMMUNITY_CHAT_ROOM_NOT_FOUND", "Chat room was not found.")
        if result == "not_owner":
            raise _not_found("COMMUNITY_CHAT_ROOM_NOT_FOUND", "Chat room was not found.")
        if result == "not_private":
            raise ServiceError(
                status_code=422,
                code="COMMUNITY_CHAT_ROOM_NOT_PRIVATE",
                message="Only private rooms support membership.",
                retryable=False,
            )
        if result == "missing_member":
            raise _not_found("COMMUNITY_CHAT_MEMBER_USER_NOT_FOUND", "Member user was not found.")
        return {
            "room_id": str(room_id),
            "member_user_id": str(member_user_id),
            "added": result == "added",
        }

    def list_messages(
        self,
        *,
        room_id: UUID,
        limit: int,
        offset: int,
        viewer_issuer: str | None = None,
        viewer_subject: str | None = None,
    ) -> dict[str, Any]:
        try:
            room = self._repository.room_access(
                room_id=room_id,
                viewer_issuer=viewer_issuer,
                viewer_subject=viewer_subject,
            )
            if room is None:
                raise _not_found("COMMUNITY_CHAT_ROOM_NOT_FOUND", "Chat room was not found.")
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
        idempotency_key: str | None = None,
    ) -> dict[str, Any]:
        """Create a chat message; durable-idempotent when a key is supplied."""

        try:
            if idempotency_key:
                result = self._repository.create_message_idempotent(
                    room_id=room_id,
                    issuer=issuer,
                    subject=subject,
                    body=body,
                    idempotency_key=idempotency_key,
                )
            else:
                row = self._repository.create_message(
                    room_id=room_id, issuer=issuer, subject=subject, body=body
                )
                result = (
                    {"outcome": "denied", "message": None}
                    if row is None
                    else {"outcome": "created", "message": _message_payload(row)}
                )
        except CommunityChatRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        outcome = result["outcome"]
        if outcome == "denied":
            raise _not_found("COMMUNITY_CHAT_ROOM_NOT_FOUND", "Chat room was not found.")
        if outcome == "conflict":
            raise ServiceError(
                status_code=409,
                code="IDEMPOTENCY_KEY_CONFLICT",
                message=("This idempotency key was already used with a different payload."),
                retryable=False,
            )
        payload = result["message"]
        assert payload is not None  # created/replayed always carry a message.
        return payload

    def issue_ws_ticket(
        self,
        *,
        room_id: UUID,
        issuer: str,
        subject: str,
    ) -> dict[str, Any]:
        """Issue a single-use ticket after verifying room access for the actor."""

        try:
            room = self._repository.room_access(
                room_id=room_id, viewer_issuer=issuer, viewer_subject=subject
            )
            if room is None:
                raise _not_found("COMMUNITY_CHAT_ROOM_NOT_FOUND", "Chat room was not found.")
            row = self._repository.issue_ws_ticket(room_id=room_id, issuer=issuer, subject=subject)
        except CommunityChatRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        return {
            "room_id": row["room_id"],
            "ticket": row["ticket"],
            "expires_at": (
                row["expires_at"].isoformat()
                if hasattr(row["expires_at"], "isoformat")
                else row["expires_at"]
            ),
        }

    def claim_ws_ticket(
        self,
        *,
        ticket: str,
        room_id: UUID,
    ) -> dict[str, Any] | None:
        try:
            return self._repository.claim_ws_ticket(ticket=ticket, room_id=room_id)
        except CommunityChatRepositoryUnavailable as exc:
            raise _database_unavailable() from exc

    def fetch_message_for_fanout(self, *, message_id: UUID) -> dict[str, Any] | None:
        try:
            row = self._repository.fetch_message_for_fanout(message_id=message_id)
        except CommunityChatRepositoryUnavailable:
            return None
        return _message_payload(row) if row is not None else None


def get_community_chat_service() -> CommunityChatService:
    return CommunityChatService(CommunityChatRepository(get_settings()))


def _room_payload(row: dict[str, Any]) -> dict[str, Any]:
    created_at = row.get("created_at")
    return {
        "id": str(row["id"]),
        "name": row["name"],
        "visibility": row.get("visibility", "public"),
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
