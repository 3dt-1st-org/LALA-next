from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from apps.api.app.services.identity_rollout_plan import build_identity_rollout_plan

ROOT = Path(__file__).resolve().parents[3]


def test_identity_rollout_plan_is_secret_safe_and_non_mutating():
    plan = build_identity_rollout_plan()
    payload = plan.to_dict()
    encoded = json.dumps(payload, ensure_ascii=False)

    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["applies_changes"] is False
    assert payload["key_vault_name"] == "lala-next-kv-27db5e"
    assert payload["api_app_id_uri"] == "api://lala-next-dev"
    assert "oauth-issuer" in payload["key_vault_secret_names"]
    assert "oauth-required-scopes" in payload["key_vault_secret_names"]
    assert "client_identity" in payload["readiness_checks"]
    assert any(step["approval_required"] for step in payload["steps"])
    assert any("scripts/unix/start_api.sh" in step["command"] for step in payload["steps"])

    assert "onmu-dev-kv" not in encoded
    assert "client_secret" not in encoded.lower()
    assert "password=" not in encoded.lower()
    assert "BEGIN PRIVATE KEY" not in encoded
    assert "<flutter-public-client-id>" in encoded


def test_identity_rollout_plan_rejects_onmu_vault_and_bad_scope():
    plan = build_identity_rollout_plan(
        key_vault_name="onmu-dev-kv-27db5e",
        required_scopes=("bad scope",),
    )

    assert plan.ok is False
    assert len(plan.warnings) == 3
    assert any("ONMU" in warning for warning in plan.warnings)
    assert all("onmu-dev-kv" not in step.command for step in plan.steps)


def test_plan_identity_rollout_cli_outputs_json_without_secret_values():
    result = subprocess.run(
        [sys.executable, "-m", "apps.api.app.tools.plan_identity_rollout", "--json"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )

    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert payload["applies_changes"] is False
    assert payload["key_vault_name"] == "lala-next-kv-27db5e"
    assert "oauth-jwks-url" in result.stdout
    assert "onmu-dev-kv" not in result.stdout
    assert "client_secret" not in result.stdout.lower()
    assert "password=" not in result.stdout.lower()
