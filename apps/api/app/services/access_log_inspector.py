from __future__ import annotations

import json
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ACCESS_LOG_FIELDS = (
    "request_id",
    "method",
    "path",
    "status_code",
    "duration_ms",
    "client_host",
)


@dataclass(frozen=True)
class AccessLogRecord:
    request_id: str
    method: str
    path: str
    status_code: int
    duration_ms: float
    client_host: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "request_id": self.request_id,
            "method": self.method,
            "path": self.path,
            "status_code": self.status_code,
            "duration_ms": self.duration_ms,
            "client_host": self.client_host,
        }


@dataclass(frozen=True)
class AccessLogInspection:
    path: str
    exists: bool
    total_lines: int
    invalid_lines: int
    matched_count: int
    records: tuple[AccessLogRecord, ...]
    warnings: tuple[str, ...] = ()

    @property
    def ok(self) -> bool:
        return self.exists and not self.warnings

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "mode": "read-only",
            "applies_changes": False,
            "path": self.path,
            "exists": self.exists,
            "total_lines": self.total_lines,
            "invalid_lines": self.invalid_lines,
            "matched_count": self.matched_count,
            "records": [record.to_dict() for record in self.records],
            "warnings": list(self.warnings),
            "fields": list(ACCESS_LOG_FIELDS),
        }


def inspect_access_log(
    path: str,
    *,
    request_id: str = "",
    route_path: str = "",
    limit: int = 20,
) -> AccessLogInspection:
    log_path = Path(path)
    warnings: list[str] = []
    if not log_path.exists():
        return AccessLogInspection(
            path=str(log_path),
            exists=False,
            total_lines=0,
            invalid_lines=0,
            matched_count=0,
            records=(),
            warnings=(f"Access log does not exist: {log_path}",),
        )
    if not log_path.is_file():
        return AccessLogInspection(
            path=str(log_path),
            exists=True,
            total_lines=0,
            invalid_lines=0,
            matched_count=0,
            records=(),
            warnings=(f"Access log path is not a file: {log_path}",),
        )

    safe_limit = max(1, min(limit, 200))
    matches: deque[AccessLogRecord] = deque(maxlen=safe_limit)
    total_lines = 0
    invalid_lines = 0
    matched_count = 0
    request_id = request_id.strip()
    route_path = route_path.strip()

    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            total_lines += 1
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                invalid_lines += 1
                continue
            if not isinstance(payload, dict):
                invalid_lines += 1
                continue
            record = _record_from_payload(payload)
            if request_id and record.request_id != request_id:
                continue
            if route_path and record.path != route_path:
                continue
            matched_count += 1
            matches.append(record)

    return AccessLogInspection(
        path=str(log_path),
        exists=True,
        total_lines=total_lines,
        invalid_lines=invalid_lines,
        matched_count=matched_count,
        records=tuple(matches),
        warnings=tuple(warnings),
    )


def _record_from_payload(payload: dict[str, Any]) -> AccessLogRecord:
    return AccessLogRecord(
        request_id=_as_string(payload.get("request_id")),
        method=_as_string(payload.get("method")),
        path=_as_string(payload.get("path")),
        status_code=_as_int(payload.get("status_code")),
        duration_ms=_as_float(payload.get("duration_ms")),
        client_host=_as_string(payload.get("client_host")),
    )


def _as_string(value: Any) -> str:
    return str(value).strip() if value is not None else ""


def _as_int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _as_float(value: Any) -> float:
    try:
        return round(float(value), 3)
    except (TypeError, ValueError):
        return 0.0
