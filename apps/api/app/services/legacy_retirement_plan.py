from __future__ import annotations

import re
import shlex
from dataclasses import dataclass
from typing import Any

DEFAULT_BASE_URL = "http://127.0.0.1:8080"
DEFAULT_LEGACY_APP_LABEL = "legacy-flask"
DEFAULT_FASTAPI_APP_LABEL = "lala-next-fastapi"

_LABEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_. -]{1,80}[A-Za-z0-9]$")

LEGACY_ROUTE_MAPPINGS: tuple[dict[str, Any], ...] = (
    {
        "legacy_routes": ("/api/places", "/api/ios/v1/places"),
        "new_route": "/api/v1/places",
        "consumer": "map/mobile place lookup",
        "fastapi_status": "implemented",
        "retirement_gate": "Flutter/iOS use /api/v1/places only and place payload parity is verified.",
    },
    {
        "legacy_routes": ("/api/weather", "/api/ios/v1/weather"),
        "new_route": "/api/v1/weather",
        "consumer": "weather snapshot and planner context",
        "fastapi_status": "implemented",
        "retirement_gate": "Weather DB-backed/fallback behavior and freshness status are verified on /readyz.",
    },
    {
        "legacy_routes": ("/api/docent/script", "/api/ios/v1/docent/script"),
        "new_route": "/api/v1/docents/script",
        "consumer": "docent script generation",
        "fastapi_status": "implemented",
        "retirement_gate": "Script request hash, cache key, live AI fallback, and cache write behavior are verified.",
    },
    {
        "legacy_routes": ("/api/docent/audio", "/api/ios/v1/docent/audio"),
        "new_route": "/api/v1/docents/audio",
        "consumer": "Azure Speech audio generation",
        "fastapi_status": "implemented",
        "retirement_gate": "audio/mpeg success, JSON error envelope, and paid Speech smoke are verified.",
    },
    {
        "legacy_routes": ("/api/planner/daily-plan",),
        "new_route": "/api/v1/plans/daily",
        "consumer": "daily planner",
        "fastapi_status": "implemented",
        "retirement_gate": "Flutter contract, coordinate validation, and request identity are verified.",
    },
    {
        "legacy_routes": ("/api/planner/intervention",),
        "new_route": "/api/v1/plans/intervention",
        "consumer": "location intervention",
        "fastapi_status": "implemented",
        "retirement_gate": "Flutter contract and authenticated smoke are verified.",
    },
    {
        "legacy_routes": ("/api/health",),
        "new_route": "/healthz and /readyz",
        "consumer": "legacy process health checks",
        "fastapi_status": "implemented",
        "retirement_gate": "Windows/shared-backend runbooks use /healthz and /readyz only.",
    },
    {
        "legacy_routes": ("/map", "/dashboard", "/settings"),
        "new_route": "no FastAPI replacement in Wave 1",
        "consumer": "legacy web UI and operations pages",
        "fastapi_status": "keep_or_migrate_later",
        "retirement_gate": "Product owner decides keep-as-admin, rebuild frontend, or remove after user inventory.",
    },
    {
        "legacy_routes": ("action log routes",),
        "new_route": "no public Flutter route",
        "consumer": "analytics and personalization candidates",
        "fastapi_status": "worker_or_ops_lane",
        "retirement_gate": "Event ownership, retention, and Power BI/ops dependencies are assigned.",
    },
)


@dataclass(frozen=True)
class LegacyRetirementPlanStep:
    order: int
    title: str
    command: str
    approval_required: bool
    notes: tuple[str, ...] = ()

    def to_dict(self) -> dict[str, Any]:
        return {
            "order": self.order,
            "title": self.title,
            "command": self.command,
            "approval_required": self.approval_required,
            "notes": list(self.notes),
        }


@dataclass(frozen=True)
class LegacyRetirementPlan:
    base_url: str
    legacy_app_label: str
    fastapi_app_label: str
    applies_changes: bool
    route_mappings: tuple[dict[str, Any], ...]
    decision_options: tuple[dict[str, str], ...]
    evidence_requirements: tuple[str, ...]
    steps: tuple[LegacyRetirementPlanStep, ...]
    risk_gates: tuple[str, ...]
    warnings: tuple[str, ...]

    @property
    def ok(self) -> bool:
        return not self.warnings

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "mode": "plan",
            "applies_changes": self.applies_changes,
            "base_url": self.base_url,
            "legacy_app_label": self.legacy_app_label,
            "fastapi_app_label": self.fastapi_app_label,
            "route_mappings": [
                {
                    **mapping,
                    "legacy_routes": list(mapping["legacy_routes"]),
                }
                for mapping in self.route_mappings
            ],
            "decision_options": [dict(option) for option in self.decision_options],
            "evidence_requirements": list(self.evidence_requirements),
            "steps": [step.to_dict() for step in self.steps],
            "risk_gates": list(self.risk_gates),
            "warnings": list(self.warnings),
        }


def build_legacy_retirement_plan(
    *,
    base_url: str = DEFAULT_BASE_URL,
    legacy_app_label: str = DEFAULT_LEGACY_APP_LABEL,
    fastapi_app_label: str = DEFAULT_FASTAPI_APP_LABEL,
) -> LegacyRetirementPlan:
    base_url = base_url.rstrip("/")
    warnings = _validate_inputs(
        legacy_app_label=legacy_app_label,
        fastapi_app_label=fastapi_app_label,
    )

    steps = (
        LegacyRetirementPlanStep(
            order=1,
            title="Confirm FastAPI contract and current route set",
            command="\n".join(
                (
                    _cmd("scripts/unix/export_openapi.sh", "--in-process"),
                    _cmd("python", "-m", "apps.api.app.tools.check_flutter_client_contract"),
                )
            ),
            approval_required=False,
            notes=(
                "Read-only. Confirms /api/v1/*, /healthz, /readyz, and schema expectations before comparing legacy consumers.",
            ),
        ),
        LegacyRetirementPlanStep(
            order=2,
            title="Smoke the FastAPI edge without paid dependencies",
            command=_cmd("scripts/unix/smoke_api.sh", "--base-url", base_url),
            approval_required=False,
            notes=(
                "Requires an approved local smoke auth token or API key for /api/v1/*.",
                "Does not call live Azure OpenAI or Speech unless the paid flag is added separately.",
            ),
        ),
        LegacyRetirementPlanStep(
            order=3,
            title="Inventory legacy Flask consumers",
            command=(
                "manual: confirm current users of /api/*, /api/ios/v1/*, /api/planner/*, "
                "/map, /dashboard, /settings, and action-log routes"
            ),
            approval_required=False,
            notes=(
                "Use access logs, app configuration, Swift/Flutter route references, and dashboard owners.",
                "Do not delete or redirect Flask routes before this inventory is complete.",
            ),
        ),
        LegacyRetirementPlanStep(
            order=4,
            title="Compare payload parity for migrated mobile routes",
            command=(
                "manual: compare representative legacy Flask responses with /api/v1/* responses "
                "using sanitized fixtures and current OpenAPI schemas"
            ),
            approval_required=False,
            notes=(
                "Focus on fields used by mobile clients, not byte-for-byte legacy payload shape.",
                "Compatibility views under compat are DB handoff aids, not a reason to keep legacy HTTP routes.",
            ),
        ),
        LegacyRetirementPlanStep(
            order=5,
            title="Move mobile clients to the versioned FastAPI route family",
            command="manual: configure Flutter/iOS builds to use /api/v1/*, /healthz, and /readyz only",
            approval_required=True,
            notes=(
                "Requires release owner approval and rollback instructions.",
                "Static auth retirement remains blocked until Flutter token acquisition is complete.",
            ),
        ),
        LegacyRetirementPlanStep(
            order=6,
            title="Decide the legacy web/dashboard fate",
            command=(
                "manual: choose keep Flask as legacy admin, rebuild web/dashboard on a new frontend, "
                "or remove after usage reaches zero"
            ),
            approval_required=True,
            notes=(
                "Do not make Flask removal a prerequisite for Flutter launch.",
                "Power BI and Azure producer resources are not replaced by this decision.",
            ),
        ),
        LegacyRetirementPlanStep(
            order=7,
            title="Run deprecation window before any Flask route removal",
            command=(
                "manual: announce route deprecation, monitor access logs for an approved window, "
                "and retain rollback to the previous Flask/App Service deployment"
            ),
            approval_required=True,
            notes=(
                "The plan intentionally has no command that deletes Flask code or routes.",
            ),
        ),
    )

    return LegacyRetirementPlan(
        base_url=base_url,
        legacy_app_label=legacy_app_label,
        fastapi_app_label=fastapi_app_label,
        applies_changes=False,
        route_mappings=LEGACY_ROUTE_MAPPINGS,
        decision_options=(
            {
                "option": "keep_legacy_admin",
                "meaning": "Keep Flask only for internal/admin web surfaces while Flutter uses FastAPI.",
            },
            {
                "option": "migrate_web_frontend",
                "meaning": "Rebuild map/dashboard/settings surfaces on a separate frontend before retiring Flask.",
            },
            {
                "option": "remove_flask",
                "meaning": "Remove Flask only after mobile, web, dashboard, and action-log consumers are proven gone.",
            },
        ),
        evidence_requirements=(
            "FastAPI OpenAPI export and Flutter client contract check pass.",
            "FastAPI smoke passes for public and authenticated route families.",
            "Legacy consumer inventory identifies owners for web, iOS, dashboard, planner, and action-log routes.",
            "Mobile clients are configured to call /api/v1/* only.",
            "Live DB, AI, Speech, and worker freshness expectations are covered by readiness or approved runbooks.",
            "Rollback to the previous Flask deployment is documented before any removal.",
        ),
        steps=steps,
        risk_gates=(
            "Do not import Flask route internals into FastAPI.",
            "Do not remove Flask web/dashboard before owner and traffic inventory.",
            "Do not retire static auth until Flutter token acquisition is verified.",
            "Do not treat Windows hosting as a replacement for Azure Functions/Event Hub/Power BI.",
            "Do not delete legacy routes before a monitored deprecation window and rollback approval.",
        ),
        warnings=tuple(warnings),
    )


def _validate_inputs(*, legacy_app_label: str, fastapi_app_label: str) -> list[str]:
    warnings: list[str] = []
    if not _LABEL_RE.fullmatch(legacy_app_label):
        warnings.append("Legacy app label contains unsafe characters.")
    if not _LABEL_RE.fullmatch(fastapi_app_label):
        warnings.append("FastAPI app label contains unsafe characters.")
    return warnings


def _cmd(*parts: str) -> str:
    return shlex.join(parts)
