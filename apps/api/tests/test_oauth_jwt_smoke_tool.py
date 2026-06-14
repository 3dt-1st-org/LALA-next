from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def test_local_oauth_jwt_smoke_tool_runs_without_secret_values():
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "apps.api.app.tools.smoke_oauth_jwt",
            "--api-port",
            "0",
            "--json",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
        timeout=40,
    )

    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert payload["applies_changes"] is False
    assert payload["client_identity"] == "oauth-configured"
    assert payload["jwt_validation"] == "configured"
    assert payload["wrong_scope_status"] == "rejected"
    assert "eyJ" not in result.stdout
    assert "BEGIN PRIVATE KEY" not in result.stdout
    assert "secret show" not in result.stdout
