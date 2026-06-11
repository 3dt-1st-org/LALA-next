from __future__ import annotations

import re
from pathlib import Path

from apps.api.app.core.key_vault import is_allowed_key_vault_url, key_vault_name_from_url

ROOT = Path(__file__).resolve().parents[3]
TEXT_SUFFIXES = {".env", ".example", ".md", ".ps1", ".py", ".sql", ".toml", ".txt"}


def test_canonical_sql_has_no_shared_destructive_statements():
    canonical_dir = ROOT / "sql" / "canonical"
    destructive_patterns = [
        re.compile(r"\bDROP\s+(TABLE|SCHEMA|VIEW|MATERIALIZED\s+VIEW|DATABASE)\b", re.IGNORECASE),
        re.compile(r"\bTRUNCATE\b", re.IGNORECASE),
        re.compile(r"\bDELETE\s+FROM\b", re.IGNORECASE),
        re.compile(r"\bALTER\s+TABLE\b.*\bDROP\s+COLUMN\b", re.IGNORECASE | re.DOTALL),
    ]
    findings: list[str] = []
    for path in canonical_dir.glob("*.sql"):
        text = path.read_text(encoding="utf-8")
        for pattern in destructive_patterns:
            if pattern.search(text):
                findings.append(f"{path}: {pattern.pattern}")

    assert findings == []


def test_canonical_sql_declares_compatibility_views():
    views_sql = (ROOT / "sql" / "canonical" / "050_views_and_indexes.sql").read_text(
        encoding="utf-8"
    )

    assert "locallink.v_legacy_places_api" in views_sql
    assert "locallink.v_legacy_docent_script_cache_api" in views_sql
    assert "locallink.v_latest_weather_api" in views_sql


def test_repo_docs_and_scripts_do_not_contain_secret_literals():
    target_roots = [
        ROOT / ".env.example",
        ROOT / "scripts",
        ROOT / "sql",
        ROOT / "docs",
        ROOT / "apps" / "api" / "app",
        ROOT / "apps" / "workers" / "app",
    ]
    patterns = [
        re.compile(r"postgresql://[^\s<>]+:[^\s<>]+@"),
        re.compile(r"^IOS_API_KEY[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile(r"^API_BEARER_TOKEN[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile(r"^POSTGRES_PASSWORD[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile(r"^AZURE_OPENAI_API_KEY[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile(r"^AZURE_OPENAI_KEY[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile(r"^AZURE_SPEECH_KEY[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile("SharedAccessKey" + "=", re.IGNORECASE),
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


def test_paid_smoke_requires_authenticated_api_key():
    script = (ROOT / "scripts" / "windows" / "smoke_api.ps1").read_text(encoding="utf-8")
    start_script = (ROOT / "scripts" / "windows" / "start_api.ps1").read_text(encoding="utf-8")
    db_schema_script = (ROOT / "scripts" / "windows" / "verify_db_schema.ps1").read_text(
        encoding="utf-8"
    )
    db_resources_script = (
        ROOT / "scripts" / "windows" / "verify_db_resources.ps1"
    ).read_text(encoding="utf-8")
    apply_sql_script = (ROOT / "scripts" / "windows" / "apply_canonical_sql.ps1").read_text(
        encoding="utf-8"
    )
    worker_smoke_script = (
        ROOT / "scripts" / "windows" / "smoke_workers.ps1"
    ).read_text(encoding="utf-8")
    worker_contracts = (
        ROOT / "apps" / "workers" / "app" / "contracts.py"
    ).read_text(encoding="utf-8")
    apply_sql_tool = (
        ROOT / "apps" / "api" / "app" / "tools" / "apply_canonical_sql.py"
    ).read_text(encoding="utf-8")

    assert "[string]$KeyVaultUrl" in script
    assert "[string]$KeyVaultUrl" in start_script
    assert "lala-next-kv-27db5e.vault.azure.net" in script
    assert "lala-next-kv-27db5e.vault.azure.net" in start_script
    assert "if ($PaidDependency)" in script
    assert "Client auth is required for paid dependency smoke" in script
    assert "--no-access-log" in start_script
    assert "DB_DSN value is never printed by this script." in db_schema_script
    assert "Write-Host $env:DB_DSN" not in db_schema_script
    assert "$toolArgs" in db_schema_script
    assert "Secret values are never printed by this script." in db_resources_script
    assert "secret show" not in db_resources_script
    assert "db-dsn" in db_resources_script
    assert "Default mode is dry-run plan only." in apply_sql_script
    assert "Write-Host $env:DB_DSN" not in apply_sql_script
    assert "-m apps.workers.app.cli" in worker_smoke_script
    assert "--dry-run" in worker_smoke_script
    assert "Write-Host $env:DB_DSN" not in worker_smoke_script
    assert "ALLOW_WORKER_MUTATION" in worker_contracts
    assert "ALLOW_CANONICAL_SQL_APPLY" in apply_sql_tool
    assert "APPLY_CANONICAL_SQL" in apply_sql_tool


def test_key_vault_url_is_lala_next_only():
    assert is_allowed_key_vault_url("https://lala-next-kv-27db5e.vault.azure.net/")
    assert not is_allowed_key_vault_url("https://onmu-dev-kv-27db5e.vault.azure.net/")
    assert not is_allowed_key_vault_url("http://lala-next-kv-27db5e.vault.azure.net/")
    assert key_vault_name_from_url("https://lala-next-kv-27db5e.vault.azure.net/") == "lala-next-kv-27db5e"
    assert key_vault_name_from_url("https://onmu-dev-kv-27db5e.vault.azure.net/") == ""
