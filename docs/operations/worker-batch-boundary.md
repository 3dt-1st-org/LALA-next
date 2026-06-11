# Worker and Batch Boundary

Wave 1 keeps the public FastAPI edge separate from producer and batch work.
The worker package is intentionally executable as dry-run only so the team can
agree on job ownership, write targets, and future Azure wiring before anything
mutates shared PostgreSQL or streaming resources.

## Current Boundary

| Job id | Trigger | Future source | Intended writes |
|---|---|---|---|
| `weather-refresh` | schedule/manual | legacy `weather_air_func`, Azure Function candidate | `locallink.realtime_weather_conditions` |
| `daangn-weekly-keywords` | schedule/manual | legacy `daangn_weekly_crawler` | `daangn.crawl_runs`, `daangn.crawl_tasks`, `daangn.weekly_keywords` |
| `daangn-community-ingest` | queue/manual | Azure Event Hub, Azure Stream Analytics | `daangn.community_posts`, `daangn.place_mentions_weekly` |
| `monitoring-rollup` | schedule/manual | API readiness, Azure cost export candidate | `monitoring.dependency_checks`, `monitoring.cost_daily` |

## Runbook

List worker contracts:

```powershell
python -m apps.workers.app.cli list --json
```

Dry-run one job:

```powershell
python -m apps.workers.app.cli run weather-refresh --dry-run --json
```

Run all worker dry-runs through the Windows wrapper:

```powershell
.\scripts\windows\smoke_workers.ps1
```

The wrapper chooses `.venv\Scripts\python.exe` automatically when it exists.
It prints job ids and dry-run status only. It does not print environment
variables, connection strings, API keys, Key Vault secret values, or DB DSNs.

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

## Relationship to FastAPI

FastAPI reads from the canonical API relations and compatibility views. Worker
jobs own producer-side writes into those relations or their staging tables.
Keeping this split prevents request handlers from becoming crawlers, schedulers,
or streaming consumers.
