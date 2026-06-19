# Worker and Batch Boundary

Wave 1 keeps the public FastAPI edge separate from producer and batch work.
The worker package is intentionally executable as dry-run only so the team can
agree on job ownership, write targets, and future Azure wiring before anything
mutates shared PostgreSQL or streaming resources.

## Current Boundary

| Job id | Trigger | Future source | Intended writes |
|---|---|---|---|
| `weather-refresh` | schedule/manual | legacy weather collector, Azure Function candidate | `travel.weather_observations` |
| `community-keyword-watchlist` | schedule/manual | community keyword source | `community.ingest_runs`, `community.ingest_tasks`, `community.keyword_watchlist` |
| `community-post-ingest` | queue/manual | Azure Event Hub, Azure Stream Analytics | `community.posts`, `community.place_mentions_weekly` |
| `ops-rollup` | schedule/manual | API readiness, Azure cost export candidate | `ops.dependency_checks`, `ops.daily_costs` |

## Retry, Idempotency, and Poison Policy

The worker registry exposes these policies in `list --json` and dry-run output.
They are contract data only in Wave 1; live retry loops, queue bindings, and
dead-letter writes remain blocked until the DB and worker runtime are approved.

| Job id | Retry | Idempotency key | Poison handling |
|---|---|---|---|
| `weather-refresh` | 3 attempts, exponential 30s/2m/5m | `source_system + region + observed_at` | record failed dependency status and keep API fallback behavior |
| `community-keyword-watchlist` | 2 attempts, linear 10m | `iso_week + keyword + region_slug` | mark ingest run failed for operator review |
| `community-post-ingest` | 5 attempts, exponential 10s/30s/1m/2m/5m | `event_hub_partition + sequence_number` or source `external_key` | quarantine malformed event in a future dead-letter store before live Event Hub binding |
| `ops-rollup` | 3 attempts, exponential 1m/5m/15m | dependency bucket or `usage_date + resource_name` | record failed worker run and keep process-local `/metrics` as fallback evidence |

## Runbook

List worker contracts:

```bash
python -m apps.workers.app.cli list --json
```

Dry-run one job:

```bash
python -m apps.workers.app.cli run weather-refresh --dry-run --json
```

Evaluate live rollout prerequisites without external reads or writes:

```bash
python -m apps.workers.app.cli preflight --json
```

Run all worker dry-runs through the macOS/Linux wrapper:

```bash
scripts/unix/smoke_workers.sh
```

Run all worker dry-runs through the Windows wrapper:

```powershell
.\scripts\windows\smoke_workers.ps1
```

The wrappers choose the local virtual environment automatically when it exists.
They verify the live preflight remains blocked, then print job ids and dry-run
status only. They do not print environment variables, connection strings, API
keys, Key Vault secret values, or DB DSNs.
The API `/readyz` surface reports `worker_contracts=configured` when this dry-run
registry can be loaded, and `/metrics` exports the same state as a dependency
gauge. This is registry readiness only; it is not a live Azure Functions or Event
Hub freshness check.

## Rollout Plan

Generate the non-mutating live rollout plan:

```bash
scripts/unix/plan_worker_rollout.sh
```

```powershell
.\scripts\windows\plan_worker_rollout.ps1
```

The plan prints candidate Azure CLI/manual steps and approval gates for worker
storage, Event Hub, an Azure Functions lane, DB/schema verification, canary
order, idempotency, poison-message handling, and rollback ownership. It does not
create Azure resources, bind queues, enable `ALLOW_WORKER_MUTATION`, write
PostgreSQL rows, or print secret values.

The plan keeps runtime configuration scoped to `lala-key-vault`. ONMU Key
Vault values are not worker inputs for this repository.

## Mutation Guard

Live execution is blocked in Wave 1. Calling:

```powershell
python -m apps.workers.app.cli run weather-refresh --execute --json
```

returns a structured JSON error unless mutation has been explicitly enabled.
Even with `ALLOW_WORKER_MUTATION=1`, the current implementation returns
`not_implemented`. That is deliberate. The next wave should add actual worker
entrypoints only after these decisions are made:

- Azure Function versus Windows scheduled task ownership per job.
- Queue/Event Hub binding and poison-message policy for ingest jobs.
- PostgreSQL target and `db-dsn` Key Vault secret approval.
- Retry, idempotency key, and write conflict policy for each table.
- Persistent log, metric, and alert destination.

The preflight command reports these blockers as structured JSON. It checks only
whether required environment names are present; it does not connect to
PostgreSQL, Key Vault, Event Hub, Azure Functions, or Stream Analytics.

## Relationship to FastAPI

FastAPI reads from the canonical API relations and compatibility views. Worker
jobs own producer-side writes into those relations or their staging tables.
Keeping this split prevents request handlers from becoming crawlers, schedulers,
or streaming consumers.
