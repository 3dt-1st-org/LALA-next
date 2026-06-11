# LALA-next

LALA-next is the migration skeleton for the next LALA backend. Wave 1 focuses on a FastAPI public API edge that Flutter can use later, while keeping Azure OpenAI, Azure Speech, Azure Key Vault, Azure Functions, Event Hub, Stream Analytics, Power BI, and PostgreSQL/PostGIS/pgvector as managed dependencies.

This repository intentionally starts as a migration skeleton instead of a full copy of the legacy LALA repository.

## Wave 1 Scope

- FastAPI public API edge under `apps/api`.
- Flutter-facing `/api/v1/*` contract.
- PostgreSQL-backed read/cache hooks, docent cache write-back, and skeleton fallback.
- Windows shared backend start and smoke scripts.
- Canonical SQL and compatibility view baseline for future migration review.
- Documentation for Flutter handoff and Windows operations.

Out of scope for Wave 1:

- Building the Flutter app.
- Removing or replacing the legacy Flask app.
- Running live DB migrations.
- Moving Azure managed resources into Windows.

## Quick Start

```powershell
cd C:\Users\EL035\dataschool\LALA-next
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e ".[dev]"
Copy-Item .env.example .env
$env:IOS_API_KEY = "local-dev-key"
python -m uvicorn apps.api.app.main:app --host 0.0.0.0 --port 8080 --no-access-log
```

Smoke check:

```powershell
Invoke-RestMethod http://127.0.0.1:8080/healthz
Invoke-RestMethod http://127.0.0.1:8080/readyz
```

Run tests:

```powershell
python -m pytest apps/api/tests
```

Run the full local verification pass:

```powershell
.\scripts\windows\verify_repo.ps1 -SkipInstall
```

## API Contract

See [docs/api/flutter-contract.md](docs/api/flutter-contract.md).
For generated schema handoff, see [docs/api/openapi-usage.md](docs/api/openapi-usage.md).
For the client handoff checklist, see [docs/api/flutter-handoff-checklist.md](docs/api/flutter-handoff-checklist.md).

Wave 1 routes:

- `GET /healthz`
- `GET /readyz`
- `GET /api/v1/places`
- `GET /api/v1/weather`
- `POST /api/v1/docents/script`
- `POST /api/v1/docents/audio`
- `POST /api/v1/plans/daily`
- `GET /api/v1/plans/intervention`

Client auth accepts either `Authorization: Bearer <token>` from
`API_BEARER_TOKEN` or the migration `X-API-Key` header from `IOS_API_KEY`.

## Azure Resources

Wave 1 resources were created in resource group `3dt-final-team1`:

- Key Vault: `lala-next-kv-27db5e`
- Azure OpenAI account: `lala-next-aoai-27db5e`
- Azure OpenAI deployment: `gpt-4o-mini`
- Azure Speech account: `lala-next-speech-27db5e`

Use `KEY_VAULT_URL=https://lala-next-kv-27db5e.vault.azure.net/` for this repository. The ONMU vault `onmu-dev-kv-27db5e` is in the same resource group, but LALA-next does not use it. The API allowlists the LALA-next vault host and ignores other Key Vault URLs.

Live Azure calls are opt-in. Start the API with `.\scripts\windows\start_api.ps1 -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ -EnableLiveAI -EnableLiveSpeech` and run `.\scripts\windows\smoke_api.ps1 -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ -PaidDependency` when a small paid OpenAI/Speech smoke check is acceptable.

See [docs/operations/azure-resources.md](docs/operations/azure-resources.md).

## Verification

See [docs/operations/verification.md](docs/operations/verification.md).

## Migration Status

See [docs/migration/wave1-completion-audit.md](docs/migration/wave1-completion-audit.md)
for the current Wave 1 requirement-by-requirement completion audit.
