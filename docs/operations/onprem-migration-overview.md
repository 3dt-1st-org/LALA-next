# On-Premises Migration Overview

Last updated: 2026-06-26 KST

This document defines the operating baseline for moving LALA's shared runtime
from Azure to an on-premises environment. The first approved target is a
Docker-backed PostgreSQL/PostGIS/pgvector database plus the existing FastAPI
service, exposed through a managed ingress or reverse proxy.

## Target State

The public Flutter Web app remains on the existing web deployment path. The API
domain moves independently through `api.lala-next.cloud`.

| Current Azure role | On-premises replacement | Notes |
|---|---|---|
| Azure Container Apps | macOS LaunchAgent, Linux `systemd`, or Windows service wrapper | FastAPI remains the API edge and should bind to localhost behind the ingress. |
| Azure Database for PostgreSQL Flexible Server | Docker PostgreSQL with PostGIS and pgvector | `compose.local.yml` and `infra/local-postgres/Dockerfile` are the default on-premises DB path. Native packages are optional, not required. |
| Azure Key Vault | OS-protected env file or team-approved secret store | Runtime still receives process env values such as `DB_DSN`; `KEY_VAULT_URL` is normally empty on-premises. |
| Application Insights and Log Analytics | Local structured logs plus retention policy | `runtime/` stays ignored; production logs need operator-owned storage. |
| Azure Container Registry | Direct checkout deploy plus Docker Compose, or later a local registry | The first on-premises runbook assumes direct checkout plus `uv`. |
| Azure custom hostname binding | Cloudflare Tunnel, reverse proxy, or DNS record for `api.lala-next.cloud` | Keep Azure as rollback until the retention window ends. |

## Current On-Premises State

As of 2026-06-26 KST, `api.lala-next.cloud` is routed through Cloudflare Tunnel
to the on-premises API host. The API process runs on localhost and reads the
Docker PostgreSQL database exposed on a localhost port.

Current acceptance evidence to refresh before any final handoff:

- `https://api.lala-next.cloud/readyz` reports `overall=db-backed`.
- `/readyz.data.checks.db` reports `configured`.
- `/readyz.data.checks.postgis` reports `configured`.
- `/readyz.data.checks.static_snapshot_fallback` reports `disabled`.
- `scripts/unix/smoke_api.sh --base-url https://api.lala-next.cloud` passes.
- `scripts/unix/smoke_api_matrix.sh --base-url https://api.lala-next.cloud`
  passes.

Live AI and live speech are separate readiness dimensions. If the on-premises
LaunchAgent clears `KEY_VAULT_URL`, those features must be supplied from the
local env file before they are expected to report `configured`.

## Non-Negotiable Runtime Policy

- `LALA_STATIC_SNAPSHOT_FALLBACK=false` in the normal on-premises runtime.
- Mock/demo data is never the normal data path.
- The database-backed path must be PostgreSQL plus PostGIS plus reviewed ingest,
  scoring, and RAG outputs.
- Static snapshot fallback is only an offline, read-only recovery path for DB
  outage handling or isolated local checks.
- Azure remains the rollback target until the team approves decommissioning.
- Secret values, DSNs, Key Vault URLs, subscription ids, and live resource names
  stay out of tracked Markdown.

## Documentation Set

- [onprem-prerequisites.md](onprem-prerequisites.md): server, network, TLS,
  backup, account, and secret prerequisites.
- [onprem-runbook-docker-macos.md](onprem-runbook-docker-macos.md): current
  Docker Desktop, macOS LaunchAgent, and Cloudflare Tunnel operation.
- [onprem-runbook-windows.md](onprem-runbook-windows.md): Windows API operation.
- [onprem-runbook-linux.md](onprem-runbook-linux.md): Linux API and DB operation.
- [onprem-data-secrets-migration.md](onprem-data-secrets-migration.md): DB and
  secret migration flow.
- [onprem-cutover-rollback.md](onprem-cutover-rollback.md): parallel
  verification, DNS cutover, and rollback rules.
- [onprem-cutover-status-2026-06-26.md](onprem-cutover-status-2026-06-26.md):
  current review-runtime cutover status and refreshable evidence.

## Recommended Migration Shape

1. Freeze the Azure baseline evidence: `/readyz`, API matrix smoke, latest DB
   schema verification, and latest ingest/scoring/RAG job status.
2. Prepare the on-premises host, database, secret injection, TLS endpoint, and
   operator accounts without touching public DNS.
3. Restore a fresh Azure database dump into the Docker PostgreSQL target.
4. Verify canonical SQL, PostGIS, pgvector, and API readiness locally.
5. Run the same API matrix smoke against the on-premises API URL.
6. Run a browser/mobile rehearsal with an explicit API base URL override.
7. Change DNS only after the team reviews the rehearsal evidence.
8. Keep Azure healthy as rollback until the retention window ends.

## Out Of Scope For This Documentation Slice

- Actual Azure resource deletion.
- Production auth redesign.
- Flutter Web hosting migration.
- Replacing the current environment-variable based runtime configuration.
