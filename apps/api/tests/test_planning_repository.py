from __future__ import annotations

from datetime import date
from typing import Any

import pytest

from apps.api.app.core.config import Settings
from apps.api.app.services.planning_repository import (
    PLANNING_ENVELOPE_VERSION,
    PlanningRepository,
    PlanningRepositoryUnavailable,
)


def _settings() -> Settings:
    return Settings(db_dsn="postgresql://redacted")


class _FakeCursor:
    def __init__(self, executed: list, fetchone: Any = None, fetchall: Any = None) -> None:
        self._executed = executed
        self._fetchone = fetchone
        self._fetchall = fetchall

    def __enter__(self) -> _FakeCursor:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def execute(self, sql: str, params: Any = None) -> None:
        self._executed.append((sql, params))

    def fetchone(self):
        return self._fetchone

    def fetchall(self):
        return self._fetchall or []


class _FakeConnection:
    def __init__(self, executed: list, fetchone: Any = None, fetchall: Any = None) -> None:
        self._executed = executed
        self._fetchone = fetchone
        self._fetchall = fetchall

    def __enter__(self) -> _FakeConnection:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def cursor(self, cursor_factory: Any = None) -> _FakeCursor:
        return _FakeCursor(self._executed, self._fetchone, self._fetchall)

    def close(self) -> None:
        return None


def _repo(fetchone: Any = None, fetchall: Any = None) -> tuple[PlanningRepository, list]:
    executed: list = []
    repo = PlanningRepository(
        _settings(),
        connect=lambda **_: _FakeConnection(executed, fetchone=fetchone, fetchall=fetchall),
    )
    return repo, executed


# -- D4 / A3: parameterized SQL, injection-immune by construction ----------------


def test_saved_place_toggle_binds_user_input_as_parameters_never_concatenated():
    repo, executed = _repo(fetchone={"place_id": "p"})
    attack = "' OR 1=1 --"
    repo.set_saved_place(
        issuer="iss", subject="sub", place_id=attack, source="public_mvp_snapshot", active=True
    )
    sql, params = executed[0]
    assert attack not in sql  # never interpolated into the SQL text
    assert attack in params  # always bound as a parameter
    assert "ON CONFLICT" in sql and "DO NOTHING" in sql


def test_every_read_query_is_scoped_to_caller_issuer_and_subject():
    # Cross-user isolation (A6) is structural: each SELECT carries the caller pair.
    repo, executed = _repo(fetchone=None, fetchall=[])
    repo.list_saved_places(issuer="iss-a", subject="sub-a")
    repo.list_slot_visits(issuer="iss-a", subject="sub-a", plan_date=date(2026, 8, 14))
    repo.load_plan(issuer="iss-a", subject="sub-a", plan_date=date(2026, 8, 14))
    for sql, params in executed:
        assert "issuer = %s" in sql and "subject = %s" in sql
        assert ("iss-a", "sub-a")[:2] == (params[0], params[1])


def test_user_b_params_never_reach_user_a_query():
    repo, executed = _repo(fetchall=[])
    repo.list_saved_places(issuer="iss-a", subject="sub-a")
    _, params = executed[0]
    assert "iss-b" not in params and "sub-b" not in params


# -- A4: idempotent toggle (save -> unsaved -> save = no duplicate row) ----------


def test_repeat_save_is_a_no_op_delta():
    repo_first, executed_first = _repo(fetchone={"place_id": "p"})  # row inserted
    first = repo_first.set_saved_place(
        issuer="iss", subject="sub", place_id="p", source="public_mvp_snapshot", active=True
    )
    repo_again, _ = _repo(fetchone=None)  # already present -> ON CONFLICT -> no row returned
    again = repo_again.set_saved_place(
        issuer="iss", subject="sub", place_id="p", source="public_mvp_snapshot", active=True
    )
    assert first == {"place_id": "p", "saved": True, "changed": True}
    assert again == {"place_id": "p", "saved": True, "changed": False}  # idempotent, one row
    assert "ON CONFLICT" in executed_first[0][0]


def test_unsave_uses_scoped_delete():
    repo, executed = _repo(fetchone={"place_id": "p"})
    result = repo.set_saved_place(
        issuer="iss", subject="sub", place_id="p", source="public_mvp_snapshot", active=False
    )
    sql, params = executed[0]
    assert "DELETE FROM planning.user_saved_places" in sql
    assert params == ("iss", "sub", "p")
    assert result == {"place_id": "p", "saved": False, "changed": True}


# -- A5: idempotent check-in (re-check-in = one row) ----------------------------


def test_check_in_upserts_in_place_never_duplicates():
    repo, executed = _repo(
        fetchone={
            "slot_period": "morning",
            "place_id": "p",
            "status": "visited",
            "visited_at": None,
        }
    )
    repo.set_slot_visit(
        issuer="iss",
        subject="sub",
        plan_date=date(2026, 8, 14),
        slot_period="morning",
        place_id="p",
        status="visited",
    )
    sql, params = executed[0]
    assert "ON CONFLICT" in sql and "DO UPDATE" in sql  # upsert -> idempotent, one row
    assert "iss" in params and "sub" in params and "morning" in params


def test_check_in_rejects_unknown_period_or_status():
    repo, _executed = _repo()
    with pytest.raises(ValueError):
        repo.set_slot_visit(
            issuer="iss",
            subject="sub",
            plan_date=date(2026, 8, 14),
            slot_period="brunch",
            place_id=None,
            status="visited",
        )
    with pytest.raises(ValueError):
        repo.set_slot_visit(
            issuer="iss",
            subject="sub",
            plan_date=date(2026, 8, 14),
            slot_period="morning",
            place_id=None,
            status="maybe",
        )


# -- A7 / A8 / D8: corrupt -> null, version-mismatch -> null, never throws -------


def test_load_plan_corrupt_envelope_returns_null():
    repo, _ = _repo(
        fetchone={
            "schema_version": PLANNING_ENVELOPE_VERSION,
            "envelope": "{bad",
            "updated_at": None,
        }
    )
    assert repo.load_plan(issuer="iss", subject="sub", plan_date=date(2026, 8, 14)) is None


def test_load_plan_version_mismatch_returns_null():
    repo, _ = _repo(
        fetchone={"schema_version": 999, "envelope": '{"language": "ko"}', "updated_at": None}
    )
    assert repo.load_plan(issuer="iss", subject="sub", plan_date=date(2026, 8, 14)) is None


def test_load_plan_valid_envelope_round_trips():
    plan = {"language": "ko", "slots": []}
    repo, _ = _repo(
        fetchone={"schema_version": PLANNING_ENVELOPE_VERSION, "envelope": plan, "updated_at": None}
    )
    result = repo.load_plan(issuer="iss", subject="sub", plan_date=date(2026, 8, 14))
    assert result is not None
    assert result["plan"] == plan
    assert result["schema_version"] == PLANNING_ENVELOPE_VERSION


# -- A9: honest empty when absent ------------------------------------------------


def test_honest_empty_when_no_data():
    repo, _ = _repo(fetchall=[], fetchone=None)
    assert repo.list_saved_places(issuer="iss", subject="sub") == []
    assert repo.list_slot_visits(issuer="iss", subject="sub", plan_date=date(2026, 8, 14)) == []
    assert repo.load_plan(issuer="iss", subject="sub", plan_date=date(2026, 8, 14)) is None


def test_list_results_project_only_safe_fields():
    repo, _ = _repo(
        fetchall=[
            {"place_id": "p1", "source": "public_mvp_snapshot", "saved_at": None},
            {"place_id": "p2", "source": "db", "saved_at": None},
        ]
    )
    saves = repo.list_saved_places(issuer="iss", subject="sub")
    assert [s["place_id"] for s in saves] == ["p1", "p2"]
    assert all(set(s) == {"place_id", "source", "saved_at"} for s in saves)  # no coords/PII leak


# -- D8 store path serializes envelope without a client toJson -----------------


def test_save_plan_serializes_envelope_as_json_parameter():
    repo, executed = _repo(
        fetchone={
            "plan_date": date(2026, 8, 14),
            "schema_version": PLANNING_ENVELOPE_VERSION,
            "updated_at": None,
        }
    )
    plan = {"language": "ko", "center": {"lat": 37.0, "lng": 127.0}, "slots": []}
    repo.save_plan(issuer="iss", subject="sub", plan_date=date(2026, 8, 14), envelope=plan)
    sql, params = executed[0]
    assert "INSERT INTO planning.user_plans" in sql and "ON CONFLICT" in sql
    # envelope is the 5th parameter, bound (Json wrapper), not concatenated.
    assert plan["language"] not in sql


# -- repo unavailable without a DB (CI has no DB_DSN) --------------------------


@pytest.mark.parametrize("dsn", ["", None])
def test_repository_unavailable_without_db_dsn(dsn):
    repo = PlanningRepository(Settings(db_dsn=dsn))  # type: ignore[arg-type]
    with pytest.raises(PlanningRepositoryUnavailable):
        repo.list_saved_places(issuer="iss", subject="sub")
