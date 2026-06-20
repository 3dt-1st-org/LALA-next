from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from apps.api.app.services.db_rollout_plan import build_db_rollout_plan

ROOT = Path(__file__).resolve().parents[3]


def test_db_rollout_plan_is_secret_safe_and_non_mutating():
    plan = build_db_rollout_plan()
    payload = plan.to_dict()
    encoded = json.dumps(payload, ensure_ascii=False)

    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["applies_changes"] is False
    assert payload["key_vault_name"] == "lala-key-vault"
    assert payload["postgres_server_name"] == "lala-postgres-server"
    assert payload["canonical_sql"]["file_count"] >= 6
    assert payload["canonical_sql"]["safety_findings"] == []
    assert any(step["approval_required"] for step in payload["steps"])
    assert any("verify_db_resources.sh" in step["command"] for step in payload["steps"])
    assert any("apply_canonical_sql.sh" in step["command"] for step in payload["steps"])

    assert "onmu-dev-kv" not in encoded
    assert "postgresql://user:" not in encoded
    assert "password=" not in encoded.lower()
    assert "<redacted-postgresql-dsn>" in encoded
    assert any('"$POSTGRES_ADMIN_PASSWORD"' in step["command"] for step in payload["steps"])


def test_db_rollout_plan_rejects_unsafe_resource_names():
    plan = build_db_rollout_plan(
        postgres_server_name="BAD_server_name!",
        database_name="lala;drop",
        admin_user="admin user",
        storage_size_gb=16,
    )

    assert plan.ok is False
    assert len(plan.warnings) == 4


def test_plan_db_rollout_cli_outputs_json_without_secret_values():
    result = subprocess.run(
        [sys.executable, "-m", "apps.api.app.tools.plan_db_rollout", "--json"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )

    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert payload["applies_changes"] is False
    assert payload["canonical_sql"]["file_count"] >= 6
    assert "db-dsn" in result.stdout
    assert "onmu-dev-kv" not in result.stdout
    assert "postgresql://user:" not in result.stdout
    assert "password=" not in result.stdout.lower()


def test_plan_db_rollout_human_output_redacts_operational_resource_names():
    result = subprocess.run(
        [sys.executable, "-m", "apps.api.app.tools.plan_db_rollout"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )

    assert "key_vault=<key-vault>" in result.stdout
    assert "resource_group=<resource-group>" in result.stdout
    assert "postgres_server=<postgres-server>" in result.stdout
    assert "lala-key-vault" not in result.stdout
    assert "lala-resource-group" not in result.stdout
    assert "lala-postgres-server" not in result.stdout
    assert "<database>admin" not in result.stdout
