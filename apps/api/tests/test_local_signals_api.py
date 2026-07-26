from __future__ import annotations

from datetime import UTC, date, datetime
from pathlib import Path
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
from apps.api.app.routers.local_signals import get_local_signals_service
from apps.api.app.services.local_signals_service import (
    LocalSignalsRepository,
    LocalSignalsService,
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
