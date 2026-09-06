from __future__ import annotations

import json
import sys
from types import SimpleNamespace

import pytest

from apps.api.app.services import canonical_sql
from apps.api.app.tools import apply_canonical_sql

EXPECTED_CANONICAL_MIGRATION_ORDER = (
    "000_extensions_and_schemas.sql",
    "005_identity_users.sql",
    "010_travel_core_tables.sql",
    "020_travel_domain_tables.sql",
    "030_community_core_tables.sql",
    "035_data_pipeline_tables.sql",
    "036_rag_knowledge_tables.sql",
    "040_ops_core_tables.sql",
    "050_views_and_indexes.sql",
    "060_community_tables.sql",
    "061_community_chat_tables.sql",
    "062_review_ingestion_governance.sql",
    "063_local_signals_contract.sql",
    "064_planning_action_tables.sql",
    "065_user_travel_preferences.sql",
    "066_trip_library_and_visit_feedback.sql",
    "067_community_post_reports.sql",
    "068_community_chat_durable_controls.sql",
)


class FakeCursor:
    def __init__(self, executed: list) -> None:
        self.executed = executed

    def __enter__(self) -> FakeCursor:
        return self

    def __exit__(self, *args) -> None:
        return None

    def execute(self, sql: str, params: tuple | None = None) -> None:
        self.executed.append((sql, params))


class FakeConnection:
    def __init__(self, executed: list) -> None:
        self.executed = executed

    def __enter__(self) -> FakeConnection:
        return self

    def __exit__(self, *args) -> None:
        return None

    def cursor(self) -> FakeCursor:
        return FakeCursor(self.executed)


def test_load_canonical_sql_plan_is_safe_and_ordered():
    plan = canonical_sql.load_canonical_sql_plan()

    assert plan.ok is True
    assert tuple(item.name for item in plan.files) == EXPECTED_CANONICAL_MIGRATION_ORDER
    assert canonical_sql.CANONICAL_MIGRATION_ORDER == EXPECTED_CANONICAL_MIGRATION_ORDER
    assert canonical_sql.CANONICAL_MIGRATION_LATEST == "068_community_chat_durable_controls.sql"
    assert plan.to_dict()["statement_count"] >= 10
    assert all(len(item.sha256) == 64 for item in plan.files)


def test_canonical_migration_order_is_numeric_and_deterministic():
    names = (
        "063_local_signals_contract.sql",
        "005_identity_users.sql",
        "040_ops_core_tables.sql",
    )

    assert canonical_sql.validate_canonical_migration_order(names, require_baseline=False) == (
        "005_identity_users.sql",
        "040_ops_core_tables.sql",
        "063_local_signals_contract.sql",
    )


@pytest.mark.parametrize(
    "names",
    [
        ("010_first.sql", "010_second.sql"),
        ("10_missing_zero.sql",),
        ("010_bad-name.sql",),
    ],
)
def test_canonical_migration_filename_contract_rejects_duplicate_or_invalid_prefixes(names):
    with pytest.raises(ValueError):
        canonical_sql.validate_canonical_migration_order(names, require_baseline=False)


def test_future_migration_does_not_silently_extend_the_merged_baseline():
    future_names = EXPECTED_CANONICAL_MIGRATION_ORDER + (
        "069_rag_knowledge_retrieval_metadata.sql",
    )

    with pytest.raises(ValueError, match="baseline drifted"):
        canonical_sql.validate_canonical_migration_order(future_names, require_baseline=True)


def test_trip_library_migration_is_additive_and_bounded():
    sql = (canonical_sql.CANONICAL_SQL_DIR / "066_trip_library_and_visit_feedback.sql").read_text(
        encoding="utf-8"
    )

    assert "CREATE TABLE IF NOT EXISTS planning.trip_preference_overrides" in sql
    assert "ADD COLUMN IF NOT EXISTS reason_code" in sql
    assert "ADD COLUMN IF NOT EXISTS use_for_recommendations" in sql
    assert "ADD COLUMN IF NOT EXISTS confirmed_at" in sql
    assert "status IN ('planned', 'visited', 'not_visited')" in sql
    assert "jsonb_typeof(payload) = 'object'" in sql
    assert "DROP TABLE" not in sql.upper()
    assert "TRUNCATE" not in sql.upper()
    assert "DELETE FROM" not in sql.upper()


def test_community_post_reports_migration_is_idempotent_and_governed():
    sql = (canonical_sql.CANONICAL_SQL_DIR / "067_community_post_reports.sql").read_text(
        encoding="utf-8"
    )

    assert "CREATE TABLE IF NOT EXISTS community.post_reports" in sql
    assert "REFERENCES community.user_posts(id) ON DELETE CASCADE" in sql
    # The reporter must be a provisioned internal user (ownership constraint).
    assert "REFERENCES identity.users (issuer, subject)" in sql
    # Bounded reason vocabulary; no free-text report column exists.
    assert "post_reports_reason_check" in sql
    assert "'other_policy'" in sql
    # One unresolved report per reporter/post is enforced by a partial unique index.
    assert "CREATE UNIQUE INDEX IF NOT EXISTS idx_post_reports_unresolved" in sql
    assert "WHERE status IN ('open', 'triaged')" in sql
    assert "DROP TABLE" not in sql.upper()
    assert "TRUNCATE" not in sql.upper()
    assert "DELETE FROM" not in sql.upper()
    # No raw free-text report body/note column is part of the governed contract.
    assert "body text" not in sql.lower()
    assert "note text" not in sql.lower()
    assert "free_text" not in sql.lower()


def test_community_chat_durable_controls_migration_is_additive_and_governed():
    sql = (canonical_sql.CANONICAL_SQL_DIR / "068_community_chat_durable_controls.sql").read_text(
        encoding="utf-8"
    )

    # Room visibility defaults to public so pre-existing rooms keep semantics.
    assert "ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public'" in sql
    assert "chat_rooms_visibility_check" in sql
    assert "'private'" in sql
    # Private access is explicit: creator ownership plus a membership table.
    # Creator columns are ON DELETE SET NULL and intentionally carry no
    # non-null CHECK: account deletion must never be blocked by chat rooms.
    assert "ADD COLUMN IF NOT EXISTS created_by_issuer text" in sql
    assert "ADD COLUMN IF NOT EXISTS created_by_subject text" in sql
    assert "ON DELETE SET NULL" in sql
    assert "private_creator_check" not in sql
    assert "CREATE TABLE IF NOT EXISTS community.chat_room_members" in sql
    assert "role IN ('owner', 'member')" in sql
    assert "REFERENCES identity.users (issuer, subject)" in sql
    # Durable idempotency: unique primary key on (scope, actor, key), hashed
    # payloads, bounded key length, expiry-driven TTL, and account-deletion
    # participation through the actor FK cascade (no replay copies survive
    # account deletion).
    assert "CREATE TABLE IF NOT EXISTS community.idempotency_keys" in sql
    assert "PRIMARY KEY (scope, actor_issuer, actor_subject, idempotency_key)" in sql
    assert "fk_idempotency_keys_actor" in sql
    assert "ON DELETE CASCADE" in sql
    assert "char_length(request_hash) = 64" in sql
    assert "char_length(idempotency_key) BETWEEN 1 AND 200" in sql
    assert "CREATE INDEX IF NOT EXISTS idx_idempotency_keys_expiry" in sql
    # WebSocket tickets: only sha256 hashes at rest, single-use + expiry.
    assert "CREATE TABLE IF NOT EXISTS community.chat_ws_tickets" in sql
    assert "ticket_hash text PRIMARY KEY" in sql
    assert "char_length(ticket_hash) = 64" in sql
    assert "used_at timestamptz" in sql
    assert "DROP TABLE" not in sql.upper()
    assert "TRUNCATE" not in sql.upper()
    assert "DELETE FROM" not in sql.upper()


def test_custom_fake_runner_plan_reports_duplicate_prefix_without_db_access(tmp_path):
    (tmp_path / "000_first.sql").write_text("CREATE SCHEMA IF NOT EXISTS one;", encoding="utf-8")
    (tmp_path / "000_second.sql").write_text("CREATE SCHEMA IF NOT EXISTS two;", encoding="utf-8")

    plan = canonical_sql.load_canonical_sql_plan(tmp_path)

    assert plan.ok is False
    assert any(
        "Duplicate canonical migration numeric prefix: 000" in item for item in plan.safety_findings
    )


def test_identity_user_migration_has_only_local_identity_columns():
    schema_sql = (canonical_sql.CANONICAL_SQL_DIR / "000_extensions_and_schemas.sql").read_text()
    user_sql = (canonical_sql.CANONICAL_SQL_DIR / "005_identity_users.sql").read_text()

    assert "CREATE SCHEMA IF NOT EXISTS identity" in schema_sql
    for column in (
        "id uuid PRIMARY KEY DEFAULT gen_random_uuid()",
        "issuer text NOT NULL",
        "subject text NOT NULL",
        "status text NOT NULL DEFAULT 'active'",
        "created_at timestamptz NOT NULL DEFAULT now()",
        "last_seen_at timestamptz NOT NULL DEFAULT now()",
        "deletion_requested_at timestamptz",
        "UNIQUE (issuer, subject)",
    ):
        assert column in user_sql
    assert "CHECK (status IN ('active', 'deleting'))" in user_sql
    assert "CREATE TABLE IF NOT EXISTS identity.deleted_users" in user_sql
    assert "identity_digest bytea NOT NULL" in user_sql
    assert "deleted_at timestamptz NOT NULL DEFAULT now()" in user_sql
    assert "UNIQUE (identity_digest)" in user_sql
    assert "octet_length(identity_digest) = 32" in user_sql
    for forbidden in ("email", "nationality", "token", "claim", "client_secret"):
        assert forbidden not in user_sql.lower()


def test_sql_safety_scan_flags_destructive_and_secret_text():
    fake_dsn = "postgresql://user:" + "pass@example/db"
    findings = canonical_sql.scan_sql_safety(
        text=(f"DROP TABLE travel.places;\nSELECT '{fake_dsn}';\nDELETE FROM ops.daily_costs;"),
        label="bad.sql",
    )

    assert len(findings) == 3
    assert all(item.startswith("bad.sql:") for item in findings)


def test_apply_canonical_sql_cli_defaults_to_plan_json(capsys):
    exit_code = apply_canonical_sql.main(["--json"])

    output = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert output["ok"] is True
    assert output["mode"] == "plan"
    assert output["plan"]["file_count"] == len(EXPECTED_CANONICAL_MIGRATION_ORDER)
    assert "result" not in output


def test_apply_canonical_sql_cli_requires_apply_guard(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.delenv(apply_canonical_sql.ALLOW_ENV, raising=False)

    exit_code = apply_canonical_sql.main(["--apply", "--confirm", apply_canonical_sql.CONFIRM_TEXT])

    output = capsys.readouterr().out
    assert exit_code == 2
    assert apply_canonical_sql.ALLOW_ENV in output
    assert dsn not in output
    assert password not in output


def test_apply_canonical_sql_cli_redacts_execution_errors(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.setenv(apply_canonical_sql.ALLOW_ENV, "1")

    def fail(**kwargs):
        raise RuntimeError(f"connection failed for {dsn} password={password}")

    monkeypatch.setattr(apply_canonical_sql, "execute_canonical_sql", fail)

    exit_code = apply_canonical_sql.main(["--apply", "--confirm", apply_canonical_sql.CONFIRM_TEXT])

    output = capsys.readouterr().out
    assert exit_code == 2
    assert "[redacted]" in output
    assert password not in output
    assert dsn not in output


def test_execute_canonical_sql_runs_files_with_timeouts(monkeypatch, tmp_path):
    sql_dir = tmp_path / "canonical"
    sql_dir.mkdir()
    (sql_dir / "000_first.sql").write_text("CREATE SCHEMA IF NOT EXISTS one;", encoding="utf-8")
    (sql_dir / "010_second.sql").write_text(
        "CREATE TABLE IF NOT EXISTS one.t(id int);", encoding="utf-8"
    )
    plan = canonical_sql.load_canonical_sql_plan(sql_dir)
    executed: list = []

    def connect(dsn: str, connect_timeout: int) -> FakeConnection:
        executed.append(("connect", dsn, connect_timeout))
        return FakeConnection(executed)

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))

    result = canonical_sql.execute_canonical_sql(
        dsn="postgresql://redacted",
        plan=plan,
        connect_timeout=7,
        lock_timeout="1s",
        statement_timeout="2s",
    )

    assert result == {"ok": True, "applied_files": ["000_first.sql", "010_second.sql"]}
    assert executed[0] == ("connect", "postgresql://redacted", 7)
    assert executed[1] == ("SET LOCAL lock_timeout = %s", ("1s",))
    assert executed[2] == ("SET LOCAL statement_timeout = %s", ("2s",))
    assert "CREATE SCHEMA IF NOT EXISTS one;" in executed[3][0]
    assert "CREATE TABLE IF NOT EXISTS one.t(id int);" in executed[4][0]
