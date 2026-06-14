from __future__ import annotations

import json
import sys
from types import SimpleNamespace

from apps.api.app.services import canonical_sql
from apps.api.app.tools import apply_canonical_sql


class FakeCursor:
    def __init__(self, executed: list) -> None:
        self.executed = executed

    def __enter__(self) -> "FakeCursor":
        return self

    def __exit__(self, *args) -> None:
        return None

    def execute(self, sql: str, params: tuple | None = None) -> None:
        self.executed.append((sql, params))


class FakeConnection:
    def __init__(self, executed: list) -> None:
        self.executed = executed

    def __enter__(self) -> "FakeConnection":
        return self

    def __exit__(self, *args) -> None:
        return None

    def cursor(self) -> FakeCursor:
        return FakeCursor(self.executed)


def test_load_canonical_sql_plan_is_safe_and_ordered():
    plan = canonical_sql.load_canonical_sql_plan()

    assert plan.ok is True
    assert [item.name for item in plan.files] == [
        "000_extensions_and_schemas.sql",
        "010_travel_core_tables.sql",
        "020_travel_domain_tables.sql",
        "030_community_core_tables.sql",
        "035_data_pipeline_tables.sql",
        "040_ops_core_tables.sql",
        "050_views_and_indexes.sql",
    ]
    assert plan.to_dict()["statement_count"] >= 10
    assert all(len(item.sha256) == 64 for item in plan.files)


def test_sql_safety_scan_flags_destructive_and_secret_text():
    fake_dsn = "postgresql://user:" + "pass@example/db"
    findings = canonical_sql.scan_sql_safety(
        text=(
            "DROP TABLE travel.places;\n"
            f"SELECT '{fake_dsn}';\n"
            "DELETE FROM ops.daily_costs;"
        ),
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
    assert output["plan"]["file_count"] == 7
    assert "result" not in output


def test_apply_canonical_sql_cli_requires_apply_guard(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.delenv(apply_canonical_sql.ALLOW_ENV, raising=False)

    exit_code = apply_canonical_sql.main(
        ["--apply", "--confirm", apply_canonical_sql.CONFIRM_TEXT]
    )

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

    exit_code = apply_canonical_sql.main(
        ["--apply", "--confirm", apply_canonical_sql.CONFIRM_TEXT]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert "[redacted]" in output
    assert password not in output
    assert dsn not in output


def test_execute_canonical_sql_runs_files_with_timeouts(monkeypatch, tmp_path):
    sql_dir = tmp_path / "canonical"
    sql_dir.mkdir()
    (sql_dir / "000_first.sql").write_text("CREATE SCHEMA IF NOT EXISTS one;", encoding="utf-8")
    (sql_dir / "010_second.sql").write_text("CREATE TABLE IF NOT EXISTS one.t(id int);", encoding="utf-8")
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
