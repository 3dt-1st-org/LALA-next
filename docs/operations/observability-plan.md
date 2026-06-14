# Observability Plan

Wave 1 exposes process-local logs, `/readyz`, and `/metrics`. This document
defines the dashboard and alert plan to review before creating persistent
observability resources.

Generate the non-mutating plan:

```bash
scripts/unix/plan_observability.sh
```

```powershell
.\scripts\windows\plan_observability.ps1
```

The plan does not create dashboards, alerts, Azure resources, or log sinks. It
summarizes:

- Metrics exported by `/metrics`.
- Readiness checks exposed by `/readyz` and `lala_next_dependency_ready`.
- Identity transition checks, including `client_identity` and the bounded
  `oauth_*` configuration status fields.
- Runtime mode labels exposed by `/readyz.data.mode` and `lala_next_runtime_mode`.
- Candidate alert rules for health, readiness, 5xx, latency, and worker rollout
  preflight.
- Dashboard panels for readiness, route traffic, latency, and worker rollout
  gate state.
- Log fields that are safe to index.

## Safe Signals

Use only these current signal sources:

- `/healthz`
- `/readyz`
- `/metrics`
- `python -m apps.workers.app.cli preflight --json`
- `request_completed` log records with request id, method, route path, status,
  duration, and client host.
- Optional `LALA_ACCESS_LOG_PATH` JSONL records with the same bounded request
  fields for Windows/shared-backend log correlation.
- Read-only local access-log inspection by request id through
  `scripts/unix/inspect_access_log.sh` and
  `scripts/windows/inspect_access_log.ps1`.

Do not send auth headers, query strings, request bodies, `DB_DSN`, Key Vault
secret values, generated scripts, or audio payloads to dashboards or alerts.

## Current Metrics

- `lala_next_process_uptime_seconds`
- `lala_next_http_requests_total`
- `lala_next_http_request_duration_ms_sum`
- `lala_next_http_request_duration_ms_max`
- `lala_next_readiness_status`
- `lala_next_dependency_ready`
- `lala_next_runtime_mode`

Route labels are bounded by known route paths. Unknown 404 paths collapse into
`__unmatched__`, so arbitrary URLs and query strings are not exported.
Runtime mode labels are bounded to the known components `overall`, `data`, `ai`,
`speech`, and `worker`, with values such as `skeleton`, `public-cache`,
`db-backed`, `live-azure`, `dry-run`, and `degraded`.

## Approval Gate

Persistent Azure Monitor, Log Analytics, Application Insights, or Grafana setup
is outside the current local verification path. Create those resources only
after the shared backend URL, log destination, retention, and alert owner are
approved.
