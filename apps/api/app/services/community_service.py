from __future__ import annotations

from collections.abc import Callable, Iterator
from contextlib import closing, contextmanager
from typing import Any
from uuid import UUID

from apps.api.app.core.config import Settings, get_settings
from apps.api.app.core.errors import ServiceError


class CommunityRepositoryUnavailable(RuntimeError):
    """The configured community store cannot be reached."""


_POST_LIST_COLUMNS = """
    p.id,
    p.author_issuer,
    p.author_subject,
    p.title,
    p.body,
    p.tags,
    p.created_at,
    p.updated_at,
    u.id AS author_user_id,
    (
        SELECT count(*)::int
        FROM community.post_comments c
        WHERE c.post_id = p.id
    ) AS comment_count,
    (
        SELECT count(*)::int
        FROM community.post_likes l
        WHERE l.post_id = p.id
    ) AS like_count,
    (
        SELECT EXISTS (
            SELECT 1
            FROM community.post_likes l
            WHERE l.post_id = p.id
              AND l.issuer = %s
              AND l.subject = %s
        )
    ) AS viewer_liked,
    (
        SELECT EXISTS (
            SELECT 1
            FROM community.user_follows f
            WHERE f.follower_issuer = %s
              AND f.follower_subject = %s
              AND f.followee_issuer = p.author_issuer
              AND f.followee_subject = p.author_subject
        )
    ) AS viewer_following
"""


def _viewer_params(viewer_issuer: str | None, viewer_subject: str | None) -> tuple[str, str]:
    """Viewer identity for the viewer_liked/viewer_following subqueries.

    ``None`` is passed straight to psycopg2 (SQL NULL), which makes the
    ``l.issuer = %s`` predicate evaluate to NULL and the EXISTS clause to FALSE.
    """
    return (viewer_issuer or None, viewer_subject or None)  # type: ignore[return-value]


class CommunityRepository:
    """psycopg2-backed community data access.

    ``connect`` is injectable so unit tests can drive the SQL with a fake
    connection (same pattern as ``IdentityRepository``).
    """

    def __init__(
        self,
        settings: Settings,
        *,
        connect: Callable[..., object] | None = None,
    ) -> None:
        self._settings = settings
        self._connect = connect or _connect

    def list_posts(
        self,
        *,
        limit: int,
        offset: int,
        viewer_issuer: str | None,
        viewer_subject: str | None,
    ) -> tuple[list[dict[str, Any]], int]:
        sql = f"""
            SELECT {_POST_LIST_COLUMNS}
            FROM community.user_posts p
            JOIN identity.users u
              ON u.issuer = p.author_issuer AND u.subject = p.author_subject
            ORDER BY p.created_at DESC, p.id DESC
            LIMIT %s OFFSET %s
        """
        total_sql = "SELECT count(*)::int FROM community.user_posts"
        # The viewer pair is bound once per viewer-state subquery
        # (viewer_liked, then viewer_following).
        viewer = _viewer_params(viewer_issuer, viewer_subject) * 2
        with self._cursor() as cur:
            cur.execute(total_sql)
            total = int(cur.fetchone()["count"])  # type: ignore[index]
            cur.execute(sql, (*viewer, limit, offset))
            rows = list(cur.fetchall())
        return rows, total

    def get_post(
        self,
        *,
        post_id: UUID,
        viewer_issuer: str | None,
        viewer_subject: str | None,
    ) -> dict[str, Any] | None:
        sql = f"""
            SELECT {_POST_LIST_COLUMNS}
            FROM community.user_posts p
            JOIN identity.users u
              ON u.issuer = p.author_issuer AND u.subject = p.author_subject
            WHERE p.id = %s
        """
        viewer = _viewer_params(viewer_issuer, viewer_subject) * 2
        with self._cursor() as cur:
            cur.execute(sql, (*viewer, str(post_id)))
            return cur.fetchone()

    def create_post(
        self,
        *,
        issuer: str,
        subject: str,
        title: str,
        body: str,
        tags: list[str],
    ) -> dict[str, Any]:
        sql = """
            INSERT INTO community.user_posts
                (author_issuer, author_subject, title, body, tags)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING
                id,
                author_issuer,
                author_subject,
                title,
                body,
                tags,
                created_at,
                updated_at
        """
        with self._cursor() as cur:
            cur.execute(sql, (issuer, subject, title, body, tags))
            row = cur.fetchone()
        assert row is not None  # RETURNING always yields one row on insert.
        return row

    def list_comments(
        self, *, post_id: UUID, limit: int, offset: int
    ) -> tuple[list[dict[str, Any]], int]:
        sql = """
            SELECT
                c.id,
                c.post_id,
                c.author_issuer,
                c.author_subject,
                c.body,
                c.created_at,
                c.updated_at,
                u.id AS author_user_id
            FROM community.post_comments c
            JOIN identity.users u
              ON u.issuer = c.author_issuer AND u.subject = c.author_subject
            WHERE c.post_id = %s
            ORDER BY c.created_at ASC, c.id ASC
            LIMIT %s OFFSET %s
        """
        total_sql = "SELECT count(*)::int FROM community.post_comments WHERE post_id = %s"
        with self._cursor() as cur:
            cur.execute(total_sql, (str(post_id),))
            total = int(cur.fetchone()["count"])  # type: ignore[index]
            cur.execute(sql, (str(post_id), limit, offset))
            rows = list(cur.fetchall())
        return rows, total

    def create_comment(
        self,
        *,
        post_id: UUID,
        issuer: str,
        subject: str,
        body: str,
    ) -> dict[str, Any] | None:
        sql = """
            INSERT INTO community.post_comments
                (post_id, author_issuer, author_subject, body)
            SELECT %s, %s, %s, %s
            FROM community.user_posts
            WHERE id = %s
            RETURNING
                id,
                post_id,
                author_issuer,
                author_subject,
                body,
                created_at,
                updated_at
        """
        with self._cursor() as cur:
            cur.execute(sql, (str(post_id), issuer, subject, body, str(post_id)))
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

    def toggle_like(self, *, post_id: UUID, issuer: str, subject: str) -> dict[str, Any] | None:
        delete_sql = """
            DELETE FROM community.post_likes
            WHERE post_id = %s AND issuer = %s AND subject = %s
            RETURNING post_id
        """
        insert_sql = """
            INSERT INTO community.post_likes (post_id, issuer, subject)
            SELECT %s, %s, %s
            WHERE EXISTS (SELECT 1 FROM community.user_posts WHERE id = %s)
            ON CONFLICT DO NOTHING
            RETURNING post_id
        """
        count_sql = (
            "SELECT count(*)::int AS like_count FROM community.post_likes WHERE post_id = %s"
        )
        with self._cursor() as cur:
            cur.execute(delete_sql, (str(post_id), issuer, subject))
            deleted = cur.fetchone()
            if deleted is not None:
                liked = False
            else:
                cur.execute(insert_sql, (str(post_id), issuer, subject, str(post_id)))
                liked = cur.fetchone() is not None
            cur.execute(count_sql, (str(post_id),))
            count_row = cur.fetchone()
            if count_row is None:
                return None
            like_count = int(count_row["like_count"])  # type: ignore[index]
        return {"post_id": str(post_id), "liked": liked, "like_count": like_count}

    def list_follows(
        self,
        *,
        issuer: str,
        subject: str,
        limit: int,
        offset: int,
    ) -> tuple[list[dict[str, Any]], int]:
        sql = """
            SELECT
                u.id AS followee_user_id,
                f.created_at
            FROM community.user_follows f
            JOIN identity.users u
              ON u.issuer = f.followee_issuer AND u.subject = f.followee_subject
            WHERE f.follower_issuer = %s AND f.follower_subject = %s
            ORDER BY f.created_at DESC, u.id DESC
            LIMIT %s OFFSET %s
        """
        total_sql = (
            "SELECT count(*)::int FROM community.user_follows "
            "WHERE follower_issuer = %s AND follower_subject = %s"
        )
        with self._cursor() as cur:
            cur.execute(total_sql, (issuer, subject))
            total = int(cur.fetchone()["count"])  # type: ignore[index]
            cur.execute(sql, (issuer, subject, limit, offset))
            rows = list(cur.fetchall())
        return rows, total

    def toggle_follow(
        self,
        *,
        follower_issuer: str,
        follower_subject: str,
        followee_user_id: UUID,
    ) -> dict[str, Any]:
        """Toggle a follow addressed by the followee's internal user UUID.

        The wire never carries issuer/subject pairs for the followee, so the
        repository resolves them server-side and reports back only an outcome;
        policy (self-follow, missing followee) is decided by the service.
        """
        resolve_followee_sql = "SELECT issuer, subject FROM identity.users WHERE id = %s"
        resolve_viewer_sql = "SELECT id FROM identity.users WHERE issuer = %s AND subject = %s"
        delete_sql = """
            DELETE FROM community.user_follows
            WHERE follower_issuer = %s AND follower_subject = %s
              AND followee_issuer = %s AND followee_subject = %s
            RETURNING followee_issuer
        """
        insert_sql = """
            INSERT INTO community.user_follows
                (follower_issuer, follower_subject, followee_issuer, followee_subject)
            VALUES (%s, %s, %s, %s)
            RETURNING followee_issuer
        """
        with self._cursor() as cur:
            cur.execute(resolve_followee_sql, (str(followee_user_id),))
            followee = cur.fetchone()
            if followee is None:
                return {"outcome": "missing_followee"}
            cur.execute(resolve_viewer_sql, (follower_issuer, follower_subject))
            viewer = cur.fetchone()
            if viewer is not None and str(viewer["id"]) == str(followee_user_id):
                # Why: the self-follow guard runs before any mutation so a
                # rejected attempt can never create or flip a follow row.
                return {"outcome": "self_follow"}
            cur.execute(
                delete_sql,
                (
                    follower_issuer,
                    follower_subject,
                    followee["issuer"],
                    followee["subject"],
                ),
            )
            following = False
            if cur.fetchone() is None:
                cur.execute(
                    insert_sql,
                    (
                        follower_issuer,
                        follower_subject,
                        followee["issuer"],
                        followee["subject"],
                    ),
                )
                following = cur.fetchone() is not None
        return {"outcome": "followed" if following else "unfollowed"}

    def report_post(
        self,
        *,
        post_id: UUID,
        issuer: str,
        subject: str,
        reason_code: str,
    ) -> dict[str, Any]:
        """Create (or idempotently re-receive) a governed post report.

        The unique partial index on unresolved reports makes a repeat submit
        return the original case unchanged; ``xmax = 0`` distinguishes the
        fresh insert from the conflict path without a second round trip.
        """
        author_sql = "SELECT author_issuer, author_subject FROM community.user_posts WHERE id = %s"
        insert_sql = """
            INSERT INTO community.post_reports AS r
                (post_id, reporter_issuer, reporter_subject, reason_code)
            SELECT %s, %s, %s, %s
            ON CONFLICT (reporter_issuer, reporter_subject, post_id)
                WHERE status IN ('open', 'triaged')
            DO UPDATE SET reason_code = r.reason_code
            RETURNING r.id, r.reason_code, r.status, (xmax = 0) AS inserted
        """
        with self._cursor() as cur:
            cur.execute(author_sql, (str(post_id),))
            post = cur.fetchone()
            if post is None:
                return {"outcome": "missing_post"}
            if post["author_issuer"] == issuer and post["author_subject"] == subject:
                # Why: a self-report is rejected before the insert so the
                # one-report-per-reporter slot is never consumed by it.
                return {"outcome": "self_report"}
            cur.execute(insert_sql, (str(post_id), issuer, subject, reason_code))
            row = cur.fetchone()
            assert row is not None  # DO UPDATE always returns the conflicted row.
        return {
            "outcome": "created" if row["inserted"] else "duplicate",
            "report_id": row["id"],
            "reason_code": row["reason_code"],
            "status": row["status"],
        }

    @contextmanager
    def _cursor(self) -> Iterator[Any]:
        if not self._settings.db_dsn:
            raise CommunityRepositoryUnavailable()
        try:
            from psycopg2.extras import RealDictCursor
        except Exception as exc:
            raise CommunityRepositoryUnavailable() from exc
        try:
            with closing(self._connect(dsn=self._settings.db_dsn, connect_timeout=3)) as conn:
                with conn:
                    with conn.cursor(cursor_factory=RealDictCursor) as cur:
                        yield cur
        except CommunityRepositoryUnavailable:
            raise
        except Exception as exc:
            raise CommunityRepositoryUnavailable() from exc


def _connect(*, dsn: str, connect_timeout: int):
    try:
        import psycopg2
    except Exception as exc:
        raise CommunityRepositoryUnavailable() from exc
    return psycopg2.connect(dsn, connect_timeout=connect_timeout)


class CommunityService:
    """Thin orchestration layer that shapes repository rows and maps DB errors."""

    def __init__(self, repository: CommunityRepository) -> None:
        self._repository = repository

    def list_posts(
        self,
        *,
        limit: int,
        offset: int,
        viewer_issuer: str | None,
        viewer_subject: str | None,
    ) -> dict[str, Any]:
        try:
            rows, total = self._repository.list_posts(
                limit=limit,
                offset=offset,
                viewer_issuer=viewer_issuer,
                viewer_subject=viewer_subject,
            )
        except CommunityRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        return {"count": len(rows), "total": total, "posts": [_post_payload(row) for row in rows]}

    def get_post(
        self,
        *,
        post_id: UUID,
        viewer_issuer: str | None,
        viewer_subject: str | None,
    ) -> dict[str, Any]:
        try:
            row = self._repository.get_post(
                post_id=post_id,
                viewer_issuer=viewer_issuer,
                viewer_subject=viewer_subject,
            )
        except CommunityRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if row is None:
            raise _not_found("COMMUNITY_POST_NOT_FOUND", "Community post was not found.")
        return _post_payload(row)

    def create_post(
        self,
        *,
        issuer: str,
        subject: str,
        title: str,
        body: str,
        tags: list[str],
    ) -> dict[str, Any]:
        try:
            row = self._repository.create_post(
                issuer=issuer,
                subject=subject,
                title=title,
                body=body,
                tags=tags,
            )
            return _post_payload(row)
        except CommunityRepositoryUnavailable as exc:
            raise _database_unavailable() from exc

    def list_comments(self, *, post_id: UUID, limit: int, offset: int) -> dict[str, Any]:
        try:
            rows, total = self._repository.list_comments(
                post_id=post_id, limit=limit, offset=offset
            )
        except CommunityRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        return {
            "count": len(rows),
            "total": total,
            "comments": [_comment_payload(row) for row in rows],
        }

    def create_comment(
        self,
        *,
        post_id: UUID,
        issuer: str,
        subject: str,
        body: str,
    ) -> dict[str, Any]:
        try:
            row = self._repository.create_comment(
                post_id=post_id, issuer=issuer, subject=subject, body=body
            )
        except CommunityRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if row is None:
            raise _not_found("COMMUNITY_POST_NOT_FOUND", "Community post was not found.")
        return _comment_payload(row)

    def toggle_like(self, *, post_id: UUID, issuer: str, subject: str) -> dict[str, Any]:
        try:
            row = self._repository.toggle_like(post_id=post_id, issuer=issuer, subject=subject)
        except CommunityRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        if row is None:
            raise _not_found("COMMUNITY_POST_NOT_FOUND", "Community post was not found.")
        return row

    def list_follows(self, *, issuer: str, subject: str, limit: int, offset: int) -> dict[str, Any]:
        try:
            rows, total = self._repository.list_follows(
                issuer=issuer, subject=subject, limit=limit, offset=offset
            )
        except CommunityRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        return {
            "count": len(rows),
            "total": total,
            "follows": [_follow_payload(row) for row in rows],
        }

    def toggle_follow(
        self,
        *,
        follower_issuer: str,
        follower_subject: str,
        followee_user_id: UUID,
    ) -> dict[str, Any]:
        try:
            row = self._repository.toggle_follow(
                follower_issuer=follower_issuer,
                follower_subject=follower_subject,
                followee_user_id=followee_user_id,
            )
        except CommunityRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        outcome = row.get("outcome")
        if outcome == "missing_followee":
            raise _not_found("COMMUNITY_FOLLOWEE_NOT_FOUND", "Followee user was not found.")
        if outcome == "self_follow":
            raise ServiceError(
                status_code=422,
                code="INVALID_FOLLOW_TARGET",
                message="A user cannot follow themselves.",
                retryable=False,
            )
        return {"followee_user_id": str(followee_user_id), "following": outcome == "followed"}

    def report_post(
        self,
        *,
        post_id: UUID,
        issuer: str,
        subject: str,
        reason_code: str,
    ) -> dict[str, Any]:
        try:
            row = self._repository.report_post(
                post_id=post_id,
                issuer=issuer,
                subject=subject,
                reason_code=reason_code,
            )
        except CommunityRepositoryUnavailable as exc:
            raise _database_unavailable() from exc
        outcome = row.get("outcome")
        if outcome == "missing_post":
            raise _not_found("COMMUNITY_POST_NOT_FOUND", "Community post was not found.")
        if outcome == "self_report":
            raise ServiceError(
                status_code=422,
                code="INVALID_REPORT_TARGET",
                message="A user cannot report their own post.",
                retryable=False,
            )
        return {
            "report_id": str(row["report_id"]),
            "reason_code": row["reason_code"],
            "status": row["status"],
            "duplicate": outcome == "duplicate",
        }


def get_community_service() -> CommunityService:
    return CommunityService(CommunityRepository(get_settings()))


def _post_payload(row: dict[str, Any]) -> dict[str, Any]:
    created_at = row.get("created_at")
    updated_at = row.get("updated_at")
    return {
        "id": str(row["id"]),
        "author_user_id": str(row["author_user_id"]),
        "title": row["title"],
        "body": row["body"],
        "tags": list(row.get("tags") or []),
        "comment_count": int(row.get("comment_count") or 0),
        "like_count": int(row.get("like_count") or 0),
        "viewer_liked": bool(row.get("viewer_liked")),
        "viewer_following": bool(row.get("viewer_following")),
        "created_at": created_at.isoformat() if created_at else None,
        "updated_at": updated_at.isoformat() if updated_at else None,
    }


def _comment_payload(row: dict[str, Any]) -> dict[str, Any]:
    created_at = row.get("created_at")
    updated_at = row.get("updated_at")
    author_user_id = row.get("author_user_id")
    return {
        "id": str(row["id"]),
        "post_id": str(row["post_id"]),
        "author_user_id": str(author_user_id) if author_user_id is not None else None,
        "body": row["body"],
        "created_at": created_at.isoformat() if created_at else None,
        "updated_at": updated_at.isoformat() if updated_at else None,
    }


def _follow_payload(row: dict[str, Any]) -> dict[str, Any]:
    created_at = row.get("created_at")
    followee_user_id = row.get("followee_user_id")
    return {
        "followee_user_id": str(followee_user_id) if followee_user_id is not None else None,
        "created_at": created_at.isoformat() if created_at else None,
    }


def _database_unavailable() -> ServiceError:
    return ServiceError(
        status_code=503,
        code="COMMUNITY_DB_UNAVAILABLE",
        message="Community content store is temporarily unavailable.",
        retryable=True,
    )


def _not_found(code: str, message: str) -> ServiceError:
    return ServiceError(
        status_code=404,
        code=code,
        message=message,
        retryable=False,
    )
