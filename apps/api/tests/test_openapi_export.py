from __future__ import annotations

import json
import subprocess
import sys

from apps.api.app.tools.export_openapi import export_openapi_schema


def test_export_openapi_schema_writes_flutter_contract_paths(tmp_path):
    output_path = tmp_path / "lala-next-openapi.json"

    schema = export_openapi_schema(output_path)
    written = json.loads(output_path.read_text(encoding="utf-8"))

    assert written == schema
    assert written["info"]["title"] == "LALA-next Public API"
    assert "/api/v1/places" in written["paths"]
    assert "/api/v1/docents/audio" in written["paths"]


def test_export_openapi_cli_json_status_is_secret_safe(tmp_path):
    output_path = tmp_path / "lala-next-openapi.json"
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "apps.api.app.tools.export_openapi",
            "--output",
            str(output_path),
            "--json",
        ],
        check=True,
        capture_output=True,
        text=True,
    )

    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert payload["path_count"] >= 9
    assert output_path.exists()
    assert "IOS_API_KEY" not in result.stdout
    assert "DB_DSN" not in result.stdout
