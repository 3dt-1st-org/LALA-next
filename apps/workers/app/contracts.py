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
class WorkerJobDefinition:
    job_id: str
    description: str
    trigger: str
    writes: tuple[str, ...]
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
        }


_JOB_DEFINITIONS: tuple[WorkerJobDefinition, ...] = (
    WorkerJobDefinition(
        job_id="weather-refresh",
        description="Refresh latest weather conditions consumed by /api/v1/weather.",
        trigger="schedule/manual",
        writes=("locallink.realtime_weather_conditions",),
        dependencies=("DB_DSN", "KEY_VAULT_URL"),
        source_systems=("legacy weather_air_func", "Azure Function candidate"),
        dry_run_payload={
            "sample_region": "suwon",
            "rows_expected": "one row per observed region and timestamp",
        },
    ),
    WorkerJobDefinition(
        job_id="daangn-weekly-keywords",
        description="Build weekly local keyword summaries for planner and community insights.",
        trigger="schedule/manual",
        writes=(
            "daangn.crawl_runs",
            "daangn.crawl_tasks",
            "daangn.weekly_keywords",
        ),
        dependencies=("DB_DSN", "KEY_VAULT_URL"),
        source_systems=("legacy daangn_weekly_crawler",),
        dry_run_payload={
            "sample_window": "current ISO week",
            "rows_expected": "one keyword aggregate set per region",
        },
    ),
    WorkerJobDefinition(
        job_id="daangn-community-ingest",
        description="Ingest community posts and place mentions from the streaming boundary.",
        trigger="queue/manual",
        writes=(
            "daangn.community_posts",
            "daangn.place_mentions_weekly",
        ),
        dependencies=("DB_DSN", "KEY_VAULT_URL", "EVENT_HUB_NAMESPACE"),
        source_systems=("Azure Event Hub", "Azure Stream Analytics"),
        dry_run_payload={
            "sample_batch": "no live queue read in Wave 1",
            "rows_expected": "posts and normalized place mention aggregates",
        },
    ),
    WorkerJobDefinition(
        job_id="monitoring-rollup",
        description="Roll up dependency and cost telemetry for operations handoff.",
        trigger="schedule/manual",
        writes=(
            "monitoring.dependency_checks",
            "monitoring.cost_daily",
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
