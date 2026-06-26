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
- Browser/mobile happy-path checks should be rerun after any frontend API-base
  configuration change.
