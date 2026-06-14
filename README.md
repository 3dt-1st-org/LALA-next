# LALA-next

LALA-next is the migration skeleton for the next LALA backend. Wave 1 focuses on a FastAPI public API edge that Flutter can use later, while keeping Azure OpenAI, Azure Speech, Azure Key Vault, Azure Functions, Event Hub, Stream Analytics, Power BI, and PostgreSQL/PostGIS/pgvector as managed dependencies.

This repository intentionally starts as a migration skeleton instead of a full copy of the legacy LALA repository.

## Wave 1 Scope

- FastAPI public API edge under `apps/api`.
- Flutter-facing `/api/v1/*` contract.
- PostgreSQL-backed read/cache hooks, docent cache write-back, and skeleton fallback.
- Windows shared backend start and smoke scripts.
- Canonical SQL, compatibility views, and guarded SQL plan/apply tooling.
- Worker/batch dry-run contracts for producer boundaries.
- Documentation, a reference Dart client, and a Flutter app shell for handoff.
- Windows and macOS/Linux verification wrappers.

Out of scope for Wave 1:

- Production Flutter auth/storage, app-store packaging, and release hardening.
- Removing or replacing the legacy Flask app.
- Running unguarded live DB migrations.
- Moving Azure managed resources into Windows.

## Quick Start

Mac/Linux:

```bash
uv sync --extra dev
cp .env.example .env
export IOS_API_KEY="local-dev-key"
scripts/unix/start_api.sh --port 8080
```

Add `--access-log-path runtime/api-access.jsonl` when a shared backend operator
needs local JSONL request correlation during a handoff.

Mac/Linux smoke check:

```bash
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS http://127.0.0.1:8080/readyz
```

Review the local PostgreSQL MVP bootstrap plan:

```bash
scripts/unix/bootstrap_local_mvp_db.sh
```

To execute the local DB pipeline, set `LALA_POSTGRES_PASSWORD` in your shell or
`.env`, then run the guarded local-only flow:

```bash
scripts/unix/bootstrap_local_mvp_db.sh --all
```

That starts `compose.local.yml`, applies canonical SQL, loads local demo seed
data, computes `local-value-v1` score snapshots, and refreshes the bundled
public MVP snapshot. The script builds a localhost `DB_DSN` internally and never
prints it.

Run the full local verification pass:

```bash
scripts/unix/verify_repo.sh
```

Generate a Mac handoff status report:

```bash
scripts/unix/handoff_report.sh
```

Windows:

```powershell
cd C:\Users\EL035\dataschool\LALA-next
uv sync --extra dev
Copy-Item .env.example .env
$env:IOS_API_KEY = "local-dev-key"
uv run python -m uvicorn apps.api.app.main:app --host 0.0.0.0 --port 8080 --no-access-log
```

Smoke check:

```powershell
Invoke-RestMethod http://127.0.0.1:8080/healthz
Invoke-RestMethod http://127.0.0.1:8080/readyz
```

Run tests:

```powershell
uv run pytest apps/api/tests
```

Run the full local verification pass:

```powershell
.\scripts\windows\verify_repo.ps1
```

Review the canonical SQL rollout plan without touching a database:

```powershell
.\scripts\windows\apply_canonical_sql.ps1
```

Review local-only dev seed/reset SQL without touching a database:

```bash
scripts/unix/plan_dev_reset.sh
```

```powershell
.\scripts\windows\plan_dev_reset.ps1
```

Apply is available only for an explicit localhost `DB_DSN` after the canonical
schema exists:

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

Review the local-value place score batch without touching a database:

```bash
scripts/unix/plan_place_score_batch.sh
```

```powershell
.\scripts\windows\plan_place_score_batch.ps1
```

Review Azure OpenAI place enrichment without touching a database or calling AI:

```bash
scripts/unix/plan_place_ai_enrichment.sh
```

```powershell
.\scripts\windows\plan_place_ai_enrichment.ps1
```

After canonical places are loaded, use dry-run AI to preview English names,
English addresses, region labels, and indoor/outdoor classification without
updating rows:

```bash
scripts/unix/plan_place_ai_enrichment.sh --dry-run-ai --limit 20
```

Apply requires an explicit guard because it calls Azure OpenAI and updates
`travel.places` plus `travel.place_enrichments`:

```bash
ALLOW_AI_PLACE_ENRICHMENT_APPLY=1 \
  scripts/unix/plan_place_ai_enrichment.sh \
  --apply \
  --confirm APPLY_AI_PLACE_ENRICHMENT
```

After canonical SQL and local seed data are loaded, preview score snapshots:

```bash
scripts/unix/plan_place_score_batch.sh --preview --limit 20
```

Review the public MVP snapshot export without connecting to a database:

```bash
scripts/unix/export_public_mvp_snapshot.sh
```

After score snapshots exist in the canonical DB, preview the bundled fallback
payload that Vercel can serve without `DB_DSN`:

```bash
scripts/unix/export_public_mvp_snapshot.sh --preview --limit 20
```

Writing `apps/api/app/data/public_mvp_places.json` is a local file mutation and
requires an explicit guard:

```bash
ALLOW_PUBLIC_MVP_SNAPSHOT_WRITE=1 \
  scripts/unix/export_public_mvp_snapshot.sh \
  --write \
  --confirm WRITE_PUBLIC_MVP_SNAPSHOT
```

Review TourAPI place ingestion without external calls or DB writes:

```bash
scripts/unix/plan_tour_api_ingest.sh
```

After `PUBLIC_DATA_SERVICE_KEY` and `DB_DSN` are configured, preview official
TourAPI rows:

```bash
scripts/unix/plan_tour_api_ingest.sh --preview --rows 20
```

Check whether Azure PostgreSQL rollout prerequisites exist:

```bash
scripts/unix/plan_db_rollout.sh
```

```powershell
.\scripts\windows\plan_db_rollout.ps1
```

```bash
scripts/unix/verify_db_resources.sh
```

```powershell
.\scripts\windows\verify_db_resources.ps1
```

Review the OAuth/Entra identity rollout plan without creating app
registrations, Key Vault secrets, or token validators:

```bash
scripts/unix/plan_identity_rollout.sh
```

```powershell
.\scripts\windows\plan_identity_rollout.ps1
```

Review whether any ONMU Key Vault values are safe to reuse without reading,
printing, copying, or setting secret values:

```bash
scripts/unix/plan_key_vault_reuse.sh
```

```powershell
.\scripts\windows\plan_key_vault_reuse.ps1
```

Run a local-only OAuth/JWT end-to-end smoke without real Entra or Key Vault:

```bash
scripts/unix/smoke_oauth_jwt.sh
```

```powershell
.\scripts\windows\smoke_oauth_jwt.ps1
```

Review the legacy Flask replacement or retirement plan without deleting routes
or changing deployments:

```bash
scripts/unix/plan_legacy_retirement.sh
```

```powershell
.\scripts\windows\plan_legacy_retirement.ps1
```

Dry-run the worker/batch contracts and confirm live worker preflight remains
blocked without external writes:

```bash
scripts/unix/smoke_workers.sh
```

```powershell
.\scripts\windows\smoke_workers.ps1
```

Review worker/batch live rollout gates without creating Azure Functions, Event
Hub, queue, Key Vault, or DB writes:

```bash
scripts/unix/plan_worker_rollout.sh
```

```powershell
.\scripts\windows\plan_worker_rollout.ps1
```

## API Contract

See [docs/api/flutter-contract.md](docs/api/flutter-contract.md).
For generated schema handoff, see [docs/api/openapi-usage.md](docs/api/openapi-usage.md).
For the client handoff checklist, see [docs/api/flutter-handoff-checklist.md](docs/api/flutter-handoff-checklist.md).
For a reference Dart client, see [clients/flutter/lib/lala_api_client.dart](clients/flutter/lib/lala_api_client.dart).
For the Flutter app shell, see [apps/flutter_app/lib/main.dart](apps/flutter_app/lib/main.dart).

When Dart is installed, verify the reference client package:

```bash
scripts/unix/verify_flutter_client.sh --require-dart
```

When Flutter is installed, verify the app shell:

```bash
scripts/unix/verify_flutter_app.sh --require-flutter
```

Wave 1 routes:

- `GET /healthz`
- `GET /readyz`
- `GET /metrics`
- `GET /api/v1/places`
- `GET /api/v1/weather`
- `POST /api/v1/docents/script`
- `POST /api/v1/docents/audio`
- `POST /api/v1/plans/daily`
- `GET /api/v1/plans/intervention`

Client auth accepts `Authorization: Bearer <token>` as either the static
transition token from `API_BEARER_TOKEN` or a signed OAuth/Entra JWT when
`OAUTH_ISSUER`, `OAUTH_AUDIENCE`, `OAUTH_JWKS_URL`, and
`OAUTH_REQUIRED_SCOPES` are configured. The migration `X-API-Key` header from
`IOS_API_KEY` remains accepted during the transition window. For local smoke
with an already-issued OAuth JWT, set `LALA_SMOKE_BEARER_TOKEN` in the smoke
shell instead of changing the server-side `API_BEARER_TOKEN`.
`/readyz` includes `data.mode` so Flutter and backend operators can distinguish
`skeleton`, `db-backed`, and opt-in `live-azure` operation without inferring it
from individual dependency checks.
Set `LALA_ACCESS_LOG_PATH` to an ignored local path such as
`runtime/api-access.jsonl` when a shared backend operator needs JSONL request
correlation. Those records contain only bounded method, route path, status,
duration, request id, and client-host fields; they omit query strings, auth
headers, request bodies, and generated content.
Inspect a local JSONL access log by request id without printing secret-bearing
fields:

```bash
scripts/unix/inspect_access_log.sh runtime/api-access.jsonl --request-id <request-id>
```

```powershell
.\scripts\windows\inspect_access_log.ps1 -Path .\runtime\api-access.jsonl -RequestId <request-id>
```

## Azure Resources

Wave 1 resources were created in resource group `3dt-final-team1`:

- Key Vault: `lala-next-kv-27db5e`
- Azure OpenAI account: `lala-next-aoai-27db5e`
- Azure OpenAI deployment: `gpt-4o-mini`
- Azure Speech account: `lala-next-speech-27db5e`

Use `KEY_VAULT_URL=https://lala-next-kv-27db5e.vault.azure.net/` for this repository. The ONMU vault `onmu-dev-kv-27db5e` is in the same resource group, but LALA-next does not use it. The API allowlists the LALA-next vault host and ignores other Key Vault URLs.
The only ONMU-derived value currently reused is the optional CORS origin list,
already copied into the LALA-next vault as `cors-allow-origins`; ONMU DB, token,
OAuth provider, Redis, and MinIO secrets are not wired into LALA-next.
Use `scripts/unix/plan_key_vault_reuse.sh` or
`.\scripts\windows\plan_key_vault_reuse.ps1` to review that boundary.

Live Azure calls are opt-in. Start the API with `.\scripts\windows\start_api.ps1 -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ -EnableLiveAI -EnableLiveSpeech` and run `.\scripts\windows\smoke_api.ps1 -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ -PaidDependency` when a small paid OpenAI/Speech smoke check is acceptable.

See [docs/operations/azure-resources.md](docs/operations/azure-resources.md).

## Verification

See [docs/operations/verification.md](docs/operations/verification.md).

Worker and batch producer boundaries are described in
[docs/operations/worker-batch-boundary.md](docs/operations/worker-batch-boundary.md).
Observability planning is described in
[docs/operations/observability-plan.md](docs/operations/observability-plan.md).
Identity rollout planning is described in
[docs/operations/identity-rollout.md](docs/operations/identity-rollout.md).

## Migration Status

See [docs/migration/wave1-completion-audit.md](docs/migration/wave1-completion-audit.md)
for the current Wave 1 requirement-by-requirement completion audit.
The legacy Flask replacement/removal decision is tracked in
[docs/migration/legacy-flask-retirement.md](docs/migration/legacy-flask-retirement.md).
