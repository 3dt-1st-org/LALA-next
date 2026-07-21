from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from apps.api.app.services.canonical_sql import REPO_ROOT

FLUTTER_CLIENT_PATH = REPO_ROOT / "clients" / "flutter" / "lib" / "lala_api_client.dart"

# OpenAPI 에는 노출되지만 Flutter 클라이언트가 의도적으로 소비하지 않는 라우트(ops/모니터링 전용).
# 신규 ops 라우트 추가 시 여기에 명시적으로 기록한다 (SSOT 예외).
CLIENT_EXEMPT_ROUTES: frozenset[tuple[str, str]] = frozenset(
    {
        ("GET", "/metrics"),
    }
)

_HTTP_METHODS = ("get", "post", "put", "delete", "patch")


def _api_routes_from_openapi(openapi_schema: dict[str, Any]) -> list[tuple[str, str]]:
    """OpenAPI paths 에서 (METHOD, path) 를 파생한다 — 하드코딩 라우트 리스트 없이 SSOT."""
    paths = openapi_schema.get("paths", {}) or {}
    routes: list[tuple[str, str]] = []
    for path, methods in paths.items():
        if not isinstance(methods, dict):
            continue
        for method in methods:
            if method.lower() in _HTTP_METHODS:
                routes.append((method.upper(), path))
    routes.sort()
    return routes


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

    # SSOT: 검증 대상 라우트를 OpenAPI 스키마에서 파생 (하드코딩 EXPECTED_CLIENT_ROUTES 제거).
    # 라우트 추가 시 자동으로 검증 대상이 되어 스펙-클라이언트 드리프트를 즉시 포착.
    for method, route in _api_routes_from_openapi(openapi_schema):
        checked_routes.append(f"{method} {route}")
        if (method, route) in CLIENT_EXEMPT_ROUTES:
            continue  # ops/모니터링 전용 — Flutter 클라이언트가 소비하지 않는 라우트
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
        "smallMerchantFitScore",
        "accessibilityFitScore",
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
