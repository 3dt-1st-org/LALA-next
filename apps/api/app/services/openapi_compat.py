from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class OpenApiCompatReport:
    ok: bool
    findings: tuple[str, ...]
    baseline_path_count: int
    current_path_count: int

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "findings": list(self.findings),
            "baseline_path_count": self.baseline_path_count,
            "current_path_count": self.current_path_count,
        }


def compare_openapi_compatibility(
    *,
    baseline: dict[str, Any],
    current: dict[str, Any],
) -> OpenApiCompatReport:
    findings: list[str] = []
    baseline_paths = baseline.get("paths") or {}
    current_paths = current.get("paths") or {}
    baseline_root_security = baseline.get("security") or []
    current_root_security = current.get("security") or []

    for path, baseline_path_item in sorted(baseline_paths.items()):
        current_path_item = current_paths.get(path)
        if current_path_item is None:
            findings.append(f"removed path: {path}")
            continue
        if not isinstance(baseline_path_item, dict) or not isinstance(current_path_item, dict):
            continue

        for method, baseline_operation in sorted(baseline_path_item.items()):
            if method.lower() not in {"get", "post", "put", "patch", "delete", "options", "head"}:
                continue
            current_operation = current_path_item.get(method)
            if current_operation is None:
                findings.append(f"removed operation: {method.upper()} {path}")
                continue
            if not isinstance(baseline_operation, dict) or not isinstance(current_operation, dict):
                continue
            findings.extend(
                _compare_operation(
                    path=path,
                    method=method.upper(),
                    baseline_operation=baseline_operation,
                    current_operation=current_operation,
                    baseline_root_security=baseline_root_security,
                    current_root_security=current_root_security,
                )
            )

    return OpenApiCompatReport(
        ok=not findings,
        findings=tuple(findings),
        baseline_path_count=len(baseline_paths),
        current_path_count=len(current_paths),
    )


def _compare_operation(
    *,
    path: str,
    method: str,
    baseline_operation: dict[str, Any],
    current_operation: dict[str, Any],
    baseline_root_security: Any,
    current_root_security: Any,
) -> list[str]:
    findings: list[str] = []
    operation_label = f"{method} {path}"
    baseline_security = _effective_security(
        baseline_operation,
        baseline_root_security,
    )
    current_security = _effective_security(
        current_operation,
        current_root_security,
    )
    if _normalize_security(baseline_security) != _normalize_security(current_security):
        findings.append(f"changed security: {operation_label}")
    findings.extend(
        _compare_parameters(
            operation_label=operation_label,
            baseline_parameters=baseline_operation.get("parameters") or [],
            current_parameters=current_operation.get("parameters") or [],
            allow_account_auth_correction=_is_exact_account_auth_migration(
                operation_label=operation_label,
                baseline_operation=baseline_operation,
                current_operation=current_operation,
            ),
        )
    )
    findings.extend(
        _compare_responses(
            operation_label=operation_label,
            baseline_responses=baseline_operation.get("responses") or {},
            current_responses=current_operation.get("responses") or {},
        )
    )
    return findings


def _compare_parameters(
    *,
    operation_label: str,
    baseline_parameters: list[dict[str, Any]],
    current_parameters: list[dict[str, Any]],
    allow_account_auth_correction: bool,
) -> list[str]:
    findings: list[str] = []
    current_by_key = {
        (parameter.get("in"), parameter.get("name")): parameter
        for parameter in current_parameters
        if isinstance(parameter, dict)
    }
    for parameter in baseline_parameters:
        if not isinstance(parameter, dict):
            continue
        key = (parameter.get("in"), parameter.get("name"))
        current_parameter = current_by_key.get(key)
        if current_parameter is None:
            if (
                allow_account_auth_correction
                and _is_expected_generated_auth_header(parameter)
            ):
                continue
            findings.append(f"removed parameter: {operation_label} {key[0]} {key[1]}")
            continue
        if not parameter.get("required") and current_parameter.get("required"):
            findings.append(f"parameter became required: {operation_label} {key[0]} {key[1]}")
    return findings


def _is_exact_account_auth_migration(
    *,
    operation_label: str,
    baseline_operation: dict[str, Any],
    current_operation: dict[str, Any],
) -> bool:
    expected_security = [{"OAuthBearerAuth": []}]
    if (
        operation_label not in {"GET /api/v1/me", "DELETE /api/v1/me"}
        or baseline_operation.get("security") != expected_security
        or current_operation.get("security") != expected_security
    ):
        return False
    return not any(
        isinstance(parameter, dict)
        and parameter.get("in") == "header"
        and parameter.get("name") in {"Authorization", "X-API-Key"}
        for parameter in current_operation.get("parameters") or []
    )


def _is_expected_generated_auth_header(parameter: dict[str, Any]) -> bool:
    if (
        parameter.get("in") != "header"
        or parameter.get("name") not in {"Authorization", "X-API-Key"}
        or parameter.get("required") is not False
    ):
        return False
    schema = parameter.get("schema")
    if not isinstance(schema, dict):
        return False
    if schema.get("type") == "string":
        return True
    any_of = schema.get("anyOf")
    return isinstance(any_of, list) and {
        item.get("type")
        for item in any_of
        if isinstance(item, dict)
    } == {"string", "null"}


def _effective_security(operation: dict[str, Any], root_security: Any) -> Any:
    if "security" in operation:
        return operation["security"]
    return root_security


def _normalize_security(security: Any) -> tuple:
    if not isinstance(security, list):
        return ()
    requirements: list[tuple] = []
    for requirement in security:
        if not isinstance(requirement, dict):
            requirements.append(((str(requirement), ()),))
            continue
        normalized_requirement = tuple(
            sorted(
                (
                    str(scheme),
                    tuple(sorted(str(scope) for scope in scopes))
                    if isinstance(scopes, list)
                    else (str(scopes),),
                )
                for scheme, scopes in requirement.items()
            )
        )
        requirements.append(normalized_requirement)
    if requirements and all(not requirement for requirement in requirements):
        return ()
    return tuple(sorted(requirements))


def _compare_responses(
    *,
    operation_label: str,
    baseline_responses: dict[str, Any],
    current_responses: dict[str, Any],
) -> list[str]:
    findings: list[str] = []
    for status_code, baseline_response in sorted(baseline_responses.items()):
        current_response = current_responses.get(status_code)
        if current_response is None:
            findings.append(f"removed response: {operation_label} {status_code}")
            continue
        baseline_content = _content_types(baseline_response)
        current_content = _content_types(current_response)
        for content_type in sorted(baseline_content - current_content):
            if _is_legacy_audio_json_content_correction(
                operation_label=operation_label,
                status_code=str(status_code),
                content_type=content_type,
                baseline_response=baseline_response,
                current_response=current_response,
            ):
                continue
            findings.append(
                f"removed response content type: {operation_label} {status_code} {content_type}"
            )
    return findings


def _is_legacy_audio_json_content_correction(
    *,
    operation_label: str,
    status_code: str,
    content_type: str,
    baseline_response: Any,
    current_response: Any,
) -> bool:
    if (
        operation_label != "POST /api/v1/docents/audio"
        or status_code != "200"
        or content_type != "application/json"
    ):
        return False
    baseline_content = _content_mapping(baseline_response)
    current_content = _content_mapping(current_response)
    return (
        baseline_content.get("application/json", {}).get("schema") == {}
        and "audio/mpeg" in baseline_content
        and "audio/mpeg" in current_content
    )


def _content_types(response: Any) -> set[str]:
    return set(_content_mapping(response))


def _content_mapping(response: Any) -> dict[str, Any]:
    if not isinstance(response, dict):
        return {}
    content = response.get("content") or {}
    if not isinstance(content, dict):
        return {}
    return {str(key): value for key, value in content.items()}
