# On-Premises Docker macOS Runbook

Last updated: 2026-06-26 KST

This runbook captures the current lightweight on-premises operating shape:
Docker Desktop hosts PostgreSQL/PostGIS/pgvector, macOS LaunchAgent keeps the
FastAPI process alive, and Cloudflare Tunnel exposes `api.lala-next.cloud`.

Use this for the review and team-shared runtime. A later Linux server can use
the same Docker database shape with `systemd`.

## Runtime Shape

```text
lala-next.cloud Flutter Web
  -> https://api.lala-next.cloud
  -> Cloudflare Tunnel
  -> 127.0.0.1:8080 FastAPI
  -> 127.0.0.1:<local-postgres-port> Docker PostgreSQL
```

Tracked files:

- `compose.local.yml`
- `infra/local-postgres/Dockerfile`
- `scripts/unix/restore_docker_postgres_dump.sh`
- `scripts/unix/install_onprem_launchd_macos.sh`

Ignored local files:

- `runtime/onprem-api.env`
- `runtime/local-postgres.env`
- `runtime/cloudflared/*.yml`
- `runtime/backups/*.dump`
- `runtime/logs/*`

Do not commit ignored runtime files. They may contain DSNs, tunnel credential
paths, backup data, or operational logs.

## Docker PostgreSQL

Start the database:

```bash
set -a
source runtime/local-postgres.env
set +a
docker compose -f compose.local.yml up -d postgres
docker inspect --format '{{.State.Health.Status}}' lala-next-postgres
```

The local PostgreSQL image is built from `postgis/postgis:16-3.4` and installs
`postgresql-16-pgvector`. Do not install host-level PostGIS or pgvector for this
runtime unless the team intentionally moves away from Docker.

Restore a dump into the Docker database:

```bash
scripts/unix/restore_docker_postgres_dump.sh \
  --dump runtime/backups/lala-azure-<date>.dump
```

After reviewing the plan output, execute:

```bash
scripts/unix/restore_docker_postgres_dump.sh \
  --dump runtime/backups/lala-azure-<date>.dump \
  --apply \
  --confirm RESTORE_DOCKER_POSTGRES
```

The restore script drops and recreates the target database in the Docker
container. Use it only during a rehearsal or approved replacement window.

## API LaunchAgent

Install or refresh the macOS LaunchAgents:

```bash
scripts/unix/install_onprem_launchd_macos.sh
```

After reviewing the plan output, execute:

```bash
scripts/unix/install_onprem_launchd_macos.sh \
  --apply \
  --confirm INSTALL_LAUNCHD
```

The installer writes:

- `~/Library/LaunchAgents/cloud.lala-next.api.plist`
- `~/Library/LaunchAgents/cloud.lala-next.cloudflared.plist`

The API LaunchAgent sources `runtime/onprem-api.env` when present, otherwise it
falls back to `runtime/local-postgres.env`. It forces
`LALA_STATIC_SNAPSHOT_FALLBACK=false`, and binds FastAPI to `127.0.0.1:8080`.
By default it clears `KEY_VAULT_URL`; provide live AI and speech values
directly in `runtime/onprem-api.env` if those features must be enabled
on-premises.

Check status:

```bash
launchctl list | rg 'lala-next|cloudflared'
docker ps --filter name=lala-next-postgres
```

Restart:

```bash
launchctl kickstart -k gui/$UID/cloud.lala-next.api
launchctl kickstart -k gui/$UID/cloud.lala-next.cloudflared
```

Logs:

```bash
tail -n 200 runtime/logs/lala-onprem-api.launchd.err
tail -n 200 runtime/logs/lala-next-cloudflared.err.log
tail -n 200 runtime/logs/onprem-api-access.jsonl
```

## Cloudflare Tunnel

The tracked repository must not contain the tunnel credential JSON or the live
tunnel config. Keep them under ignored `runtime/cloudflared/`.

The local tunnel config should route:

```yaml
tunnel: <tunnel-id>
credentials-file: <ignored-cloudflared-credential-json>
protocol: http2

ingress:
  - hostname: api.lala-next.cloud
    service: http://127.0.0.1:8080
  - service: http_status:404
```

Use `protocol: http2` for the current review host. It avoids intermittent
QUIC/UDP edge timeouts seen on this network while keeping the public hostname
unchanged.

If the tunnel is recreated, rerun the Cloudflare DNS route command from the
private runbook and verify that `api.lala-next.cloud` reaches the tunnel before
changing the public app.

## Verification

Local API:

```bash
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS http://127.0.0.1:8080/readyz
scripts/unix/smoke_api.sh --base-url http://127.0.0.1:8080
scripts/unix/smoke_api_matrix.sh --base-url http://127.0.0.1:8080
```

Public API:

```bash
curl -fsS https://api.lala-next.cloud/healthz
curl -fsS https://api.lala-next.cloud/readyz
scripts/unix/smoke_api.sh --base-url https://api.lala-next.cloud
scripts/unix/smoke_api_matrix.sh --base-url https://api.lala-next.cloud
```

Cutover is accepted only when public readiness reports DB-backed data with
PostGIS configured and static snapshot fallback disabled.

## Disk Operations

Docker Desktop stores images, containers, build cache, and volumes in
`Docker.raw`. Use `docker system df -v` before deleting anything. Do not prune
volumes unless there is a verified database backup and restore evidence.

Safe cleanup examples:

```bash
docker container prune --filter until=336h --force
docker image prune --all --filter until=336h --force
docker network prune --filter until=336h --force
docker builder prune --filter until=336h --force
```
