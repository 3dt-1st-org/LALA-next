# Devlog - 2026-06-26 On-Premises Hardening

This log records the implementation work following the GLM-5.2 post-migration
gap audit. It intentionally avoids secrets, DSNs, resource ids, and live
credential values.

## Goals

- Reduce contest-window operational risk for `api.lala-next.cloud`.
- Prefer code-enforced guardrails over manual-only instructions.
- Keep normal data flow DB-backed; do not introduce mock/demo fallback paths.
- Document each hardening decision as it lands.

## Entries

### 1. PostgreSQL Localhost Binding

Changed `compose.local.yml` so the Docker PostgreSQL port binds to
`127.0.0.1` instead of every host interface.

Why:

- GLM-5.2 flagged broad Postgres exposure as P0.
- The API and maintenance scripts only need localhost access on the current
  Docker-backed Mac runtime.

Verification target:

```bash
docker compose -f compose.local.yml config
docker ps --filter name=lala-next-postgres --format '{{.Ports}}'
```

### 2. Backup Restore Drill and Offsite Guard

Added a disposable restore drill script that restores a Docker PostgreSQL dump
into a temporary container, runs canonical schema verification, prints only safe
row-count summaries, and then destroys the drill container.

Also added a `--require-offsite` guard to the backup script so operators can
fail the backup job when an off-host backup target is expected but not provided.
The macOS backup LaunchAgent installer can pass the same guard through to the
daily backup job.

Why:

- GLM-5.2 flagged local-only backups and missing restore evidence as P0/High.
- A backup is not operationally credible until restore has been rehearsed.

Verification target:

```bash
scripts/unix/backup_docker_postgres.sh --apply --confirm BACKUP_DOCKER_POSTGRES
scripts/unix/drill_restore_docker_postgres_backup.sh \
  --apply \
  --confirm DRILL_DOCKER_POSTGRES_RESTORE
```

### 3. Public Contest Paid Route Rate Limit

Added an in-process fixed-window rate limit for paid docent routes when
`LALA_PUBLIC_CONTEST_ACCESS=true`.

Covered routes:

- `POST /api/v1/docents/script`
- `POST /api/v1/docents/audio`

Runtime knobs:

- `LALA_PAID_ROUTE_RATE_LIMIT_ENABLED`
- `LALA_DOCENT_SCRIPT_RATE_LIMIT_PER_MINUTE`
- `LALA_DOCENT_AUDIO_RATE_LIMIT_PER_MINUTE`

Why:

- GLM-5.2 flagged public contest access plus live Azure OpenAI/Speech as a P0
  cost/quota abuse risk.
- This is not a replacement for Cloudflare WAF/rate limiting, but it gives the
  API an immediate first line of defense.

Verification target:

```bash
uv run pytest apps/api/tests/test_v1_routes.py -k rate_limited
```

### 4. Readiness Overall Mode Clarification

Changed readiness `mode.overall` precedence so DB-backed data remains the
overall runtime label even when AI/Speech are live Azure dependencies. The
separate `mode.ai` and `mode.speech` fields still report `live-azure`.

Why:

- GLM-5.2 flagged the mismatch between "DB-backed migration" acceptance and
  `overall=live-azure` as a High documentation/acceptance risk.
- Operators should be able to see both facts: the data path is on-prem DB-backed
  while AI/Speech remain live Azure dependencies.

Verification target:

```bash
uv run pytest apps/api/tests/test_health_auth.py -k live_azure_runtime_modes
```

### 5. Data Freshness Signal

Added a readiness `data_freshness` check for DB-backed runtimes. It verifies
that core DB-backed datasets are queryable and that the latest weather
observation is not older than `LALA_WEATHER_FRESHNESS_MAX_HOURS`.

The base readiness endpoint reports the signal, while the on-prem monitor only
fails on stale data when launched with `--require-data-freshness`.

Why:

- GLM-5.2 flagged stale weather/RAG/score evidence as a migration gap.
- This gives operators a visible freshness signal without unexpectedly taking
  the contest API down.

Verification target:

```bash
uv run pytest apps/api/tests/test_health_auth.py -k data_freshness
scripts/unix/check_onprem_runtime.sh --require-data-freshness
```

Operational note:

- Initial readiness exposed `data_freshness=degraded` because weather
  observations were from 2026-06-23.
- Ran guarded weather refresh with public-data APIs:
  `ALLOW_WEATHER_OBSERVATION_REFRESH_APPLY=1 ... --apply`.
- Inserted 20 fresh observations and confirmed
  `check_onprem_runtime.sh --require-data-freshness` passes.

### 6. Shutdown, Alerts, and Log Rotation

Added:

- `--timeout-graceful-shutdown` wiring to `scripts/unix/start_api.sh`.
- LaunchAgent `ExitTimeOut` wiring for the API service.
- Optional failure webhook support in `onprem_monitor_tick.sh` via an env-var
  name rather than a literal URL in tracked files.
- Daily log rotation scripts for ignored `runtime/logs`.

Why:

- GLM-5.2 flagged restart-time request drops, local-only alerts, and unbounded
  log growth as operational gaps.

Verification target:

```bash
bash -n scripts/unix/start_api.sh \
  scripts/unix/install_onprem_launchd_macos.sh \
  scripts/unix/onprem_monitor_tick.sh \
  scripts/unix/install_onprem_monitor_launchd_macos.sh \
  scripts/unix/rotate_onprem_logs.sh \
  scripts/unix/install_onprem_log_rotation_launchd_macos.sh
scripts/unix/rotate_onprem_logs.sh
```

### 7. Final Verification Pass

Ran the hardening verification set after applying runtime changes locally.

Verified:

- `git diff --check`
- secret-pattern scan over `README.md`, `docs`, `scripts`, and `apps`
- on-prem runtime check with live AI, live speech, and data freshness required
- public API matrix smoke against `https://api.lala-next.cloud`
- public paid dependency smoke, including live docent audio response
- targeted API tests for route rate limiting, readiness, and safety contracts
- full repository verification script

Observed result:

- API tests: 379 passed in full repository verification.
- Targeted hardening tests: 94 passed.
- Flutter app widget tests and web release build passed.
- Public API matrix smoke passed with 10 checked route variants.
- Paid dependency smoke returned `audio/mpeg` bytes.

### 8. Follow-Up Operational Value Hooks

Added the next-layer hooks for the remaining team-owned values:

- `scripts/unix/verify_onprem_offsite_backup.sh` verifies that the offsite
  backup target is writable and not accidentally inside the repo. By default it
  also rejects targets on the same filesystem as the repo.
- `scripts/unix/test_onprem_alert_webhook.sh` sends a safe test alert through an
  env-var-provided webhook without printing the URL.
- `scripts/unix/apply_cloudflare_edge_controls.sh` applies a Cloudflare
  Rulesets API `http_ratelimit` rule to the live paid docent routes after a
  scoped token and zone id are supplied outside git.
- `scripts/unix/plan_onprem_standby.sh` prints the cold-standby checklist for a
  second host without assuming the host already exists.

Why:

- These values should not be committed, but the operational path should be
  repeatable once the team provides them.
- The repo can now distinguish "not provided yet" from "not implemented yet."

Verification target:

```bash
bash -n scripts/unix/verify_onprem_offsite_backup.sh \
  scripts/unix/test_onprem_alert_webhook.sh \
  scripts/unix/apply_cloudflare_edge_controls.sh \
  scripts/unix/plan_onprem_standby.sh
scripts/unix/verify_onprem_offsite_backup.sh --offsite-dir /tmp/lala-offsite-check
scripts/unix/test_onprem_alert_webhook.sh
scripts/unix/apply_cloudflare_edge_controls.sh
scripts/unix/plan_onprem_standby.sh
```
