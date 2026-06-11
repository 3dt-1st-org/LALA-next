# Wave 1 Completion Audit

Audit date: 2026-06-11

Verified implementation head before this audit document was added:

```text
a7f67af Verify canonical DB relations in readiness
```

Latest CI evidence:

```text
CI run: https://github.com/3dt-1st-org/LALA-next/actions/runs/27321591131
Job: API tests and safety contracts
Result: success
```

## Scope

Wave 1 is a migration skeleton for the LALA-next shared backend. It does not
replace the legacy Flask app, does not build the Flutter app, and does not run
live DB migrations. It does establish the FastAPI edge, Flutter-facing API
contract, Windows shared backend operations, canonical SQL baseline, and managed
Azure dependency handoff.

## Requirement Status

| Requirement | Status | Evidence |
|---|---|---|
| Bootstrap `C:\Users\EL035\dataschool\LALA-next` from `https://github.com/3dt-1st-org/LALA-next.git` | Done | `git remote -v`, pushed `main` history |
| Keep legacy LALA repo read-only | Done | Only `LALA-next` files are tracked in this repository |
| FastAPI app under `apps/api` | Done | `apps/api/app/main.py`, `apps/api/app/routers/*` |
| Public `/healthz` and `/readyz` | Done | `apps/api/app/routers/health.py`, `apps/api/tests/test_health_auth.py` |
| `/api/v1/*` guarded by `X-API-Key` | Done | `apps/api/app/core/auth.py`, auth tests, OpenAPI test |
| `/api/v1/*` accepts `Authorization: Bearer` transition auth | Done | `apps/api/app/core/auth.py`, auth tests, OpenAPI test |
| JSON envelope with `meta.request_id` | Done | `apps/api/app/core/responses.py`, route tests |
| `docents/audio` success returns `audio/mpeg` | Done | `apps/api/app/routers/v1.py`, `apps/api/tests/test_openapi_contract.py`, route tests |
| Flutter-facing route family | Done | `apps/api/app/routers/v1.py`, `docs/api/flutter-contract.md` |
| Deterministic skeleton fallback | Done | `places_service.py`, `weather_service.py`, `planner_service.py`, `docent_service.py` |
| DB-backed reads behind `DB_DSN` | Done | `apps/api/app/services/db_repository.py`, DB repository tests |
| DB readiness checks canonical API relations | Done | `check_db_status()` verifies `v_public_places`, `realtime_weather_conditions`, `docent_cache` |
| Azure OpenAI live script path | Done | `apps/api/app/services/ai_service.py`, live smoke evidence |
| Azure Speech live audio path | Done | `apps/api/app/services/speech_service.py`, live smoke evidence |
| LALA-next-only Key Vault usage | Done | `apps/api/app/core/key_vault.py`, `scripts/windows/verify_azure_resources.ps1` |
| Existing ONMU vault not used | Done | `docs/operations/azure-resources.md`, Azure verification script |
| Canonical SQL baseline | Done | `sql/canonical/*.sql`, SQL safety tests |
| Guarded canonical SQL plan/apply tooling | Done | `apps/api/app/services/canonical_sql.py`, `scripts/windows/apply_canonical_sql.ps1`, canonical SQL tests |
| No destructive shared SQL | Done | `apps/api/tests/test_safety_contracts.py` |
| Read-only canonical DB schema verification | Done | `apps/api/app/services/db_schema.py`, `scripts/windows/verify_db_schema.ps1`, DB schema tests |
| Windows start/smoke scripts | Done | `scripts/windows/start_api.ps1`, `scripts/windows/smoke_api.ps1` |
| OpenAPI export for Flutter handoff | Done | `scripts/windows/export_openapi.ps1`, `docs/api/openapi-usage.md` |
| Configurable browser CORS | Done | `CORS_ALLOW_ORIGINS`, `apps/api/tests/test_cors.py` |
| Secret-safe request logging, duration headers, and process-local metrics | Done | `apps/api/app/core/observability.py`, `apps/api/app/core/metrics.py`, `apps/api/tests/test_observability.py` |
| Flutter handoff checklist | Done | `docs/api/flutter-handoff-checklist.md` |
| Azure resource verification | Done | `scripts/windows/verify_azure_resources.ps1` |
| Live Azure paid smoke evidence | Done | `docs/operations/live-azure-smoke-2026-06-11.md` |
| CI for tests and PowerShell parser | Done | `.github/workflows/ci.yml`, latest CI success |

## Verification Commands

Controller-session local verification:

```powershell
python -m pytest apps/api/tests
.\scripts\windows\verify_repo.ps1 -SkipInstall
.\scripts\windows\apply_canonical_sql.ps1
.\scripts\windows\verify_db_schema.ps1
.\scripts\windows\verify_azure_resources.ps1
```

Observed latest local result before this audit:

```text
46 passed
PowerShell parser pass
LALA-next Azure resource verification completed
```

`verify_db_schema.ps1` is expected to return non-zero when `DB_DSN` is absent or
when a target DB is missing canonical objects. That result is a rollout guard,
not a CI failure. The script never prints `DB_DSN`.
`apply_canonical_sql.ps1` defaults to a no-DB dry-run plan. Apply mode requires
`-Apply`, `-Confirm APPLY_CANONICAL_SQL`, and
`ALLOW_CANONICAL_SQL_APPLY=1`.

Live paid dependency smoke was run with:

```powershell
.\scripts\windows\start_api.ps1 `
  -Port 8093 `
  -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ `
  -EnableLiveAI `
  -EnableLiveSpeech

.\scripts\windows\smoke_api.ps1 `
  -BaseUrl http://127.0.0.1:8093 `
  -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ `
  -PaidDependency
```

Observed result:

```text
Azure OpenAI-backed docent script path passed.
Azure Speech audio path returned audio/mpeg bytes.
No LALA-next uvicorn process remained after cleanup.
```

## Known Non-Wave-1 Work

These items remain intentionally outside Wave 1 and should not be treated as
missing from this migration skeleton:

- Flutter app implementation.
- Final OAuth/Entra-style identity model.
- Unguarded live DB migration execution against Azure PostgreSQL.
- Full worker/batch rewrite for Azure Functions, Event Hub, and Stream
  Analytics producers.
- Observability dashboards and persistent runtime log aggregation beyond the
  current in-process metrics surface.
- Replacing or removing the legacy Flask application.

## Next Decision Gate

The next implementation wave should pick one of these lanes explicitly:

- Flutter app integration against the `/api/v1/*` contract.
- Final OAuth/Entra-style client identity model.
- Live DB rollout and seed/migration procedure beyond the current guarded
  canonical SQL apply path.
- Worker/batch boundary implementation.
- Observability and operations hardening.
