from __future__ import annotations

from dataclasses import dataclass
from threading import Lock
from time import monotonic


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


def render_prometheus(metrics: RuntimeMetrics) -> str:
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
            f"lala_next_http_request_duration_ms_sum{{{labels}}} "
            f"{route.duration_ms_sum:.2f}"
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
            f"lala_next_http_request_duration_ms_max{{{labels}}} "
            f"{route.duration_ms_max:.2f}"
        )
    return "\n".join(lines) + "\n"


UNMATCHED_ROUTE_PATH = "__unmatched__"


def route_path_from_scope(scope: dict, fallback_path: str = UNMATCHED_ROUTE_PATH) -> str:
    route = scope.get("route")
    route_path = getattr(route, "path", "")
    return route_path or fallback_path


def _labels(route: RouteMetric) -> str:
    return (
        f'method="{_escape_label(route.method)}",'
        f'path="{_escape_label(route.path)}",'
        f'status_code="{route.status_code}",'
        f'status_class="{route.status_class}"'
    )


def _escape_label(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')
