from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from threading import Lock
from time import monotonic

AUTH_COUNTER_NAMES = (
    "oauth_success",
    "jwt_rejection",
    "account_deletion_failure",
)


READY_STATUSES = frozenset(
    {
        "ok",
        "configured",
        "enabled",
        "static",
        "transition",
        "oauth-configured",
        "guest",
        "public-contest",
    }
)


@dataclass(frozen=True)
class RouteMetric:
    method: str
    path: str
    status_code: int
    count: int
    duration_ms_sum: float
    duration_ms_max: float

    @property
    def status_class(self) -> str:
        return f"{self.status_code // 100}xx"


class RuntimeMetrics:
    def __init__(self) -> None:
        self._started_at = monotonic()
        self._lock = Lock()
        self._routes: dict[tuple[str, str, int], dict[str, float | int]] = {}
        self._auth_counters = {name: 0 for name in AUTH_COUNTER_NAMES}

    def record_request(
        self,
        *,
        method: str,
        path: str,
        status_code: int,
        duration_ms: float,
    ) -> None:
        key = (method.upper(), path, status_code)
        with self._lock:
            current = self._routes.setdefault(
                key,
                {"count": 0, "duration_ms_sum": 0.0, "duration_ms_max": 0.0},
            )
            current["count"] = int(current["count"]) + 1
            current["duration_ms_sum"] = float(current["duration_ms_sum"]) + duration_ms
            current["duration_ms_max"] = max(float(current["duration_ms_max"]), duration_ms)

    def record_auth_event(self, name: str) -> None:
        if name not in self._auth_counters:
            raise ValueError("Unsupported auth metric name.")
        with self._lock:
            self._auth_counters[name] += 1

    def snapshot(self) -> tuple[float, tuple[RouteMetric, ...]]:
        with self._lock:
            uptime_seconds = monotonic() - self._started_at
            routes = tuple(
                RouteMetric(
                    method=method,
                    path=path,
                    status_code=status_code,
                    count=int(values["count"]),
                    duration_ms_sum=float(values["duration_ms_sum"]),
                    duration_ms_max=float(values["duration_ms_max"]),
                )
                for (method, path, status_code), values in sorted(self._routes.items())
            )
        return uptime_seconds, routes

    def auth_snapshot(self) -> dict[str, int]:
        with self._lock:
            return dict(self._auth_counters)


def render_prometheus(
    metrics: RuntimeMetrics, readiness: Mapping[str, object] | None = None
) -> str:
    uptime_seconds, routes = metrics.snapshot()
    lines = [
        "# HELP lala_next_process_uptime_seconds Process uptime in seconds.",
        "# TYPE lala_next_process_uptime_seconds gauge",
        f"lala_next_process_uptime_seconds {uptime_seconds:.3f}",
        "# HELP lala_next_http_requests_total Total HTTP requests by method, path, and status.",
        "# TYPE lala_next_http_requests_total counter",
    ]
    for route in routes:
        labels = _labels(route)
        lines.append(f"lala_next_http_requests_total{{{labels}}} {route.count}")
    lines.extend(
        [
            "# HELP lala_next_http_request_duration_ms_sum Total request duration in milliseconds.",
            "# TYPE lala_next_http_request_duration_ms_sum counter",
        ]
    )
    for route in routes:
        labels = _labels(route)
        lines.append(
            f"lala_next_http_request_duration_ms_sum{{{labels}}} {route.duration_ms_sum:.2f}"
        )
    lines.extend(
        [
            "# HELP lala_next_http_request_duration_ms_max Max observed request duration in milliseconds.",
            "# TYPE lala_next_http_request_duration_ms_max gauge",
        ]
    )
    for route in routes:
        labels = _labels(route)
        lines.append(
            f"lala_next_http_request_duration_ms_max{{{labels}}} {route.duration_ms_max:.2f}"
        )
    if readiness is not None:
        lines.extend(_readiness_lines(readiness))
    auth_counters = metrics.auth_snapshot()
    lines.extend(
        [
            "# HELP lala_next_auth_oauth_success_total Accepted OAuth JWT authentications.",
            "# TYPE lala_next_auth_oauth_success_total counter",
            f"lala_next_auth_oauth_success_total {auth_counters['oauth_success']}",
            "# HELP lala_next_auth_jwt_rejection_total Rejected presented OAuth JWTs.",
            "# TYPE lala_next_auth_jwt_rejection_total counter",
            f"lala_next_auth_jwt_rejection_total {auth_counters['jwt_rejection']}",
            "# HELP lala_next_account_deletion_failure_total Account deletion orchestration failures.",
            "# TYPE lala_next_account_deletion_failure_total counter",
            f"lala_next_account_deletion_failure_total {auth_counters['account_deletion_failure']}",
        ]
    )
    return "\n".join(lines) + "\n"


UNMATCHED_ROUTE_PATH = "__unmatched__"
STATIC_ROUTE_PATHS = frozenset(
    {
        "/docs",
        "/docs/oauth2-redirect",
        "/openapi.json",
        "/redoc",
    }
)


def route_path_from_scope(scope: dict, fallback_path: str = UNMATCHED_ROUTE_PATH) -> str:
    route = scope.get("route")
    route_path = getattr(route, "path", "")
    if route_path:
        return route_path
    raw_path = str(scope.get("path", ""))
    if raw_path in STATIC_ROUTE_PATHS:
        return raw_path
    return fallback_path


def _labels(route: RouteMetric) -> str:
    return (
        f'method="{_escape_label(route.method)}",'
        f'path="{_escape_label(route.path)}",'
        f'status_code="{route.status_code}",'
        f'status_class="{route.status_class}"'
    )


def _readiness_lines(readiness: Mapping[str, object]) -> list[str]:
    status = str(readiness.get("status", "unknown"))
    checks = readiness.get("checks", {})
    mode = readiness.get("mode", {})
    lines = [
        "# HELP lala_next_readiness_status Overall readiness status as 1 when ok.",
        "# TYPE lala_next_readiness_status gauge",
        f'lala_next_readiness_status{{status="{_escape_label(status)}"}} {_status_value(status)}',
        "# HELP lala_next_dependency_ready Dependency readiness as 1 when configured, enabled, or ok.",
        "# TYPE lala_next_dependency_ready gauge",
    ]
    if isinstance(checks, Mapping):
        for name, value in sorted(checks.items()):
            dependency_status = str(value)
            labels = (
                f'name="{_escape_label(str(name))}",status="{_escape_label(dependency_status)}"'
            )
            lines.append(
                f"lala_next_dependency_ready{{{labels}}} {_status_value(dependency_status)}"
            )
    if isinstance(mode, Mapping):
        lines.extend(
            [
                "# HELP lala_next_runtime_mode Runtime mode by component as a labeled gauge.",
                "# TYPE lala_next_runtime_mode gauge",
            ]
        )
        for component, runtime_mode in sorted(mode.items()):
            labels = (
                f'component="{_escape_label(str(component))}",'
                f'mode="{_escape_label(str(runtime_mode))}"'
            )
            lines.append(f"lala_next_runtime_mode{{{labels}}} 1")
    return lines


def _status_value(status: str) -> int:
    return 1 if status in READY_STATUSES else 0


def _escape_label(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')
