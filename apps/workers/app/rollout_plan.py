from __future__ import annotations

import re
import shlex
from dataclasses import dataclass
from typing import Any

from apps.workers.app.contracts import list_worker_jobs

DEFAULT_SUBSCRIPTION_ID = "00000000-0000-0000-0000-000000000000"
DEFAULT_RESOURCE_GROUP = "lala-resource-group"
DEFAULT_LOCATION = "koreacentral"
DEFAULT_KEY_VAULT_NAME = "lala-key-vault"
DEFAULT_FUNCTION_APP_NAME = "lala-next-workers-dev"
DEFAULT_STORAGE_ACCOUNT_NAME = "lalaworkersdev"
DEFAULT_EVENT_HUB_NAMESPACE = "lala-eventhub-dev"
DEFAULT_EVENT_HUB_NAME = "community-post-ingest-events"
DEFAULT_BASE_URL = "http://127.0.0.1:8080"

WORKER_KEY_VAULT_SECRET_NAMES = (
    "db-dsn",
    "worker-storage-account",
    "worker-poison-store",
    "event-hub-namespace",
    "event-hub-name",
)

_AZURE_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_. -]{1,118}[A-Za-z0-9]$")
_DASH_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{1,58}[A-Za-z0-9]$")
_STORAGE_ACCOUNT_RE = re.compile(r"^[a-z0-9]{3,24}$")


@dataclass(frozen=True)
class WorkerRolloutPlanStep:
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
class WorkerRolloutPlan:
    subscription_id: str
    resource_group: str
    location: str
    key_vault_name: str
    function_app_name: str
    storage_account_name: str
    event_hub_namespace: str
    event_hub_name: str
    base_url: str
    applies_changes: bool
    worker_jobs: tuple[dict[str, Any], ...]
    key_vault_secret_names: tuple[str, ...]
    readiness_checks: tuple[str, ...]
    steps: tuple[WorkerRolloutPlanStep, ...]
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
            "subscription_id": self.subscription_id,
            "resource_group": self.resource_group,
            "location": self.location,
            "key_vault_name": self.key_vault_name,
            "function_app_name": self.function_app_name,
            "storage_account_name": self.storage_account_name,
            "event_hub_namespace": self.event_hub_namespace,
            "event_hub_name": self.event_hub_name,
            "base_url": self.base_url,
            "worker_jobs": list(self.worker_jobs),
            "key_vault_secret_names": list(self.key_vault_secret_names),
            "readiness_checks": list(self.readiness_checks),
            "steps": [step.to_dict() for step in self.steps],
            "risk_gates": list(self.risk_gates),
            "warnings": list(self.warnings),
        }


def build_worker_rollout_plan(
    *,
    subscription_id: str = DEFAULT_SUBSCRIPTION_ID,
    resource_group: str = DEFAULT_RESOURCE_GROUP,
    location: str = DEFAULT_LOCATION,
    key_vault_name: str = DEFAULT_KEY_VAULT_NAME,
    function_app_name: str = DEFAULT_FUNCTION_APP_NAME,
    storage_account_name: str = DEFAULT_STORAGE_ACCOUNT_NAME,
    event_hub_namespace: str = DEFAULT_EVENT_HUB_NAMESPACE,
    event_hub_name: str = DEFAULT_EVENT_HUB_NAME,
    base_url: str = DEFAULT_BASE_URL,
) -> WorkerRolloutPlan:
    base_url = base_url.rstrip("/")
    warnings = _validate_inputs(
        key_vault_name=key_vault_name,
        function_app_name=function_app_name,
        storage_account_name=storage_account_name,
        event_hub_namespace=event_hub_namespace,
        event_hub_name=event_hub_name,
        resource_group=resource_group,
    )
    command_key_vault_name = (
        key_vault_name
        if key_vault_name == DEFAULT_KEY_VAULT_NAME and "onmu" not in key_vault_name.lower()
        else DEFAULT_KEY_VAULT_NAME
    )
    jobs = tuple(_job_summary(job) for job in list_worker_jobs())

    steps = (
        WorkerRolloutPlanStep(
            order=1,
            title="Confirm dry-run worker contracts and blocked live preflight",
            command=_cmd("python", "-m", "apps.workers.app.cli", "preflight", "--json"),
            approval_required=False,
            notes=(
                "Read-only. This must remain ready=false until DB, queue, runtime, and observability gates are approved.",
            ),
        ),
        WorkerRolloutPlanStep(
            order=2,
            title="Confirm DB and canonical schema readiness",
            command=_cmd(
                "scripts/unix/verify_db_resources.sh",
                "--subscription-id",
                subscription_id,
                "--resource-group",
                resource_group,
                "--key-vault-name",
                command_key_vault_name,
                "--require-database",
            ),
            approval_required=False,
            notes=(
                "Read-only. Worker mutation stays blocked until the approved LALA DB and canonical schema pass verification.",
            ),
        ),
        WorkerRolloutPlanStep(
            order=3,
            title="Create approved worker storage account",
            command=_cmd(
                "az",
                "storage",
                "account",
                "create",
                "--subscription",
                subscription_id,
                "--resource-group",
                resource_group,
                "--location",
                location,
                "--name",
                storage_account_name,
                "--sku",
                "Standard_LRS",
                "--kind",
                "StorageV2",
                "--allow-blob-public-access",
                "false",
                "--tags",
                "app=lala-next",
                "component=workers",
                "environment=dev",
            ),
            approval_required=True,
            notes=(
                "Create only after the worker runtime owner approves the queue and poison-message topology.",
                "Prefer managed identity over copied connection strings for runtime access.",
            ),
        ),
        WorkerRolloutPlanStep(
            order=4,
            title="Create approved Event Hub namespace for ingest jobs",
            command=_cmd(
                "az",
                "eventhubs",
                "namespace",
                "create",
                "--subscription",
                subscription_id,
                "--resource-group",
                resource_group,
                "--location",
                location,
                "--name",
                event_hub_namespace,
                "--sku",
                "Basic",
                "--tags",
                "app=lala-next",
                "component=workers",
                "environment=dev",
            ),
            approval_required=True,
            notes=(
                "Required only for queue/stream ingest jobs such as community-post-ingest.",
                "Do not bind the API process directly to Event Hub.",
            ),
        ),
        WorkerRolloutPlanStep(
            order=5,
            title="Create approved Event Hub for community ingest",
            command=_cmd(
                "az",
                "eventhubs",
                "eventhub",
                "create",
                "--subscription",
                subscription_id,
                "--resource-group",
                resource_group,
                "--namespace-name",
                event_hub_namespace,
                "--name",
                event_hub_name,
                "--partition-count",
                "2",
                "--message-retention",
                "1",
            ),
            approval_required=True,
            notes=(
                "Partition and retention settings are dev defaults; production sizing needs separate approval.",
            ),
        ),
        WorkerRolloutPlanStep(
            order=6,
            title="Create approved worker Function App after runtime decision",
            command=_cmd(
                "az",
                "functionapp",
                "create",
                "--subscription",
                subscription_id,
                "--resource-group",
                resource_group,
                "--consumption-plan-location",
                location,
                "--runtime",
                "python",
                "--runtime-version",
                "3.11",
                "--functions-version",
                "4",
                "--name",
                function_app_name,
                "--storage-account",
                storage_account_name,
                "--os-type",
                "Linux",
                "--tags",
                "app=lala-next",
                "component=workers",
                "environment=dev",
            ),
            approval_required=True,
            notes=(
                "This is a candidate Azure Functions lane; Windows scheduled tasks remain a separate explicit decision.",
                "Live worker entrypoints are still absent in Wave 1.",
            ),
        ),
        WorkerRolloutPlanStep(
            order=7,
            title="Register worker runtime names in the LALA-next Key Vault",
            command="\n".join(
                (
                    _cmd(
                        "az",
                        "keyvault",
                        "secret",
                        "set",
                        "--vault-name",
                        command_key_vault_name,
                        "--name",
                        "worker-storage-account",
                        "--value",
                        storage_account_name,
                    ),
                    _cmd(
                        "az",
                        "keyvault",
                        "secret",
                        "set",
                        "--vault-name",
                        command_key_vault_name,
                        "--name",
                        "event-hub-namespace",
                        "--value",
                        event_hub_namespace,
                    ),
                    _cmd(
                        "az",
                        "keyvault",
                        "secret",
                        "set",
                        "--vault-name",
                        command_key_vault_name,
                        "--name",
                        "event-hub-name",
                        "--value",
                        event_hub_name,
                    ),
                )
            ),
            approval_required=True,
            notes=(
                "Stores approved runtime names only. Do not store copied queue or Event Hub connection strings unless managed identity is rejected.",
                "Use the LALA-next vault, never the ONMU vault.",
            ),
        ),
        WorkerRolloutPlanStep(
            order=8,
            title="Smoke dry-run workers and API readiness before any canary",
            command="\n".join(
                (
                    _cmd("scripts/unix/smoke_workers.sh"),
                    _cmd("scripts/unix/smoke_api.sh", "--base-url", base_url),
                )
            ),
            approval_required=False,
            notes=(
                "Read-only. Confirms worker contracts, ready=false live preflight, and API runtime-mode reporting.",
            ),
        ),
        WorkerRolloutPlanStep(
            order=9,
            title="Deploy a shadow worker canary with mutation still disabled",
            command=(
                "manual: deploy one approved worker job in shadow mode, keep live mutation disabled, "
                "compare dependency logs and retry/idempotency decisions against the dry-run contract"
            ),
            approval_required=True,
            notes=(
                "Shadow mode must not write PostgreSQL, queues, or poison stores.",
                "Stop here if logs, metrics, or rollback ownership are unclear.",
            ),
        ),
        WorkerRolloutPlanStep(
            order=10,
            title="Approve one live worker job and rollback path",
            command=(
                "manual: enable live writes for one approved job only after DB, queue, idempotency, "
                "poison handling, alerts, and rollback owner are all confirmed"
            ),
            approval_required=True,
            notes=(
                "Do not enable the global mutation guard for every job at once.",
                "Canary weather-refresh before queue ingest because it has the smallest write surface.",
            ),
        ),
    )

    return WorkerRolloutPlan(
        subscription_id=subscription_id,
        resource_group=resource_group,
        location=location,
        key_vault_name=key_vault_name,
        function_app_name=function_app_name,
        storage_account_name=storage_account_name,
        event_hub_namespace=event_hub_namespace,
        event_hub_name=event_hub_name,
        base_url=base_url,
        applies_changes=False,
        worker_jobs=jobs,
        key_vault_secret_names=WORKER_KEY_VAULT_SECRET_NAMES,
        readiness_checks=(
            "python -m apps.workers.app.cli preflight --json",
            "scripts/unix/smoke_workers.sh",
            "scripts/unix/verify_db_resources.sh --require-database",
            "/readyz.data.checks.worker_contracts",
            '/metrics lala_dependency_ready{dependency="worker_contracts"}',
        ),
        steps=steps,
        risk_gates=(
            "Approved DB_DSN and canonical schema verification",
            "Queue/Event Hub topology and poison-message destination approval",
            "Idempotency keys and conflict strategy implemented per write target",
            "Persistent worker logs, metrics, alerts, and owner routing",
            "One-job canary and rollback owner approval before mutation",
            "LALA-next Key Vault only; ONMU vault remains out of runtime scope",
        ),
        warnings=tuple(warnings),
    )


def _job_summary(job: dict[str, Any]) -> dict[str, Any]:
    return {
        "job_id": job["job_id"],
        "trigger": job["trigger"],
        "writes": list(job["writes"]),
        "dependencies": list(job["dependencies"]),
        "source_systems": list(job["source_systems"]),
        "rollout_phase": "dry_run_contract_only",
    }


def _validate_inputs(
    *,
    key_vault_name: str,
    function_app_name: str,
    storage_account_name: str,
    event_hub_namespace: str,
    event_hub_name: str,
    resource_group: str,
) -> list[str]:
    warnings: list[str] = []

    if key_vault_name != DEFAULT_KEY_VAULT_NAME:
        warnings.append(
            "Key Vault target must remain lala-key-vault unless the owner approves a LALA-next vault migration."
        )
    if "onmu" in key_vault_name.lower():
        warnings.append("ONMU Key Vault values are not worker runtime inputs for LALA-next.")
    if not _DASH_NAME_RE.fullmatch(key_vault_name):
        warnings.append("Key Vault name is not Azure-name safe.")
    if not _DASH_NAME_RE.fullmatch(function_app_name):
        warnings.append("Function App name is not Azure-name safe.")
    if not _STORAGE_ACCOUNT_RE.fullmatch(storage_account_name):
        warnings.append("Storage account name must be 3-24 lowercase letters or numbers.")
    if not _DASH_NAME_RE.fullmatch(event_hub_namespace):
        warnings.append("Event Hub namespace is not Azure-name safe.")
    if not _DASH_NAME_RE.fullmatch(event_hub_name):
        warnings.append("Event Hub name is not Azure-name safe.")
    if not _AZURE_NAME_RE.fullmatch(resource_group):
        warnings.append("Resource group name is not Azure-name safe.")

    return warnings


def _cmd(*parts: str) -> str:
    return shlex.join(parts)
