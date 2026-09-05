from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import pytest

from apps.api.app.core.auth import RequestIdentity, require_oauth_identity
from apps.api.app.core.config import Settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.services.community_idempotency import canonical_request_hash
from apps.api.app.services.community_service import (
    CommunityRepository,
    CommunityService,
    get_community_service,
)

POST_ID = UUID("00000000-0000-0000-0000-000000000001")
AUTHOR_USER_ID = UUID("00000000-0000-0000-0000-000000000002")
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


def _inserted_post_row() -> dict[str, Any]:
    return {
        "id": POST_ID,
        "author_issuer": ISSUER,
        "author_subject": SUBJECT,
        "title": "title",
        "body": "body",
        "tags": ["travel"],
        "created_at": datetime(2026, 9, 5, tzinfo=UTC),
        "updated_at": datetime(2026, 9, 5, tzinfo=UTC),
    }


def _oauth_identity() -> RequestIdentity:
    return RequestIdentity(mode="oauth", issuer=ISSUER, subject=SUBJECT)


# ===========================================================================
# Repository: durable idempotent post creation protocol.
# ===========================================================================


def test_post_idempotent_created_path_claims_stores_and_returns_payload() -> None:
    repository, executed = _repo(
        [
            {"idempotency_key": "key-1"},  # claim wins
            _inserted_post_row(),  # insert
            {"id": AUTHOR_USER_ID},  # author resolve
        ]
    )
    request_hash = canonical_request_hash({"body": "body", "tags": ["travel"], "title": "title"})

    result = repository.create_post_idempotent(
        issuer=ISSUER,
        subject=SUBJECT,
        title="title",
        body="body",
        tags=["travel"],
        idempotency_key="key-1",
    )

    assert result["outcome"] == "created"
    payload = result["row"]
    assert payload["id"] == str(POST_ID)
    assert payload["author_user_id"] == str(AUTHOR_USER_ID)
    purge_sql, purge_params = executed[0]
    assert "DELETE FROM community.idempotency_keys" in purge_sql
    assert purge_params == ("community.post.create", ISSUER, SUBJECT)
    claim_sql, claim_params = executed[1]
    assert "ON CONFLICT (scope, actor_issuer, actor_subject, idempotency_key)" in claim_sql
    assert claim_params[4] == request_hash
    store_sql, store_params = executed[4]
    assert "SET response_json = %s::jsonb" in store_sql
    assert store_params[4] == "key-1"


def test_post_idempotent_replays_committed_response_without_second_insert() -> None:
    stored = {
        "id": str(POST_ID),
        "author_user_id": str(AUTHOR_USER_ID),
        "title": "title",
        "body": "body",
        "tags": ["travel"],
        "comment_count": 0,
        "like_count": 0,
        "viewer_liked": False,
        "viewer_following": False,
        "created_at": "2026-09-05T00:00:00+00:00",
        "updated_at": "2026-09-05T00:00:00+00:00",
    }
    request_hash = canonical_request_hash({"body": "body", "tags": ["travel"], "title": "title"})
    repository, executed = _repo(
        [
            None,  # claim loses to a committed winner
            {"request_hash": request_hash, "response_json": stored},
        ]
    )

    result = repository.create_post_idempotent(
        issuer=ISSUER,
        subject=SUBJECT,
        title="title",
        body="body",
        tags=["travel"],
        idempotency_key="key-1",
    )

    assert result["outcome"] == "replayed"
    assert result["row"] == stored
    assert not any("INSERT INTO community.user_posts" in sql for sql, _ in executed)


def test_post_idempotent_rejects_same_key_different_payload() -> None:
    request_hash = canonical_request_hash({"body": "body", "tags": ["travel"], "title": "title"})
    repository, executed = _repo(
        [
            None,
            {"request_hash": request_hash, "response_json": {}},
        ]
    )

    result = repository.create_post_idempotent(
        issuer=ISSUER,
        subject=SUBJECT,
        title="different",
        body="body",
        tags=["travel"],
        idempotency_key="key-1",
    )

    assert result == {"outcome": "conflict", "row": None}
    assert not any("INSERT INTO community.user_posts" in sql for sql, _ in executed)


def test_post_idempotent_keys_are_actor_scoped_by_primary_key() -> None:
    repository, executed = _repo(
        [{"idempotency_key": "key-1"}, _inserted_post_row(), {"id": AUTHOR_USER_ID}]
    )

    repository.create_post_idempotent(
        issuer=ISSUER,
        subject=SUBJECT,
        title="t",
        body="b",
        tags=[],
        idempotency_key="key-1",
    )

    claim_sql, claim_params = executed[1]
    assert "ON CONFLICT" in claim_sql  # unique enforcement lives in the DDL
    assert claim_params[0] == "community.post.create"
    assert claim_params[1] == ISSUER and claim_params[2] == SUBJECT
    assert claim_params[3] == "key-1"


# ===========================================================================
# Service + router: durable idempotency surfaces.
# ===========================================================================


class _UnavailableRepository:
    def create_post_idempotent(self, **_: Any) -> dict[str, Any]:
        raise RuntimeError("unavailable")


def test_service_create_post_maps_conflict_to_409() -> None:
    class ConflictRepository(_UnavailableRepository):
        def create_post_idempotent(self, **_: Any) -> dict[str, Any]:
            return {"outcome": "conflict", "row": None}

    service = CommunityService(ConflictRepository())  # type: ignore[arg-type]

    with pytest.raises(ServiceError) as exc_info:
        service.create_post(
            issuer=ISSUER,
            subject=SUBJECT,
            title="t",
            body="b",
            tags=[],
            idempotency_key="key",
        )

    assert exc_info.value.status_code == 409
    assert exc_info.value.code == "IDEMPOTENCY_KEY_CONFLICT"
    assert exc_info.value.retryable is False


def test_service_create_post_replays_stored_payload_verbatim() -> None:
    stored = {
        "id": str(POST_ID),
        "author_user_id": str(AUTHOR_USER_ID),
        "title": "t",
        "body": "b",
        "tags": [],
        "comment_count": 0,
        "like_count": 0,
        "viewer_liked": False,
        "viewer_following": False,
        "created_at": "2026-09-05T00:00:00+00:00",
        "updated_at": "2026-09-05T00:00:00+00:00",
    }

    class ReplayRepository(_UnavailableRepository):
        def create_post_idempotent(self, **_: Any) -> dict[str, Any]:
            return {"outcome": "replayed", "row": dict(stored)}

    payload = CommunityService(ReplayRepository()).create_post(  # type: ignore[arg-type]
        issuer=ISSUER,
        subject=SUBJECT,
        title="t",
        body="b",
        tags=[],
        idempotency_key="key",
    )

    assert payload == stored


def test_router_forwards_idempotency_key_header_to_service(client, api_key) -> None:
    seen: list[dict[str, Any]] = []

    class RecordingService:
        def create_post(self, **kwargs: Any) -> dict[str, Any]:
            seen.append(dict(kwargs))
            return {
                "id": str(POST_ID),
                "author_user_id": str(AUTHOR_USER_ID),
                "title": kwargs["title"],
                "body": kwargs["body"],
                "tags": kwargs["tags"],
                "comment_count": 0,
                "like_count": 0,
                "viewer_liked": False,
                "viewer_following": False,
                "created_at": "2026-09-05T00:00:00+00:00",
                "updated_at": "2026-09-05T00:00:00+00:00",
            }

    client.app.dependency_overrides[get_community_service] = lambda: RecordingService()
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    first = client.post(
        "/api/v1/community/posts",
        headers={"X-API-Key": api_key, "Idempotency-Key": "retry-9"},
        json={"title": "t", "body": "b"},
    )
    second = client.post(
        "/api/v1/community/posts",
        headers={"X-API-Key": api_key, "Idempotency-Key": "retry-9"},
        json={"title": "t", "body": "b"},
    )

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["data"] == second.json()["data"]
    assert [call["idempotency_key"] for call in seen] == ["retry-9", "retry-9"]
    assert seen[0] == seen[1]


def test_router_without_key_sends_none_and_still_creates(client, api_key) -> None:
    seen: list[dict[str, Any]] = []

    class RecordingService:
        def create_post(self, **kwargs: Any) -> dict[str, Any]:
            seen.append(dict(kwargs))
            return {
                "id": str(POST_ID),
                "author_user_id": str(AUTHOR_USER_ID),
                "title": kwargs["title"],
                "body": kwargs["body"],
                "tags": kwargs["tags"],
                "comment_count": 0,
                "like_count": 0,
                "viewer_liked": False,
                "viewer_following": False,
                "created_at": "2026-09-05T00:00:00+00:00",
                "updated_at": "2026-09-05T00:00:00+00:00",
            }

    client.app.dependency_overrides[get_community_service] = lambda: RecordingService()
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        "/api/v1/community/posts",
        headers={"X-API-Key": api_key},
        json={"title": "t", "body": "b"},
    )

    assert response.status_code == 200
    assert seen[0]["idempotency_key"] is None


def test_router_conflict_maps_to_409_envelope(client, api_key) -> None:
    class ConflictService:
        def create_post(self, **kwargs: Any) -> dict[str, Any]:
            raise ServiceError(
                status_code=409,
                code="IDEMPOTENCY_KEY_CONFLICT",
                message="This idempotency key was already used with a different payload.",
                retryable=False,
            )

    client.app.dependency_overrides[get_community_service] = lambda: ConflictService()
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    response = client.post(
        "/api/v1/community/posts",
        headers={"X-API-Key": api_key, "Idempotency-Key": "k"},
        json={"title": "t", "body": "b"},
    )

    assert response.status_code == 409
    body = response.json()
    assert body["ok"] is False
    assert body["error"]["code"] == "IDEMPOTENCY_KEY_CONFLICT"
