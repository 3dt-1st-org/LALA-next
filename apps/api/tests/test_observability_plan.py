from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from apps.api.app.services.observability_plan import build_observability_plan

ROOT = Path(__file__).resolve().parents[3]


def test_observability_plan_is_non_mutating_and_tracks_metrics():
    plan = build_observability_plan(base_url="https://dev-api.example.test")
    payload = plan.to_dict()
    encoded = json.dumps(payload, ensure_ascii=False)

    assert payload["ok"] is True
    assert payload["applies_changes"] is False
    assert payload["scrape_endpoint"] == "https://dev-api.example.test/metrics"
    assert "lala_next_http_requests_total" in payload["metrics"]
    assert "lala_next_dependency_ready" in payload["metrics"]
    assert "lala_next_runtime_mode" in payload["metrics"]
    assert "client_auth" in payload["readiness_checks"]
    assert "client_identity" in payload["readiness_checks"]
    assert "jwt_validation" in payload["readiness_checks"]
    assert "oauth_jwks_url" in payload["readiness_checks"]
    assert "mode.overall" in payload["readiness_checks"]
    assert "worker_contracts" in payload["readiness_checks"]
    assert len(payload["alert_rules"]) >= 5
    assert len(payload["dashboard_panels"]) >= 4
    assert "request_id" in payload["log_fields"]

    assert "API_BEARER_TOKEN" not in encoded
    assert "IOS_API_KEY" not in encoded
    assert "postgresql://" not in encoded
    assert "secret show" not in encoded


def test_observability_plan_cli_json_is_secret_safe():
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "apps.api.app.tools.plan_observability",
            "--base-url",
            "https://dev-api.example.test/",
            "--json",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )

    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert payload["applies_changes"] is False
    assert payload["scrape_endpoint"] == "https://dev-api.example.test/metrics"
    assert "api-readyz-degraded" in result.stdout
    assert "API_BEARER_TOKEN" not in result.stdout
    assert "postgresql://" not in result.stdout
