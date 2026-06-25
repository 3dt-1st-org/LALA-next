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
| OS | Windows Server 2022 or Ubuntu LTS | Team standard image |
| Network | Stable public ingress or tunnel | Static public IP or managed reverse proxy |

PostgreSQL and the API may share a host only for a small shared-dev runtime. For
heavier data ingest, separate the DB host from the API host.

## Required Software

Windows host:

- Git.
- Python compatible with the repo and `uv`.
- `uv`.
- PostgreSQL client tools: `psql`, `pg_dump`, `pg_restore`.
- Optional reverse proxy or tunnel software approved by the team.

Linux host:

- Git.
- Python compatible with the repo and `uv`.
- `uv`.
- PostgreSQL server and client tools.
- PostGIS package.
- pgvector package or approved build/install path.
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

- PostgreSQL version compatible with the canonical SQL.
- PostGIS extension.
- pgvector extension.
- Database role for LALA runtime.
- Database role or operator path for restore and migration.
- Backup directory with enough free space for at least two compressed dumps.
- Restore rehearsal target before touching the final runtime DB.

Before API cutover, the following checks must pass:

```bash
scripts/unix/verify_db_schema.sh --json --connect-timeout 30 --python .venv/bin/python
```

```powershell
.\scripts\windows\verify_db_schema.ps1 -ConnectTimeout 30
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

- Define backup frequency and retention.
- Define restore owner and restore test cadence.
- Define log retention and access owner.
- Define process restart owner.
- Define emergency rollback owner.
- Confirm where local-only runbooks with live hostnames and secret locations are
  stored.

## Ready-To-Rehearse Gate

Do not rehearse DNS cutover until all are true:

- On-premises DB restore has completed once.
- Schema verification passes.
- `/healthz` and `/readyz` pass on the on-premises API.
- API matrix smoke passes against the on-premises URL.
- Browser/mobile smoke can use the on-premises API URL by explicit override.
- Azure API remains healthy for rollback.
