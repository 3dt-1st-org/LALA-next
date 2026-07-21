from __future__ import annotations

import re
import shlex
from dataclasses import dataclass
from typing import Any

from apps.api.app.services.canonical_sql import CanonicalSqlPlan, load_canonical_sql_plan

DEFAULT_SUBSCRIPTION_ID = "00000000-0000-0000-0000-000000000000"
DEFAULT_RESOURCE_GROUP = "lala-resource-group"
DEFAULT_LOCATION = "koreacentral"
DEFAULT_KEY_VAULT_NAME = "lala-key-vault"
DEFAULT_POSTGRES_SERVER_NAME = "lala-postgres-server"
DEFAULT_DATABASE_NAME = "lala"
DEFAULT_ADMIN_USER = "lalaadmin"
DEFAULT_POSTGRES_VERSION = "16"
DEFAULT_SKU_NAME = "Standard_B1ms"
DEFAULT_TIER = "Burstable"
DEFAULT_STORAGE_SIZE_GB = 32
DEFAULT_PUBLIC_ACCESS = "None"
REQUIRED_EXTENSIONS = ("POSTGIS", "VECTOR", "PGCRYPTO")
KEY_VAULT_URL_PLACEHOLDER = "<KEY_VAULT_URL>"

_SERVER_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$")
_SIMPLE_NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,63}$")


@dataclass(frozen=True)
class DbRolloutPlanStep:
    order: int
    title: str
    command: str
    approval_required: bool
    secret_sensitive: bool = False
    notes: tuple[str, ...] = ()

    def to_dict(self) -> dict[str, Any]:
        return {
            "order": self.order,
            "title": self.title,
            "command": self.command,
            "approval_required": self.approval_required,
            "secret_sensitive": self.secret_sensitive,
            "notes": list(self.notes),
        }


@dataclass(frozen=True)
class DbRolloutPlan:
    subscription_id: str
    resource_group: str
    location: str
    key_vault_name: str
    postgres_server_name: str
    database_name: str
    admin_user: str
    network_access: str
    steps: tuple[DbRolloutPlanStep, ...]
    canonical_sql: dict[str, Any]
    risk_gates: tuple[str, ...]
    warnings: tuple[str, ...]

    @property
    def ok(self) -> bool:
        return not self.warnings

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "mode": "plan",
            "applies_changes": False,
            "subscription_id": self.subscription_id,
            "resource_group": self.resource_group,
            "location": self.location,
            "key_vault_name": self.key_vault_name,
            "postgres_server_name": self.postgres_server_name,
            "database_name": self.database_name,
            "admin_user": self.admin_user,
            "network_access": self.network_access,
            "steps": [step.to_dict() for step in self.steps],
            "canonical_sql": self.canonical_sql,
            "risk_gates": list(self.risk_gates),
            "warnings": list(self.warnings),
        }


def build_db_rollout_plan(
    *,
    subscription_id: str = DEFAULT_SUBSCRIPTION_ID,
    resource_group: str = DEFAULT_RESOURCE_GROUP,
    location: str = DEFAULT_LOCATION,
    key_vault_name: str = DEFAULT_KEY_VAULT_NAME,
    postgres_server_name: str = DEFAULT_POSTGRES_SERVER_NAME,
    database_name: str = DEFAULT_DATABASE_NAME,
    admin_user: str = DEFAULT_ADMIN_USER,
    postgres_version: str = DEFAULT_POSTGRES_VERSION,
    sku_name: str = DEFAULT_SKU_NAME,
    tier: str = DEFAULT_TIER,
    storage_size_gb: int = DEFAULT_STORAGE_SIZE_GB,
    public_access: str = DEFAULT_PUBLIC_ACCESS,
    canonical_plan: CanonicalSqlPlan | None = None,
) -> DbRolloutPlan:
    canonical_plan = canonical_plan or load_canonical_sql_plan()
    warnings = _validate_inputs(
        postgres_server_name=postgres_server_name,
        database_name=database_name,
        admin_user=admin_user,
        storage_size_gb=storage_size_gb,
    )

    canonical_summary = {
        "ok": canonical_plan.ok,
        "file_count": len(canonical_plan.files),
        "statement_count": sum(item.statement_count for item in canonical_plan.files),
        "files": [
            {
                "path": item.to_dict()["path"],
                "sha256": item.sha256,
                "statement_count": item.statement_count,
            }
            for item in canonical_plan.files
        ],
        "safety_findings": list(canonical_plan.safety_findings),
    }
    if not canonical_plan.ok:
        warnings.append("Canonical SQL plan has safety findings; do not provision/apply yet.")

    steps = (
        DbRolloutPlanStep(
            order=1,
            title="Verify current Azure and DB readiness state",
            command=_cmd(
                "scripts/unix/verify_db_resources.sh",
                "--subscription-id",
                subscription_id,
                "--resource-group",
                resource_group,
                "--key-vault-name",
                key_vault_name,
            ),
            approval_required=False,
            notes=("Read-only. Confirms whether db-dsn/server/database already exist.",),
        ),
        DbRolloutPlanStep(
            order=2,
            title="Create approved PostgreSQL Flexible Server",
            command=(
                _cmd(
                    "az",
                    "postgres",
                    "flexible-server",
                    "create",
                    "--subscription",
                    subscription_id,
                    "--resource-group",
                    resource_group,
                    "--location",
                    location,
                    "--name",
                    postgres_server_name,
                    "--admin-user",
                    admin_user,
                    "--admin-password",
                )
                + ' "$POSTGRES_ADMIN_PASSWORD" '
                + _cmd(
                    "--version",
                    postgres_version,
                    "--sku-name",
                    sku_name,
                    "--tier",
                    tier,
                    "--storage-size",
                    str(storage_size_gb),
                    "--public-access",
                    public_access,
                    "--tags",
                    "app=lala-next",
                    "environment=dev",
                    "managed-by=manual-rollout",
                )
            ),
            approval_required=True,
            secret_sensitive=True,
            notes=(
                "Set POSTGRES_ADMIN_PASSWORD only in the shell or a password manager; do not commit it.",
                "public-access=None creates no broad firewall rule; approve networking separately.",
            ),
        ),
        DbRolloutPlanStep(
            order=3,
            title="Create application database",
            command=_cmd(
                "az",
                "postgres",
                "flexible-server",
                "db",
                "create",
                "--subscription",
                subscription_id,
                "--resource-group",
                resource_group,
                "--server-name",
                postgres_server_name,
                "--database-name",
                database_name,
            ),
            approval_required=True,
            notes=("Uses the currently installed Azure CLI db create shape.",),
        ),
        DbRolloutPlanStep(
            order=4,
            title="Allow required PostgreSQL extensions",
            command=_cmd(
                "az",
                "postgres",
                "flexible-server",
                "parameter",
                "set",
                "--subscription",
                subscription_id,
                "--resource-group",
                resource_group,
                "--server-name",
                postgres_server_name,
                "--name",
                "azure.extensions",
                "--value",
                ",".join(REQUIRED_EXTENSIONS),
            ),
            approval_required=True,
            notes=("Restart the server only if Azure reports a pending restart.",),
        ),
        DbRolloutPlanStep(
            order=5,
            title="Register db-dsn in LALA-next Key Vault",
            command=_cmd(
                "az",
                "keyvault",
                "secret",
                "set",
                "--subscription",
                subscription_id,
                "--vault-name",
                key_vault_name,
                "--name",
                "db-dsn",
                "--value",
                "<redacted-postgresql-dsn>",
            ),
            approval_required=True,
            secret_sensitive=True,
            notes=(
                "Use SSL-required PostgreSQL DSN. Do not paste the secret value into chat or docs.",
            ),
        ),
        DbRolloutPlanStep(
            order=6,
            title="Run strict Azure DB readiness verification",
            command=_cmd(
                "scripts/unix/verify_db_resources.sh",
                "--subscription-id",
                subscription_id,
                "--resource-group",
                resource_group,
                "--key-vault-name",
                key_vault_name,
                "--postgres-server-name",
                postgres_server_name,
                "--database-name",
                database_name,
                "--require-database",
            ),
            approval_required=False,
            notes=("Read-only. Must pass before canonical SQL apply.",),
        ),
        DbRolloutPlanStep(
            order=7,
            title="Review and apply canonical SQL",
            command=(
                "ALLOW_CANONICAL_SQL_APPLY=1 "
                + _cmd(
                    "scripts/unix/apply_canonical_sql.sh",
                    "--apply",
                    "--confirm",
                    "APPLY_CANONICAL_SQL",
                    "--key-vault-url",
                    KEY_VAULT_URL_PLACEHOLDER,
                )
            ),
            approval_required=True,
            notes=(
                "Runs sql/canonical/*.sql in sorted order inside one transaction.",
                "Resolve <KEY_VAULT_URL> from a private runbook or environment variable, not tracked docs.",
            ),
        ),
        DbRolloutPlanStep(
            order=8,
            title="Verify canonical schema",
            command=_cmd(
                "scripts/unix/verify_db_schema.sh",
                "--key-vault-url",
                KEY_VAULT_URL_PLACEHOLDER,
            ),
            approval_required=False,
            notes=("Read-only. Confirms required extensions, schemas, tables, and views.",),
        ),
        DbRolloutPlanStep(
            order=9,
            title="Start and smoke DB-backed API",
            command=(
                _cmd(
                    "scripts/unix/start_api.sh",
                    "--port",
                    "8080",
                    "--key-vault-url",
                    KEY_VAULT_URL_PLACEHOLDER,
                )
                + "\n"
                + _cmd(
                    "scripts/unix/smoke_api.sh",
                    "--base-url",
                    "http://127.0.0.1:8080",
                    "--key-vault-url",
                    KEY_VAULT_URL_PLACEHOLDER,
                )
            ),
            approval_required=False,
            notes=("Smoke verifies public and authenticated API routes without printing secrets.",),
        ),
    )

    return DbRolloutPlan(
        subscription_id=subscription_id,
        resource_group=resource_group,
        location=location,
        key_vault_name=key_vault_name,
        postgres_server_name=postgres_server_name,
        database_name=database_name,
        admin_user=admin_user,
        network_access=f"public-access={public_access}; firewall/private access approval remains separate",
        steps=steps,
        canonical_sql=canonical_summary,
        risk_gates=(
            "No Azure PostgreSQL create command should be run without explicit operator approval.",
            "Do not put POSTGRES_ADMIN_PASSWORD, DB_DSN, or connection strings in Markdown, git, or chat.",
            "Key Vault db-dsn must belong to the LALA-next vault, not ONMU.",
            "Canonical SQL apply still requires ALLOW_CANONICAL_SQL_APPLY=1 and exact confirmation.",
            "Worker live mutation remains blocked after DB rollout until queue/runtime observability is approved.",
        ),
        warnings=tuple(warnings),
    )


def _cmd(*parts: str) -> str:
    return " ".join(shlex.quote(part) for part in parts)


def _validate_inputs(
    *,
    postgres_server_name: str,
    database_name: str,
    admin_user: str,
    storage_size_gb: int,
) -> list[str]:
    warnings: list[str] = []
    if not _SERVER_NAME_RE.fullmatch(postgres_server_name):
        warnings.append(
            "PostgreSQL server name must be 3-63 lowercase letters, numbers, and hyphens."
        )
    if not _SIMPLE_NAME_RE.fullmatch(database_name):
        warnings.append("Database name must contain only letters, numbers, underscore, or hyphen.")
    if not _SIMPLE_NAME_RE.fullmatch(admin_user):
        warnings.append("Admin user must contain only letters, numbers, underscore, or hyphen.")
    if storage_size_gb < 32:
        warnings.append("PostgreSQL storage size must be at least 32 GiB.")
    return warnings
