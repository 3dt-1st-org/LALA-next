# Windows Shared Backend Runbook

Wave 1 runs the FastAPI public API as the shared backend edge.

## Start

```powershell
cd C:\Users\EL035\dataschool\LALA-next
.\scripts\windows\start_api.ps1 -Port 8080
```

The script uses `.venv\Scripts\python.exe` automatically when it exists. Use
`-Python <path-to-python.exe>` to override the interpreter. Use `-KeyVaultUrl`
to set the LALA-next Key Vault URL for the started API process. When a Key Vault
URL is provided, the script loads known LALA-next secrets into process
environment variables without printing their values.

For a live Azure demo:

```powershell
.\scripts\windows\start_api.ps1 -Port 8080 -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ -EnableLiveAI -EnableLiveSpeech
```

For Flutter Web or browser-based contract checks, configure explicit browser
origins before starting the API:

```powershell
$env:CORS_ALLOW_ORIGINS = "http://localhost:3000,http://127.0.0.1:3000"
.\scripts\windows\start_api.ps1 -Port 8080
```

CORS is disabled by default. Do not use a wildcard for a shared backend unless
the team has agreed that the URL is temporary and LAN-only.

## Smoke

```powershell
az login
Copy-Item .env.example .env
.\scripts\windows\smoke_api.ps1 -BaseUrl "http://127.0.0.1:8080"
```

The smoke script does not print secret values. If Key Vault access is unavailable, set `IOS_API_KEY` as a process-local environment variable before running authenticated checks.
For new clients, prefer `API_BEARER_TOKEN`; the smoke script uses bearer auth
when that environment variable is present and falls back to `IOS_API_KEY`.

For live Azure OpenAI and Speech validation:

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl "http://127.0.0.1:8080" -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ -PaidDependency
```

If the shared backend will use a PostgreSQL target, run the read-only schema
verification before the API handoff:

```powershell
.\scripts\windows\verify_db_resources.ps1
.\scripts\windows\verify_db_schema.ps1 -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/
```

This check confirms the canonical extensions, schemas, tables, and views are
present. It does not apply migrations and does not print `DB_DSN`.

If the schema is missing because the target is an approved dev/shared database,
review the canonical SQL plan first:

```powershell
.\scripts\windows\apply_canonical_sql.ps1
```

Only after review should an operator apply the non-destructive canonical
baseline:

```powershell
$env:ALLOW_CANONICAL_SQL_APPLY = "1"
.\scripts\windows\apply_canonical_sql.ps1 `
  -Apply `
  -Confirm APPLY_CANONICAL_SQL `
  -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/
```

After apply mode succeeds, rerun `verify_db_schema.ps1` and then `/readyz`
before handing the backend URL to Flutter clients.

## LAN Exposure

Use `127.0.0.1` for operator-only checks and the Windows host LAN IP for real
device checks. Before sharing the URL, verify:

```powershell
ipconfig
Test-NetConnection -ComputerName 127.0.0.1 -Port 8080
```

If teammates cannot connect from the same network, check Windows Firewall,
VPN/tunnel routing, and whether the API was started with `-HostName 0.0.0.0`.
Do not ask mobile clients to use `localhost`.

## Logs and Restart

For a short demo, a foreground `start_api.ps1` terminal is enough. For a longer
shared session, assign one operator who owns the process and captures logs:

```powershell
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
New-Item -ItemType Directory -Force .\runtime\logs | Out-Null
.\scripts\windows\start_api.ps1 -Port 8080 *> ".\runtime\logs\api-$stamp.log"
```

`runtime/` is ignored by git. If `/healthz` fails, stop and restart the API
process from the same branch/commit, then rerun smoke before handing the URL
back to teammates.

Each API response includes:

- `X-Request-ID`
- `X-Request-Duration-Ms`

The start script disables uvicorn access logs and the API writes one
`request_completed` log entry per request with method, path, status, duration,
request id, and client host. It does not log query strings or auth headers. Set
`LOG_LEVEL=DEBUG`, `INFO`, `WARNING`, or `ERROR` before starting the API to
adjust verbosity.

The API also exposes process-local Prometheus text metrics at `/metrics`.
Metrics include process uptime, request counts, duration sums, and max duration
by method, route path, status code, and status class. They do not include query
strings, request bodies, auth headers, API keys, bearer tokens, or client IPs.
Unmatched 404 paths are collapsed into the fixed `__unmatched__` label instead
of exporting arbitrary URL paths.
The `/metrics` scrape route itself is excluded from request counters, and the
counters reset when the API process restarts.

## Handoff

Share this format with teammates:

```text
Backend URL: http://<host>:8080
Mode: shared LAN dev
Branch/build: main or commit SHA
DB target: skeleton or approved dev DB
Health: /healthz
Ready: /readyz
Metrics: /metrics
Known degraded features: DB/Azure live calls are not required in Wave 1
```

If `DB_DSN` is set, `/readyz` connects to PostgreSQL and verifies the canonical
relations used by places/weather/planner/docent cache routes:
`locallink.v_public_places`, `locallink.realtime_weather_conditions`, and
`locallink.docent_cache`. If the DB is absent, missing those relations, or
otherwise degraded, the API remains usable through deterministic skeleton
fallbacks.
