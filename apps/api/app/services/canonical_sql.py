from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[4]
CANONICAL_SQL_DIR = REPO_ROOT / "sql" / "canonical"
DEFAULT_LOCK_TIMEOUT = "5s"
DEFAULT_STATEMENT_TIMEOUT = "30s"

DESTRUCTIVE_PATTERNS = (
    re.compile(r"\bDROP\s+(TABLE|SCHEMA|VIEW|MATERIALIZED\s+VIEW|DATABASE)\b", re.IGNORECASE),
    re.compile(r"\bTRUNCATE\b", re.IGNORECASE),
    re.compile(r"\bDELETE\s+FROM\b", re.IGNORECASE),
    re.compile(r"\bALTER\s+TABLE\b.*\bDROP\s+COLUMN\b", re.IGNORECASE | re.DOTALL),
)
SECRET_PATTERNS = (
    re.compile(r"postgresql://[^\s<>]+:[^\s<>]+@", re.IGNORECASE),
    re.compile(r"\bpassword\s*=\s*[^ \t\r\n;]+", re.IGNORECASE),
    re.compile("SharedAccessKey" + "=", re.IGNORECASE),
    re.compile(r"BEGIN [A-Z ]*PRIVATE KEY"),
    re.compile(r"(?<![A-Za-z])sk-[A-Za-z0-9]{20,}"),
)


@dataclass(frozen=True)
class CanonicalSqlFile:
    path: Path
    name: str
    bytes_count: int
    statement_count: int
    sha256: str

    def read_text(self) -> str:
        return self.path.read_text(encoding="utf-8")

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "path": str(self.path.relative_to(REPO_ROOT)).replace("\\", "/"),
            "bytes": self.bytes_count,
            "statement_count": self.statement_count,
            "sha256": self.sha256,
        }


@dataclass(frozen=True)
class CanonicalSqlPlan:
    files: tuple[CanonicalSqlFile, ...]
    safety_findings: tuple[str, ...]

    @property
    def ok(self) -> bool:
        return not self.safety_findings and bool(self.files)

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "file_count": len(self.files),
            "statement_count": sum(item.statement_count for item in self.files),
            "files": [item.to_dict() for item in self.files],
            "safety_findings": list(self.safety_findings),
        }


def load_canonical_sql_plan(sql_dir: Path = CANONICAL_SQL_DIR) -> CanonicalSqlPlan:
    sql_dir = sql_dir.resolve()
    files = tuple(sorted(sql_dir.glob("*.sql")))
    planned: list[CanonicalSqlFile] = []
    findings: list[str] = []

    for path in files:
        text = path.read_text(encoding="utf-8")
        planned.append(
            CanonicalSqlFile(
                path=path,
                name=path.name,
                bytes_count=len(text.encode("utf-8")),
                statement_count=len(split_sql_statements(text)),
                sha256=hashlib.sha256(text.encode("utf-8")).hexdigest(),
            )
        )
        findings.extend(scan_sql_safety(text=text, label=path.name))

    if not planned:
        findings.append(f"No canonical SQL files found under {sql_dir}.")

    return CanonicalSqlPlan(files=tuple(planned), safety_findings=tuple(findings))


def scan_sql_safety(*, text: str, label: str) -> list[str]:
    findings: list[str] = []
    for pattern in (*DESTRUCTIVE_PATTERNS, *SECRET_PATTERNS):
        if pattern.search(text):
            findings.append(f"{label}: {pattern.pattern}")
    return findings


def split_sql_statements(text: str) -> list[str]:
    statements: list[str] = []
    current: list[str] = []
    in_single_quote = False
    in_double_quote = False
    i = 0

    while i < len(text):
        char = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""

        if not in_single_quote and not in_double_quote and char == "-" and nxt == "-":
            while i < len(text) and text[i] not in "\r\n":
                current.append(text[i])
                i += 1
            continue

        if char == "'" and not in_double_quote:
            in_single_quote = not in_single_quote
        elif char == '"' and not in_single_quote:
            in_double_quote = not in_double_quote

        if char == ";" and not in_single_quote and not in_double_quote:
            statement = "".join(current).strip()
            if statement and not _is_comment_only(statement):
                statements.append(statement)
            current = []
        else:
            current.append(char)
        i += 1

    tail = "".join(current).strip()
    if tail and not _is_comment_only(tail):
        statements.append(tail)
    return statements


def execute_canonical_sql(
    *,
    dsn: str,
    plan: CanonicalSqlPlan,
    connect_timeout: int = 5,
    lock_timeout: str = DEFAULT_LOCK_TIMEOUT,
    statement_timeout: str = DEFAULT_STATEMENT_TIMEOUT,
) -> dict[str, Any]:
    if not dsn:
        raise ValueError("DB_DSN is required.")
    if not plan.ok:
        raise ValueError("Canonical SQL plan has safety findings.")
    try:
        import psycopg2
    except Exception as exc:
        raise RuntimeError("psycopg2 is required for canonical SQL execution.") from exc

    applied: list[str] = []
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            cur.execute("SET LOCAL lock_timeout = %s", (lock_timeout,))
            cur.execute("SET LOCAL statement_timeout = %s", (statement_timeout,))
            for item in plan.files:
                cur.execute(item.read_text())
                applied.append(item.name)

    return {"ok": True, "applied_files": applied}


def _is_comment_only(statement: str) -> bool:
    meaningful_lines = [
        line.strip()
        for line in statement.splitlines()
        if line.strip() and not line.strip().startswith("--")
    ]
    return not meaningful_lines
