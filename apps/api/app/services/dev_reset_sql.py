from __future__ import annotations

import hashlib
import shlex
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from apps.api.app.services.canonical_sql import (
    DESTRUCTIVE_PATTERNS,
    DEFAULT_LOCK_TIMEOUT,
    DEFAULT_STATEMENT_TIMEOUT,
    REPO_ROOT,
    SECRET_PATTERNS,
    split_sql_statements,
)

DEV_RESET_SQL_DIR = REPO_ROOT / "sql" / "dev_reset"
LOCAL_ONLY_MARKER = "local-only dev seed/reset SQL"
LOCAL_DSN_HOSTS = {"localhost", "127.0.0.1", "::1"}


@dataclass(frozen=True)
class DevResetSqlFile:
    path: Path
    name: str
    bytes_count: int
    statement_count: int
    sha256: str
    destructive_findings: tuple[str, ...]
    safety_findings: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "path": str(self.path.relative_to(REPO_ROOT)).replace("\\", "/"),
            "bytes": self.bytes_count,
            "statement_count": self.statement_count,
            "sha256": self.sha256,
            "destructive_findings": list(self.destructive_findings),
            "safety_findings": list(self.safety_findings),
        }


@dataclass(frozen=True)
class DevResetSqlPlan:
    files: tuple[DevResetSqlFile, ...]
    safety_findings: tuple[str, ...]

    @property
    def ok(self) -> bool:
        return bool(self.files) and not self.safety_findings

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "local_only": True,
            "apply_supported": True,
            "apply_scope": "local_only_guarded",
            "apply_requires": [
                "explicit localhost DB_DSN",
                "ALLOW_DEV_RESET_APPLY=1",
                "--confirm APPLY_DEV_RESET_SQL",
            ],
            "file_count": len(self.files),
            "statement_count": sum(item.statement_count for item in self.files),
            "files": [item.to_dict() for item in self.files],
            "safety_findings": list(self.safety_findings),
        }


def load_dev_reset_sql_plan(sql_dir: Path = DEV_RESET_SQL_DIR) -> DevResetSqlPlan:
    sql_dir = sql_dir.resolve()
    planned: list[DevResetSqlFile] = []
    findings: list[str] = []

    for path in sorted(sql_dir.glob("*.sql")):
        text = path.read_text(encoding="utf-8")
        file_safety_findings = tuple(scan_dev_reset_sql_safety(text=text, label=path.name))
        destructive_findings = tuple(scan_dev_reset_sql_destructive(text=text, label=path.name))
        planned.append(
            DevResetSqlFile(
                path=path,
                name=path.name,
                bytes_count=len(text.encode("utf-8")),
                statement_count=len(split_sql_statements(text)),
                sha256=hashlib.sha256(text.encode("utf-8")).hexdigest(),
                destructive_findings=destructive_findings,
                safety_findings=file_safety_findings,
            )
        )
        findings.extend(file_safety_findings)
        if LOCAL_ONLY_MARKER not in text:
            findings.append(f"{path.name}: missing local-only marker")

    if not planned:
        findings.append(f"No dev reset SQL files found under {sql_dir}.")

    return DevResetSqlPlan(files=tuple(planned), safety_findings=tuple(findings))


def scan_dev_reset_sql_safety(*, text: str, label: str) -> list[str]:
    findings: list[str] = []
    for pattern in SECRET_PATTERNS:
        if pattern.search(text):
            findings.append(f"{label}: {pattern.pattern}")
    return findings


def scan_dev_reset_sql_destructive(*, text: str, label: str) -> list[str]:
    findings: list[str] = []
    for pattern in DESTRUCTIVE_PATTERNS:
        if pattern.search(text):
            findings.append(f"{label}: {pattern.pattern}")
    return findings


def execute_dev_reset_sql(
    *,
    dsn: str,
    plan: DevResetSqlPlan,
    connect_timeout: int = 5,
    lock_timeout: str = DEFAULT_LOCK_TIMEOUT,
    statement_timeout: str = DEFAULT_STATEMENT_TIMEOUT,
) -> dict[str, Any]:
    if not dsn:
        raise ValueError("DB_DSN is required.")
    if not plan.ok:
        raise ValueError("Dev reset SQL plan has safety findings.")

    local_host = extract_local_dsn_host(dsn)
    if not local_host:
        raise ValueError("Dev reset apply requires DB_DSN host to be localhost, 127.0.0.1, or ::1.")

    try:
        import psycopg2
    except Exception as exc:
        raise RuntimeError("psycopg2 is required for dev reset SQL execution.") from exc

    applied: list[str] = []
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            cur.execute("SET LOCAL lock_timeout = %s", (lock_timeout,))
            cur.execute("SET LOCAL statement_timeout = %s", (statement_timeout,))
            for item in plan.files:
                cur.execute(item.path.read_text(encoding="utf-8"))
                applied.append(item.name)

    return {"ok": True, "local_host": local_host, "applied_files": applied}


def extract_local_dsn_host(dsn: str) -> str:
    host = _extract_dsn_host(dsn)
    if host in LOCAL_DSN_HOSTS:
        return host
    return ""


def _extract_dsn_host(dsn: str) -> str:
    dsn = (dsn or "").strip()
    if not dsn:
        return ""

    parsed = urlparse(dsn)
    if parsed.scheme in {"postgres", "postgresql"}:
        return (parsed.hostname or "").lower()

    values: dict[str, str] = {}
    try:
        parts = shlex.split(dsn)
    except ValueError:
        return ""
    for part in parts:
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        values[key.strip().lower()] = value.strip()

    return (values.get("hostaddr") or values.get("host") or "").lower()
