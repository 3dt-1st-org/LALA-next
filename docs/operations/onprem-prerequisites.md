# On-Premises Prerequisites

Last updated: 2026-06-26 KST

This checklist must be complete before any Azure-to-on-premises cutover
rehearsal. Use placeholders in shared notes. Put live values only in the
team-private runbook or approved secret store.

## Host Requirements

Minimum starting point for a shared dev/review-grade runtime:

| Component | Minimum | Preferred |
|---|---:|---:|
| CPU | 4 vCPU | 8 vCPU |
| Memory | 16 GiB | 32 GiB |
| Disk | 200 GiB SSD | 500 GiB SSD/NVMe |
| OS | macOS host for the current review runtime, Windows Server 2022, or Ubuntu LTS | Team standard image |
| Network | Stable public ingress or tunnel | Static public IP or managed reverse proxy |

PostgreSQL and the API may share a host only for a small shared-dev runtime. For
heavier data ingest, separate the DB host from the API host.

## Required Software

Current macOS Docker host:

- Docker Desktop.
- Git.
- Python compatible with the repo and `uv`.
- `uv`.
- Cloudflared when using Cloudflare Tunnel.
- PostgreSQL client tools are useful for diagnostics, but host-level PostGIS and
  pgvector packages are not required when `compose.local.yml` is used.

Windows host:

- Git.
- Python compatible with the repo and `uv`.
- `uv`.
- PostgreSQL client tools: `psql`, `pg_dump`, `pg_restore`. Use client tools
  from the same major version as the Azure source server or newer.
- Optional reverse proxy or tunnel software approved by the team.

Linux host:

- Git.
- Python compatible with the repo and `uv`.
- `uv`.
- Docker Engine and Compose for the preferred DB runtime.
- PostgreSQL client tools.
- Host-level PostgreSQL, PostGIS, and pgvector packages only if the team
  intentionally chooses a native DB install instead of Docker.
- `systemd`.
- Reverse proxy such as nginx, Caddy, or an approved tunnel.

## Network And DNS

Prepare these before cutover:

- Public API endpoint candidate for smoke testing before DNS cutover.
- Firewall rule allowing HTTPS ingress to the reverse proxy.
- Firewall rule allowing API host to reach PostgreSQL.
- No broad PostgreSQL public exposure unless explicitly approved.
- DNS change plan for `api.lala-next.cloud`.
- DNS rollback plan back to the Azure API target.
- TLS certificate strategy for the API domain.

Keep `lala-next.cloud` web hosting out of this migration unless a separate
frontend migration is approved.

## Database Prerequisites

The on-premises PostgreSQL target must support:

- PostgreSQL 16 as the preferred target major version. The current local
  canonical DB baseline is compatible with the `postgis/postgis:16-3.4`
  container image used by existing development scripts.
- PostGIS 3.4 or a package-compatible PostGIS version for the selected
  PostgreSQL major version.
- pgvector installed for the selected PostgreSQL major version.
- `pgcrypto`, `postgis`, and `vector` extensions enabled in the target
  database before or during restore.
- Database role for LALA runtime.
- Database role or operator path for restore and migration.
- Backup directory with enough free space for at least two compressed dumps.
- Restore rehearsal target before touching the final runtime DB.

Recommended role split:

| Role | Purpose | Required capability |
|---|---|---|
| Restore operator | One-time dump restore and canonical SQL apply | Create schemas, create extensions, restore objects |
| Runtime role | `DB_DSN` used by the API | Read/write only to approved LALA schemas |

When Docker is used, `infra/local-postgres/Dockerfile` provides PostGIS and
pgvector inside the container. If a native database is used, and the restore
operator cannot create extensions, a database administrator must pre-create
`pgcrypto`, `postgis`, and `vector`, then rerun schema verification.
Do not grant the long-lived runtime role broad database-owner privileges merely
to make restore easier.

Before API cutover, the following checks must pass:

```bash
scripts/unix/verify_db_schema.sh --json --connect-timeout 30 --python .venv/bin/python
```

```powershell
.\scripts\windows\verify_db_schema.ps1 `
  -EnvFile C:\services\lala-secrets\api.env `
  -ConnectTimeout 30
```

## Secret Prerequisites

On-premises runtime secrets must be injected as process environment variables or
loaded from an OS-protected env file. The file must be readable only by the API
service account and operators.

Required secret names or env values:

- `DB_DSN`
- `PUBLIC_DATA_SERVICE_KEY`
- `KOPIS_API_KEY`
- `NAVER_CLIENT_ID`
- `NAVER_CLIENT_SECRET`
- `KAKAO_JAVASCRIPT_KEY`
- `KAKAO_REST_API_KEY`
- `AZURE_OPENAI_ENDPOINT`
- `AZURE_OPENAI_KEY`
- `AZURE_OPENAI_DEPLOYMENT`
- `AZURE_OPENAI_API_VERSION`
- `AZURE_OPENAI_DOCENT_DEPLOYMENT` when the role-specific deployment exists
- `AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT` when the role-specific deployment exists

Optional or transition values:

- `API_BEARER_TOKEN`
- `LALA_SMOKE_BEARER_TOKEN`
- `IOS_API_KEY`
- `CORS_ALLOW_ORIGINS`
- `AZURE_SPEECH_REGION`
- `AZURE_SPEECH_ENDPOINT`
- `AZURE_SPEECH_KEY`

Keep `KEY_VAULT_URL` unset for the normal on-premises runtime unless the team
intentionally keeps Azure Key Vault as a temporary secret source.

## Backup And Operations

Before cutover rehearsal:

- Define backup frequency and retention. The starting minimum for a shared
  review runtime is a daily compressed logical dump, 7 to 14 days of local
  retention, and one weekly off-host copy.
- Define restore owner and restore test cadence. Run at least one monthly
  restore drill, and run an extra restore drill before contest/review windows.
- Define log retention and access owner. Start with 14 days for API access logs
  and 30 days for system/service logs unless the team approves a different
  policy.
- Define process restart owner.
- Define emergency rollback owner.
- Confirm where local-only runbooks with live hostnames and secret locations are
  stored.

## Observability Prerequisites

Application Insights and Log Analytics do not automatically follow the app
on-premises. Before cutover rehearsal, define the local replacement:

- API stdout/stderr destination and owner.
- JSONL access-log destination when `LALA_ACCESS_LOG_PATH` is enabled.
- Log rotation policy and secure deletion/retention policy.
- Health monitor for `/healthz` and `/readyz`.
- Alert route for API down, DB degraded, PostGIS degraded, and disk space low.
- Operator playbook link for restart, rollback, and backup restore.

The minimum acceptable review runtime can start with local service logs plus a
simple external uptime monitor, but an owner must be assigned and the alert path
must be tested once before DNS cutover.

## Ready-To-Rehearse Gate

Do not rehearse DNS cutover until all are true:

- On-premises DB restore has completed once.
- Schema verification passes.
- `/healthz` and `/readyz` pass on the on-premises API.
- API matrix smoke passes against the on-premises URL.
- Browser/mobile smoke can use the on-premises API URL by explicit override.
- Azure API remains healthy for rollback.
