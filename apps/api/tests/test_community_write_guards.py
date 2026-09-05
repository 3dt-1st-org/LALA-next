from __future__ import annotations

import json
from typing import Any
from uuid import UUID

import pytest
from fastapi import Request

from apps.api.app.core.auth import RequestIdentity, require_oauth_identity
from apps.api.app.core.errors import ApiError
from apps.api.app.core.rate_limit import (
    enforce_chat_message_rate_limit,
    enforce_community_write_rate_limit,
    reset_rate_limit_state_for_tests,
)
from apps.api.app.routers.community import (
    COMMENT_CREATE_LIMIT_PER_MINUTE,
    FOLLOW_TOGGLE_LIMIT_PER_MINUTE,
    LIKE_TOGGLE_LIMIT_PER_MINUTE,
    POST_CREATE_LIMIT_PER_MINUTE,
    REPORT_CREATE_LIMIT_PER_MINUTE,
)
from apps.api.app.routers.community_chat import (
    CHAT_MESSAGE_LIMIT_PER_MINUTE,
    CHAT_MESSAGE_REST_LIMIT_PER_MINUTE,
    MEMBER_ADD_LIMIT_PER_MINUTE,
    ROOM_CREATE_LIMIT_PER_MINUTE,
    WS_TICKET_LIMIT_PER_MINUTE,
    manager,
)
from apps.api.app.services.community_chat_service import get_community_chat_service
from apps.api.app.services.community_service import get_community_service

POST_ID = UUID("00000000-0000-0000-0000-000000000001")
FOLLOWEE_ID = UUID("00000000-0000-0000-0000-000000000003")
ROOM_ID = UUID("00000000-0000-0000-0000-000000000010")
MESSAGE_ID = UUID("00000000-0000-0000-0000-000000000011")
ISSUER = "https://issuer.example"
SUBJECT = "user-subject"
OTHER_SUBJECT = "other-user-subject"


class CountingCommunityService:
    """Records every mutation call; nothing may advance on a rejected request."""

    def __init__(self) -> None:
        self.calls: dict[str, int] = {
            name: 0
            for name in (
                "create_post",
                "create_comment",
                "toggle_like",
                "toggle_follow",
                "report_post",
            )
        }

    def _record(self, name: str) -> None:
        self.calls[name] += 1

    def create_post(self, **kwargs: Any) -> dict[str, Any]:
        self._record("create_post")
        return {"id": str(POST_ID)}

    def create_comment(self, **kwargs: Any) -> dict[str, Any]:
        self._record("create_comment")
        return {"id": str(POST_ID)}

    def toggle_like(self, **kwargs: Any) -> dict[str, Any]:
        self._record("toggle_like")
        return {"post_id": str(kwargs["post_id"]), "liked": True, "like_count": 1}

    def toggle_follow(self, **kwargs: Any) -> dict[str, Any]:
        self._record("toggle_follow")
        return {"followee_user_id": str(FOLLOWEE_ID), "following": True}

    def report_post(self, **kwargs: Any) -> dict[str, Any]:
        self._record("report_post")
        return {"report_id": str(POST_ID), "duplicate": False}


class CountingChatService:
    def __init__(self) -> None:
        self.created_rooms: list[str] = []
        self.created_messages: list[tuple[UUID, str, str, str]] = []
        # Ticket -> actor identity; tickets are single-use per handshake test.
        self.ticket_identities = {
            "valid": (ISSUER, SUBJECT),
            "alice": (ISSUER, SUBJECT),
            "bob": (ISSUER, OTHER_SUBJECT),
        }

    def list_rooms(self, **kwargs: Any) -> dict[str, Any]:
        return {"count": 0, "total": 0, "rooms": []}

    def create_room(self, **kwargs: Any) -> dict[str, Any]:
        self.created_rooms.append(kwargs["name"])
        return {"id": str(ROOM_ID)}

    def room_access(self, **kwargs: Any) -> dict[str, Any] | None:
        return {"id": str(ROOM_ID), "visibility": "public"}

    def add_room_member(self, **kwargs: Any) -> dict[str, Any]:
        return {"room_id": str(kwargs["room_id"]), "member_user_id": "m", "added": True}

    def list_messages(self, **kwargs: Any) -> dict[str, Any]:
        return {"count": 0, "total": 0, "messages": []}

    def issue_ws_ticket(self, **kwargs: Any) -> dict[str, Any]:
        return {"room_id": str(kwargs["room_id"]), "ticket": "t", "expires_at": "soon"}

    def claim_ws_ticket(self, **kwargs: Any) -> dict[str, Any] | None:
        identity = self.ticket_identities.get(kwargs["ticket"])
        if identity is None:
            return None
        return {"issuer": identity[0], "subject": identity[1]}

    def fetch_message_for_fanout(self, **kwargs: Any) -> dict[str, Any] | None:
        return None

    def create_message(self, **kwargs: Any) -> dict[str, Any]:
        self.created_messages.append(
            (kwargs["room_id"], kwargs["issuer"], kwargs["subject"], kwargs["body"])
        )
        # Unique id per created message so delivery dedup stays per-message.
        unique_id = UUID(f"00000000-0000-0000-0000-{len(self.created_messages):012d}")
        return {
            "id": str(unique_id),
            "room_id": str(kwargs["room_id"]),
            "author_user_id": None,
            "body": kwargs["body"],
            "created_at": "2026-09-05T00:00:00+00:00",
        }


def _oauth_identity(subject: str = SUBJECT) -> RequestIdentity:
    return RequestIdentity(mode="oauth", issuer=ISSUER, subject=subject)


def _install(
    client,
    community: CountingCommunityService | None = None,
    chat: CountingChatService | None = None,
) -> None:
    if community is not None:
        client.app.dependency_overrides[get_community_service] = lambda: community
    if chat is not None:
        client.app.dependency_overrides[get_community_chat_service] = lambda: chat


def _ws_url(ticket: str = "valid") -> str:
    return f"/api/v1/community/chat/rooms/{ROOM_ID}/ws?ticket={ticket}"


@pytest.fixture(autouse=True)
def _reset_chat_delivery_state() -> None:
    manager._rooms.clear()
    manager.reset_delivery_dedup_for_tests()
    yield
    manager._rooms.clear()
    manager.reset_delivery_dedup_for_tests()


# ---------------------------------------------------------------------------
# HTTP mutations: exact limit, bounded 429 envelope, no service advancement.
# ---------------------------------------------------------------------------

HTTP_FAMILIES = [
    pytest.param(
        "community-post-create",
        "POST_CREATE_LIMIT_PER_MINUTE",
        POST_CREATE_LIMIT_PER_MINUTE,
        "/api/v1/community/posts",
        {"title": "t", "body": "b"},
        "create_post",
        "community",
        id="post-create",
    ),
    pytest.param(
        "community-comment-create",
        "COMMENT_CREATE_LIMIT_PER_MINUTE",
        COMMENT_CREATE_LIMIT_PER_MINUTE,
        f"/api/v1/community/posts/{POST_ID}/comments",
        {"body": "b"},
        "create_comment",
        "community",
        id="comment-create",
    ),
    pytest.param(
        "community-like-toggle",
        "LIKE_TOGGLE_LIMIT_PER_MINUTE",
        LIKE_TOGGLE_LIMIT_PER_MINUTE,
        f"/api/v1/community/posts/{POST_ID}/like",
        None,
        "toggle_like",
        "community",
        id="like-toggle",
    ),
    pytest.param(
        "community-follow-toggle",
        "FOLLOW_TOGGLE_LIMIT_PER_MINUTE",
        FOLLOW_TOGGLE_LIMIT_PER_MINUTE,
        "/api/v1/community/follows",
        {"followee_user_id": str(FOLLOWEE_ID)},
        "toggle_follow",
        "community",
        id="follow-toggle",
    ),
    pytest.param(
        "community-report-create",
        "REPORT_CREATE_LIMIT_PER_MINUTE",
        REPORT_CREATE_LIMIT_PER_MINUTE,
        f"/api/v1/community/posts/{POST_ID}/reports",
        {"reason_code": "spam_promotion"},
        "report_post",
        "community",
        id="report-create",
    ),
    pytest.param(
        "community-chat-room-create",
        "ROOM_CREATE_LIMIT_PER_MINUTE",
        ROOM_CREATE_LIMIT_PER_MINUTE,
        "/api/v1/community/chat/rooms",
        {"name": "general"},
        "create_room",
        "chat",
        id="room-create",
    ),
]


@pytest.mark.parametrize(
    ("route_key", "limit_attr", "documented_limit", "path", "payload", "counter", "kind"),
    HTTP_FAMILIES,
)
def test_http_mutation_family_enforces_exact_limit(
    client,
    api_key,
    monkeypatch,
    route_key,
    limit_attr,
    documented_limit,
    path,
    payload,
    counter,
    kind,
) -> None:
    module_name = (
        "apps.api.app.routers.community"
        if kind == "community"
        else "apps.api.app.routers.community_chat"
    )
    router = pytest.importorskip(module_name)
    monkeypatch.setattr(router, limit_attr, 1)
    community = CountingCommunityService()
    chat = CountingChatService()
    _install(client, community=community, chat=chat)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity
    service = community if kind == "community" else chat
    call_count = (
        (lambda: service.calls[counter])
        if kind == "community"
        else (lambda: len(service.created_rooms))
    )

    first = client.post(path, headers={"X-API-Key": api_key}, json=payload)
    assert first.status_code == 200

    second = client.post(path, headers={"X-API-Key": api_key}, json=payload)
    assert second.status_code == 429
    body = second.json()
    assert body["ok"] is False
    assert body["error"]["code"] == "COMMUNITY_RATE_LIMITED"
    assert body["error"]["retryable"] is True
    assert body["error"]["message"]
    assert "request_id" in body["meta"]

    # Exactly one call advanced to the service; the rejected one never did.
    assert call_count() == 1
    assert documented_limit >= 1


def test_http_route_keys_and_documented_limits_are_distinct(client, api_key, monkeypatch) -> None:
    community_router = pytest.importorskip("apps.api.app.routers.community")
    chat_router = pytest.importorskip("apps.api.app.routers.community_chat")
    real = enforce_community_write_rate_limit
    calls: list[tuple[str, str, int]] = []

    def spy(request, *, route_key, actor_key, limit_per_minute):
        calls.append((route_key, actor_key, limit_per_minute))
        return real(
            request,
            route_key=route_key,
            actor_key=actor_key,
            limit_per_minute=limit_per_minute,
        )

    monkeypatch.setattr(community_router, "enforce_community_write_rate_limit", spy)
    monkeypatch.setattr(chat_router, "enforce_community_write_rate_limit", spy)
    _install(client, CountingCommunityService(), CountingChatService())
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity

    requests = [
        ("/api/v1/community/posts", {"title": "t", "body": "b"}),
        (f"/api/v1/community/posts/{POST_ID}/comments", {"body": "b"}),
        (f"/api/v1/community/posts/{POST_ID}/like", None),
        ("/api/v1/community/follows", {"followee_user_id": str(FOLLOWEE_ID)}),
        (f"/api/v1/community/posts/{POST_ID}/reports", {"reason_code": "spam_promotion"}),
        ("/api/v1/community/chat/rooms", {"name": "general"}),
    ]
    for path, payload in requests:
        assert client.post(path, headers={"X-API-Key": api_key}, json=payload).status_code == 200

    assert [call[0] for call in calls] == [family.values[0] for family in HTTP_FAMILIES]
    assert len({call[0] for call in calls}) == len(calls)
    assert all(call[1] == f"{ISSUER}:{SUBJECT}" for call in calls)
    assert [call[2] for call in calls] == [family.values[2] for family in HTTP_FAMILIES]


def test_unauthenticated_calls_fail_auth_without_consuming_actor_window(
    client, api_key, monkeypatch
) -> None:
    community_router = pytest.importorskip("apps.api.app.routers.community")
    monkeypatch.setattr(community_router, "POST_CREATE_LIMIT_PER_MINUTE", 1)
    limiter_calls: list[str] = []
    real = enforce_community_write_rate_limit

    def spy(request, **kwargs):
        limiter_calls.append(kwargs["route_key"])
        return real(
            request,
            route_key=kwargs["route_key"],
            actor_key=kwargs["actor_key"],
            limit_per_minute=kwargs["limit_per_minute"],
        )

    monkeypatch.setattr(community_router, "enforce_community_write_rate_limit", spy)
    service = CountingCommunityService()
    _install(client, community=service)

    unauthenticated = client.post(
        "/api/v1/community/posts", headers={"X-API-Key": api_key}, json={"title": "t", "body": "b"}
    )
    assert unauthenticated.status_code == 401
    assert unauthenticated.json()["error"]["code"] == "USER_AUTH_REQUIRED"
    assert limiter_calls == []

    # The 401s never touched the actor's window: the first authenticated call
    # still succeeds and only the second one is throttled.
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity
    headers = {"X-API-Key": api_key}
    assert (
        client.post(
            "/api/v1/community/posts", headers=headers, json={"title": "t", "body": "b"}
        ).status_code
        == 200
    )
    throttled = client.post(
        "/api/v1/community/posts", headers=headers, json={"title": "t", "body": "b"}
    )
    assert throttled.status_code == 429
    assert service.calls["create_post"] == 1


def test_actors_are_isolated_from_each_others_windows(client, api_key, monkeypatch) -> None:
    community_router = pytest.importorskip("apps.api.app.routers.community")
    monkeypatch.setattr(community_router, "POST_CREATE_LIMIT_PER_MINUTE", 1)
    service = CountingCommunityService()
    _install(client, community=service)
    current: list[RequestIdentity] = []
    client.app.dependency_overrides[require_oauth_identity] = lambda: current[-1]
    headers = {"X-API-Key": api_key}

    current.append(_oauth_identity(SUBJECT))
    assert (
        client.post(
            "/api/v1/community/posts", headers=headers, json={"title": "t", "body": "b"}
        ).status_code
        == 200
    )
    assert (
        client.post(
            "/api/v1/community/posts", headers=headers, json={"title": "t", "body": "b"}
        ).status_code
        == 429
    )

    # A distinct actor has an untouched window even from the same client.
    current.append(_oauth_identity(OTHER_SUBJECT))
    assert (
        client.post(
            "/api/v1/community/posts", headers=headers, json={"title": "t", "body": "b"}
        ).status_code
        == 200
    )
    assert service.calls["create_post"] == 2


def test_clients_are_isolated_from_each_others_windows(client, api_key, monkeypatch) -> None:
    community_router = pytest.importorskip("apps.api.app.routers.community")
    monkeypatch.setattr(community_router, "POST_CREATE_LIMIT_PER_MINUTE", 1)
    service = CountingCommunityService()
    _install(client, community=service)
    client.app.dependency_overrides[require_oauth_identity] = _oauth_identity
    path = "/api/v1/community/posts"
    payload = {"title": "t", "body": "b"}

    first_ip = {"X-API-Key": api_key, "CF-Connecting-IP": "203.0.113.1"}
    second_ip = {"X-API-Key": api_key, "CF-Connecting-IP": "203.0.113.2"}
    assert client.post(path, headers=first_ip, json=payload).status_code == 200
    assert client.post(path, headers=first_ip, json=payload).status_code == 429
    # Same actor behind a different client address keeps its own window.
    assert client.post(path, headers=second_ip, json=payload).status_code == 200
    assert service.calls["create_post"] == 2


# ---------------------------------------------------------------------------
# Rate-limit seam: hashed keys, scoped windows, exact error contracts.
# ---------------------------------------------------------------------------


def test_documented_limits_are_explicit_and_bounded() -> None:
    documented = {
        "community-post-create": POST_CREATE_LIMIT_PER_MINUTE,
        "community-comment-create": COMMENT_CREATE_LIMIT_PER_MINUTE,
        "community-like-toggle": LIKE_TOGGLE_LIMIT_PER_MINUTE,
        "community-follow-toggle": FOLLOW_TOGGLE_LIMIT_PER_MINUTE,
        "community-report-create": REPORT_CREATE_LIMIT_PER_MINUTE,
        "community-chat-room-create": ROOM_CREATE_LIMIT_PER_MINUTE,
        "community-chat-message": CHAT_MESSAGE_LIMIT_PER_MINUTE,
        "community-chat-message-rest": CHAT_MESSAGE_REST_LIMIT_PER_MINUTE,
        "community-chat-ws-ticket": WS_TICKET_LIMIT_PER_MINUTE,
        "community-chat-member-add": MEMBER_ADD_LIMIT_PER_MINUTE,
    }
    assert documented == {
        "community-post-create": 10,
        "community-comment-create": 20,
        "community-like-toggle": 60,
        "community-follow-toggle": 30,
        "community-report-create": 5,
        "community-chat-room-create": 5,
        "community-chat-message": 30,
        "community-chat-message-rest": 30,
        "community-chat-ws-ticket": 30,
        "community-chat-member-add": 20,
    }
    assert all(0 < limit <= 120 for limit in documented.values())


def _http_request(client_host: str, forwarded_for: str | None = None) -> Request:
    headers: list[tuple[bytes, bytes]] = []
    if forwarded_for:
        headers.append((b"x-forwarded-for", forwarded_for.encode()))
    return Request({"type": "http", "headers": headers, "client": (client_host, 1234)})


def test_community_write_seam_hashes_keys_and_isolates_windows() -> None:
    reset_rate_limit_state_for_tests()
    kwargs = {
        "route_key": "test-community",
        "actor_key": f"{ISSUER}:{SUBJECT}",
        "limit_per_minute": 1,
    }

    enforce_community_write_rate_limit(_http_request("198.51.100.1"), **kwargs)
    with pytest.raises(ApiError) as exc_info:
        enforce_community_write_rate_limit(_http_request("198.51.100.1"), **kwargs)
    assert exc_info.value.status_code == 429
    assert exc_info.value.code == "COMMUNITY_RATE_LIMITED"
    assert exc_info.value.retryable is True
    assert exc_info.value.message == "Too many community requests. Please retry shortly."

    # Distinct actor and distinct client each get a fresh window.
    other_actor = {**kwargs, "actor_key": f"{ISSUER}:{OTHER_SUBJECT}"}
    enforce_community_write_rate_limit(_http_request("198.51.100.1"), **other_actor)
    enforce_community_write_rate_limit(_http_request("198.51.100.2"), **kwargs)
    enforce_community_write_rate_limit(
        _http_request("198.51.100.3", forwarded_for="198.51.100.4"), **kwargs
    )

    from apps.api.app.core import rate_limit as rl

    stored = repr(rl._windows)
    assert ISSUER not in stored and SUBJECT not in stored and "198.51.100.1" not in stored


def test_chat_message_seam_is_actor_and_client_scoped() -> None:
    reset_rate_limit_state_for_tests()
    client_a = "seam-client-a"
    client_b = "seam-client-b"
    kwargs = {
        "route_key": "test-chat",
        "actor_key": f"{ISSUER}:{SUBJECT}",
        "client_key": client_a,
        "limit_per_minute": 1,
    }

    enforce_chat_message_rate_limit(**kwargs)
    with pytest.raises(ApiError) as exc_info:
        enforce_chat_message_rate_limit(**kwargs)
    assert exc_info.value.status_code == 429
    assert exc_info.value.code == "RATE_LIMITED"
    assert exc_info.value.retryable is True
    assert exc_info.value.message == "Too many chat messages. Please retry shortly."

    enforce_chat_message_rate_limit(**{**kwargs, "actor_key": f"{ISSUER}:{OTHER_SUBJECT}"})
    enforce_chat_message_rate_limit(**{**kwargs, "client_key": client_b})

    from apps.api.app.core import rate_limit as rl

    stored = repr(rl._windows)
    assert ISSUER not in stored and SUBJECT not in stored
    assert client_a not in stored and client_b not in stored


# ---------------------------------------------------------------------------
# WebSocket: strict ChatMessageIn validation without persistence/broadcast.
# ---------------------------------------------------------------------------


INVALID_FRAMES = [
    pytest.param("not-json", id="malformed-json"),
    pytest.param(json.dumps(["body", "hi"]), id="json-array"),
    pytest.param(json.dumps("just a string"), id="json-string"),
    pytest.param(json.dumps(42), id="json-number"),
    pytest.param(json.dumps({}), id="missing-body"),
    pytest.param(json.dumps({"body": "   "}), id="whitespace-only-body"),
    pytest.param(json.dumps({"body": 123}), id="wrong-body-type"),
    pytest.param(json.dumps({"body": "hi", "extra": "nope"}), id="unknown-field"),
    pytest.param(json.dumps({"body": "a" * 4001}), id="over-4000-body"),
]


@pytest.mark.parametrize("frame", INVALID_FRAMES)
def test_ws_rejects_invalid_frames_without_persistence_or_broadcast(
    client, api_key, monkeypatch, frame
) -> None:
    service = CountingChatService()
    _install(client, chat=service)
    broadcasts: list[dict] = []

    async def spy_broadcast(**kwargs):
        broadcasts.append(kwargs["payload"])

    monkeypatch.setattr(manager, "broadcast", spy_broadcast)

    with client.websocket_connect(_ws_url()) as ws:
        ws.send_text(frame)
        error = ws.receive_json()

    assert error["type"] == "error"
    assert error["error"]["code"] in {"INVALID_JSON", "INVALID_MESSAGE"}
    assert service.created_messages == []
    assert broadcasts == []


@pytest.mark.parametrize("body", ["a", "a" * 4000, "  padded  "])
def test_ws_persists_valid_boundary_bodies_exactly(client, api_key, monkeypatch, body) -> None:
    service = CountingChatService()
    _install(client, chat=service)

    with client.websocket_connect(_ws_url()) as ws:
        ws.send_text(json.dumps({"body": body}))
        frame = ws.receive_json()

    assert frame["type"] == "message"
    assert frame["data"]["body"] == body
    assert service.created_messages == [(ROOM_ID, ISSUER, SUBJECT, body)]


def test_ws_rate_limit_sends_one_bounded_error_frame_and_stays_open(
    client, api_key, monkeypatch
) -> None:
    chat_router = pytest.importorskip("apps.api.app.routers.community_chat")
    monkeypatch.setattr(chat_router, "CHAT_MESSAGE_LIMIT_PER_MINUTE", 2)
    service = CountingChatService()
    _install(client, chat=service)
    broadcasts: list[dict] = []
    real_broadcast = manager.broadcast

    async def spy_broadcast(**kwargs):
        broadcasts.append(kwargs["payload"])
        await real_broadcast(**kwargs)

    monkeypatch.setattr(manager, "broadcast", spy_broadcast)

    with client.websocket_connect(_ws_url()) as ws:
        ws.send_text(json.dumps({"body": "one"}))
        ws.send_text(json.dumps({"body": "two"}))
        assert ws.receive_json()["type"] == "message"
        assert ws.receive_json()["type"] == "message"

        marker = "THIRD-FRAME-UNIQUE-MARKER-3f9a"
        ws.send_text(json.dumps({"body": marker}))
        throttled = ws.receive_json()
        assert throttled == {
            "type": "error",
            "error": {
                "code": "RATE_LIMITED",
                "message": "Too many chat messages. Please retry shortly.",
            },
        }
        assert marker not in json.dumps(throttled)

        # Deterministic behavior: the connection stays open and further frames
        # keep answering with the same bounded error, still without persisting.
        ws.send_text(json.dumps({"body": "four"}))
        assert ws.receive_json()["error"]["code"] == "RATE_LIMITED"

    assert service.created_messages == [
        (ROOM_ID, ISSUER, SUBJECT, "one"),
        (ROOM_ID, ISSUER, SUBJECT, "two"),
    ]
    assert len(broadcasts) == 2


def test_ws_rate_limit_actors_are_isolated(client, api_key, monkeypatch) -> None:
    chat_router = pytest.importorskip("apps.api.app.routers.community_chat")
    monkeypatch.setattr(chat_router, "CHAT_MESSAGE_LIMIT_PER_MINUTE", 1)
    service = CountingChatService()
    _install(client, chat=service)

    with client.websocket_connect(_ws_url("alice")) as alice:
        alice.send_text(json.dumps({"body": "alice-1"}))
        assert alice.receive_json()["type"] == "message"
        alice.send_text(json.dumps({"body": "alice-2"}))
        assert alice.receive_json()["error"]["code"] == "RATE_LIMITED"

    with client.websocket_connect(_ws_url("bob")) as bob:
        bob.send_text(json.dumps({"body": "bob-1"}))
        assert bob.receive_json()["type"] == "message"

    assert service.created_messages == [
        (ROOM_ID, ISSUER, SUBJECT, "alice-1"),
        (ROOM_ID, ISSUER, OTHER_SUBJECT, "bob-1"),
    ]


def test_ws_failed_handshake_does_not_consume_message_window(client, api_key, monkeypatch) -> None:
    from fastapi import WebSocketDisconnect

    chat_router = pytest.importorskip("apps.api.app.routers.community_chat")
    monkeypatch.setattr(chat_router, "CHAT_MESSAGE_LIMIT_PER_MINUTE", 1)

    # No service installed: the ticket store is unavailable, so the handshake
    # is rejected with 1013 (retry later) before any message window use.
    with pytest.raises(WebSocketDisconnect) as rejected:
        with client.websocket_connect(_ws_url()):
            pass  # pragma: no cover - handshake must fail first
    assert rejected.value.code == 1013

    service = CountingChatService()
    _install(client, chat=service)
    with client.websocket_connect(_ws_url()) as ws:
        ws.send_text(json.dumps({"body": "hello"}))
        assert ws.receive_json()["type"] == "message"
    assert service.created_messages == [(ROOM_ID, ISSUER, SUBJECT, "hello")]


# ---------------------------------------------------------------------------
# OpenAPI: community mutations document 429 without unrelated churn.
# ---------------------------------------------------------------------------


def test_openapi_documents_429_on_community_write_mutations(client) -> None:
    schema = client.get("/openapi.json").json()
    paths = schema["paths"]
    envelope_ref = {"$ref": "#/components/schemas/ApiErrorEnvelope"}

    for path in (
        "/api/v1/community/posts",
        "/api/v1/community/posts/{post_id}/comments",
        "/api/v1/community/posts/{post_id}/like",
        "/api/v1/community/posts/{post_id}/reports",
        "/api/v1/community/follows",
        "/api/v1/community/chat/rooms",
        "/api/v1/community/chat/rooms/{room_id}/messages",
        "/api/v1/community/chat/rooms/{room_id}/ws-ticket",
        "/api/v1/community/chat/rooms/{room_id}/members",
    ):
        response = paths[path]["post"]["responses"]["429"]
        assert response["description"] == "The community write rate limit was exceeded."
        assert response["content"]["application/json"]["schema"] == envelope_ref

    # Reads stay unthrottled at this seam.
    for path, method in (
        ("/api/v1/community/posts", "get"),
        ("/api/v1/community/posts/{post_id}", "get"),
        ("/api/v1/community/posts/{post_id}/comments", "get"),
        ("/api/v1/community/follows", "get"),
        ("/api/v1/community/chat/rooms", "get"),
        ("/api/v1/community/chat/rooms/{room_id}/messages", "get"),
    ):
        assert "429" not in paths[path][method]["responses"]

    # Local Signals keeps its own distinct 429 contract (no churn).
    local_signals = paths["/api/v1/community/signals"]["post"]["responses"]["429"]
    assert local_signals["description"] == "The Local Signals rate limit was exceeded."


def test_chat_message_in_wire_contract_is_strict() -> None:
    from pydantic import ValidationError

    from apps.api.app.schemas.community_chat import ChatMessageIn

    assert ChatMessageIn.model_validate({"body": "a" * 4000}).body == "a" * 4000
    for payload in (
        {},
        {"body": "   "},
        {"body": 123},
        {"body": "a" * 4001},
        {"body": "hi", "extra": 1},
    ):
        with pytest.raises(ValidationError):
            ChatMessageIn.model_validate(payload)
