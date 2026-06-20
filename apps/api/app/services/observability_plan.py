from __future__ import annotations

from dataclasses import dataclass
from typing import Any

METRIC_NAMES = (
    "lala_next_process_uptime_seconds",
    "lala_next_http_requests_total",
    "lala_next_http_request_duration_ms_sum",
    "lala_next_http_request_duration_ms_max",
    "lala_next_readiness_status",
    "lala_next_dependency_ready",
    "lala_next_runtime_mode",
)

READINESS_CHECKS = (
    "client_auth",
    "client_identity",
    "jwt_validation",
    "db",
    "key_vault",
    "live_ai",
    "live_speech",
    "oauth_issuer",
    "oauth_audience",
    "oauth_jwks_url",
    "oauth_client_id",
    "oauth_required_scopes",
    "mode.overall",
    "mode.data",
    "mode.ai",
    "mode.speech",
    "mode.worker",
    "worker_contracts",
)


@dataclass(frozen=True)
class AlertRulePlan:
    name: str
    severity: str
    signal: str
    condition: str
    window: str
    runbook: str
    approval_required: bool

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "severity": self.severity,
            "signal": self.signal,
            "condition": self.condition,
            "window": self.window,
            "runbook": self.runbook,
            "approval_required": self.approval_required,
        }


@dataclass(frozen=True)
class DashboardPanelPlan:
    title: str
    source: str
    query_or_metric: str
    purpose: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "title": self.title,
            "source": self.source,
            "query_or_metric": self.query_or_metric,
            "purpose": self.purpose,
        }


@dataclass(frozen=True)
class ObservabilityPlan:
    applies_changes: bool
    scrape_endpoint: str
    metrics: tuple[str, ...]
    readiness_checks: tuple[str, ...]
    alert_rules: tuple[AlertRulePlan, ...]
    dashboard_panels: tuple[DashboardPanelPlan, ...]
    log_fields: tuple[str, ...]
    risk_gates: tuple[str, ...]

    @property
    def ok(self) -> bool:
        return True

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "mode": "plan",
            "applies_changes": self.applies_changes,
            "scrape_endpoint": self.scrape_endpoint,
            "metrics": list(self.metrics),
            "readiness_checks": list(self.readiness_checks),
            "alert_rules": [rule.to_dict() for rule in self.alert_rules],
            "dashboard_panels": [panel.to_dict() for panel in self.dashboard_panels],
            "log_fields": list(self.log_fields),
            "risk_gates": list(self.risk_gates),
        }


def build_observability_plan(*, base_url: str = "http://127.0.0.1:8080") -> ObservabilityPlan:
    base_url = base_url.rstrip("/")
    return ObservabilityPlan(
        applies_changes=False,
        scrape_endpoint=f"{base_url}/metrics",
        metrics=METRIC_NAMES,
        readiness_checks=READINESS_CHECKS,
        alert_rules=(
            AlertRulePlan(
                name="api-healthz-unreachable",
                severity="critical",
                signal=f"{base_url}/healthz",
                condition="HTTP probe fails or returns non-2xx for 2 consecutive checks",
                window="2m",
                runbook="Restart API process, verify branch/commit, then rerun smoke_api.",
                approval_required=True,
            ),
            AlertRulePlan(
                name="api-readyz-degraded",
                severity="warning",
                signal="lala_next_dependency_ready",
                condition="Any required dependency gauge remains 0 for client_auth, db, or worker_contracts",
                window="5m",
                runbook="Inspect /readyz JSON mode and checks, verify Key Vault/DB/worker registry, and treat offline snapshot fallback as a limited recovery path only.",
                approval_required=True,
            ),
            AlertRulePlan(
                name="api-5xx-rate",
                severity="critical",
                signal="lala_next_http_requests_total{status_class=\"5xx\"}",
                condition="5xx count increases in two consecutive scrape windows",
                window="5m",
                runbook="Check request_completed logs by request_id and route, then run verify_repo if reproducible.",
                approval_required=True,
            ),
            AlertRulePlan(
                name="api-latency-spike",
                severity="warning",
                signal="lala_next_http_request_duration_ms_max",
                condition="Max route latency exceeds 3000 ms outside paid live dependency smoke",
                window="10m",
                runbook="Compare affected route with /readyz dependency states; disable live AI/Speech if needed.",
                approval_required=True,
            ),
            AlertRulePlan(
                name="worker-live-preflight-unexpected-ready",
                severity="warning",
                signal="python -m apps.workers.app.cli preflight --json",
                condition="ready becomes true before a worker live rollout ticket is approved",
                window="manual or scheduled verification",
                runbook="Stop rollout, confirm DB/queue/observability approval, and review worker mutation gate.",
                approval_required=True,
            ),
        ),
        dashboard_panels=(
            DashboardPanelPlan(
                title="Readiness Overview",
                source="/metrics",
                query_or_metric="lala_next_readiness_status, lala_next_dependency_ready, and lala_next_runtime_mode",
                purpose="Show API readiness, dependency state, and unavailable/db-backed/live Azure runtime mode.",
            ),
            DashboardPanelPlan(
                title="Route Traffic",
                source="/metrics",
                query_or_metric="lala_next_http_requests_total grouped by method,path,status_class",
                purpose="Track public, authenticated, and unmatched route activity without query strings.",
            ),
            DashboardPanelPlan(
                title="Route Latency",
                source="/metrics",
                query_or_metric="lala_next_http_request_duration_ms_sum/max",
                purpose="Spot slow routes and live dependency spikes.",
            ),
            DashboardPanelPlan(
                title="Worker Rollout Gate",
                source="worker preflight JSON",
                query_or_metric="python -m apps.workers.app.cli preflight --json",
                purpose="Keep worker live mutation blocked until DB/queue/observability approvals exist.",
            ),
        ),
        log_fields=(
            "request_id",
            "method",
            "path",
            "status_code",
            "duration_ms",
            "client_host",
        ),
        risk_gates=(
            "Do not send auth headers, query strings, request bodies, or DB_DSN values to dashboards.",
            "Do not create Azure Monitor alerts until the shared backend URL and scrape path are approved.",
            "Use /metrics and /readyz as read-only sources; do not add mutation endpoints for observability.",
            "Persistent worker alerts remain blocked until live worker runtime ownership is approved.",
        ),
    )
