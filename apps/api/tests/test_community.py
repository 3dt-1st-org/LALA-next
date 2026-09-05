from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import pytest

from apps.api.app.core.auth import RequestIdentity, require_oauth_identity
from apps.api.app.core.config import Settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.routers.community import _viewer_identity
from apps.api.app.services.community_service import (
    CommunityRepository,
    CommunityRepositoryUnavailable,
    CommunityService,
    get_community_service,
)

POST_ID = UUID("00000000-0000-0000-0000-000000000001")
AUTHOR_ID = UUID("00000000-0000-0000-0000-000000000002")
FOLLOWEE_ID = UUID("00000000-0000-0000-0000-000000000003")
AUTHOR_USER_ID = UUID("00000000-0000-0000-0000-000000000002")
REPORT_ID = UUID("00000000-0000-0000-0000-000000000004")
NOW = datetime(2026, 7, 23, tzinfo=UTC)
ISSUER = "https://issuer.example"
SUBJECT = "user-subject"
DB_DSN = "postgresql://redacted"


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


def _repo(rows: list[Any]) -> tuple[CommunityRepository, list[tuple[str, Any]]]:
    executed: list[tuple[str, Any]] = []
    repository = CommunityRepository(
        Settings(db_dsn=DB_DSN),
        connect=lambda **kwargs: FakeConnection(rows, executed),
    )
    return repository, executed


def _post_row(
    *,
    viewer_liked: bool = False,
    viewer_following: bool = False,
) -> dict[str, Any]:
    return {
        "id": POST_ID,
        "author_issuer": ISSUER,
        "author_subject": SUBJECT,
        "title": "title",
        "body": "body",
        "tags": ["travel", "food"],
        "created_at": NOW,
        "updated_at": NOW,
        "author_user_id": AUTHOR_ID,
        "comment_count": 3,
        "like_count": 5,
        "viewer_liked": viewer_liked,
        "viewer_following": viewer_following,
    }


# ---------------------------------------------------------------------------
# Repository: SQL generation + row shaping (no real database).
# ---------------------------------------------------------------------------


def test_list_posts_emits_count_then_paginated_query_and_returns_rows() -> None:
    repository, executed = _repo([{"count": 1}, _post_row()])

    rows, total = repository.list_posts(
        limit=20, offset=0, viewer_issuer=ISSUER, viewer_subject=SUBJECT
    )

    assert total == 1
    assert rows == [_post_row()]
    assert len(executed) == 2
    assert "count(*)" in executed[0][0]
    assert "FROM community.user_posts" in executed[0][0]
    list_sql = executed[1][0]
    assert "FROM community.user_posts p" in list_sql
    assert "JOIN identity.users u" in list_sql
    assert "ORDER BY p.created_at DESC" in list_sql
    # Viewer identity is bound once per viewer-state subquery: viewer_liked
    # first, then viewer_following.
    assert "AS viewer_liked" in list_sql
    assert "AS viewer_following" in list_sql
    assert "FROM community.user_follows f" in list_sql
    assert executed[1][1] == (ISSUER, SUBJECT, ISSUER, SUBJECT, 20, 0)


def test_list_posts_passes_null_viewer_when_anonymous() -> None:
    repository, executed = _repo([{"count": 0}])

    repository.list_posts(limit=10, offset=0, viewer_issuer=None, viewer_subject=None)

    assert executed[1][1] == (None, None, None, None, 10, 0)


def test_create_post_inserts_author_identity_tags_and_returns_row() -> None:
    repository, executed = _repo([_post_row(), {"id": AUTHOR_USER_ID}])

    row = repository.create_post(
        issuer=ISSUER, subject=SUBJECT, title="title", body="body", tags=["travel"]
    )

    assert row == _post_row()
    sql, params = executed[0]
    assert "INSERT INTO community.user_posts" in sql
    assert "author_issuer, author_subject, title, body, tags" in sql
    assert params == (ISSUER, SUBJECT, "title", "body", ["travel"])
    # The author's internal uuid is resolved on the same connection so the
    # response payload never exposes issuer/subject identity.
    assert "FROM identity.users" in executed[1][0]


def test_toggle_like_likes_when_no_existing_row() -> None:
    repository, executed = _repo([None, {"post_id": str(POST_ID)}, {"like_count": 1}])

    result = repository.toggle_like(post_id=POST_ID, issuer=ISSUER, subject=SUBJECT)

    assert result == {"post_id": str(POST_ID), "liked": True, "like_count": 1}
    assert "DELETE FROM community.post_likes" in executed[0][0]
    assert "INSERT INTO community.post_likes" in executed[1][0]
    assert "count(*)" in executed[2][0]


def test_toggle_like_unlikes_when_existing_row_removed() -> None:
    repository, executed = _repo([{"post_id": str(POST_ID)}, {"like_count": 0}])

    result = repository.toggle_like(post_id=POST_ID, issuer=ISSUER, subject=SUBJECT)

    assert result == {"post_id": str(POST_ID), "liked": False, "like_count": 0}
    # Delete path skips the insert entirely.
    assert len(executed) == 2
    assert "DELETE FROM community.post_likes" in executed[0][0]
    assert "count(*)" in executed[1][0]


def test_create_comment_resolves_author_identity_across_two_cursors() -> None:
    inserted = {
        "id": POST_ID,
        "post_id": POST_ID,
        "author_issuer": ISSUER,
        "author_subject": SUBJECT,
        "body": "hi",
        "created_at": NOW,
        "updated_at": NOW,
    }
    repository, executed = _repo([inserted, {"id": AUTHOR_ID}])

    row = repository.create_comment(post_id=POST_ID, issuer=ISSUER, subject=SUBJECT, body="hi")

    assert row["body"] == "hi"
    assert row["author_user_id"] == AUTHOR_ID
    assert "INSERT INTO community.post_comments" in executed[0][0]
    assert "SELECT %s, %s, %s, %s\n            FROM community.user_posts" in executed[0][0]
    assert "FROM identity.users" in executed[1][0]


def test_create_comment_returns_none_when_post_missing() -> None:
    repository, _executed = _repo([None])

    assert (
        repository.create_comment(post_id=POST_ID, issuer=ISSUER, subject=SUBJECT, body="hi")
        is None
    )


def test_toggle_follow_follows_by_user_id_with_identity_resolved_server_side() -> None:
    repository, executed = _repo(
        [
            {"issuer": "https://other.example", "subject": "followee-subject"},
            {"id": AUTHOR_ID},
            None,
            {"followee_issuer": "https://other.example"},
        ]
    )

    result = repository.toggle_follow(
        follower_issuer=ISSUER,
        follower_subject=SUBJECT,
        followee_user_id=FOLLOWEE_ID,
    )

    assert result == {"outcome": "followed"}
    # The followee identity is resolved from the internal UUID, never from wire.
    assert "FROM identity.users WHERE id = %s" in executed[0][0]
    assert executed[0][1] == (str(FOLLOWEE_ID),)
    assert executed[1][1] == (ISSUER, SUBJECT)
    assert "DELETE FROM community.user_follows" in executed[2][0]
    assert executed[2][1] == (
        ISSUER,
        SUBJECT,
        "https://other.example",
        "followee-subject",
    )
    assert "INSERT INTO community.user_follows" in executed[3][0]


def test_toggle_follow_unfollows_when_existing_row_removed() -> None:
    repository, executed = _repo(
        [
            {"issuer": "https://other.example", "subject": "followee-subject"},
            {"id": AUTHOR_ID},
            {"followee_issuer": "https://other.example"},
        ]
    )

    result = repository.toggle_follow(
        follower_issuer=ISSUER,
        follower_subject=SUBJECT,
        followee_user_id=FOLLOWEE_ID,
    )

    assert result == {"outcome": "unfollowed"}
    # Delete hit, so no INSERT statement is issued.
    assert len(executed) == 3
    assert "INSERT INTO community.user_follows" not in executed[-1][0]


def test_toggle_follow_missing_followee_short_circuits_before_mutation() -> None:
    repository, executed = _repo([None])

    result = repository.toggle_follow(
        follower_issuer=ISSUER,
        follower_subject=SUBJECT,
        followee_user_id=FOLLOWEE_ID,
    )

    assert result == {"outcome": "missing_followee"}
    assert all("user_follows" not in sql for sql, _ in executed)


def test_toggle_follow_self_target_returns_outcome_without_mutation() -> None:
    repository, executed = _repo(
        [
            {"issuer": ISSUER, "subject": SUBJECT},
            {"id": FOLLOWEE_ID},
        ]
    )

    result = repository.toggle_follow(
        follower_issuer=ISSUER,
        follower_subject=SUBJECT,
        followee_user_id=FOLLOWEE_ID,
    )

    assert result == {"outcome": "self_follow"}
    # The guard runs before the DELETE/INSERT so a self-follow never persists.
    assert all("user_follows" not in sql for sql, _ in executed)


def test_report_post_inserts_bounded_reason_and_returns_receipt() -> None:
    repository, executed = _repo(
        [
            {"author_issuer": "https://other.example", "author_subject": "author"},
            {
                "id": REPORT_ID,
                "reason_code": "spam_promotion",
                "status": "open",
                "inserted": True,
            },
        ]
    )

    result = repository.report_post(
        post_id=POST_ID,
        issuer=ISSUER,
        subject=SUBJECT,
        reason_code="spam_promotion",
    )

    assert result == {
        "outcome": "created",
        "report_id": REPORT_ID,
        "reason_code": "spam_promotion",
        "status": "open",
    }
    author_sql, author_params = executed[0]
    assert "FROM community.user_posts" in author_sql
    assert author_params == (str(POST_ID),)
    insert_sql, insert_params = executed[1]
    assert "INSERT INTO community.post_reports" in insert_sql
    # One unresolved report per reporter/post; a conflict replays the original
    # receipt instead of taking the new reason.
    assert "ON CONFLICT (reporter_issuer, reporter_subject, post_id)" in insert_sql
    assert "DO UPDATE SET reason_code = r.reason_code" in insert_sql
    assert insert_params == (str(POST_ID), ISSUER, SUBJECT, "spam_promotion")


def test_report_post_conflict_returns_original_receipt_as_duplicate() -> None:
    repository, _ = _repo(
        [
            {"author_issuer": "https://other.example", "author_subject": "author"},
            {
                "id": REPORT_ID,
                "reason_code": "privacy_exposure",
                "status": "open",
                "inserted": False,
            },
        ]
    )

    result = repository.report_post(
        post_id=POST_ID,
        issuer=ISSUER,
        subject=SUBJECT,
        reason_code="misinformation",
    )

    assert result == {
        "outcome": "duplicate",
        # The originally recorded reason is the receipt, not the new value.
        "report_id": REPORT_ID,
        "reason_code": "privacy_exposure",
        "status": "open",
    }


def test_report_post_missing_post_and_self_report_short_circuit() -> None:
    missing, _ = _repo([None])
    assert missing.report_post(
        post_id=POST_ID, issuer=ISSUER, subject=SUBJECT, reason_code="misinformation"
    ) == {"outcome": "missing_post"}

    self_report, executed = _repo([{"author_issuer": ISSUER, "author_subject": SUBJECT}])
    assert self_report.report_post(
        post_id=POST_ID, issuer=ISSUER, subject=SUBJECT, reason_code="misinformation"
    ) == {"outcome": "self_report"}
    # No INSERT is issued for a self-report.
    assert all("post_reports" not in sql for sql, _ in executed)


def test_repository_without_dsn_is_unavailable() -> None:
    repository = CommunityRepository(Settings(db_dsn=""))

    with pytest.raises(CommunityRepositoryUnavailable):
        repository.list_posts(limit=1, offset=0, viewer_issuer=None, viewer_subject=None)


# ---------------------------------------------------------------------------
# Service: error mapping + payload shaping.
# ---------------------------------------------------------------------------


class _UnavailableRepository:
    def list_posts(self, **_: Any) -> tuple[list[dict[str, Any]], int]:
        raise CommunityRepositoryUnavailable()

    def get_post(self, **_: Any) -> dict[str, Any] | None:
        raise CommunityRepositoryUnavailable()

    def create_post(self, **_: Any) -> dict[str, Any]:
        raise CommunityRepositoryUnavailable()

    def list_comments(self, **_: Any) -> tuple[list[dict[str, Any]], int]:
        raise CommunityRepositoryUnavailable()

    def create_comment(self, **_: Any) -> dict[str, Any] | None:
        raise CommunityRepositoryUnavailable()

    def toggle_like(self, **_: Any) -> dict[str, Any] | None:
        raise CommunityRepositoryUnavailable()

    def list_follows(self, **_: Any) -> tuple[list[dict[str, Any]], int]:
        raise CommunityRepositoryUnavailable()

    def toggle_follow(self, **_: Any) -> dict[str, Any]:
        raise CommunityRepositoryUnavailable()

    def report_post(self, **_: Any) -> dict[str, Any]:
        raise CommunityRepositoryUnavailable()


def test_service_maps_repository_unavailability_to_retryable_503() -> None:
    service = CommunityService(_UnavailableRepository())

    with pytest.raises(ServiceError) as exc_info:
        service.list_posts(limit=1, offset=0, viewer_issuer=None, viewer_subject=None)

    assert exc_info.value.status_code == 503
    assert exc_info.value.code == "COMMUNITY_DB_UNAVAILABLE"
    assert exc_info.value.retryable is True


def test_service_maps_follow_outcomes() -> None:
    class StubRepository(_UnavailableRepository):
        def __init__(self, outcome: str) -> None:
            self.outcome = outcome

        def toggle_follow(self, **_: Any) -> dict[str, Any]:
            return {"outcome": self.outcome}

    followed = CommunityService(StubRepository("followed")).toggle_follow(
        follower_issuer=ISSUER,
        follower_subject=SUBJECT,
        followee_user_id=FOLLOWEE_ID,
    )
    assert followed == {"followee_user_id": str(FOLLOWEE_ID), "following": True}

    unfollowed = CommunityService(StubRepository("unfollowed")).toggle_follow(
        follower_issuer=ISSUER,
        follower_subject=SUBJECT,
        followee_user_id=FOLLOWEE_ID,
    )
    assert unfollowed == {"followee_user_id": str(FOLLOWEE_ID), "following": False}

    with pytest.raises(ServiceError) as missing_info:
        CommunityService(StubRepository("missing_followee")).toggle_follow(
            follower_issuer=ISSUER,
            follower_subject=SUBJECT,
            followee_user_id=FOLLOWEE_ID,
        )
    assert missing_info.value.status_code == 404
    assert missing_info.value.code == "COMMUNITY_FOLLOWEE_NOT_FOUND"

    with pytest.raises(ServiceError) as self_info:
        CommunityService(StubRepository("self_follow")).toggle_follow(
            follower_issuer=ISSUER,
            follower_subject=SUBJECT,
            followee_user_id=FOLLOWEE_ID,
        )
    assert self_info.value.status_code == 422
    assert self_info.value.code == "INVALID_FOLLOW_TARGET"
    assert self_info.value.retryable is False


def test_service_maps_report_outcomes() -> None:
    class StubRepository(_UnavailableRepository):
        def __init__(self, outcome: dict[str, Any]) -> None:
            self.outcome = outcome

        def report_post(self, **_: Any) -> dict[str, Any]:
            return self.outcome

    created = CommunityService(
        StubRepository(
            {
                "outcome": "created",
                "report_id": REPORT_ID,
                "reason_code": "spam_promotion",
                "status": "open",
            }
        )
    ).report_post(post_id=POST_ID, issuer=ISSUER, subject=SUBJECT, reason_code="spam_promotion")
    assert created == {
        "report_id": str(REPORT_ID),
        "reason_code": "spam_promotion",
        "status": "open",
        "duplicate": False,
    }

    duplicate = CommunityService(
        StubRepository(
            {
                "outcome": "duplicate",
                "report_id": REPORT_ID,
                "reason_code": "privacy_exposure",
                "status": "open",
            }
        )
    ).report_post(post_id=POST_ID, issuer=ISSUER, subject=SUBJECT, reason_code="misinformation")
    assert duplicate == {
        "report_id": str(REPORT_ID),
        "reason_code": "privacy_exposure",
        "status": "open",
        "duplicate": True,
    }

    with pytest.raises(ServiceError) as missing_info:
        CommunityService(StubRepository({"outcome": "missing_post"})).report_post(
            post_id=POST_ID, issuer=ISSUER, subject=SUBJECT, reason_code="misinformation"
        )
    assert missing_info.value.status_code == 404
    assert missing_info.value.code == "COMMUNITY_POST_NOT_FOUND"

    with pytest.raises(ServiceError) as self_info:
        CommunityService(StubRepository({"outcome": "self_report"})).report_post(
            post_id=POST_ID, issuer=ISSUER, subject=SUBJECT, reason_code="misinformation"
        )
    assert self_info.value.status_code == 422
    assert self_info.value.code == "INVALID_REPORT_TARGET"
    assert self_info.value.retryable is False


def test_service_get_post_maps_missing_row_to_404() -> None:
    class MissingRepository(_UnavailableRepository):
        def get_post(self, **_: Any) -> dict[str, Any] | None:
            return None

    service = CommunityService(MissingRepository())

    with pytest.raises(ServiceError) as exc_info:
        service.get_post(post_id=POST_ID, viewer_issuer=None, viewer_subject=None)

    assert exc_info.value.status_code == 404
    assert exc_info.value.code == "COMMUNITY_POST_NOT_FOUND"


def test_service_shapes_post_payload_with_aggregates() -> None:
    class StubRepository(_UnavailableRepository):
        def list_posts(self, **kwargs: Any) -> tuple[list[dict[str, Any]], int]:
            return ([_post_row(viewer_liked=True, viewer_following=True)], 1)

    service = CommunityService(StubRepository())

    payload = service.list_posts(limit=1, offset=0, viewer_issuer=ISSUER, viewer_subject=SUBJECT)

    assert payload == {
        "count": 1,
        "total": 1,
        "posts": [
            {
                "id": str(POST_ID),
                "author_user_id": str(AUTHOR_ID),
                "title": "title",
                "body": "body",
                "tags": ["travel", "food"],
                "comment_count": 3,
                "like_count": 5,
                "viewer_liked": True,
                "viewer_following": True,
                "created_at": NOW.isoformat(),
                "updated_at": NOW.isoformat(),
            }
        ],
    }


# ---------------------------------------------------------------------------
# Router: auth gating + envelope contract.
# ---------------------------------------------------------------------------


class FakeCommunityService:
    def __init__(self) -> None:
        self.created_posts: list[tuple[str, str, str, str, list[str]]] = []
        self.toggled_likes: list[tuple[UUID, str, str]] = []
        self.follow_calls: list[tuple[str, str, UUID]] = []
        self.report_calls: list[tuple[UUID, str, str, str]] = []
        self.report_result: dict[str, Any] | None = None

    def list_posts(self, **kwargs: Any) -> dict[str, Any]:
        return {"count": 0, "total": 0, "posts": []}

    def get_post(self, **kwargs: Any) -> dict[str, Any]:
        raise ServiceError(
            status_code=404, code="COMMUNITY_POST_NOT_FOUND", message="x", retryable=False
        )

    def create_post(self, **kwargs: Any) -> dict[str, Any]:
        self.created_posts.append(
            (
                kwargs["issuer"],
                kwargs["subject"],
                kwargs["title"],
                kwargs["body"],
                kwargs["tags"],
            )
        )
        return {
            "id": str(POST_ID),
            "author_user_id": str(AUTHOR_ID),
            "title": kwargs["title"],
            "body": kwargs["body"],
            "tags": kwargs["tags"],
            "comment_count": 0,
            "like_count": 0,
            "viewer_liked": False,
            "viewer_following": False,
            "created_at": NOW.isoformat(),
            "updated_at": NOW.isoformat(),
        }

    def list_comments(self, **kwargs: Any) -> dict[str, Any]:
        return {"count": 0, "total": 0, "comments": []}

    def create_comment(self, **kwargs: Any) -> dict[str, Any]:
        return {
            "id": str(POST_ID),
            "post_id": str(kwargs["post_id"]),
            "author_user_id": str(AUTHOR_ID),
            "body": kwargs["body"],
            "created_at": NOW.isoformat(),
            "updated_at": NOW.isoformat(),
        }

    def toggle_like(self, **kwargs: Any) -> dict[str, Any]:
        self.toggled_likes.append((kwargs["post_id"], kwargs["issuer"], kwargs["subject"]))
        return {"post_id": str(kwargs["post_id"]), "liked": True, "like_count": 1}

    def list_follows(self, **kwargs: Any) -> dict[str, Any]:
        return {"count": 0, "total": 0, "follows": []}

    def toggle_follow(self, **kwargs: Any) -> dict[str, Any]:
        self.follow_calls.append(
            (
                kwargs["follower_issuer"],
                kwargs["follower_subject"],
                kwargs["followee_user_id"],
            )
        )
        if kwargs["followee_user_id"] == AUTHOR_ID:
            raise ServiceError(
                status_code=422,
                code="INVALID_FOLLOW_TARGET",
                message="A user cannot follow themselves.",
                retryable=False,
            )
        return {"followee_user_id": str(FOLLOWEE_ID), "following": True}

    def report_post(self, **kwargs: Any) -> dict[str, Any]:
        self.report_calls.append(
            (
                kwargs["post_id"],
                kwargs["issuer"],
                kwargs["subject"],
                kwargs["reason_code"],
            )
        )
        if self.report_result is not None:
            return self.report_result
        return {
            "report_id": str(REPORT_ID),
            "reason_code": kwargs["reason_code"],
            "status": "open",
            "duplicate": False,
        }


def _oauth_identity() -> RequestIdentity:
    return RequestIdentity(mode="oauth", issuer=ISSUER, subject=SUBJECT)


def _install_fake_service(client, service: FakeCommunityService) -> None:
    client.app.dependency_overrides[get_community_service] = lambda: service


def test_get_posts_is_guest_readable_and_returns_envelope(client, api_key) -> None:
    service = FakeCommunityService()
    _install_fake_service(client, service)

    response = client.get("/api/v1/community/posts", headers={"X-API-Key": api_key})

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["error"] is None
    assert body["data"] == {"count": 0, "total": 0, "posts": []}
    assert body["meta"]["source"] == "db"
    assert body["meta"]["total"] == 0
    assert "request_id" in body["meta"]


def test_create_post_requires_oauth_identity(client, api_key) -> None:
    service = FakeCommunityService()
    _install_fake_service(client, service)

    response = client.post(
        "/api/v1/community/posts",
        headers={"X-API-Key": api_key},
        json={"title": "t", "body": "b"},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "USER_AUTH_REQUIRED"
    assert service.created_posts == []


def test_create_post_with_oauth_creates_and_returns_envelope(client, api_key) -> None:
    service = FakeCommunityService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        "/api/v1/community/posts",
        headers={"X-API-Key": api_key},
        json={"title": "hello", "body": "world", "tags": ["#Travel", "Travel", ""]},
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["title"] == "hello"
    # '#' stripped, duplicates collapsed, empties dropped (case-sensitive, like GEOND_OPIc).
    assert data["tags"] == ["Travel"]
    assert service.created_posts == [(ISSUER, SUBJECT, "hello", "world", ["Travel"])]


def test_toggle_like_with_oauth_delegates_identity(client, api_key) -> None:
    service = FakeCommunityService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        f"/api/v1/community/posts/{POST_ID}/like",
        headers={"X-API-Key": api_key},
    )

    assert response.status_code == 200
    assert response.json()["data"] == {"post_id": str(POST_ID), "liked": True, "like_count": 1}
    assert service.toggled_likes == [(POST_ID, ISSUER, SUBJECT)]


def test_toggle_follow_rejects_external_identity_fields(client, api_key) -> None:
    service = FakeCommunityService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        "/api/v1/community/follows",
        headers={"X-API-Key": api_key},
        json={"followee_issuer": "https://other.example", "followee_subject": "other"},
    )

    # Why: issuer/subject must not be addressable on the wire — the only
    # accepted followee reference is the internal user UUID.
    assert response.status_code == 422
    assert service.follow_calls == []


def test_toggle_follow_self_target_is_422(client, api_key) -> None:
    service = FakeCommunityService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        "/api/v1/community/follows",
        headers={"X-API-Key": api_key},
        json={"followee_user_id": str(AUTHOR_ID)},
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "INVALID_FOLLOW_TARGET"
    # The guard runs before any follow is persisted (verified at the service layer).


def test_toggle_follow_with_oauth_uses_internal_user_uuid(client, api_key) -> None:
    service = FakeCommunityService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        "/api/v1/community/follows",
        headers={"X-API-Key": api_key},
        json={"followee_user_id": str(FOLLOWEE_ID)},
    )

    assert response.status_code == 200
    assert response.json()["data"] == {"followee_user_id": str(FOLLOWEE_ID), "following": True}
    assert service.follow_calls == [(ISSUER, SUBJECT, FOLLOWEE_ID)]


def test_toggle_follow_requires_oauth_identity(client, api_key) -> None:
    service = FakeCommunityService()
    _install_fake_service(client, service)

    response = client.post(
        "/api/v1/community/follows",
        headers={"X-API-Key": api_key},
        json={"followee_user_id": str(FOLLOWEE_ID)},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "USER_AUTH_REQUIRED"
    assert service.follow_calls == []


def test_report_post_requires_oauth_identity(client, api_key) -> None:
    service = FakeCommunityService()
    _install_fake_service(client, service)

    response = client.post(
        f"/api/v1/community/posts/{POST_ID}/reports",
        headers={"X-API-Key": api_key},
        json={"reason_code": "spam_promotion"},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "USER_AUTH_REQUIRED"
    assert service.report_calls == []


@pytest.mark.parametrize(
    ("payload", "code"),
    [
        ({"reason_code": "not_a_real_reason"}, "literal_error"),
        ({"reason_code": "spam_promotion", "body": "raw free text"}, "extra_forbidden"),
        ({"reason_code": "spam_promotion", "note": "raw free text"}, "extra_forbidden"),
        ({}, "missing"),
    ],
)
def test_report_post_rejects_unknown_reason_and_free_text(client, api_key, payload, code) -> None:
    service = FakeCommunityService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        f"/api/v1/community/posts/{POST_ID}/reports",
        headers={"X-API-Key": api_key},
        json=payload,
    )

    assert response.status_code == 422
    assert service.report_calls == []


def test_report_post_with_oauth_returns_idempotent_receipt(client, api_key) -> None:
    service = FakeCommunityService()
    service.report_result = {
        "report_id": str(REPORT_ID),
        "reason_code": "spam_promotion",
        "status": "open",
        "duplicate": True,
    }
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        f"/api/v1/community/posts/{POST_ID}/reports",
        headers={"X-API-Key": api_key},
        json={"reason_code": "spam_promotion"},
    )

    assert response.status_code == 200
    assert response.json()["data"] == {
        "report_id": str(REPORT_ID),
        "reason_code": "spam_promotion",
        "status": "open",
        "duplicate": True,
    }
    assert service.report_calls == [(POST_ID, ISSUER, SUBJECT, "spam_promotion")]


def test_report_post_not_found_maps_to_404_envelope(client, api_key) -> None:
    class MissingService(FakeCommunityService):
        def report_post(self, **kwargs: Any) -> dict[str, Any]:
            raise ServiceError(
                status_code=404,
                code="COMMUNITY_POST_NOT_FOUND",
                message="Community post was not found.",
                retryable=False,
            )

    _install_fake_service(client, MissingService())
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        f"/api/v1/community/posts/{POST_ID}/reports",
        headers={"X-API-Key": api_key},
        json={"reason_code": "spam_promotion"},
    )

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "COMMUNITY_POST_NOT_FOUND"


def test_service_unavailability_is_returned_as_503_envelope(client, api_key) -> None:
    class UnavailableService(FakeCommunityService):
        def list_posts(self, **kwargs: Any) -> dict[str, Any]:
            raise ServiceError(
                status_code=503,
                code="COMMUNITY_DB_UNAVAILABLE",
                message="Community content store is temporarily unavailable.",
                retryable=True,
            )

    _install_fake_service(client, UnavailableService())

    response = client.get("/api/v1/community/posts", headers={"X-API-Key": api_key})

    assert response.status_code == 503
    assert response.json()["error"]["retryable"] is True


def test_viewer_identity_helper_only_exposes_oauth_identities() -> None:
    assert _viewer_identity(RequestIdentity(mode="oauth", issuer=ISSUER, subject=SUBJECT)) == (
        ISSUER,
        SUBJECT,
    )
    assert _viewer_identity(RequestIdentity(mode="static")) == (None, None)
    assert _viewer_identity(RequestIdentity(mode="public")) == (None, None)
