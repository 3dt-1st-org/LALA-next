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


def _post_row(*, viewer_liked: bool = False) -> dict[str, Any]:
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
    # viewer identity is bound to the viewer_liked subquery first.
    assert executed[1][1] == (ISSUER, SUBJECT, 20, 0)


def test_list_posts_passes_null_viewer_when_anonymous() -> None:
    repository, executed = _repo([{"count": 0}])

    repository.list_posts(limit=10, offset=0, viewer_issuer=None, viewer_subject=None)

    assert executed[1][1] == (None, None, 10, 0)


def test_create_post_inserts_author_identity_tags_and_returns_row() -> None:
    repository, executed = _repo([_post_row()])

    row = repository.create_post(
        issuer=ISSUER, subject=SUBJECT, title="title", body="body", tags=["travel"]
    )

    assert row == _post_row()
    sql, params = executed[0]
    assert "INSERT INTO community.user_posts" in sql
    assert "author_issuer, author_subject, title, body, tags" in sql
    assert params == (ISSUER, SUBJECT, "title", "body", ["travel"])


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


def test_toggle_follow_follows_then_resolves_followee_identity() -> None:
    repository, executed = _repo([None, {"followee_issuer": ISSUER}, {"id": FOLLOWEE_ID}])

    result = repository.toggle_follow(
        follower_issuer=ISSUER,
        follower_subject=SUBJECT,
        followee_issuer="https://other.example",
        followee_subject="followee-subject",
    )

    assert result == {"followee_user_id": FOLLOWEE_ID, "following": True}
    assert "DELETE FROM community.user_follows" in executed[0][0]
    assert "INSERT INTO community.user_follows" in executed[1][0]


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


def test_service_maps_repository_unavailability_to_retryable_503() -> None:
    service = CommunityService(_UnavailableRepository())

    with pytest.raises(ServiceError) as exc_info:
        service.list_posts(limit=1, offset=0, viewer_issuer=None, viewer_subject=None)

    assert exc_info.value.status_code == 503
    assert exc_info.value.code == "COMMUNITY_DB_UNAVAILABLE"
    assert exc_info.value.retryable is True


def test_service_rejects_self_follow_with_422() -> None:
    service = CommunityService(_UnavailableRepository())

    with pytest.raises(ServiceError) as exc_info:
        service.toggle_follow(
            follower_issuer=ISSUER,
            follower_subject=SUBJECT,
            followee_issuer=ISSUER,
            followee_subject=SUBJECT,
        )

    assert exc_info.value.status_code == 422
    assert exc_info.value.code == "INVALID_FOLLOW_TARGET"
    # Repository is never consulted for self-follow.
    assert exc_info.value.retryable is False


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
            return ([_post_row(viewer_liked=True)], 1)

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
        self.follow_calls: list[tuple[str, str, str, str]] = []
        self.fail_follow_with_self = False

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
                kwargs["followee_issuer"],
                kwargs["followee_subject"],
            )
        )
        if (
            kwargs["follower_issuer"] == kwargs["followee_issuer"]
            and kwargs["follower_subject"] == kwargs["followee_subject"]
        ):
            raise ServiceError(
                status_code=422,
                code="INVALID_FOLLOW_TARGET",
                message="A user cannot follow themselves.",
                retryable=False,
            )
        return {"followee_user_id": str(FOLLOWEE_ID), "following": True}


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


def test_toggle_follow_self_target_is_422(client, api_key) -> None:
    service = FakeCommunityService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        "/api/v1/community/follows",
        headers={"X-API-Key": api_key},
        json={"followee_issuer": ISSUER, "followee_subject": SUBJECT},
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "INVALID_FOLLOW_TARGET"
    # The guard runs before any follow is persisted (verified at the service layer).


def test_toggle_follow_with_oauth_creates_follow(client, api_key) -> None:
    service = FakeCommunityService()
    _install_fake_service(client, service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        "/api/v1/community/follows",
        headers={"X-API-Key": api_key},
        json={"followee_issuer": "https://other.example", "followee_subject": "other"},
    )

    assert response.status_code == 200
    assert response.json()["data"] == {"followee_user_id": str(FOLLOWEE_ID), "following": True}
    assert service.follow_calls == [(ISSUER, SUBJECT, "https://other.example", "other")]


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
