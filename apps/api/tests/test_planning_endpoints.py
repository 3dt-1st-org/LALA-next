from __future__ import annotations

from typing import Any

from fastapi.testclient import TestClient

from apps.api.app.core.auth import RequestIdentity, require_client_auth, require_logto_identity
from apps.api.app.main import create_app
from apps.api.app.services.planning_repository import get_planning_repository


class FakePlanningRepository:
    """In-memory stand-in used via dependency override so endpoint tests need no DB."""

    def __init__(self) -> None:
        self.calls: list[tuple] = []
        self.plan: dict[str, Any] | None = None
        self.saved_places: list[dict[str, Any]] = []
        self.visits: list[dict[str, Any]] = []

    def list_saved_places(self, *, issuer: str, subject: str):
        self.calls.append(("list_saved_places", issuer, subject))
        return self.saved_places

    def set_saved_place(self, *, issuer, subject, place_id, source, active):
        self.calls.append(("set_saved_place", issuer, subject, place_id, active))
        return {"place_id": place_id, "saved": active, "changed": True}

    def save_plan(self, *, issuer, subject, plan_date, envelope):
        self.calls.append(("save_plan", issuer, subject, plan_date, envelope))
        return {
            "plan_date": plan_date.isoformat(),
            "schema_version": 1,
            "updated_at": None,
        }

    def load_plan(self, *, issuer, subject, plan_date):
        self.calls.append(("load_plan", issuer, subject, plan_date))
        return self.plan

    def list_slot_visits(self, *, issuer, subject, plan_date):
        self.calls.append(("list_slot_visits", issuer, subject, plan_date))
        return self.visits

    def set_slot_visit(self, *, issuer, subject, plan_date, slot_period, place_id, status):
        self.calls.append(("set_slot_visit", issuer, subject, plan_date, slot_period, status))
        return {
            "slot_period": slot_period,
            "place_id": place_id,
            "status": status,
            "visited_at": None,
        }


def _client(repo: FakePlanningRepository, identity: RequestIdentity) -> TestClient:
    app = create_app()
    # Override both the router-level auth gate and the strict logto resolver so the
    # caller identity is fixed without a real JWT (the repo is faked too -> no DB).
    app.dependency_overrides[require_client_auth] = lambda: identity
    app.dependency_overrides[require_logto_identity] = lambda: identity
    app.dependency_overrides[get_planning_repository] = lambda: repo
    return TestClient(app)


def _identity_a() -> RequestIdentity:
    return RequestIdentity(mode="oauth", issuer="https://issuer.example", subject="user-a")


def _assert_envelope(payload: dict) -> dict:
    assert payload["ok"] is True
    assert payload["error"] is None
    assert "request_id" in payload["meta"]
    return payload["data"]


def test_list_saved_places_honest_empty_and_caller_scoped():
    repo = FakePlanningRepository()
    resp = _client(repo, _identity_a()).get("/api/v1/me/saved-places")
    assert resp.status_code == 200
    data = _assert_envelope(resp.json())
    assert data == {"items": []}  # honest empty (D9)
    assert repo.calls[0] == ("list_saved_places", "https://issuer.example", "user-a")


def test_save_and_unsave_place_toggle():
    repo = FakePlanningRepository()
    client = _client(repo, _identity_a())
    saved = client.put("/api/v1/me/saved-places/p1", json={"source": "db"})
    assert saved.status_code == 200
    assert _assert_envelope(saved.json())["saved"] is True
    unsaved = client.delete("/api/v1/me/saved-places/p1")
    assert unsaved.status_code == 200
    assert _assert_envelope(unsaved.json())["saved"] is False


def test_load_plan_honest_null_when_absent():
    repo = FakePlanningRepository()  # plan is None
    resp = _client(repo, _identity_a()).get("/api/v1/me/plans/2026-08-14")
    assert resp.status_code == 200
    payload = resp.json()
    assert payload["ok"] is True
    assert payload["data"] is None  # honest null, never a throw (D8/D9)
    assert payload["meta"]["source"] == "unavailable"


def test_load_plan_returns_plan_when_present():
    repo = FakePlanningRepository()
    repo.plan = {
        "plan_date": "2026-08-14",
        "schema_version": 1,
        "plan": {"language": "ko"},
        "updated_at": None,
    }
    resp = _client(repo, _identity_a()).get("/api/v1/me/plans/2026-08-14")
    data = _assert_envelope(resp.json())
    assert data["plan"] == {"language": "ko"}
    assert resp.json()["meta"]["source"] == "db"


def test_save_plan_persists_envelope_body():
    repo = FakePlanningRepository()
    plan = {"language": "ko", "center": {"lat": 37.0, "lng": 127.0}, "slots": []}
    resp = _client(repo, _identity_a()).put("/api/v1/me/plans/2026-08-14", json={"plan": plan})
    assert resp.status_code == 200
    _assert_envelope(resp.json())
    assert repo.calls[0][0] == "save_plan"
    assert repo.calls[0][4] == plan  # envelope passed through verbatim


def test_visits_list_honest_empty_and_check_in():
    repo = FakePlanningRepository()
    client = _client(repo, _identity_a())
    listed = client.get("/api/v1/me/plans/2026-08-14/visits")
    assert _assert_envelope(listed.json()) == {"items": []}
    checked = client.put(
        "/api/v1/me/plans/2026-08-14/visits/morning",
        json={"status": "visited", "place_id": "p1"},
    )
    data = _assert_envelope(checked.json())
    assert data == {
        "slot_period": "morning",
        "place_id": "p1",
        "status": "visited",
        "visited_at": None,
    }


def test_check_in_rejects_unknown_slot_period_with_422():
    repo = FakePlanningRepository()
    resp = _client(repo, _identity_a()).put(
        "/api/v1/me/plans/2026-08-14/visits/brunch", json={"status": "visited"}
    )
    assert resp.status_code == 422  # Literal path-param validation
    assert repo.calls == []  # repository never reached


def test_cross_user_isolation_wires_caller_identity():
    # User B's request must hand user B's identity to the repository, never user A's.
    repo = FakePlanningRepository()
    identity_b = RequestIdentity(mode="oauth", issuer="https://issuer.example", subject="user-b")
    _client(repo, identity_b).get("/api/v1/me/saved-places")
    assert repo.calls[0][2] == "user-b"
    assert repo.calls[0][2] != "user-a"


def test_guest_identity_is_rejected_by_logto_gate():
    # A public/guest caller is admitted by the router-level auth gate but must be
    # rejected by require_logto_identity (401) — the action layer is oauth-scoped.
    repo = FakePlanningRepository()
    app = create_app()
    app.dependency_overrides[require_client_auth] = lambda: RequestIdentity(mode="public")
    app.dependency_overrides[get_planning_repository] = lambda: repo
    resp = TestClient(app).get("/api/v1/me/saved-places")
    assert resp.status_code == 401
    assert repo.calls == []  # repository never reached for a non-oauth caller
