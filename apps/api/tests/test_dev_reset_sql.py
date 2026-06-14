from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from apps.api.app.services import dev_reset_sql

ROOT = Path(__file__).resolve().parents[3]


def test_load_dev_reset_sql_plan_is_local_only_and_secret_safe():
    plan = dev_reset_sql.load_dev_reset_sql_plan()
    payload = plan.to_dict()

    assert plan.ok is True
    assert payload["local_only"] is True
    assert payload["apply_supported"] is True
    assert payload["apply_scope"] == "local_only_guarded"
    assert "explicit localhost DB_DSN" in payload["apply_requires"]
    assert [item["name"] for item in payload["files"]] == [
        "010_seed_demo_travel.sql",
        "020_seed_demo_weather_docent.sql",
        "025_seed_demo_economy_culture.sql",
        "030_seed_demo_worker_ops.sql",
    ]
    assert payload["statement_count"] >= 3
    assert payload["safety_findings"] == []
    assert all(item["destructive_findings"] == [] for item in payload["files"])


def test_dev_reset_sql_requires_local_only_marker(tmp_path):
    sql_dir = tmp_path / "dev_reset"
    sql_dir.mkdir()
    (sql_dir / "010_seed.sql").write_text("SELECT 1;", encoding="utf-8")

    plan = dev_reset_sql.load_dev_reset_sql_plan(sql_dir)

    assert plan.ok is False
    assert "missing local-only marker" in plan.safety_findings[0]


def test_plan_dev_reset_cli_is_plan_only_and_secret_safe():
    result = subprocess.run(
        [sys.executable, "-m", "apps.api.app.tools.plan_dev_reset", "--json"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )

    payload = json.loads(result.stdout)
    plan = payload["plan"]
    assert payload["mode"] == "plan"
    assert plan["ok"] is True
    assert plan["local_only"] is True
    assert plan["apply_supported"] is True
    assert plan["apply_scope"] == "local_only_guarded"
    assert "postgresql://" not in result.stdout
    assert "password=" not in result.stdout


def test_dev_reset_dsn_host_guard_accepts_only_explicit_local_hosts():
    assert dev_reset_sql.extract_local_dsn_host("postgresql://user:pass@localhost:5432/lala")
    assert dev_reset_sql.extract_local_dsn_host("postgres://user:pass@127.0.0.1/lala")
    assert dev_reset_sql.extract_local_dsn_host("host=::1 dbname=lala user=demo")
    assert dev_reset_sql.extract_local_dsn_host("hostaddr=127.0.0.1 dbname=lala user=demo")

    assert dev_reset_sql.extract_local_dsn_host("postgresql://user:pass@example.com/lala") == ""
    assert dev_reset_sql.extract_local_dsn_host("host=lala-next-db.postgres.database.azure.com dbname=lala") == ""
    assert dev_reset_sql.extract_local_dsn_host("dbname=lala user=demo") == ""


def test_dev_reset_apply_requires_explicit_guards_and_redacts_dsn(monkeypatch):
    dsn = "host=lala-next-db.postgres.database.azure.com dbname=lala user=demo password=sensitive"
    env = {
        **os.environ,
        "ALLOW_DEV_RESET_APPLY": "1",
        "DB_DSN": dsn,
    }

    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "apps.api.app.tools.plan_dev_reset",
            "--json",
            "--apply",
            "--confirm",
            "APPLY_DEV_RESET_SQL",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )

    assert result.returncode == 2
    payload = json.loads(result.stdout)
    assert payload["mode"] == "apply"
    assert payload["ok"] is False
    assert "localhost" in payload["error"]
    assert "sensitive" not in result.stdout
    assert "lala-next-db.postgres.database.azure.com" not in result.stdout


def test_dev_reset_apply_rejects_missing_confirm_before_reading_dsn(monkeypatch):
    monkeypatch.delenv("ALLOW_DEV_RESET_APPLY", raising=False)
    monkeypatch.delenv("DB_DSN", raising=False)

    result = subprocess.run(
        [sys.executable, "-m", "apps.api.app.tools.plan_dev_reset", "--json", "--apply"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 2
    payload = json.loads(result.stdout)
    assert payload["error"] == "--apply requires --confirm APPLY_DEV_RESET_SQL."
