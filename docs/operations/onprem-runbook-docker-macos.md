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
- `scripts/unix/backup_docker_postgres.sh`
- `scripts/unix/install_onprem_launchd_macos.sh`
- `scripts/unix/install_onprem_backup_launchd_macos.sh`
- `scripts/unix/check_onprem_runtime.sh`
- `scripts/unix/install_onprem_monitor_launchd_macos.sh`

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

## Backup Automation

Create and verify one Docker PostgreSQL backup:

```bash
scripts/unix/backup_docker_postgres.sh
scripts/unix/backup_docker_postgres.sh \
  --apply \
  --confirm BACKUP_DOCKER_POSTGRES
```

The backup script creates a custom-format dump under ignored
`runtime/backups/`, validates it with `pg_restore --list`, and prunes backups
older than the configured retention window. It does not print DSNs, passwords,
or secret values.

Install the daily backup LaunchAgent:

```bash
scripts/unix/install_onprem_backup_launchd_macos.sh
scripts/unix/install_onprem_backup_launchd_macos.sh \
  --apply \
  --confirm INSTALL_BACKUP_LAUNCHD
```

Default schedule: daily at 03:30 KST. Default retention: 14 days.

Check backup status:

```bash
launchctl list | rg 'cloud\.lala-next\.backup'
tail -n 200 runtime/logs/lala-onprem-backup.launchd.out
tail -n 200 runtime/logs/lala-onprem-backup.launchd.err
ls -lh runtime/backups/lala-docker-postgres-*.dump
```

For off-host storage, pass an ignored local mount or sync target:

```bash
scripts/unix/install_onprem_backup_launchd_macos.sh \
  --offsite-dir /Volumes/<team-backup-volume>/lala-next-postgres \
  --apply \
  --confirm INSTALL_BACKUP_LAUNCHD
```

Do not configure an offsite target inside the repository.

## Runtime Monitoring

Run the health check once:

```bash
scripts/unix/check_onprem_runtime.sh \
  --require-live-ai \
  --require-live-speech
```

The check covers:

- macOS LaunchAgents for API and Cloudflare Tunnel.
- Docker PostgreSQL health.
- Local and public `/readyz`.
- DB-backed data mode, PostGIS, snapshot fallback, live AI, and live speech.
- Host disk headroom.

Install the 5-minute monitor LaunchAgent:

```bash
scripts/unix/install_onprem_monitor_launchd_macos.sh
scripts/unix/install_onprem_monitor_launchd_macos.sh \
  --apply \
  --confirm INSTALL_MONITOR_LAUNCHD
```

The monitor writes JSONL to ignored `runtime/logs/onprem-health.jsonl`.
By default, failed checks also emit a local macOS notification for the logged-in
operator. Disable local notification only when another alert path exists:

```bash
scripts/unix/install_onprem_monitor_launchd_macos.sh \
  --alert none \
  --apply \
  --confirm INSTALL_MONITOR_LAUNCHD
```

Check monitor status:

```bash
launchctl list | rg 'cloud\.lala-next\.monitor'
tail -n 5 runtime/logs/onprem-health.jsonl
tail -n 200 runtime/logs/lala-onprem-monitor.launchd.err
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
scripts/unix/check_onprem_runtime.sh
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

Additional operating policies:

- [onprem-post-contest-auth-transition.md](onprem-post-contest-auth-transition.md)
  covers disabling `LALA_PUBLIC_CONTEST_ACCESS` after the review window.
- [onprem-ai-speech-cost-fallback.md](onprem-ai-speech-cost-fallback.md)
  covers live AI/Speech cost, quota, and incident fallback.
- [onprem-browser-ios-revalidation.md](onprem-browser-ios-revalidation.md)
  covers desktop/mobile/iOS flow checks after runtime changes.

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
