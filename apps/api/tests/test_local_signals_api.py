from __future__ import annotations

import importlib
from concurrent.futures import ThreadPoolExecutor, TimeoutError
from datetime import UTC, date, datetime
from pathlib import Path
from threading import Event, Lock
from typing import Any
from uuid import UUID

import pytest
from fastapi import Request
from fastapi.testclient import TestClient

from apps.api.app.core.auth import RequestIdentity, require_logto_identity
from apps.api.app.core.config import Settings
from apps.api.app.core.errors import ApiError, ServiceError
from apps.api.app.core.rate_limit import (
    enforce_local_signals_rate_limit,
    reset_rate_limit_state_for_tests,
)
from apps.api.app.routers.local_signals import _idempotency_key, get_local_signals_service
from apps.api.app.services.local_signals_service import (
    LocalSignalsRepository,
    LocalSignalsService,
    SignalCursor,
    decode_signal_cursor,
    encode_signal_cursor,
    validate_local_signal_policy,
)

SIGNAL_ID = UUID("00000000-0000-0000-0000-000000000101")
OTHER_SIGNAL_ID = UUID("00000000-0000-0000-0000-000000000102")
AUTHOR_ISSUER = "https://tenant.logto.example/oidc"
AUTHOR_SUBJECT = "logto-subject"
OTHER_SUBJECT = "other-subject"
NOW = datetime(2026, 7, 27, 1, 0, tzinfo=UTC)
RAW_FIRST_PARTY_BODY = "A first-party body in Korean."


def _settings(*, read: bool = True, write: bool = True) -> Settings:
    return Settings(
        feature_flags={
            "LOCAL_SIGNALS_READ": read,
            "LOCAL_SIGNALS_WRITE": write,
        }
    )


def _public_row(**overrides: Any) -> dict[str, Any]:
    row = {
        "id": SIGNAL_ID,
        "kind": "place_tip",
        "source_language": "ko",
        "title": "A dated local tip",
        "body": RAW_FIRST_PARTY_BODY,
        "locality_level": "district",
        "locality_code": "suwon:paldal",
        "commercial_disclosure": "none",
        "observation_date": date(2026, 7, 26),
        "published_at": NOW,
        "place_links": [{"place_id": "place-1", "relation": "primary"}],
        "translation_body": "A translated local tip.",
        "translation_method": "machine",
        "translator_version": "policy-v1",
        "source_content_hash": "a" * 64,
        "provenance": "machine_reviewed",
        "review_state": "available",
        "reviewed_at": NOW,
        "reaction_count": 2,
        "comment_count": 1,
        "useful_count": 2,
    }
    row.update(overrides)
    return row


class FakeLocalSignalsRepository:
    def __init__(self, *, owner_subject: str = AUTHOR_SUBJECT) -> None:
        self.owner_subject = owner_subject
        self.created = 0
        self.rows = [_public_row()]

    def list_public_signals(self, **_: Any) -> list[dict[str, Any]]:
        return list(self.rows)

    def get_public_signal(self, *, signal_id: UUID, **_: Any) -> dict[str, Any] | None:
        return next((row for row in self.rows if row["id"] == signal_id), None)

    def list_public_comments(self, **_: Any) -> list[dict[str, Any]]:
        return [
            {
                "id": OTHER_SIGNAL_ID,
                "source_language": "ko",
                "body": "A published answer.",
                "created_at": NOW,
            }
        ]

    def get_signal_for_owner(self, *, signal_id: UUID) -> dict[str, Any] | None:
        if signal_id != SIGNAL_ID:
            return None
        return {
            "id": SIGNAL_ID,
            "author_issuer": AUTHOR_ISSUER,
            "author_subject": self.owner_subject,
            "kind": "place_tip",
            "status": "draft",
            "moderation_state": "unreviewed",
            "visibility": "private",
            "source_language": "ko",
            "title": "Draft title",
            "body": "Draft body.",
            "locality_level": "district",
            "locality_code": "suwon:paldal",
            "commercial_disclosure": "none",
            "observation_date": date(2026, 7, 26),
            "aggregate_opt_in": False,
        }

    def create_draft(self, **kwargs: Any) -> dict[str, Any]:
        self.created += 1
        values = kwargs["values"]
        return {
            "id": SIGNAL_ID,
            "kind": values["kind"],
            "status": "draft",
            "moderation_state": "unreviewed",
            "visibility": "private",
            "source_language": values["source_language"],
            "title": values["title"],
            "body": values["body"],
            "locality_level": values["locality_level"],
            "locality_code": values["locality_code"],
            "commercial_disclosure": values["commercial_disclosure"],
            "observation_date": values["observation_date"],
            "place_links": [],
        }

    def update_draft(self, **kwargs: Any) -> dict[str, Any]:
        values = kwargs["values"]
        result = self.create_draft(values={**_draft_values(), **values})
        return result

    def submit_signal(self, **_: Any) -> dict[str, Any]:
        return {
            "id": SIGNAL_ID,
            "kind": "place_tip",
            "status": "submitted",
            "moderation_state": "pending",
            "visibility": "pending_review",
            "source_language": "ko",
            "title": "Draft title",
            "body": "Draft body.",
            "locality_level": "district",
            "locality_code": "suwon:paldal",
            "commercial_disclosure": "none",
            "observation_date": date(2026, 7, 26),
            "place_links": [],
        }

    def delete_signal(self, **_: Any) -> dict[str, Any]:
        return {
            **self.submit_signal(),
            "status": "deleted",
            "visibility": "private",
        }

    def set_reaction(self, **_: Any) -> bool:
        return True

    def set_save(self, **_: Any) -> bool:
        return True

    def create_comment(self, **_: Any) -> dict[str, Any]:
        return {
            "id": OTHER_SIGNAL_ID,
            "signal_id": SIGNAL_ID,
            "source_language": "ko",
            "body": "Pending answer.",
            "status": "submitted",
            "created_at": NOW,
        }

    def create_report(self, **_: Any) -> UUID:
        return OTHER_SIGNAL_ID


def _draft_values() -> dict[str, Any]:
    return {
        "kind": "place_tip",
        "source_language": "ko",
        "title": "Draft title",
        "body": "Draft body.",
        "locality_level": "district",
        "locality_code": "suwon:paldal",
        "commercial_disclosure": "none",
        "observation_date": date(2026, 7, 26),
        "aggregate_opt_in": False,
        "place_links": [],
    }


def test_public_projection_is_locale_exclusive_and_has_no_identity_or_review_fields() -> None:
    service = LocalSignalsService(
        FakeLocalSignalsRepository(),
        settings=_settings(),
    )

    payload = service.list_public(
        language="en",
        region=None,
        place_id=None,
        kind=None,
        limit=10,
        cursor=None,
        sort="recent",
    )
    item = payload["items"][0]

    assert item["body"] == "A translated local tip."
    assert item["display_language"] == "en"
    assert item["translation_available"] is True
    assert item["reaction_count"] == 2
    assert item["comment_count"] == 1
    assert "author_issuer" not in item
    assert "author_subject" not in item
    assert "moderation_state" not in item
    assert "token" not in str(item).lower()
    assert RAW_FIRST_PARTY_BODY not in item["body"]


@pytest.mark.parametrize(
    "text",
    [
        "Contact me at traveller@example.com",
        "Call 010-1234-5678",
        "Meet at 37.123456, 127.123456",
        "Use Bearer access-token-value",
        "Let's coordinate a live location",
    ],
)
def test_deterministic_policy_rejects_pii_credentials_and_live_location(text: str) -> None:
    with pytest.raises(ServiceError) as exc_info:
        validate_local_signal_policy(
            title="Tip",
            body=text,
            locality_level="district",
            commercial_disclosure="none",
        )

    assert exc_info.value.code in {"CONTENT_POLICY_BLOCKED", "LOCATION_TOO_PRECISE"}
    assert text not in exc_info.value.message


def test_idempotency_replays_without_second_repository_write() -> None:
    repository = FakeLocalSignalsRepository()
    service = LocalSignalsService(repository, settings=_settings())

    first = service.create_draft(
        issuer=AUTHOR_ISSUER,
        subject=AUTHOR_SUBJECT,
        values=_draft_values(),
        idempotency_key="draft-key",
    )
    second = service.create_draft(
        issuer=AUTHOR_ISSUER,
        subject=AUTHOR_SUBJECT,
        values=_draft_values(),
        idempotency_key="draft-key",
    )

    assert first == second
    assert repository.created == 1


def test_idempotency_single_flight_waits_for_same_payload() -> None:
    class BlockingRepository(FakeLocalSignalsRepository):
        def __init__(self) -> None:
            super().__init__()
            self.first_write_started = Event()
            self.release_first_write = Event()
            self.second_write_started = Event()
            self.write_count = 0
            self.write_lock = Lock()

        def create_draft(self, **kwargs: Any) -> dict[str, Any]:
            with self.write_lock:
                self.write_count += 1
                write_number = self.write_count
            if write_number == 1:
                self.first_write_started.set()
                assert self.release_first_write.wait(timeout=2)
            else:
                self.second_write_started.set()
            return super().create_draft(**kwargs)

    repository = BlockingRepository()
    service = LocalSignalsService(repository, settings=_settings())

    with ThreadPoolExecutor(max_workers=2) as executor:
        first = executor.submit(
            service.create_draft,
            issuer=AUTHOR_ISSUER,
            subject=AUTHOR_SUBJECT,
            values=_draft_values(),
            idempotency_key="single-flight-key",
        )
        assert repository.first_write_started.wait(timeout=1)
        second = executor.submit(
            service.create_draft,
            issuer=AUTHOR_ISSUER,
            subject=AUTHOR_SUBJECT,
            values=_draft_values(),
            idempotency_key="single-flight-key",
        )

        with pytest.raises(TimeoutError):
            second.result(timeout=0.2)
        repository.release_first_write.set()
        assert first.result(timeout=2) == second.result(timeout=2)

    assert repository.write_count == 1
    assert not repository.second_write_started.is_set()


def test_idempotency_key_reuse_with_different_payload_is_rejected() -> None:
    service = LocalSignalsService(FakeLocalSignalsRepository(), settings=_settings())
    service.create_draft(
        issuer=AUTHOR_ISSUER,
        subject=AUTHOR_SUBJECT,
        values=_draft_values(),
        idempotency_key="same-key",
    )

    with pytest.raises(ServiceError, match="already used"):
        service.create_draft(
            issuer=AUTHOR_ISSUER,
            subject=AUTHOR_SUBJECT,
            values={**_draft_values(), "title": "Different"},
            idempotency_key="same-key",
        )


def test_write_ownership_and_invalid_transition_are_enforced() -> None:
    repository = FakeLocalSignalsRepository()
    service = LocalSignalsService(repository, settings=_settings())

    with pytest.raises(ServiceError) as not_owner:
        service.update_draft(
            signal_id=SIGNAL_ID,
            issuer=AUTHOR_ISSUER,
            subject=OTHER_SUBJECT,
            values={"title": "Nope"},
            idempotency_key="owner-key",
        )
    assert not_owner.value.code == "NOT_OWNER"

    original_get_signal_for_owner = repository.get_signal_for_owner
    repository.get_signal_for_owner = lambda **kwargs: {
        **original_get_signal_for_owner(**kwargs),
        "status": "submitted",
    }
    with pytest.raises(ServiceError) as invalid_transition:
        service.submit(
            signal_id=SIGNAL_ID,
            issuer=AUTHOR_ISSUER,
            subject=AUTHOR_SUBJECT,
            idempotency_key="submit-key",
        )
    assert invalid_transition.value.code == "INVALID_STATUS_TRANSITION"


def test_whitespace_idempotency_key_falls_back_to_deterministic_request_key() -> None:
    request = Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/api/v1/community/signals",
            "scheme": "http",
            "headers": [],
        }
    )
    payload = {"body": "same"}

    first = _idempotency_key(request, "   ", payload)
    second = _idempotency_key(request, "\t", payload)

    assert first
    assert first == second
    assert first != ""


def test_feature_flag_off_is_honest_disabled_response(client, api_key, monkeypatch) -> None:
    monkeypatch.setenv("LALA_LOCAL_SIGNALS_READ", "false")
    response = client.get("/api/v1/community/signals", headers={"X-API-Key": api_key})

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "LOCAL_SIGNALS_DISABLED"


def test_guest_read_is_allowed_but_guest_write_is_denied(client, api_key, monkeypatch) -> None:
    monkeypatch.setenv("LALA_LOCAL_SIGNALS_READ", "true")
    monkeypatch.setenv("LALA_LOCAL_SIGNALS_WRITE", "true")
    service = LocalSignalsService(FakeLocalSignalsRepository(), settings=_settings())
    client.app.dependency_overrides[get_local_signals_service] = lambda: service

    read_response = client.get("/api/v1/community/signals", headers={"X-API-Key": api_key})
    write_response = client.post(
        "/api/v1/community/signals",
        headers={"X-API-Key": api_key},
        json={**_draft_values(), "observation_date": "2026-07-26"},
    )

    assert read_response.status_code == 200
    assert write_response.status_code == 401
    assert write_response.json()["error"]["code"] == "USER_AUTH_REQUIRED"
    assert 'event="read"' in client.get("/metrics").text


def test_logto_write_does_not_accept_client_identity_or_status(
    client: TestClient,
    api_key: str,
    monkeypatch,
) -> None:
    monkeypatch.setenv("LALA_LOCAL_SIGNALS_WRITE", "true")
    identity = RequestIdentity(mode="oauth", issuer=AUTHOR_ISSUER, subject=AUTHOR_SUBJECT)
    client.app.dependency_overrides[require_logto_identity] = lambda: identity
    client.app.dependency_overrides[get_local_signals_service] = lambda: LocalSignalsService(
        FakeLocalSignalsRepository(),
        settings=_settings(read=False, write=True),
    )

    response = client.post(
        "/api/v1/community/signals",
        headers={"X-API-Key": api_key},
        json={
            **_draft_values(),
            "observation_date": "2026-07-26",
            "author_subject": "attacker-controlled",
            "status": "published",
        },
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"
    assert "attacker-controlled" not in response.text


def test_public_repository_query_is_first_party_projection_only() -> None:
    executed: list[tuple[str, Any]] = []

    class Cursor:
        def __enter__(self) -> Cursor:
            return self

        def __exit__(self, *args: object) -> None:
            return None

        def execute(self, sql: str, params: Any = None) -> None:
            executed.append((sql, params))

        def fetchall(self) -> list[dict[str, Any]]:
            return []

    class Connection:
        def __enter__(self) -> Connection:
            return self

        def __exit__(self, *args: object) -> None:
            return None

        def cursor(self, cursor_factory: Any = None) -> Cursor:
            return Cursor()

        def close(self) -> None:
            return None

    repository = LocalSignalsRepository(
        Settings(db_dsn="postgresql://redacted"),
        connect=lambda **_: Connection(),
    )
    repository.list_public_signals(
        language="en",
        region="suwon:paldal",
        place_id=None,
        kind="place_tip",
        limit=5,
        cursor=None,
        sort="recent",
    )

    sql = executed[0][0]
    assert "FROM community.local_signal_public" in sql
    assert "community.posts" not in sql
    assert "author_issuer" not in sql
    assert "author_subject" not in sql
    assert "local_signal_aggregate_candidates" not in sql


def test_useful_repository_query_matches_useful_cursor_tuple() -> None:
    executed: list[tuple[str, Any]] = []

    class Cursor:
        def __enter__(self) -> Cursor:
            return self

        def __exit__(self, *args: object) -> None:
            return None

        def execute(self, sql: str, params: Any = None) -> None:
            executed.append((sql, params))

        def fetchall(self) -> list[dict[str, Any]]:
            return []

    class Connection:
        def __enter__(self) -> Connection:
            return self

        def __exit__(self, *args: object) -> None:
            return None

        def cursor(self, cursor_factory: Any = None) -> Cursor:
            return Cursor()

        def close(self) -> None:
            return None

    repository = LocalSignalsRepository(
        Settings(db_dsn="postgresql://redacted"),
        connect=lambda **_: Connection(),
    )
    repository.list_public_signals(
        language="ko",
        region=None,
        place_id=None,
        kind=None,
        limit=5,
        cursor=SignalCursor(
            sort="useful",
            useful_count=2,
            published_at=NOW,
            signal_id=SIGNAL_ID,
        ),
        sort="useful",
    )

    sql, params = executed[0]
    assert "ORDER BY useful_count DESC, p.published_at DESC, p.id DESC" in sql
    assert sql.count("useful_cursor.reaction_type = 'useful'") == 2
    assert params == ("ko", "ko", "ko", "ko", 2, 2, NOW, NOW, str(SIGNAL_ID), 5)
    assert sql.count("%s") == len(params)


def test_useful_pagination_has_no_duplicate_or_skipped_item() -> None:
    rows = [
        _public_row(
            id=UUID("00000000-0000-0000-0000-000000000201"),
            useful_count=5,
            published_at=NOW,
        ),
        _public_row(
            id=UUID("00000000-0000-0000-0000-000000000202"),
            useful_count=5,
            published_at=NOW.replace(hour=0),
        ),
        _public_row(
            id=UUID("00000000-0000-0000-0000-000000000203"),
            useful_count=3,
            published_at=NOW,
        ),
        _public_row(
            id=UUID("00000000-0000-0000-0000-000000000204"),
            useful_count=1,
            published_at=NOW,
        ),
    ]

    class PagedRepository(FakeLocalSignalsRepository):
        def __init__(self) -> None:
            super().__init__()
            self.rows = rows

        def list_public_signals(
            self,
            *,
            cursor: Any,
            limit: int,
            sort: str,
            **_: Any,
        ) -> list[dict[str, Any]]:
            ordered = sorted(
                self.rows,
                key=lambda row: (row["useful_count"], row["published_at"], row["id"].int),
                reverse=True,
            )
            if cursor is not None:
                ordered = [
                    row
                    for row in ordered
                    if (
                        row["useful_count"] < cursor.useful_count
                        or (
                            row["useful_count"] == cursor.useful_count
                            and (
                                row["published_at"] < cursor.published_at
                                or (
                                    row["published_at"] == cursor.published_at
                                    and row["id"].int < cursor.signal_id.int
                                )
                            )
                        )
                    )
                ]
            assert sort == "useful"
            return ordered[:limit]

    service = LocalSignalsService(PagedRepository(), settings=_settings())
    first = service.list_public(
        language="ko",
        region=None,
        place_id=None,
        kind=None,
        limit=2,
        cursor=None,
        sort="useful",
    )
    second = service.list_public(
        language="ko",
        region=None,
        place_id=None,
        kind=None,
        limit=2,
        cursor=first["next_cursor"],
        sort="useful",
    )

    ids = [item["id"] for item in first["items"] + second["items"]]
    assert ids == [str(row["id"]) for row in rows]
    assert len(ids) == len(set(ids))
    decoded = decode_signal_cursor(first["next_cursor"], sort="useful")
    assert decoded.useful_count == 5


def test_signal_cursor_is_opaque_and_sort_bound() -> None:
    cursor = encode_signal_cursor(_public_row(useful_count=2), sort="useful")

    with pytest.raises(ServiceError) as mismatch:
        decode_signal_cursor(cursor, sort="recent")
    assert mismatch.value.code == "INVALID_CURSOR"

    with pytest.raises(ServiceError) as malformed:
        decode_signal_cursor(f"{cursor}=", sort="useful")
    assert malformed.value.code == "INVALID_CURSOR"


def test_reaction_and_save_routes_use_actor_scoped_rate_limit(
    client: TestClient,
    api_key: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LALA_LOCAL_SIGNALS_WRITE", "true")
    identity = RequestIdentity(mode="oauth", issuer=AUTHOR_ISSUER, subject=AUTHOR_SUBJECT)
    client.app.dependency_overrides[require_logto_identity] = lambda: identity
    client.app.dependency_overrides[get_local_signals_service] = lambda: LocalSignalsService(
        FakeLocalSignalsRepository(),
        settings=_settings(read=False, write=True),
    )
    local_signals_router = importlib.import_module("apps.api.app.routers.local_signals")
    calls: list[tuple[str, str, int]] = []

    def reject_rate_limit(
        request: Request, *, route_key: str, actor_key: str, limit_per_minute: int
    ) -> None:
        calls.append((route_key, actor_key, limit_per_minute))
        raise ApiError(
            status_code=429,
            code="RATE_LIMITED",
            message="Too many Local Signals requests. Please retry shortly.",
            retryable=True,
        )

    monkeypatch.setattr(local_signals_router, "enforce_local_signals_rate_limit", reject_rate_limit)
    headers = {"X-API-Key": api_key}
    requests = [
        ("put", f"/api/v1/community/signals/{SIGNAL_ID}/reactions/useful"),
        ("delete", f"/api/v1/community/signals/{SIGNAL_ID}/reactions/useful"),
        ("put", f"/api/v1/community/signals/{SIGNAL_ID}/save"),
        ("delete", f"/api/v1/community/signals/{SIGNAL_ID}/save"),
    ]

    for method, path in requests:
        response = getattr(client, method)(path, headers=headers)
        assert response.status_code == 429
        assert response.json()["error"]["code"] == "RATE_LIMITED"

    assert [call[0] for call in calls] == [
        "local-signals-reaction-add",
        "local-signals-reaction-remove",
        "local-signals-save-add",
        "local-signals-save-remove",
    ]
    assert all(call[1] == f"{AUTHOR_ISSUER}:{AUTHOR_SUBJECT}" for call in calls)
    assert all(call[2] == 60 for call in calls)


def test_openapi_exposes_safe_read_and_logto_write_boundaries(client) -> None:
    schema = client.get("/openapi.json").json()
    paths = schema["paths"]

    assert "/api/v1/community/signals" in paths
    assert "/api/v1/community/signals/{signal_id}" in paths
    assert "/api/v1/community/places/{place_id}/signals" in paths
    assert paths["/api/v1/community/signals"]["get"]["security"] == [
        {},
        {"BearerAuth": []},
        {"MigrationApiKey": []},
    ]
    assert paths["/api/v1/community/signals"]["post"]["security"] == [{"OAuthBearerAuth": []}]
    draft_schema = schema["components"]["schemas"]["LocalSignalDraftCreate"]
    assert "author_issuer" not in draft_schema["properties"]
    assert "author_subject" not in draft_schema["properties"]
    assert "status" not in draft_schema["properties"]
    assert paths["/api/v1/community/signals"]["post"]["x-lala-auth-required"] is True


def test_approved_naver_evidence_boundary_is_documented_as_separate() -> None:
    root = Path(__file__).resolve().parents[3]
    contract = (root / "docs/planning/local-signals-ls2-api-policy-contract.md").read_text(
        encoding="utf-8"
    )

    assert "approved Naver Blog API" in contract
    assert "separate review/mention evidence pipeline" in contract
    assert "Raw blog/review text remains unavailable" in contract
    assert "RAG" in contract


def test_rate_limit_seam_is_actor_scoped_and_returns_safe_error() -> None:
    reset_rate_limit_state_for_tests()
    request = Request(
        {
            "type": "http",
            "headers": [],
            "client": ("127.0.0.1", 1234),
        }
    )
    enforce_local_signals_rate_limit(
        request,
        route_key="test-local-signals",
        actor_key="hashed-actor",
        limit_per_minute=1,
    )

    with pytest.raises(ApiError) as exc_info:
        enforce_local_signals_rate_limit(
            request,
            route_key="test-local-signals",
            actor_key="hashed-actor",
            limit_per_minute=1,
        )

    assert exc_info.value.status_code == 429
    assert exc_info.value.code == "RATE_LIMITED"
