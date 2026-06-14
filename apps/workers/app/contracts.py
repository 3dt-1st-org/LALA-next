from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Any


class WorkerExecutionError(RuntimeError):
    """Raised when a worker job cannot be executed safely."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True)
class RetryPolicy:
    max_attempts: int
    backoff: str
    retryable_errors: tuple[str, ...]
    non_retryable_errors: tuple[str, ...] = ()

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "max_attempts": self.max_attempts,
            "backoff": self.backoff,
            "retryable_errors": list(self.retryable_errors),
            "non_retryable_errors": list(self.non_retryable_errors),
        }


@dataclass(frozen=True)
class IdempotencyPolicy:
    key: str
    conflict_strategy: str
    duplicate_window: str

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "conflict_strategy": self.conflict_strategy,
            "duplicate_window": self.duplicate_window,
        }


@dataclass(frozen=True)
class PoisonPolicy:
    threshold: int
    destination: str
    operator_action: str

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "threshold": self.threshold,
            "destination": self.destination,
            "operator_action": self.operator_action,
        }


@dataclass(frozen=True)
class WorkerJobDefinition:
    job_id: str
    description: str
    trigger: str
    writes: tuple[str, ...]
    retry_policy: RetryPolicy
    idempotency_policy: IdempotencyPolicy
    poison_policy: PoisonPolicy
    dependencies: tuple[str, ...] = ()
    source_systems: tuple[str, ...] = ()
    dry_run_payload: dict[str, Any] = field(default_factory=dict)

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "job_id": self.job_id,
            "description": self.description,
            "trigger": self.trigger,
            "writes": list(self.writes),
            "dependencies": list(self.dependencies),
            "source_systems": list(self.source_systems),
            "retry_policy": self.retry_policy.to_public_dict(),
            "idempotency_policy": self.idempotency_policy.to_public_dict(),
            "poison_policy": self.poison_policy.to_public_dict(),
        }


_JOB_DEFINITIONS: tuple[WorkerJobDefinition, ...] = (
    WorkerJobDefinition(
        job_id="weather-refresh",
        description="Refresh latest weather conditions consumed by /api/v1/weather.",
        trigger="schedule/manual",
        writes=("travel.weather_observations",),
        retry_policy=RetryPolicy(
            max_attempts=3,
            backoff="exponential: 30s, 2m, 5m",
            retryable_errors=("weather_api_timeout", "db_connection_error", "transient_5xx"),
            non_retryable_errors=("invalid_region", "schema_validation_error"),
        ),
        idempotency_policy=IdempotencyPolicy(
            key="source_system + region + observed_at",
            conflict_strategy="upsert latest observation for the same source/region/timestamp",
            duplicate_window="24h",
        ),
        poison_policy=PoisonPolicy(
            threshold=3,
            destination="ops.dependency_checks with status=failed",
            operator_action="record dependency failure and leave API on skeleton/latest-cache fallback",
        ),
        dependencies=("DB_DSN", "KEY_VAULT_URL"),
        source_systems=("legacy weather_air_func", "Azure Function candidate"),
        dry_run_payload={
            "sample_region": "suwon",
            "rows_expected": "one row per observed region and timestamp",
        },
    ),
    WorkerJobDefinition(
        job_id="community-keyword-watchlist",
        description="Build weekly local keyword summaries for planner and community insights.",
        trigger="schedule/manual",
        writes=(
            "community.ingest_runs",
            "community.ingest_tasks",
            "community.keyword_watchlist",
        ),
        retry_policy=RetryPolicy(
            max_attempts=2,
            backoff="linear: 10m",
            retryable_errors=("crawler_timeout", "rate_limited", "db_connection_error"),
            non_retryable_errors=("invalid_keyword", "invalid_region_slug"),
        ),
        idempotency_policy=IdempotencyPolicy(
            key="iso_week + keyword + region_slug",
            conflict_strategy="reuse existing crawl task and upsert weekly keyword aggregate",
            duplicate_window="7d",
        ),
        poison_policy=PoisonPolicy(
            threshold=2,
            destination="ops.job_runs with status=failed",
            operator_action="mark crawl run failed and review crawler quota or selector drift",
        ),
        dependencies=("DB_DSN", "KEY_VAULT_URL"),
        source_systems=("legacy community collector",),
        dry_run_payload={
            "sample_window": "current ISO week",
            "rows_expected": "one keyword aggregate set per region",
        },
    ),
    WorkerJobDefinition(
        job_id="community-post-ingest",
        description="Ingest community posts and place mentions from the streaming boundary.",
        trigger="queue/manual",
        writes=(
            "community.posts",
            "community.place_mentions_weekly",
        ),
        retry_policy=RetryPolicy(
            max_attempts=5,
            backoff="exponential: 10s, 30s, 1m, 2m, 5m",
            retryable_errors=("event_hub_lag", "db_connection_error", "transient_5xx"),
            non_retryable_errors=("invalid_event_schema", "unsupported_event_type"),
        ),
        idempotency_policy=IdempotencyPolicy(
            key="event_hub_partition + sequence_number or source external_key",
            conflict_strategy="ignore duplicate source event and upsert aggregate mention counters",
            duplicate_window="30d",
        ),
        poison_policy=PoisonPolicy(
            threshold=5,
            destination="future dead-letter store before any Event Hub live binding is enabled",
            operator_action="quarantine malformed event, preserve metadata, and alert worker owner",
        ),
        dependencies=("DB_DSN", "KEY_VAULT_URL", "EVENT_HUB_NAMESPACE"),
        source_systems=("Azure Event Hub", "Azure Stream Analytics"),
        dry_run_payload={
            "sample_batch": "no live queue read in Wave 1",
            "rows_expected": "posts and normalized place mention aggregates",
        },
    ),
    WorkerJobDefinition(
        job_id="ops-rollup",
        description="Roll up dependency and cost telemetry for operations handoff.",
        trigger="schedule/manual",
        writes=(
            "ops.dependency_checks",
            "ops.daily_costs",
        ),
        retry_policy=RetryPolicy(
            max_attempts=3,
            backoff="exponential: 1m, 5m, 15m",
            retryable_errors=("azure_cost_export_delay", "api_timeout", "db_connection_error"),
            non_retryable_errors=("unsupported_metric_shape",),
        ),
        idempotency_policy=IdempotencyPolicy(
            key="dependency_name + checked_at bucket or usage_date + resource_name",
            conflict_strategy="insert dependency snapshots and upsert daily cost rows",
            duplicate_window="24h",
        ),
        poison_policy=PoisonPolicy(
            threshold=3,
            destination="ops.job_runs with status=failed",
            operator_action="keep /metrics process-local and review Azure cost/readiness source manually",
        ),
        dependencies=("DB_DSN", "KEY_VAULT_URL"),
        source_systems=("API readiness", "Azure cost export candidate"),
        dry_run_payload={
            "sample_status": "degraded-safe",
            "rows_expected": "one dependency snapshot and optional daily cost row",
        },
    ),
)

_JOBS_BY_ID = {job.job_id: job for job in _JOB_DEFINITIONS}


def list_worker_jobs() -> list[dict[str, Any]]:
    return [job.to_public_dict() for job in _JOB_DEFINITIONS]


def get_worker_job(job_id: str) -> WorkerJobDefinition:
    try:
        return _JOBS_BY_ID[job_id]
    except KeyError as exc:
        known_jobs = ", ".join(sorted(_JOBS_BY_ID))
        raise WorkerExecutionError(
            "unknown_job",
            f"Unknown worker job '{job_id}'. Known jobs: {known_jobs}.",
        ) from exc


def run_worker_job(
    job_id: str,
    *,
    dry_run: bool = True,
    allow_mutation: bool | None = None,
) -> dict[str, Any]:
    job = get_worker_job(job_id)

    if dry_run:
        return {
            "ok": True,
            "mode": "dry_run",
            "job": job.to_public_dict(),
            "would_write": list(job.writes),
            "dependency_checks": [
                {
                    "name": dependency,
                    "configured": bool(os.getenv(dependency)),
                }
                for dependency in job.dependencies
            ],
            "payload": dict(job.dry_run_payload),
        }

    if allow_mutation is None:
        allow_mutation = os.getenv("ALLOW_WORKER_MUTATION") == "1"

    if not allow_mutation:
        raise WorkerExecutionError(
            "mutation_disabled",
            "Worker mutation is disabled. Use dry-run or set ALLOW_WORKER_MUTATION=1 only after live DB/queue wiring is approved.",
        )

    raise WorkerExecutionError(
        "not_implemented",
        "Live worker execution is not implemented in Wave 1. Keep Azure Functions/Event Hub producer wiring behind a later rollout decision.",
    )


def evaluate_worker_live_preflight(
    *,
    job_id: str | None = None,
    environ: dict[str, str] | None = None,
) -> dict[str, Any]:
    env = environ if environ is not None else os.environ
    jobs = (get_worker_job(job_id),) if job_id else _JOB_DEFINITIONS
    mutation_enabled = env.get("ALLOW_WORKER_MUTATION") == "1"

    job_results = [_preflight_job(job, env=env, mutation_enabled=mutation_enabled) for job in jobs]
    missing_dependencies = sorted(
        {
            check["name"]
            for result in job_results
            for check in result["dependency_checks"]
            if not check["configured"]
        }
    )

    global_checks = [
        {
            "name": "worker_contracts",
            "status": "configured",
            "message": "Worker registry, retry, idempotency, and poison policies are present.",
        },
        {
            "name": "mutation_guard",
            "status": "configured" if mutation_enabled else "blocked",
            "message": (
                "ALLOW_WORKER_MUTATION=1 is set for this process."
                if mutation_enabled
                else "ALLOW_WORKER_MUTATION is not enabled; live writes remain blocked."
            ),
        },
        {
            "name": "live_implementation",
            "status": "blocked",
            "message": "Wave 1 has no live worker implementation; dry-run contracts only.",
        },
    ]

    return {
        "ok": True,
        "mode": "live_preflight",
        "ready": False,
        "global_checks": global_checks,
        "missing_dependencies": missing_dependencies,
        "jobs": job_results,
        "risk_gates": [
            "DB_DSN and canonical schema approval",
            "queue/Event Hub binding approval for ingest jobs",
            "live retry/idempotency/poison implementation",
            "persistent worker logs, metrics, and alerts",
        ],
    }


def _preflight_job(
    job: WorkerJobDefinition,
    *,
    env: dict[str, str],
    mutation_enabled: bool,
) -> dict[str, Any]:
    dependency_checks = [
        {"name": dependency, "configured": bool(env.get(dependency))}
        for dependency in job.dependencies
    ]
    blockers = ["live_implementation_missing"]
    if not mutation_enabled:
        blockers.append("mutation_guard_disabled")
    blockers.extend(
        f"missing_dependency:{check['name']}"
        for check in dependency_checks
        if not check["configured"]
    )

    return {
        "job_id": job.job_id,
        "ready": False,
        "trigger": job.trigger,
        "would_write": list(job.writes),
        "dependency_checks": dependency_checks,
        "retry_policy": job.retry_policy.to_public_dict(),
        "idempotency_policy": job.idempotency_policy.to_public_dict(),
        "poison_policy": job.poison_policy.to_public_dict(),
        "blockers": blockers,
    }
