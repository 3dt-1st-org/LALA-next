from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from apps.api.app.core.auth import RequestIdentity, require_logto_identity
from apps.api.app.core.errors import ServiceError
from apps.api.app.services.identity_repository import LocalUser
from apps.api.app.services.identity_service import get_identity_service
from apps.api.app.services.travel_preferences_repository import TravelPreferencesRecord
from apps.api.app.services.travel_preferences_service import get_travel_preferences_service

USER = LocalUser(
    id=UUID("00000000-0000-0000-0000-000000000001"),
    issuer="https://issuer.example",
    subject="user-subject",
    status="active",
    created_at=datetime(2026, 9, 2, tzinfo=UTC),
    last_seen_at=datetime(2026, 9, 2, tzinfo=UTC),
    deletion_requested_at=None,
)
UPDATED_AT = datetime(2026, 9, 2, 1, 2, 3, tzinfo=UTC)


def _payload() -> dict:
    return {
        "version": 1,
        "soft": {
            "pace": "balanced",
            "interests": ["localFood", "history"],
            "food_cuisines": ["korean"],
        },
        "hard": {
            "dietary_modes": ["halal"],
            "allergens": ["shellfish"],
            "avoid_ingredients": "raw onion",
        },
        "locale": {"place_name_mode": "localizedWithKorean"},
    }


class _IdentityService:
    def __init__(self) -> None:
        self.provisioned: list[tuple[str, str]] = []

    def provision_user(self, issuer: str, subject: str) -> LocalUser:
        self.provisioned.append((issuer, subject))
        return USER


class _PreferencesService:
    def __init__(self, record: TravelPreferencesRecord | None = None) -> None:
        self.record = record
        self.get_calls: list[tuple[str, str]] = []
        self.put_calls: list[dict] = []

    def get(self, *, issuer: str, subject: str) -> TravelPreferencesRecord | None:
        self.get_calls.append((issuer, subject))
        return self.record

    def put(
        self,
        *,
        issuer: str,
        subject: str,
        expected_revision: int,
        preferences: dict,
    ) -> TravelPreferencesRecord:
        self.put_calls.append(
            {
                "issuer": issuer,
                "subject": subject,
                "expected_revision": expected_revision,
                "preferences": preferences,
            }
        )
        return TravelPreferencesRecord(
            preferences=preferences,
            revision=expected_revision + 1,
            updated_at=UPDATED_AT,
        )


def _oauth_identity() -> RequestIdentity:
    return RequestIdentity(
        mode="oauth",
        issuer="https://issuer.example",
        subject="user-subject",
    )


def test_preferences_require_oauth(client, api_key) -> None:
    response = client.get("/api/v1/me/preferences", headers={"X-API-Key": api_key})

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "USER_AUTH_REQUIRED"


def test_get_preferences_returns_honest_null_when_account_has_no_document(client, api_key) -> None:
    identity_service = _IdentityService()
    preferences_service = _PreferencesService()
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = lambda: identity_service
    client.app.dependency_overrides[get_travel_preferences_service] = lambda: preferences_service

    response = client.get("/api/v1/me/preferences", headers={"X-API-Key": api_key})

    assert response.status_code == 200
    assert response.json()["data"] is None
    assert response.json()["meta"]["source"] == "unavailable"
    assert identity_service.provisioned == [("https://issuer.example", "user-subject")]


def test_get_preferences_returns_revision_without_external_identity(client, api_key) -> None:
    record = TravelPreferencesRecord(
        preferences=_payload(),
        revision=4,
        updated_at=UPDATED_AT,
    )
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = _IdentityService
    client.app.dependency_overrides[get_travel_preferences_service] = lambda: _PreferencesService(
        record
    )

    response = client.get("/api/v1/me/preferences", headers={"X-API-Key": api_key})

    assert response.status_code == 200
    assert response.json()["data"]["revision"] == 4
    assert response.json()["data"]["preferences"]["hard"]["allergens"] == ["shellfish"]
    assert "issuer.example" not in response.text
    assert "user-subject" not in response.text


def test_put_preferences_validates_and_binds_the_authenticated_owner(client, api_key) -> None:
    service = _PreferencesService()
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = _IdentityService
    client.app.dependency_overrides[get_travel_preferences_service] = lambda: service

    response = client.put(
        "/api/v1/me/preferences",
        headers={"X-API-Key": api_key},
        json={"expected_revision": 0, "preferences": _payload()},
    )

    assert response.status_code == 200
    assert response.json()["data"]["revision"] == 1
    assert service.put_calls[0]["issuer"] == "https://issuer.example"
    assert service.put_calls[0]["subject"] == "user-subject"
    assert service.put_calls[0]["preferences"]["soft"]["pace"] == "balanced"


def test_put_preferences_rejects_duplicates_extra_fields_and_oversized_text(
    client, api_key
) -> None:
    service = _PreferencesService()
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = _IdentityService
    client.app.dependency_overrides[get_travel_preferences_service] = lambda: service
    payload = _payload()
    payload["soft"]["interests"] = ["localFood", "localFood"]
    payload["hard"]["avoid_ingredients"] = "x" * 121
    payload["unexpected"] = True

    response = client.put(
        "/api/v1/me/preferences",
        headers={"X-API-Key": api_key},
        json={"expected_revision": 0, "preferences": payload},
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"
    assert service.put_calls == []
    assert "raw onion" not in response.text


def test_put_preferences_accepts_bounded_spice_and_order_requests(client, api_key) -> None:
    service = _PreferencesService()
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = _IdentityService
    client.app.dependency_overrides[get_travel_preferences_service] = lambda: service

    payload = _payload()
    payload["soft"]["spice_level"] = "mild"
    payload["soft"]["order_requests"] = ["quietTable", "smallPortion"]

    response = client.put(
        "/api/v1/me/preferences",
        headers={"X-API-Key": api_key},
        json={"expected_revision": 0, "preferences": payload},
    )

    assert response.status_code == 200
    stored = service.put_calls[0]["preferences"]
    assert stored["soft"]["spice_level"] == "mild"
    assert stored["soft"]["order_requests"] == ["quietTable", "smallPortion"]
    assert response.json()["data"]["preferences"]["soft"]["spice_level"] == "mild"


def test_put_preferences_rejects_unknown_or_out_of_bound_restaurant_values(client, api_key) -> None:
    service = _PreferencesService()
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = _IdentityService
    client.app.dependency_overrides[get_travel_preferences_service] = lambda: service

    for invalid in (
        {"spice_level": "inferno"},
        {"spice_level": 3},
        {"order_requests": ["extraNapkins"]},
        {"order_requests": ["quietTable", "quietTable"]},
        {
            "order_requests": [
                "staffRecommendation",
                "smallPortion",
                "quietTable",
                "takeout",
                "takeout",
            ]
        },
    ):
        payload = _payload()
        payload["soft"].update(invalid)

        response = client.put(
            "/api/v1/me/preferences",
            headers={"X-API-Key": api_key},
            json={"expected_revision": 0, "preferences": payload},
        )

        assert response.status_code == 422, invalid
        assert response.json()["error"]["code"] == "VALIDATION_ERROR"

    assert service.put_calls == []


def test_put_preferences_defaults_old_payloads_without_restaurant_fields(client, api_key) -> None:
    # CP2 호환: CP1 시대 저장 문서(맵기/주문 요청 키 없음)는 honest 기본값으로
    # 파싱된다 — spice_level=None(저장 안 함), order_requests=[](요청 없음).
    service = _PreferencesService()
    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = _IdentityService
    client.app.dependency_overrides[get_travel_preferences_service] = lambda: service

    response = client.put(
        "/api/v1/me/preferences",
        headers={"X-API-Key": api_key},
        json={"expected_revision": 0, "preferences": _payload()},
    )

    assert response.status_code == 200
    stored = service.put_calls[0]["preferences"]
    assert stored["soft"]["spice_level"] is None
    assert stored["soft"]["order_requests"] == []


def test_put_preferences_surfaces_revision_conflict_without_payload_leak(client, api_key) -> None:
    class _ConflictingService(_PreferencesService):
        def put(self, **_: object) -> TravelPreferencesRecord:
            raise ServiceError(
                status_code=409,
                code="PREFERENCES_REVISION_CONFLICT",
                message="Travel preferences changed on another device.",
                retryable=False,
            )

    client.app.dependency_overrides[require_logto_identity] = _oauth_identity
    client.app.dependency_overrides[get_identity_service] = _IdentityService
    client.app.dependency_overrides[get_travel_preferences_service] = lambda: _ConflictingService()

    response = client.put(
        "/api/v1/me/preferences",
        headers={"X-API-Key": api_key},
        json={"expected_revision": 2, "preferences": _payload()},
    )

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "PREFERENCES_REVISION_CONFLICT"
    assert "raw onion" not in response.text
