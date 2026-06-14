from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from apps.api.app.services.access_log_inspector import inspect_access_log

ROOT = Path(__file__).resolve().parents[3]


def test_access_log_inspector_filters_and_drops_untrusted_fields(tmp_path):
    log_path = tmp_path / "api-access.jsonl"
    secret = "should-not-be-returned"
    log_path.write_text(
        "\n".join(
            [
                json.dumps(
                    {
                        "request_id": "ready-request",
                        "method": "GET",
                        "path": "/readyz",
                        "status_code": 200,
                        "duration_ms": 1.23,
                        "client_host": "127.0.0.1",
                        "authorization": f"Bearer {secret}",
                        "query": f"token={secret}",
                    }
                ),
                "not-json",
                json.dumps(
                    {
                        "request_id": "places-request",
                        "method": "GET",
                        "path": "/api/v1/places",
                        "status_code": 200,
                        "duration_ms": 2.5,
                        "client_host": "127.0.0.1",
                        "x-api-key": secret,
                    }
                ),
            ]
        ),
        encoding="utf-8",
    )

    inspection = inspect_access_log(
        str(log_path),
        request_id="places-request",
        route_path="/api/v1/places",
    )
    payload = inspection.to_dict()
    encoded = json.dumps(payload, ensure_ascii=False)

    assert payload["ok"] is True
    assert payload["total_lines"] == 3
    assert payload["invalid_lines"] == 1
    assert payload["matched_count"] == 1
    assert payload["records"] == [
        {
            "request_id": "places-request",
            "method": "GET",
            "path": "/api/v1/places",
            "status_code": 200,
            "duration_ms": 2.5,
            "client_host": "127.0.0.1",
        }
    ]
    assert secret not in encoded
    assert "authorization" not in encoded.lower()
    assert "x-api-key" not in encoded.lower()
    assert "query" not in encoded.lower()


def test_access_log_inspector_limits_to_latest_matches(tmp_path):
    log_path = tmp_path / "api-access.jsonl"
    log_path.write_text(
        "\n".join(
            json.dumps(
                {
                    "request_id": f"request-{index}",
                    "method": "GET",
                    "path": "/healthz",
                    "status_code": 200,
                    "duration_ms": index,
                    "client_host": "127.0.0.1",
                }
            )
            for index in range(5)
        ),
        encoding="utf-8",
    )

    payload = inspect_access_log(str(log_path), route_path="/healthz", limit=2).to_dict()

    assert payload["matched_count"] == 5
    assert [record["request_id"] for record in payload["records"]] == [
        "request-3",
        "request-4",
    ]


def test_access_log_inspector_cli_outputs_json_without_secret_values(tmp_path):
    log_path = tmp_path / "api-access.jsonl"
    secret = "do-not-print"
    log_path.write_text(
        json.dumps(
            {
                "request_id": "cli-request",
                "method": "POST",
                "path": "/api/v1/docents/audio",
                "status_code": 200,
                "duration_ms": 12.34567,
                "client_host": "127.0.0.1",
                "body": secret,
            }
        )
        + "\n",
        encoding="utf-8",
    )

    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "apps.api.app.tools.inspect_access_log",
            str(log_path),
            "--request-id",
            "cli-request",
            "--json",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )

    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert payload["matched_count"] == 1
    assert payload["records"][0]["path"] == "/api/v1/docents/audio"
    assert payload["records"][0]["duration_ms"] == 12.346
    assert secret not in result.stdout
    assert "body" not in result.stdout.lower()
