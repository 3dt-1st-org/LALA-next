# On-Premises Linux Runbook

Last updated: 2026-06-26 KST

This runbook describes a Linux on-premises runtime using Docker PostgreSQL with
PostGIS/pgvector and a `systemd` API service.

## Repository Setup

Create the service account before cloning:

```bash
sudo useradd --system --create-home --home-dir /opt/lala-next --shell /usr/sbin/nologin lala
```

```bash
sudo mkdir -p /opt/lala-next
sudo chown -R lala:lala /opt/lala-next
sudo -u lala git clone https://github.com/3dt-1st-org/LALA-next.git /opt/lala-next
cd /opt/lala-next
sudo -u lala git fetch origin --prune
sudo -u lala git switch dev
sudo -u lala git pull --ff-only origin dev
sudo -u lala uv sync --extra dev
sudo -u lala mkdir -p /opt/lala-next/runtime/logs
```

Use an unprivileged `lala` service account. Do not run the API as root.

## Docker PostgreSQL Setup

Install Docker Engine and Compose using the team's approved package source.
Create `/opt/lala-next/runtime/local-postgres.env` outside git with the local
PostgreSQL env values. Do not write passwords to shell history.

Start the database:

```bash
set -a
source /opt/lala-next/runtime/local-postgres.env
set +a
docker compose -f compose.local.yml up -d postgres
docker inspect --format '{{.State.Health.Status}}' lala-next-postgres
```

Use PostgreSQL 16 with PostGIS 3.4 as the preferred first target unless the
team explicitly validates another version. The default Dockerfile also installs
pgvector for PostgreSQL 16. Host-level PostGIS and pgvector packages are not
required for the Docker runtime.

After restore or canonical SQL apply, verify:

```bash
DB_DSN="<redacted-process-local-value>" \
  scripts/unix/verify_db_schema.sh \
  --json \
  --connect-timeout 30 \
  --python .venv/bin/python
```

Expected extension state:

- PostGIS installed and enabled.
- pgvector installed and enabled.
- Canonical schemas and views present.
- `travel.idx_places_geog_expr` exists or the canonical SQL creates it.

## Secret File

Create:

```bash
/etc/lala-next/api.env
```

Permissions:

```bash
sudo chown root:lala /etc/lala-next/api.env
sudo chmod 0640 /etc/lala-next/api.env
```

Required normal runtime values:

```bash
LALA_STATIC_SNAPSHOT_FALLBACK=false
LALA_PUBLIC_CONTEST_ACCESS=false
KEY_VAULT_URL=
DB_DSN=<redacted>
```

Add API, public-data, Kakao, Naver, KOPIS, OpenAI, and Speech values as needed.
Do not commit this file or paste it into tracked docs.

## systemd Service

Create `/etc/systemd/system/lala-api.service`:

```ini
[Unit]
Description=LALA FastAPI service
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
User=lala
Group=lala
WorkingDirectory=/opt/lala-next
EnvironmentFile=/etc/lala-next/api.env
ExecStart=/opt/lala-next/.venv/bin/python -m uvicorn apps.api.app.main:app --host 127.0.0.1 --port 8080 --no-access-log
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/opt/lala-next/runtime
CapabilityBoundingSet=
LockPersonality=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

[Install]
WantedBy=multi-user.target
```

Then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable lala-api
sudo systemctl start lala-api
sudo systemctl status lala-api --no-pager
```

If a reverse proxy runs on the same host, keep uvicorn bound to `127.0.0.1` and
terminate TLS at the proxy.

## Reverse Proxy

The reverse proxy must:

- serve HTTPS for the API hostname;
- forward to `http://127.0.0.1:8080`;
- preserve `X-Request-ID` when present;
- set sane timeouts for planner/docent requests;
- avoid logging auth headers and query strings when possible.

DNS cutover is handled in [onprem-cutover-rollback.md](onprem-cutover-rollback.md).

## Smoke Checks

```bash
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS http://127.0.0.1:8080/readyz
scripts/unix/smoke_api.sh --base-url http://127.0.0.1:8080
scripts/unix/smoke_api_matrix.sh --base-url http://127.0.0.1:8080
```

For reverse proxy rehearsal:

```bash
scripts/unix/smoke_api.sh --base-url https://<onprem-api-host>
scripts/unix/smoke_api_matrix.sh --base-url https://<onprem-api-host>
```

## Logs And Restart

```bash
journalctl -u lala-api -n 200 --no-pager
sudo systemctl restart lala-api
```

If `LALA_ACCESS_LOG_PATH` is configured, place it under an operator-owned log
directory and rotate it outside git. Never log request bodies, tokens, DSNs, or
generated scripts.
