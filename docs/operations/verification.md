# Verification

This repository keeps Wave 1 verification lightweight and repeatable. The checks
are intentionally local-first so controller, implementation, and verification
sessions can run the same commands without requiring live Azure or database
dependencies.

## Local Verification

From macOS/Linux:

```bash
scripts/unix/verify_repo.sh
```

The script runs `uv sync --extra dev` by default, then uses the Python
interpreter in the uv-managed `.venv`. Use `--python <path-to-python>` only when
you need to override that interpreter.

If uv dependencies are already synced and you only want to rerun checks:

```bash
scripts/unix/verify_repo.sh --skip-install
```

For a Mac handoff report that combines branch state, latest GitHub Actions run,
local verification, Azure resource verification, and DB rollout readiness:

```bash
scripts/unix/handoff_report.sh
```

Use `--skip-tests` or `--skip-azure` for a fast read-only status pass when the
full check was already run in the same session.
When `local-artifacts/openapi/lala-next-openapi.json` is present, the report also
checks OpenAPI compatibility against that USB handoff snapshot. Pass
`--openapi-baseline <path>` to compare against a different Flutter handoff
snapshot.

From `C:\Users\EL035\dataschool\LALA-next` on Windows:

```powershell
.\scripts\windows\verify_repo.ps1
```

The script runs `uv sync --extra dev` by default, then uses
`.venv\Scripts\python.exe`. Use `-Python <path-to-python.exe>` only when you
need to override that interpreter.

If dependencies are already installed:

```powershell
.\scripts\windows\verify_repo.ps1 -SkipInstall
```

The script runs:

- FastAPI route tests.
- API-key and response-envelope contract tests.
- Request id, request duration, public metrics with readiness gauges, and
  secret-safe request logging tests, including optional JSONL access log output
  when `LALA_ACCESS_LOG_PATH` is configured.
- Canonical SQL plan/apply guard tests.
- Worker/batch dry-run contract tests and smoke.
- Non-mutating worker/batch live rollout gate plan generation.
- In-process OpenAPI export tests and local handoff export.
- Reference Flutter client contract check against the current OpenAPI route set.
- Optional Dart package format/analyze/test for the reference Flutter client
  when Dart is installed.
- Non-mutating DB rollout plan generation.
- Non-mutating observability alert/dashboard plan generation.
- Non-mutating OAuth/Entra identity rollout plan generation.
- Non-mutating TourAPI, KCISA culture-info, KOPIS, and card-spending ingestion plan generation.
- Non-mutating legacy Flask replacement/retirement plan generation.
- SQL and documentation secret-safety tests.
- PowerShell script parser checks.

## CI Verification

GitHub Actions runs the same test suite on every push to `main` and every pull
request. The Windows job verifies the shared-backend baseline:

- `uv sync --extra dev`
- `uv run pytest apps/api/tests`
- PowerShell parser checks for `scripts/windows/*.ps1`

The Ubuntu job verifies the Mac/Linux wrapper path:

- `uv sync --extra dev`
- `bash scripts/unix/verify_repo.sh --skip-install`

CI does not require live Key Vault, Azure OpenAI, Azure Speech, or PostgreSQL.
Those dependencies are represented as `configured`, `missing`, `degraded`, or
`skipped` in `/readyz` and are smoke-tested manually when credentials are
available.
`/readyz.data.mode` adds the operator-facing runtime summary:
`overall=skeleton` when deterministic fallbacks are active, `overall=db-backed`
when the canonical DB probe is configured and no live Azure dependency is in
use, `overall=public-cache` when public demo mode serves the bundled MVP
snapshot without a live DB, `overall=live-azure` when opt-in AI or Speech live
calls are configured, and `overall=degraded` when a requested runtime dependency
is unhealthy.

When `DB_DSN` is configured, `/readyz` connects to PostgreSQL and verifies the
canonical relations required by the API:

- `travel.public_places`
- `travel.weather_observations`
- `travel.docent_scripts`
- `analytics.place_score_snapshots`

Without `DB_DSN`, DB readiness is `skipped` and DB-backed routes use their
skeleton fallback. If the connection works but those relations are absent,
DB readiness is `degraded` rather than `configured`.
`/readyz` also verifies that the Wave 1 dry-run worker contract registry can be
loaded. This does not imply live Azure Functions/Event Hub freshness; live worker
mutation remains behind the worker rollout gate.

For an explicit read-only canonical schema check against the configured DB,
run:

```bash
scripts/unix/verify_db_schema.sh
```

```powershell
.\scripts\windows\verify_db_schema.ps1
```

The script reads `DB_DSN` from the process, `.env`, or the configured
LALA-next Key Vault. It checks required extensions, schemas, tables, and views
without applying migrations or printing the DSN. A missing `DB_DSN`, connection
failure, or missing canonical object returns a non-zero exit code so operators
can stop before handing the DB to Flutter/API smoke testers.
Use `-Json` when another tool needs machine-readable output; in that mode the
PowerShell wrapper suppresses human-readable preamble text.

To review the exact canonical SQL files before any DB rollout, run:

```bash
scripts/unix/apply_canonical_sql.sh
```

```powershell
.\scripts\windows\apply_canonical_sql.ps1
```

Default mode is dry-run plan only. It lists canonical files, statement counts,
and SHA-256 hashes without connecting to PostgreSQL. Applying the plan requires
all three explicit controls:

```bash
ALLOW_CANONICAL_SQL_APPLY=1 \
  scripts/unix/apply_canonical_sql.sh \
  --apply \
  --confirm APPLY_CANONICAL_SQL \
  --key-vault-url https://lala-next-kv-27db5e.vault.azure.net/
```

```powershell
$env:ALLOW_CANONICAL_SQL_APPLY = "1"
.\scripts\windows\apply_canonical_sql.ps1 `
  -Apply `
  -Confirm APPLY_CANONICAL_SQL `
  -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/
```

The apply path reads `DB_DSN` from the process, `.env`, or LALA-next Key Vault,
runs `sql/canonical/*.sql` in sorted order inside one transaction, and does not
print the DSN. Use it only for an approved dev/shared target after the plan has
been reviewed.

To verify worker and batch boundaries without external reads or writes, run:

```bash
scripts/unix/smoke_workers.sh
```

```powershell
.\scripts\windows\smoke_workers.ps1
```

This command lists worker contracts and dry-runs each job. It is safe without
`DB_DSN`, Key Vault access, Event Hub access, or live Azure Functions. It also
runs the read-only worker live preflight and expects it to remain blocked in
Wave 1.

To review worker/batch live rollout gates without creating resources, binding
queues, enabling mutation, or writing to the database:

```bash
scripts/unix/plan_worker_rollout.sh
```

```powershell
.\scripts\windows\plan_worker_rollout.ps1
```

The plan keeps all commands pointed at the LALA-next Key Vault, rejects ONMU
vault targets, and treats Azure Functions, Event Hub, idempotency, poison
handling, alerts, and rollback ownership as approval gates.

To review the local-value recommendation score batch without connecting to a
database:

```bash
scripts/unix/plan_place_score_batch.sh
```

```powershell
.\scripts\windows\plan_place_score_batch.ps1
```

Default mode is plan-only. It reports the `local-value-v1` formula, input
relations, and target table without printing `DB_DSN`. When a canonical DB has
`travel`, `economy`, `culture`, and `analytics` relations loaded, preview the
rows that would be written:

```bash
scripts/unix/plan_place_score_batch.sh --preview --limit 20
```

```powershell
.\scripts\windows\plan_place_score_batch.ps1 -Preview -Limit 20
```

Apply inserts new rows into `analytics.place_score_snapshots` and requires the
exact confirm string plus a process-local allow flag:

```bash
ALLOW_PLACE_SCORE_BATCH_APPLY=1 \
  scripts/unix/plan_place_score_batch.sh \
  --apply \
  --confirm APPLY_PLACE_SCORE_BATCH
```

```powershell
$env:ALLOW_PLACE_SCORE_BATCH_APPLY = "1"
.\scripts\windows\plan_place_score_batch.ps1 `
  -Apply `
  -Confirm APPLY_PLACE_SCORE_BATCH
```

To review TourAPI place ingestion without calling the external API or writing to
the database:

```bash
scripts/unix/plan_tour_api_ingest.sh
```

```powershell
.\scripts\windows\plan_tour_api_ingest.ps1
```

Default mode is plan-only. The source is the public-data `한국관광공사_국문
관광정보 서비스_GW` service and the default target is `travel.places`.
Preview calls TourAPI with `PUBLIC_DATA_SERVICE_KEY` but does not mutate the DB:

```bash
scripts/unix/plan_tour_api_ingest.sh --preview --rows 20
```

```powershell
.\scripts\windows\plan_tour_api_ingest.ps1 -Preview -Rows 20
```

Apply upserts TourAPI rows into `travel.places` and records an ingest hash in
`ingest.source_files`. It requires the exact confirm string plus a process-local
allow flag:

```bash
ALLOW_TOUR_API_INGEST_APPLY=1 \
  scripts/unix/plan_tour_api_ingest.sh \
  --apply \
  --confirm APPLY_TOUR_API_INGEST \
  --rows 40
```

```powershell
$env:ALLOW_TOUR_API_INGEST_APPLY = "1"
.\scripts\windows\plan_tour_api_ingest.ps1 `
  -Apply `
  -Confirm APPLY_TOUR_API_INGEST `
  -Rows 40
```

The wrapper never prints `PUBLIC_DATA_SERVICE_KEY` or `DB_DSN`.

To review KCISA culture information ingestion without calling the external API
or writing to the database:

```bash
scripts/unix/plan_culture_info_ingest.sh
```

```powershell
.\scripts\windows\plan_culture_info_ingest.ps1
```

Default mode is plan-only. The source is the public-data
`한국문화정보원_한눈에보는문화정보조회서비스` service and the default target is
`culture.events`. Preview calls KCISA with `PUBLIC_DATA_SERVICE_KEY` but does not
mutate the DB:

```bash
scripts/unix/plan_culture_info_ingest.sh --preview --sido 경기 --sigungu 수원시 --rows 20
```

```powershell
.\scripts\windows\plan_culture_info_ingest.ps1 -Preview -Sido 경기 -Sigungu 수원시 -Rows 20
```

Apply upserts KCISA rows into `culture.events` and records an ingest hash in
`ingest.source_files`. It requires the exact confirm string plus a process-local
allow flag:

```bash
ALLOW_CULTURE_INFO_INGEST_APPLY=1 \
  scripts/unix/plan_culture_info_ingest.sh \
  --apply \
  --confirm APPLY_CULTURE_INFO_INGEST \
  --sido 경기 \
  --sigungu 수원시 \
  --rows 20
```

```powershell
$env:ALLOW_CULTURE_INFO_INGEST_APPLY = "1"
.\scripts\windows\plan_culture_info_ingest.ps1 `
  -Apply `
  -Confirm APPLY_CULTURE_INFO_INGEST `
  -Sido 경기 `
  -Sigungu 수원시 `
  -Rows 20
```

The wrapper never prints `PUBLIC_DATA_SERVICE_KEY` or `DB_DSN`.

To review KOPIS performance ingestion without calling the external API or
writing to the database:

```bash
scripts/unix/plan_kopis_ingest.sh
```

```powershell
.\scripts\windows\plan_kopis_ingest.ps1
```

Default mode is plan-only. The source is the KOPIS
`공연예술통합전산망 OPEN API 공연목록 조회 서비스` and the default target is
`culture.events`. The default region is `signgucode=41` for Gyeonggi-do, and
the default date window stays within the KOPIS 31-day list-query limit. Preview
calls KOPIS with `KOPIS_API_KEY` but does not mutate the DB:

```bash
scripts/unix/plan_kopis_ingest.sh --preview --rows 20
```

```powershell
.\scripts\windows\plan_kopis_ingest.ps1 -Preview -Rows 20
```

Apply upserts KOPIS rows into `culture.events` and records an ingest hash in
`ingest.source_files`. It requires the exact confirm string plus a process-local
allow flag:

```bash
ALLOW_KOPIS_INGEST_APPLY=1 \
  scripts/unix/plan_kopis_ingest.sh \
  --apply \
  --confirm APPLY_KOPIS_INGEST \
  --rows 40
```

```powershell
$env:ALLOW_KOPIS_INGEST_APPLY = "1"
.\scripts\windows\plan_kopis_ingest.ps1 `
  -Apply `
  -Confirm APPLY_KOPIS_INGEST `
  -Rows 40
```

The wrapper never prints `KOPIS_API_KEY` or `DB_DSN`.

To review public card spending file ingestion without reading a source file or
writing to the database:

```bash
scripts/unix/plan_card_spending_file_ingest.sh
```

```powershell
.\scripts\windows\plan_card_spending_file_ingest.ps1
```

Default mode is plan-only. The supported sources are the public-data file
datasets `경기도_카드 소비 데이터` and `경기도_데이터분석 카드매출 시군구 성연령별 집계`.
Preview parses a downloaded CSV/XLSX file into the standard economy tables but
does not mutate the DB:

```bash
scripts/unix/plan_card_spending_file_ingest.sh \
  --preview \
  --file-path local-artifacts/source-data/card-spending.csv
```

```powershell
.\scripts\windows\plan_card_spending_file_ingest.ps1 `
  -Preview `
  -FilePath local-artifacts\source-data\card-spending.csv
```

Apply inserts rows into `economy.card_spending_area_monthly` and
`economy.card_spending_demographics`, after recording the source file in
`ingest.source_files`. It requires the exact confirm string plus a process-local
allow flag:

```bash
ALLOW_CARD_SPENDING_FILE_INGEST_APPLY=1 \
  scripts/unix/plan_card_spending_file_ingest.sh \
  --apply \
  --confirm APPLY_CARD_SPENDING_FILE_INGEST \
  --file-path local-artifacts/source-data/card-spending.csv
```

```powershell
$env:ALLOW_CARD_SPENDING_FILE_INGEST_APPLY = "1"
.\scripts\windows\plan_card_spending_file_ingest.ps1 `
  -Apply `
  -Confirm APPLY_CARD_SPENDING_FILE_INGEST `
  -FilePath local-artifacts\source-data\card-spending.csv
```

The wrapper never prints `DB_DSN`. If the source file only has unmapped region
codes, pass `--region-map <path>` or `-RegionMap <path>` with a CSV/XLSX mapping
that contains code/name columns.

To export the Flutter handoff schema without running a server, run:

```bash
scripts/unix/export_openapi.sh --in-process
```

```powershell
.\scripts\windows\export_openapi.ps1 -InProcess
```

The schema is written under `artifacts/openapi/`, which is a local handoff
artifact path and is ignored by git. Omit `-Python` locally unless you need to
override the interpreter; the wrapper prefers `.venv\Scripts\python.exe` when it
exists.

To compare the current schema against a previous Flutter handoff snapshot:

```bash
scripts/unix/export_openapi.sh --check-compat artifacts/openapi/lala-next-openapi.json
```

The check is non-destructive and treats additive metadata, such as new OpenAPI
security schemes, as compatible.

To verify the reference Flutter client with Dart SDK tooling:

```bash
scripts/unix/verify_flutter_client.sh --require-dart
```

```powershell
.\scripts\windows\verify_flutter_client.ps1 -RequireDart
```

Without the required flag, these wrappers skip cleanly when Dart is not
installed. `verify_repo` still runs the Python OpenAPI/client contract check in
all environments.

To verify the Flutter app in a real browser on macOS/Linux:

```bash
scripts/unix/smoke_flutter_web.sh --require-flutter --require-browser --port 8099
```

To include a temporary local skeleton API and authenticated route checks:

```bash
scripts/unix/smoke_flutter_web.sh \
  --require-flutter \
  --require-browser \
  --start-api \
  --fail-on-console-error \
  --port 8099 \
  --api-port 18080
```

```powershell
.\scripts\windows\smoke_flutter_web.ps1 `
  -RequireFlutter `
  -RequireBrowser `
  -StartApi `
  -FailOnConsoleError `
  -Port 8099 `
  -ApiPort 18080
```

This optional smoke requires Flutter, `npx`, and the local Playwright CLI
wrapper. It is intentionally outside CI. The script builds the web bundle with
`--no-wasm-dry-run`, serves it on the selected loopback port, opens it in a
named Playwright session, validates the Flutter runtime entrypoint, and writes
snapshot, screenshot, console, and runtime-state artifacts under
`output/playwright/`. When no API is running, a refused `/healthz` console entry
is expected and the smoke still passes because it is a render check. Pass
`--api-base-url <url>` for a separately running backend, and add
`--fail-on-console-error` when the backend is expected to satisfy all public
browser requests. With `--start-api`, the wrapper starts a local skeleton API
with process-local auth and CORS, avoids Key Vault, DB, OpenAI, and Speech, and
checks the API log for `/healthz`, `/readyz`, and the authenticated `/api/v1/*`
routes loaded by the app shell.

To review alert and dashboard candidates without creating observability
resources:

```bash
scripts/unix/plan_observability.sh
```

```powershell
.\scripts\windows\plan_observability.ps1
```

For the signal inventory and approval gate, see
`docs/operations/observability-plan.md`.

To review OAuth/Entra identity rollout candidates without creating app
registrations, Key Vault secrets, or token validators:

```bash
scripts/unix/plan_identity_rollout.sh
```

```powershell
.\scripts\windows\plan_identity_rollout.ps1
```

The plan keeps LALA-next pointed at `lala-next-kv-27db5e`, rejects ONMU vault
targets, and treats static auth retirement as blocked until API JWT validation
and Flutter token acquisition are verified together. For details, see
`docs/operations/identity-rollout.md`.

To review whether any ONMU Key Vault values are safe to reuse without reading,
printing, copying, or setting secret values:

```bash
scripts/unix/plan_key_vault_reuse.sh
```

```powershell
.\scripts\windows\plan_key_vault_reuse.ps1
```

The current approved-shape candidate is ONMU `int-cors-origins` copied into the
LALA vault as `cors-allow-origins`. DB, OAuth/social-provider, storage, Redis,
API token, OpenAI, and Speech values remain rejected for LALA runtime wiring.
For details, see `docs/operations/key-vault-reuse.md`.

To review legacy Flask replacement or retirement candidates without deleting
routes or changing deployments:

```bash
scripts/unix/plan_legacy_retirement.sh
```

```powershell
.\scripts\windows\plan_legacy_retirement.ps1
```

The plan maps legacy `/api/*`, `/api/ios/v1/*`, and `/api/planner/*` mobile
surfaces to `/api/v1/*`, keeps web/dashboard/action-log surfaces behind explicit
owner inventory, and requires rollback approval before any route removal. For
details, see `docs/migration/legacy-flask-retirement.md`.

To review local-only dev seed/reset SQL without touching a database:

```bash
scripts/unix/plan_dev_reset.sh
```

```powershell
.\scripts\windows\plan_dev_reset.ps1
```

Default mode is dry-run plan only. It reports file order, statement counts, and
SHA-256 hashes without connecting to PostgreSQL or printing `DB_DSN`.

Local dev apply is intentionally narrower than canonical SQL apply. It refuses
any `DB_DSN` whose host is not explicitly `localhost`, `127.0.0.1`, or `::1`,
and it requires the exact confirm string plus a process-local allow flag:

```bash
ALLOW_DEV_RESET_APPLY=1 \
  scripts/unix/plan_dev_reset.sh \
  --apply \
  --confirm APPLY_DEV_RESET_SQL
```

```powershell
$env:ALLOW_DEV_RESET_APPLY = "1"
.\scripts\windows\plan_dev_reset.ps1 `
  -Apply `
  -Confirm APPLY_DEV_RESET_SQL
```

Do not use `sql/dev_reset` against Azure, shared, or production-like
PostgreSQL. Live DB rollout still starts with `verify_db_resources` and the
canonical SQL review/apply path.

Before any live DB apply, verify Azure-side database readiness:

```bash
scripts/unix/plan_db_rollout.sh
```

```powershell
.\scripts\windows\plan_db_rollout.ps1
```

The rollout plan is non-mutating. It shows proposed Azure CLI commands,
canonical SQL hashes, and approval gates without creating resources, applying
SQL, or printing secret values.

```bash
scripts/unix/verify_db_resources.sh
```

```powershell
.\scripts\windows\verify_db_resources.ps1
```

The strict form uses `-RequireDatabase` and fails when the PostgreSQL Flexible
Server, database, required extension allowlist, or Key Vault `db-dsn` secret
name is missing.

`docents/script` reads non-expired rows from `travel.docent_scripts` before
calling Azure OpenAI. Successful live Azure OpenAI scripts are written back to
that cache on a best-effort basis. A cache write failure emits a warning log
without logging the generated script body, but it does not fail the Wave 1 API
contract.

## Manual API Smoke

Start the API:

```powershell
.\scripts\windows\start_api.ps1 -Port 8080
```

When request correlation needs a local JSONL file:

```bash
scripts/unix/start_api.sh --port 8080 --access-log-path runtime/api-access.jsonl
```

```powershell
.\scripts\windows\start_api.ps1 -Port 8080 -AccessLogPath .\runtime\api-access.jsonl
```

To inspect that local JSONL file by the request ids shown in the Flutter app
shell, without printing query strings, auth headers, request bodies, generated
content, or untrusted extra fields:

```bash
scripts/unix/inspect_access_log.sh runtime/api-access.jsonl --request-id <request-id>
```

```powershell
.\scripts\windows\inspect_access_log.ps1 `
  -Path .\runtime\api-access.jsonl `
  -RequestId <request-id>
```

Smoke the public and authenticated routes:

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl http://127.0.0.1:8080
```

`smoke_api.ps1` can use `LALA_SMOKE_BEARER_TOKEN`,
`LALA_SMOKE_API_KEY`, `API_BEARER_TOKEN`, or `IOS_API_KEY`. Prefer
`LALA_SMOKE_BEARER_TOKEN` when validating an OAuth/Entra JWT so the client token
does not get confused with the server-side static `API_BEARER_TOKEN` setting.
When `KEY_VAULT_URL` is configured and Azure CLI is authenticated, the script
attempts to load the migration API key and then the optional static bearer token
from Key Vault. It never prints secret values.
Public smoke checks include `/healthz`, `/readyz`, `/metrics`, and
`/openapi.json`.
The smoke script validates `/readyz.data.mode`, `client_identity`, and
`jwt_validation`, then prints bounded `runtime_mode=...` and `identity=...`
summaries for the handoff log.
Without `-PaidDependency`, authenticated route checks are skipped when client
auth is not available.
When browser CORS should be verified, pass an allowed origin explicitly:

```bash
scripts/unix/smoke_api.sh --base-url http://127.0.0.1:8080 --cors-origin http://localhost:3000
```

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl http://127.0.0.1:8080 -CorsOrigin http://localhost:3000
```

To smoke an already-issued OAuth/Entra JWT against an API process that has
`OAUTH_ISSUER`, `OAUTH_AUDIENCE`, `OAUTH_JWKS_URL`, and
`OAUTH_REQUIRED_SCOPES` configured:

```bash
export LALA_SMOKE_BEARER_TOKEN="<do-not-commit-or-print>"
scripts/unix/smoke_api.sh --base-url http://127.0.0.1:8080
unset LALA_SMOKE_BEARER_TOKEN
```

```powershell
$env:LALA_SMOKE_BEARER_TOKEN = "<do-not-commit-or-print>"
.\scripts\windows\smoke_api.ps1 -BaseUrl http://127.0.0.1:8080
Remove-Item Env:\LALA_SMOKE_BEARER_TOKEN
```

To prove the JWT verifier locally without real Entra, Key Vault, or Azure
network access, run the local OAuth/JWT smoke. It creates an ephemeral RSA key,
local JWKS server, temporary API process, valid JWT, and wrong-scope JWT, then
cleans them up:

```bash
scripts/unix/smoke_oauth_jwt.sh
```

```powershell
.\scripts\windows\smoke_oauth_jwt.ps1
```

The `/metrics` response includes process-local request counters plus readiness
and dependency gauges. It also exports `lala_next_runtime_mode` for the same
`/readyz.data.mode` labels. If `DB_DSN` is configured, scraping `/metrics` can
perform the same short DB readiness probe as `/readyz`.

## Azure Resource Verification

When the question is whether this repository is using the new LALA-next Azure
resources rather than the existing ONMU vault, run:

```bash
scripts/unix/verify_azure_resources.sh
```

```powershell
.\scripts\windows\verify_azure_resources.ps1
```

This check is intentionally separate from local and CI verification because it
requires Azure CLI login and live Azure read access. It prints resource names,
deployment metadata, and secret names only; it does not print secret values.

## Paid Dependency Checks

Live Azure OpenAI and Azure Speech checks are kept opt-in. Use them only when a
small paid smoke request is acceptable:

```bash
scripts/unix/start_api.sh --port 8080 --key-vault-url https://lala-next-kv-27db5e.vault.azure.net/ --enable-live-ai --enable-live-speech
```

```powershell
.\scripts\windows\start_api.ps1 -Port 8080 -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ -EnableLiveAI -EnableLiveSpeech
```

In another terminal:

```bash
scripts/unix/smoke_api.sh --base-url http://127.0.0.1:8080 --key-vault-url https://lala-next-kv-27db5e.vault.azure.net/ --paid-dependency
```

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl http://127.0.0.1:8080 -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ -PaidDependency
```

The paid smoke checks verify that `docents/script` is backed by Azure OpenAI and
that `docents/audio` returns `audio/mpeg` bytes. They do not print secret values
or generated audio content. With `-PaidDependency`, missing client auth is a
failure rather than a skipped check.

The latest controller-session live smoke evidence is recorded in
[live-azure-smoke-2026-06-11.md](live-azure-smoke-2026-06-11.md).
