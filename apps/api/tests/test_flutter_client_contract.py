from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from apps.api.app.main import create_app
from apps.api.app.services.flutter_client_contract import (
    FLUTTER_CLIENT_PATH,
    check_flutter_client_contract,
)

ROOT = Path(__file__).resolve().parents[3]
DART_TEST_PATH = ROOT / "clients" / "flutter" / "test" / "lala_api_client_test.dart"


def test_flutter_reference_client_tracks_openapi_routes_and_auth_contract():
    report = check_flutter_client_contract(openapi_schema=create_app().openapi())

    assert report.ok is True
    assert report.findings == ()
    assert "GET /healthz" in report.checked_routes
    assert "GET /readyz" in report.checked_routes
    assert "GET /api/v1/places" in report.checked_routes
    assert "POST /api/v1/docents/audio" in report.checked_routes

    client_text = FLUTTER_CLIENT_PATH.read_text(encoding="utf-8")
    assert "Authorization" in client_text
    assert "X-API-Key" in client_text
    assert "audio/mpeg" in client_text
    assert "LalaReadiness" in client_text
    assert "LalaRuntimeMode" in client_text
    assert "LalaPlacesResponse" in client_text
    assert "LalaWeather" in client_text
    assert "LalaDailyPlan" in client_text
    assert "LalaIntervention" in client_text
    assert "smallMerchantFitScore" in client_text
    assert "accessibilityFitScore" in client_text
    assert "REQUEST_TIMEOUT" in client_text
    assert "defaultTimeout" in client_text
    assert "print(" not in client_text

    test_text = DART_TEST_PATH.read_text(encoding="utf-8")
    assert "MockClient" in test_text
    assert "public health and readiness checks do not require client auth" in test_text
    assert "typed API response models parse weather, plans, and intervention" in test_text
    assert "network timeout becomes retryable LalaApiException" in test_text
    assert "createDocentAudio returns mpeg bytes" in test_text
    assert "JSON error envelope becomes LalaApiException" in test_text


def test_flutter_client_contract_flags_missing_route(tmp_path):
    client_path = tmp_path / "lala_api_client.dart"
    client_path.write_text(
        FLUTTER_CLIENT_PATH.read_text(encoding="utf-8").replace(
            "'/api/v1/weather'",
            "'/api/v1/weather-missing'",
        ),
        encoding="utf-8",
    )

    report = check_flutter_client_contract(
        openapi_schema=create_app().openapi(),
        client_path=client_path,
    )

    assert report.ok is False
    assert "Flutter client missing route: GET /api/v1/weather" in report.findings


def test_check_flutter_client_contract_cli_is_secret_safe():
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "apps.api.app.tools.check_flutter_client_contract",
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
    assert "API_BEARER_TOKEN" not in result.stdout
    assert "DB_DSN" not in result.stdout
