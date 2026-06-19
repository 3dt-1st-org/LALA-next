from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from apps.api.app.services.key_vault_reuse_plan import build_key_vault_reuse_plan

ROOT = Path(__file__).resolve().parents[3]


def test_key_vault_reuse_plan_is_non_mutating_and_narrow():
    plan = build_key_vault_reuse_plan()
    payload = plan.to_dict()
    encoded = json.dumps(payload, ensure_ascii=False)

    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["applies_changes"] is False
    assert payload["source_vault_name"] == "onmu-source-vault"
    assert payload["target_vault_name"] == "lala-key-vault"
    assert payload["candidate_secret_mappings"] == [
        {
            "source_secret_name": "int-cors-origins",
            "target_secret_name": "cors-allow-origins",
            "action": "copy_after_owner_approval",
            "approval_required": True,
            "secret_sensitive": True,
            "validation": "Compare hashes or rerun browser CORS smoke without printing the value.",
            "notes": [
                "This is the only current ONMU-to-LALA reuse candidate.",
                "It is environment configuration for browser CORS, not a credential for DB, OAuth, storage, or upstream APIs.",
                "The copied value must live in the LALA-next vault; LALA runtime must not point at the ONMU vault.",
            ],
        }
    ]
    rejected = " ".join(pattern["pattern"] for pattern in payload["rejected_secret_patterns"])
    assert "postgres" in rejected
    assert "oauth" in rejected
    assert "redis" in rejected
    assert "azure-openai" in rejected

    assert "secret set" not in encoded
    assert "secret show" not in encoded
    assert "postgresql://" not in encoded
    assert "password=" not in encoded.lower()
    assert "client_secret" not in encoded.lower()


def test_key_vault_reuse_plan_rejects_onmu_target():
    plan = build_key_vault_reuse_plan(
        source_vault_name="onmu-source-vault",
        target_vault_name="onmu-source-vault",
    )

    assert plan.ok is False
    assert len(plan.warnings) == 3
    assert any("runtime target" in warning for warning in plan.warnings)
    assert all("lala-key-vault" in gate for gate in plan.risk_gates[:1])


def test_plan_key_vault_reuse_cli_outputs_json_without_secret_values():
    result = subprocess.run(
        [sys.executable, "-m", "apps.api.app.tools.plan_key_vault_reuse", "--json"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )

    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert payload["applies_changes"] is False
    assert payload["candidate_secret_mappings"][0]["source_secret_name"] == "int-cors-origins"
    assert "cors-allow-origins" in result.stdout
    assert "secret show" not in result.stdout
    assert "secret set" not in result.stdout
    assert "password=" not in result.stdout.lower()
