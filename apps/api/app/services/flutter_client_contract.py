from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from apps.api.app.services.canonical_sql import REPO_ROOT

FLUTTER_CLIENT_PATH = REPO_ROOT / "clients" / "flutter" / "lib" / "lala_api_client.dart"

EXPECTED_CLIENT_ROUTES: tuple[tuple[str, str], ...] = (
    ("GET", "/healthz"),
    ("GET", "/readyz"),
    ("GET", "/api/v1/places"),
    ("GET", "/api/v1/weather"),
    ("POST", "/api/v1/docents/script"),
    ("POST", "/api/v1/docents/audio"),
    ("POST", "/api/v1/plans/daily"),
    ("GET", "/api/v1/plans/intervention"),
)


@dataclass(frozen=True)
class FlutterClientContractReport:
    ok: bool
    client_path: str
    checked_routes: tuple[str, ...]
    findings: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "client_path": self.client_path,
            "checked_routes": list(self.checked_routes),
            "findings": list(self.findings),
        }


def check_flutter_client_contract(
    *,
    openapi_schema: dict[str, Any],
    client_path: Path = FLUTTER_CLIENT_PATH,
) -> FlutterClientContractReport:
    findings: list[str] = []
    checked_routes: list[str] = []

    if not client_path.exists():
        return FlutterClientContractReport(
            ok=False,
            client_path=_display_path(client_path),
            checked_routes=(),
            findings=(f"missing Flutter client file: {client_path}",),
        )

    client_text = client_path.read_text(encoding="utf-8")
    paths = openapi_schema.get("paths", {})

    for method, route in EXPECTED_CLIENT_ROUTES:
        checked_routes.append(f"{method} {route}")
        operation = paths.get(route, {}).get(method.lower())
        if operation is None:
            findings.append(f"OpenAPI missing operation: {method} {route}")
        if f"'{route}'" not in client_text and f'"{route}"' not in client_text:
            findings.append(f"Flutter client missing route: {method} {route}")

    required_snippets = (
        "Authorization",
        "Bearer ",
        "X-API-Key",
        "X-Request-ID",
        "x-lala-request-hash",
        "x-lala-cache-key",
        "audio/mpeg",
        "LalaApiException",
        "LalaEnvelope",
        "LalaReadiness",
        "LalaRuntimeMode",
        "LalaPlacesResponse",
        "LalaPlace",
        "LalaWeather",
        "LalaDocentScript",
        "LalaDailyPlan",
        "LalaIntervention",
        "requestHash",
        "cacheKey",
        "TimeoutException",
        "REQUEST_TIMEOUT",
        "defaultTimeout",
    )
    for snippet in required_snippets:
        if snippet not in client_text:
            findings.append(f"Flutter client missing snippet: {snippet}")

    if "print(" in client_text:
        findings.append("Flutter client must not print response bodies or credentials.")

    return FlutterClientContractReport(
        ok=not findings,
        client_path=_display_path(client_path),
        checked_routes=tuple(checked_routes),
        findings=tuple(findings),
    )


def _display_path(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT)).replace("\\", "/")
    except ValueError:
        return str(path)
