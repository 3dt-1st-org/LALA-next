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
.\scripts\windows\start_api.ps1 -Port 8080 -KeyVaultUrl <KEY_VAULT_URL> -EnableLiveAI -EnableLiveSpeech
```

For Flutter Web or browser-based contract checks, configure explicit browser
origins before starting the API:

```powershell
$env:CORS_ALLOW_ORIGINS = "http://localhost:3000,http://127.0.0.1:3000"
.\scripts\windows\start_api.ps1 -Port 8080
```

CORS is disabled by default. Do not use a wildcard for a shared backend unless
the team has agreed that the URL is temporary and LAN-only.
When `KEY_VAULT_URL` points at the LALA-next vault, the start wrapper and API can
also load the optional `cors-allow-origins` secret into `CORS_ALLOW_ORIGINS`.

## Smoke

```powershell
az login
Copy-Item .env.example .env
.\scripts\windows\smoke_api.ps1 -BaseUrl "http://127.0.0.1:8080"
```

The smoke script does not print secret values. If Key Vault access is
unavailable, set `IOS_API_KEY` as a process-local environment variable before
running authenticated checks. For OAuth/Entra JWT validation, prefer
`LALA_SMOKE_BEARER_TOKEN`; the smoke script uses it before falling back to the
static transition `API_BEARER_TOKEN`, then `IOS_API_KEY`.

For live Azure OpenAI and Speech validation:

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl "http://127.0.0.1:8080" -KeyVaultUrl <KEY_VAULT_URL> -PaidDependency
```

For Flutter Web or browser-based contract checks, add a CORS preflight smoke
against one allowed origin:

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl "http://127.0.0.1:8080" -CorsOrigin http://localhost:3000
```

If the shared backend will use a PostgreSQL target, run the read-only schema
verification before the API handoff:

```powershell
.\scripts\windows\verify_db_resources.ps1
.\scripts\windows\verify_db_schema.ps1 -KeyVaultUrl <KEY_VAULT_URL>
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
  -KeyVaultUrl <KEY_VAULT_URL>
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
.\scripts\windows\start_api.ps1 `
  -Port 8080 `
  -AccessLogPath ".\runtime\logs\api-access-$stamp.jsonl" `
  *> ".\runtime\logs\api-$stamp.log"
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
For Windows handoff log correlation, pass `-AccessLogPath` or set
`LALA_ACCESS_LOG_PATH` to a local ignored path such as
`runtime/api-access.jsonl`. When configured, the API writes one JSON object per
request with only these fields:

- `request_id`
- `method`
- route-template `path`
- `status_code`
- `duration_ms`
- `client_host`

The JSONL access log does not include query strings, request bodies, API keys,
bearer tokens, or generated content. Leave `LALA_ACCESS_LOG_PATH` empty when
stdout/stderr collection is enough.
When the Flutter app shell shows a request id, inspect the local JSONL file with
the read-only helper:

```powershell
.\scripts\windows\inspect_access_log.ps1 `
  -Path .\runtime\api-access.jsonl `
  -RequestId <request-id>
```

The helper prints only the bounded access-log fields and drops any untrusted
extra fields if a log line contains them.
Caller-provided `X-Request-ID` values are preserved only when they are
1-128 characters using letters, digits, `.`, `_`, `:`, or `-`; unsafe values are
replaced with a generated id before they reach response headers, envelopes, or
logs.

The API also exposes process-local Prometheus text metrics at `/metrics`.
Metrics include process uptime, request counts, duration sums, and max duration
by method, route path, status code, and status class. The same endpoint also
exports readiness gauges for the overall `/readyz` status and each dependency
check, plus `lala_next_runtime_mode` labels for `unavailable`, `disabled`,
`public-cache`, `db-backed`, `live-azure`, or `degraded` operation. They do not include query strings,
request bodies, auth headers, API keys, bearer tokens, or client IPs. Unmatched
404 paths are collapsed into the fixed `__unmatched__` label instead of
exporting arbitrary URL paths.
Known FastAPI static paths such as `/openapi.json`, `/docs`, and `/redoc` are
exported by fixed path labels.
The `/metrics` scrape route itself is excluded from request counters, and the
counters reset when the API process restarts. If `DB_DSN` is configured,
scraping `/metrics` can perform the same short DB readiness probe as `/readyz`.
Before creating persistent dashboards or alerts, review the non-mutating plan:

```powershell
.\scripts\windows\plan_observability.ps1
```

## Handoff

Share this format with teammates:

```text
Backend URL: http://<host>:8080
Mode: copy /readyz data.mode.overall (public-cache, db-backed, live-azure, or degraded)
Branch/build: main or commit SHA
DB target: approved dev DB, public-cache fallback, or unavailable
Health: /healthz
Ready: /readyz
Metrics: /metrics
Known degraded features: DB/Azure live calls are not required in Wave 1
```

If `DB_DSN` is set, `/readyz` connects to PostgreSQL and verifies the canonical
relations used by places/weather/planner/docent cache routes:
`travel.public_places`, `travel.weather_observations`, and
`travel.docent_scripts`. It also reports `postgis=configured` only when the
PostGIS extension and `travel.idx_places_geog_expr` spatial index exist. If the
DB is absent, missing those relations, missing PostGIS support, or otherwise
degraded, DB-backed routes return empty or `unavailable` contract-safe responses
unless static snapshot fallback is explicitly enabled. `/readyz.data.mode.data`
reports `db-backed` only when both `db=configured` and `postgis=configured`;
otherwise it reports `unavailable`, `public-cache`, or `degraded`.
