from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TEXT_SUFFIXES = {".env", ".example", ".md", ".ps1", ".py", ".sql", ".toml", ".txt"}


def test_canonical_sql_has_no_shared_destructive_drop_table():
    canonical_dir = ROOT / "sql" / "canonical"
    findings: list[str] = []
    for path in canonical_dir.glob("*.sql"):
        text = path.read_text(encoding="utf-8")
        if re.search(r"\bDROP\s+TABLE\b", text, flags=re.IGNORECASE):
            findings.append(str(path))

    assert findings == []


def test_repo_docs_and_scripts_do_not_contain_secret_literals():
    target_roots = [
        ROOT / ".env.example",
        ROOT / "scripts",
        ROOT / "sql",
        ROOT / "docs",
        ROOT / "apps" / "api" / "app",
    ]
    patterns = [
        re.compile(r"postgresql://[^\s<>]+:[^\s<>]+@"),
        re.compile(r"POSTGRES_PASSWORD\s*=\s*.+"),
        re.compile(r"AZURE_OPENAI_API_KEY\s*=\s*.+"),
        re.compile(r"SharedAccessKey=", re.IGNORECASE),
        re.compile(r"BEGIN [A-Z ]*PRIVATE KEY"),
        re.compile(r"(?<![A-Za-z])sk-[A-Za-z0-9]{20,}"),
    ]
    findings: list[str] = []
    for root in target_roots:
        paths = [root] if root.is_file() else [p for p in root.rglob("*") if p.is_file()]
        for path in paths:
            if "__pycache__" in path.parts:
                continue
            if path.suffix and path.suffix.lower() not in TEXT_SUFFIXES:
                continue
            text = path.read_text(encoding="utf-8")
            for pattern in patterns:
                if pattern.search(text):
                    findings.append(f"{path}: {pattern.pattern}")

    assert findings == []
