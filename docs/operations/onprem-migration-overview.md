# On-Premises Migration Overview

Last updated: 2026-06-26 KST

This document defines the safe documentation baseline for moving LALA's shared
runtime from Azure to an on-premises environment. It is intentionally a planning
and runbook document. Do not delete Azure resources, change DNS, restore
databases, or start a long-running on-premises service from this document alone.

## Target State

The public Flutter Web app remains on the existing web deployment path. The API
domain can later move from Azure Container Apps to the on-premises API after a
parallel verification window.

| Current Azure role | On-premises replacement | Notes |
|---|---|---|
| Azure Container Apps | Windows `start_api.ps1` service wrapper or Linux `systemd` service | FastAPI remains the API edge. |
| Azure Database for PostgreSQL Flexible Server | PostgreSQL with PostGIS and pgvector | Canonical schemas, extensions, and spatial index must verify before cutover. |
| Azure Key Vault | OS-protected env file or team-approved secret store | Runtime still receives process env values such as `DB_DSN`. |
| Application Insights and Log Analytics | Local structured logs plus retention policy | `runtime/` stays ignored; production logs need operator-owned storage. |
| Azure Container Registry | Local image registry, direct checkout deploy, or packaged artifact | The first on-premises runbook assumes direct checkout plus `uv`. |
| Azure custom hostname binding | DNS record for `api.lala-next.cloud` | DNS change is a later cutover step, not part of docs-only work. |

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
- [onprem-runbook-windows.md](onprem-runbook-windows.md): Windows API operation.
- [onprem-runbook-linux.md](onprem-runbook-linux.md): Linux API and DB operation.
- [onprem-data-secrets-migration.md](onprem-data-secrets-migration.md): DB and
  secret migration flow.
- [onprem-cutover-rollback.md](onprem-cutover-rollback.md): parallel
  verification, DNS cutover, and rollback rules.

## Recommended Migration Shape

1. Freeze the Azure baseline evidence: `/readyz`, API matrix smoke, latest DB
   schema verification, and latest ingest/scoring/RAG job status.
2. Prepare the on-premises host, database, secret injection, TLS endpoint, and
   operator accounts without touching public DNS.
3. Restore a fresh Azure database dump into the on-premises PostgreSQL target.
4. Verify canonical SQL, PostGIS, pgvector, and API readiness locally.
5. Run the same API matrix smoke against the on-premises API URL.
6. Run a browser/mobile rehearsal with an explicit API base URL override.
7. Change DNS only after the team reviews the rehearsal evidence.
8. Keep Azure healthy as rollback until the retention window ends.

## Out Of Scope For This Documentation Slice

- Actual Azure resource deletion.
- Actual DNS mutation.
- Actual `pg_dump` or restore execution.
- Production auth redesign.
- Flutter Web hosting migration.
- Replacing the current environment-variable based runtime configuration.
