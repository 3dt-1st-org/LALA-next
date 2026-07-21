from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from apps.api.app.services.legacy_retirement_plan import build_legacy_retirement_plan

ROOT = Path(__file__).resolve().parents[3]


def test_legacy_retirement_plan_is_non_mutating_and_maps_mobile_routes():
    plan = build_legacy_retirement_plan()
    payload = plan.to_dict()
    encoded = json.dumps(payload, ensure_ascii=False)

    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["applies_changes"] is False
    assert payload["route_mappings"]
    assert any(
        mapping["legacy_routes"] == ["/api/places", "/api/ios/v1/places"]
        and mapping["new_route"] == "/api/v1/places"
        for mapping in payload["route_mappings"]
    )
    assert any(
        mapping["legacy_routes"] == ["/api/planner/daily-plan"]
        and mapping["new_route"] == "/api/v1/plans/daily"
        for mapping in payload["route_mappings"]
    )
    assert any(option["option"] == "keep_legacy_admin" for option in payload["decision_options"])
    assert any("rollback" in item.lower() for item in payload["evidence_requirements"])
    assert any(step["approval_required"] for step in payload["steps"])

    assert "rm -rf" not in encoded
    assert "git reset" not in encoded
    assert "DROP " not in encoded
    assert "password=" not in encoded.lower()
    assert "client_secret" not in encoded.lower()


def test_legacy_retirement_plan_rejects_unsafe_labels():
    plan = build_legacy_retirement_plan(
        legacy_app_label="legacy;rm",
        fastapi_app_label="bad/api",
    )

    assert plan.ok is False
    assert len(plan.warnings) == 2


def test_plan_legacy_retirement_cli_outputs_json_without_secret_values():
    result = subprocess.run(
        [sys.executable, "-m", "apps.api.app.tools.plan_legacy_retirement", "--json"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )

    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert payload["applies_changes"] is False
    assert any(
        mapping["new_route"] == "/healthz and /readyz" for mapping in payload["route_mappings"]
    )
    assert "legacy-flask" in result.stdout
    assert "rm -rf" not in result.stdout
    assert "password=" not in result.stdout.lower()
    assert "client_secret" not in result.stdout.lower()
