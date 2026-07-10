from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from apps.api.app.main import create_app
from apps.api.app.services.openapi_compat import compare_openapi_compatibility

ROOT = Path(__file__).resolve().parents[3]


def test_openapi_compat_allows_additive_security_schemes():
    baseline = create_app().openapi()
    baseline["components"].pop("securitySchemes", None)
    current = create_app().openapi()

    report = compare_openapi_compatibility(baseline=baseline, current=current)

    assert report.ok is True
    assert report.findings == ()


def test_openapi_compat_flags_removed_paths_methods_parameters_and_content_types():
    baseline = create_app().openapi()
    current = create_app().openapi()

    current["paths"].pop("/api/v1/weather")
    current["paths"]["/api/v1/places"].pop("get")
    current["paths"]["/api/v1/docents/script"]["post"]["parameters"] = []
    current["paths"]["/api/v1/docents/audio"]["post"]["responses"]["200"]["content"] = {}

    report = compare_openapi_compatibility(baseline=baseline, current=current)

    assert report.ok is False
    assert "removed path: /api/v1/weather" in report.findings
    assert "removed operation: GET /api/v1/places" in report.findings
    assert any("removed response content type" in finding for finding in report.findings)


def test_openapi_compat_allows_legacy_docent_audio_empty_json_cleanup():
    baseline = create_app().openapi()
    current = create_app().openapi()
    baseline["paths"]["/api/v1/docents/audio"]["post"]["responses"]["200"]["content"][
        "application/json"
    ] = {"schema": {}}

    report = compare_openapi_compatibility(baseline=baseline, current=current)

    assert report.ok is True
    assert report.findings == ()


def test_openapi_compat_allows_removing_generated_auth_headers_from_exact_oauth_account_routes():
    baseline = create_app().openapi()
    current = create_app().openapi()
    for method in ("get", "delete"):
        baseline_parameters = baseline["paths"]["/api/v1/me"][method].setdefault(
            "parameters", []
        )
        if not any(parameter.get("name") == "Authorization" for parameter in baseline_parameters):
            baseline_parameters.append(_optional_auth_header("Authorization"))
        baseline_parameters.append(_optional_auth_header("X-API-Key"))
        current["paths"]["/api/v1/me"][method]["parameters"] = []

    report = compare_openapi_compatibility(baseline=baseline, current=current)

    assert report.ok is True
    assert report.findings == ()


def test_openapi_compat_flags_account_route_becoming_anonymous():
    baseline = create_app().openapi()
    current = create_app().openapi()
    current["paths"]["/api/v1/me"]["get"]["security"] = []

    report = compare_openapi_compatibility(baseline=baseline, current=current)

    assert report.ok is False
    assert "changed security: GET /api/v1/me" in report.findings


def test_openapi_compat_flags_static_auth_reintroduction_on_account_route():
    baseline = create_app().openapi()
    current = create_app().openapi()
    current["paths"]["/api/v1/me"]["delete"]["security"] = [
        {"OAuthBearerAuth": []},
        {"MigrationApiKey": []},
    ]

    report = compare_openapi_compatibility(baseline=baseline, current=current)

    assert report.ok is False
    assert "changed security: DELETE /api/v1/me" in report.findings


def test_openapi_compat_flags_security_drift_on_other_operations():
    baseline = create_app().openapi()
    current = create_app().openapi()
    current["paths"]["/api/v1/places"]["get"]["security"] = []

    report = compare_openapi_compatibility(baseline=baseline, current=current)

    assert report.ok is False
    assert "changed security: GET /api/v1/places" in report.findings


def test_openapi_compat_flags_unrelated_account_header_removal():
    baseline = create_app().openapi()
    current = create_app().openapi()
    baseline["paths"]["/api/v1/me"]["get"].setdefault("parameters", []).append(
        {
            "name": "X-Request-Trace",
            "in": "header",
            "required": False,
            "schema": {"type": "string"},
        }
    )

    report = compare_openapi_compatibility(baseline=baseline, current=current)

    assert report.ok is False
    assert (
        "removed parameter: GET /api/v1/me header X-Request-Trace"
        in report.findings
    )


def _optional_auth_header(name: str) -> dict:
    return {
        "name": name,
        "in": "header",
        "required": False,
        "schema": {
            "anyOf": [{"type": "string"}, {"type": "null"}],
            "title": name,
        },
    }


def test_check_openapi_compat_cli_passes_against_current_snapshot(tmp_path):
    baseline_path = tmp_path / "baseline-openapi.json"
    baseline_path.write_text(
        json.dumps(create_app().openapi(), ensure_ascii=False),
        encoding="utf-8",
    )

    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "apps.api.app.tools.check_openapi_compat",
            str(baseline_path),
            "--json",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )

    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert payload["findings"] == []
    assert "IOS_API_KEY" not in result.stdout
    assert "DB_DSN" not in result.stdout
