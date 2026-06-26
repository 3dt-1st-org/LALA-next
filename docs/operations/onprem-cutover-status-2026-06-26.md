# On-Premises Cutover Status - 2026-06-26

Last updated: 2026-06-26 KST

## Summary

`api.lala-next.cloud` is currently served by the on-premises path for the review
runtime:

```text
Cloudflare DNS
  -> Cloudflare Tunnel
  -> macOS LaunchAgent cloud.lala-next.cloudflared
  -> 127.0.0.1:8080 FastAPI
  -> Docker container lala-next-postgres
```

The public Flutter Web app remains on the existing web hosting path. Only the
API runtime and database path moved for this cutover step.

## Current Runtime

- API process manager: macOS LaunchAgent `cloud.lala-next.api`.
- Tunnel process manager: macOS LaunchAgent `cloud.lala-next.cloudflared`.
- Public API hostname: `https://api.lala-next.cloud`.
- Database: Docker PostgreSQL container `lala-next-postgres`.
- PostgreSQL exposure: localhost port from `runtime/local-postgres.env`.
- Normal data mode: DB-backed.
- Static snapshot fallback: disabled.
- Public contest access: enabled for the contest/review window.
- Cloudflare Tunnel protocol: `http2`.
- Live AI: enabled through the local on-premises env file.
- Live speech: enabled through the local on-premises env file.
- Backup automation: LaunchAgent `cloud.lala-next.backup`, daily 03:30 KST,
  ignored `runtime/backups/`, 14-day default retention.
- Runtime monitor: LaunchAgent `cloud.lala-next.monitor`, 5-minute JSONL
  checks in ignored `runtime/logs/onprem-health.jsonl`, with local macOS
  notification on failed checks.
- Log rotation: LaunchAgent `cloud.lala-next.log-rotation`, daily 04:00 KST.
- Paid route rate limit: enabled for public contest access on docent script and
  audio routes.
- Data freshness: latest weather observations refreshed on 2026-06-26 KST and
  readiness now reports `data_freshness=configured`.

## Restored Data Snapshot

The on-premises Docker database was restored from an Azure dump stored in an
ignored local backup path. Safe row-count summary after restore:

| Dataset | Count |
|---|---:|
| `culture.events` | 465 |
| `travel.places` | 2636 |
| `rag.knowledge_chunks` | 3464 |
| `analytics.place_score_snapshots` | 31682 |

Enabled PostgreSQL extensions:

- `pgcrypto`
- `postgis`
- `vector`

## Verification Evidence

Refresh these commands before any formal handoff:

```bash
curl -fsS https://api.lala-next.cloud/readyz
scripts/unix/smoke_api.sh --base-url https://api.lala-next.cloud
scripts/unix/smoke_api_matrix.sh --base-url https://api.lala-next.cloud --timeout 30
```

Latest observed public readiness:

- `overall=db-backed`
- `data=db-backed`
- `db=configured`
- `postgis=configured`
- `static_snapshot_fallback=disabled`
- `public_contest_access=enabled`
- `live_ai=enabled`
- `live_speech=enabled`

Latest observed smoke:

- On-prem runtime health check: passed for API LaunchAgent, Cloudflare Tunnel,
  Docker PostgreSQL, local/public readiness, live AI, live speech, data
  freshness, and disk headroom.
- Docker PostgreSQL restore drill: passed against the local backup dump.
- PostgreSQL host port: bound to `127.0.0.1`.
- Weather observation refresh: applied with 20 inserted observations and
  recorded job run.
- Local API smoke: passed.
- Local API matrix smoke: passed, 37 checks.
- Public API smoke: passed.
- Public API matrix smoke: passed, 37 checks.
- Local paid-dependency smoke: passed with Azure OpenAI script generation and
  audio/mpeg Speech response.
- Public paid-dependency smoke: passed with Azure OpenAI script generation and
  audio/mpeg Speech response.

## Known Remaining Work

- Azure should remain available as the rollback target until the team approves
  the retention window end.
- Off-host backup storage is still a team operations decision. The local daily
  backup job exists, but a mounted backup volume or team backup service should
  be attached before treating the single Mac as recoverable after disk loss.
- Team-wide external alert delivery is not yet wired. The monitor writes JSONL
  locally and emits a local Mac notification on failure; a later step should
  set `LALA_ONPREM_ALERT_WEBHOOK_URL` in the ignored runtime env and reinstall
  the monitor with `--webhook-env-name LALA_ONPREM_ALERT_WEBHOOK_URL`.
- Public contest access is intentionally enabled for review. Follow
  [onprem-post-contest-auth-transition.md](onprem-post-contest-auth-transition.md)
  after the contest window.
- Browser/mobile happy-path checks should be rerun after any frontend API-base
  configuration change.
