from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

from apps.api.app.main import create_app
from apps.api.app.services.openapi_compat import compare_openapi_compatibility

ROOT = Path(__file__).resolve().parents[3]
PRE_TASK5_OPENAPI = ROOT / "apps" / "api" / "tests" / "fixtures" / "openapi-f9551bb.json"


def _pre_task5_openapi() -> dict:
    return json.loads(PRE_TASK5_OPENAPI.read_text(encoding="utf-8"))


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


def test_openapi_compat_allows_actual_pre_task5_guest_and_account_migration():
    baseline = _pre_task5_openapi()
    current = create_app().openapi()

    report = compare_openapi_compatibility(baseline=baseline, current=current)

    assert report.ok is True
    assert report.findings == ()


@pytest.mark.parametrize(
    "security",
    [
        [{"BearerAuth": []}, {"MigrationApiKey": []}],
        [{}, {"BearerAuth": []}],
        [{}, {"BearerAuth": ["tourism:read"]}, {"MigrationApiKey": []}],
        [{"OAuthBearerAuth": []}],
    ],
    ids=[
        "anonymous-removed",
        "static-removed",
        "scope-changed",
        "unrelated-strengthening",
    ],
)
def test_openapi_compat_actual_baseline_flags_guest_security_regressions(security):
    baseline = _pre_task5_openapi()
    current = create_app().openapi()
    current["paths"]["/api/v1/places"]["get"]["security"] = security

    report = compare_openapi_compatibility(baseline=baseline, current=current)

    assert "changed security: GET /api/v1/places" in report.findings


def test_openapi_compat_actual_baseline_requires_exact_old_account_headers():
    baseline = _pre_task5_openapi()
    current = create_app().openapi()
    authorization = next(
        parameter
        for parameter in baseline["paths"]["/api/v1/me"]["get"]["parameters"]
        if parameter.get("name") == "Authorization"
    )
    authorization["schema"] = {"type": "string"}

    report = compare_openapi_compatibility(baseline=baseline, current=current)

    assert "removed parameter: GET /api/v1/me header Authorization" in report.findings


def test_openapi_compat_actual_baseline_requires_exact_oauth_only_current_contract():
    baseline = _pre_task5_openapi()
    current = create_app().openapi()
    current["paths"]["/api/v1/me"]["delete"]["parameters"] = [
        _optional_auth_header("Authorization")
    ]

    report = compare_openapi_compatibility(baseline=baseline, current=current)

    assert "changed security: DELETE /api/v1/me" in report.findings


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
    assert "removed parameter: GET /api/v1/me header X-Request-Trace" in report.findings


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


def test_check_openapi_compat_cli_passes_against_actual_pre_task5_snapshot():
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "apps.api.app.tools.check_openapi_compat",
            str(PRE_TASK5_OPENAPI),
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
