# Wave 1 Completion Audit

Audit date: 2026-06-11

Verified implementation head for this audit:

```text
0610101 Add in-process OpenAPI export
```

Latest CI evidence:

```text
CI run: https://github.com/3dt-1st-org/LALA-next/actions/runs/27324991266
Job: API tests and safety contracts
Result: success
```

## Scope

Wave 1 is a migration skeleton for the LALA-next shared backend. It does not
replace the legacy Flask app, does not finish production Flutter auth/storage,
and does not run live DB migrations. It does establish the FastAPI edge,
Flutter-facing API contract, first Flutter app shell, Windows shared backend
operations, canonical SQL baseline, and managed Azure dependency handoff.

## Requirement Status

| Requirement | Status | Evidence |
|---|---|---|
| Bootstrap `C:\Users\EL035\dataschool\LALA-next` from `https://github.com/3dt-1st-org/LALA-next.git` | Done | `git remote -v`, pushed `main` history |
| Keep legacy LALA repo read-only | Done | Only `LALA-next` files are tracked in this repository |
| FastAPI app under `apps/api` | Done | `apps/api/app/main.py`, `apps/api/app/routers/*` |
| Public `/healthz` and `/readyz` | Done | `apps/api/app/routers/health.py`, `apps/api/tests/test_health_auth.py` |
| `/api/v1/*` guarded by `X-API-Key` | Done | `apps/api/app/core/auth.py`, auth tests, OpenAPI test |
| `/api/v1/*` accepts `Authorization: Bearer` transition auth | Done | `apps/api/app/core/auth.py`, auth tests, OpenAPI test |
| Signed OAuth/Entra JWT validation path | Done | `apps/api/app/core/jwt_auth.py`, OAuth JWT auth tests, local OAuth/JWT smoke, readiness/OpenAPI tests |
| Request id header hardening | Done | safe `X-Request-ID` normalization, log/echo tests |
| Static client credential hardening | Done | bounded auth headers, digest-based constant-time compare, auth edge-case tests |
| OpenAPI client-auth security schemes and error envelope responses | Done | `apps/api/app/core/openapi.py`, OpenAPI contract tests |
| OpenAPI operation auth and timeout expectations | Done | `x-lala-auth-required` and `x-lala-timeout-seconds` documented for public contract routes |
| OpenAPI response header contract | Done | `X-Request-ID` and `X-Request-Duration-Ms` documented on operation responses |
| OpenAPI success envelope contract | Done | JSON 200 responses use envelope schemas; operational and `/api/v1/*` common `data` payloads have route-specific schemas, while audio success remains binary |
| JSON envelope with `meta.request_id` | Done | `apps/api/app/core/responses.py`, route tests |
| Validation error detail redaction | Done | raw `input` values removed from 422 details, route test |
| `docents/audio` success returns `audio/mpeg` | Done | `apps/api/app/routers/v1.py`, `apps/api/tests/test_openapi_contract.py`, route tests |
| `docents/audio` OpenAPI success content | Done | 200 response documents only `audio/mpeg`; JSON remains for failures |
| Flutter-facing route family | Done | `apps/api/app/routers/v1.py`, `docs/api/flutter-contract.md` |
| Generation request identity for idempotency-aware clients | Done | `request_hash`/`cache_key` on script and daily plan JSON; `X-LALA-Request-Hash`/`X-LALA-Cache-Key` on audio success; API/OpenAPI/Dart tests |
| Daily plan coordinate validation | Done | `DailyPlanRequest` lat/lng bounds match Flutter contract and OpenAPI schema |
| Deterministic skeleton fallback | Done | `places_service.py`, `weather_service.py`, `planner_service.py`, `docent_service.py` |
| DB-backed reads behind `DB_DSN` | Done | `apps/api/app/services/db_repository.py`, DB repository tests |
| DB readiness checks canonical API relations | Done | `check_db_status()` verifies `travel.public_places`, `travel.weather_observations`, `travel.docent_scripts` |
| Azure OpenAI live script path | Done | `apps/api/app/services/ai_service.py`, live smoke evidence |
| Docent cache write failure warning | Done | best-effort cache write logs warning without script body, route test |
| Azure Speech live audio path | Done | `apps/api/app/services/speech_service.py`, live smoke evidence |
| LALA-next-only Key Vault usage | Done | `apps/api/app/core/key_vault.py`, `scripts/windows/verify_azure_resources.ps1` |
| Existing ONMU vault not used directly | Done | runtime allowlist stays LALA-only; ONMU `int-cors-origins` copied into LALA vault as optional `cors-allow-origins` |
| Key Vault backed CORS origins | Done | `cors-allow-origins` optional secret, Settings/start-wrapper preload, CORS tests |
| Canonical SQL baseline | Done | `sql/canonical/*.sql`, SQL safety tests |
| Guarded canonical SQL plan/apply tooling | Done | `apps/api/app/services/canonical_sql.py`, `scripts/windows/apply_canonical_sql.ps1`, canonical SQL tests |
| Local-only dev seed/reset plan and guarded localhost apply | Done | `sql/dev_reset/*.sql`, `apps/api/app/tools/plan_dev_reset.py`, Unix/Windows wrappers, dev reset SQL tests |
| No destructive shared SQL | Done | `apps/api/tests/test_safety_contracts.py` |
| Read-only canonical DB schema verification | Done | `apps/api/app/services/db_schema.py`, `scripts/windows/verify_db_schema.ps1`, DB schema tests |
| Windows start/smoke scripts | Done | `scripts/windows/start_api.ps1`, `scripts/windows/smoke_api.ps1` |
| OpenAPI export for Flutter handoff | Done | `apps/api/app/tools/export_openapi.py`, `scripts/windows/export_openapi.ps1`, OpenAPI export tests, `docs/api/openapi-usage.md` |
| OpenAPI snapshot compatibility check | Done | `apps/api/app/tools/check_openapi_compat.py`, `apps/api/app/services/openapi_compat.py`, compatibility tests |
| Reference Flutter client kept in sync with OpenAPI | Done | `clients/flutter/lib/lala_api_client.dart`, auth-mode classifier, typed DTO and timeout tests, `apps/api/app/tools/check_flutter_client_contract.py`, Python contract tests, Dart analyze/test |
| Flutter app shell wired to the Wave 1 client contract | Done | `apps/flutter_app/lib/main.dart`, widget tests with fake backend including static bearer/API-key/OAuth-JWT mode display, request-id correlation, and explicit docent-audio fetch, release web build, Unix/Windows `verify_flutter_app` wrappers |
| Configurable browser CORS | Done | `CORS_ALLOW_ORIGINS`, `apps/api/tests/test_cors.py` |
| Browser CORS preflight smoke | Done | `scripts/unix/smoke_api.sh --cors-origin`, `scripts/windows/smoke_api.ps1 -CorsOrigin` |
| Secret-safe request logging, optional JSONL access log, local access-log inspection, duration headers, and process-local metrics with readiness gauges | Done | `apps/api/app/core/observability.py`, `apps/api/app/services/access_log_inspector.py`, `apps/api/app/core/metrics.py`, observability and access-log inspector tests |
| Non-mutating observability alert/dashboard plan | Done | `apps/api/app/tools/plan_observability.py`, `docs/operations/observability-plan.md`, observability plan tests |
| Non-mutating OAuth/Entra identity rollout plan | Done | `apps/api/app/tools/plan_identity_rollout.py`, `docs/operations/identity-rollout.md`, identity rollout plan tests |
| Non-mutating ONMU Key Vault reuse classification | Done | `apps/api/app/tools/plan_key_vault_reuse.py`, `docs/operations/key-vault-reuse.md`, Key Vault reuse plan tests |
| Non-mutating legacy Flask replacement/retirement plan | Done | `apps/api/app/tools/plan_legacy_retirement.py`, `docs/migration/legacy-flask-retirement.md`, legacy retirement plan tests |
| Flutter handoff checklist | Done | `docs/api/flutter-handoff-checklist.md` |
| Azure resource verification | Done | `scripts/windows/verify_azure_resources.ps1` |
| Non-mutating DB rollout plan | Done | `apps/api/app/tools/plan_db_rollout.py`, `scripts/unix/plan_db_rollout.sh`, `scripts/windows/plan_db_rollout.ps1`, DB rollout plan tests |
| PostgreSQL rollout readiness verification | Done | `scripts/windows/verify_db_resources.ps1`, `docs/operations/live-db-rollout.md` |
| Live Azure paid smoke evidence | Done | `docs/operations/live-azure-smoke-2026-06-11.md` |
| CI for Windows baseline and Unix wrapper verification | Ready for push | `.github/workflows/ci.yml`, local `scripts/unix/verify_repo.sh --skip-install` pass |
| Worker/batch dry-run contracts | Done | `apps/workers/app/contracts.py`, `apps/workers/app/cli.py`, `scripts/windows/smoke_workers.ps1`, worker contract tests |
| Worker retry/idempotency/poison policy contracts | Done | `apps/workers/app/contracts.py`, `docs/operations/worker-batch-boundary.md`, worker policy tests |
| Worker live rollout preflight remains blocked and secret-safe | Done | `python -m apps.workers.app.cli preflight --json`, worker preflight tests, worker smoke wrappers |
| Non-mutating worker/batch live rollout plan | Done | `python -m apps.workers.app.cli plan-rollout --json`, Unix/Windows wrappers, worker rollout plan tests |
| Worker contract readiness surface | Done | `/readyz` and `/metrics` expose dry-run registry readiness, health tests |
| macOS/Linux local verification wrappers | Done | `scripts/unix/*.sh`, Unix script safety and parser tests |

## Verification Commands

Controller-session local verification on macOS/Linux:

```bash
uv run pytest apps/api/tests
scripts/unix/verify_repo.sh
scripts/unix/verify_azure_resources.sh
scripts/unix/verify_db_resources.sh
scripts/unix/handoff_report.sh --skip-tests
scripts/unix/plan_worker_rollout.sh
scripts/unix/plan_legacy_retirement.sh
scripts/unix/plan_dev_reset.sh
scripts/unix/smoke_flutter_web.sh --require-flutter --require-browser --port 8099
scripts/unix/smoke_flutter_web.sh --require-flutter --require-browser --start-api --fail-on-console-error --port 8099 --api-port 18080
.\scripts\windows\smoke_flutter_web.ps1 -RequireFlutter -RequireBrowser -StartApi -FailOnConsoleError -Port 8099 -ApiPort 18080
```

Controller-session local verification on Windows:

```powershell
.\scripts\windows\verify_repo.ps1
.\scripts\windows\smoke_workers.ps1
.\scripts\windows\plan_worker_rollout.ps1
.\scripts\windows\plan_legacy_retirement.ps1
.\scripts\windows\export_openapi.ps1 -InProcess
.\scripts\windows\apply_canonical_sql.ps1
.\scripts\windows\verify_db_schema.ps1
.\scripts\windows\verify_db_resources.ps1
.\scripts\windows\verify_azure_resources.ps1
.\scripts\windows\plan_dev_reset.ps1
```

Observed latest local result before this audit:

```text
75 passed
worker dry-run smoke pass
OpenAPI in-process export pass, path_count=9
PowerShell parser pass
LALA-next Azure resource verification completed
```

Observed Mac handoff result on 2026-06-11:

```text
122 passed
Unix worker dry-run smoke pass
Worker live preflight pass with ready=false
Worker rollout plan pass; no Functions/Event Hub/queue/Key Vault/DB changes created
Unix OpenAPI in-process export pass, path_count=9
OpenAPI compatibility pass against USB handoff snapshot
Reference Flutter client contract check pass, checked_route_count=8
Reference Flutter client Dart analyze/test pass when Dart SDK is available, including public health/readiness mode checks
Flutter app shell analyze/widget-test/web-build pass when Flutter SDK is available, including partial authenticated-load failure handling and explicit docent-audio fetch without automatic paid Speech calls
Local OAuth/JWT smoke pass with ephemeral RSA key, local JWKS server, valid JWT, and wrong-scope rejection
Flutter web smoke against local skeleton API pass with CORS_ALLOW_ORIGINS=http://127.0.0.1:8099
Generation identity contract tests pass for script, audio, and daily plan request normalization
Dev seed/reset SQL plan and localhost-only apply guard pass
Unix shell parser pass
Local API smoke pass on /healthz, /readyz, /metrics, /openapi.json, and authenticated /api/v1/* skeleton routes
Smoke validates /readyz runtime_mode output
Metrics readiness/runtime-mode gauges pass; /openapi.json is exported as a fixed metrics path label
Optional JSONL access log pass with bounded route fields and no query/auth values
Observability plan pass; no dashboard or alert resources created
Identity rollout plan pass; no Entra apps, Key Vault secrets, or Flutter tokens created
Legacy Flask retirement plan pass; no routes deleted and no deployment changes created
LALA-next Azure resource verification completed
DB rollout not ready: missing db-dsn and PostgreSQL Flexible Server
DB rollout plan pass; no Azure resources created
Unix handoff report pass
CI workflow YAML parse pass; Ubuntu Unix-wrapper job added locally and ready for push
```

Observed Mac browser render smoke on 2026-06-12:

```text
scripts/unix/smoke_flutter_web.sh --require-flutter --require-browser --port 8099
Flutter web browser smoke completed.
Runtime state: title=LALA Next, hasFlutterEntrypoint=true, readyState=complete
Screenshot verified as non-blank local app render.
Console captured expected API-offline /healthz connection refusal.
No 8099 server or Playwright session remained after cleanup.
```

Observed Mac browser plus local skeleton API smoke on 2026-06-12:

```text
scripts/unix/smoke_flutter_web.sh --require-flutter --require-browser --start-api --fail-on-console-error --port 8099 --api-port 18080
Flutter web browser smoke completed.
Runtime state: title=LALA Next, hasFlutterEntrypoint=true, readyState=complete
Console: 0 errors, 0 warnings
Screenshot verified as authenticated skeleton app render.
Local API log observed /healthz, /readyz, /api/v1/places, /api/v1/weather,
/api/v1/plans/intervention, /api/v1/plans/daily, and /api/v1/docents/script.
No 8099 web server, 18080 API server, or Playwright session remained after cleanup.
```

Windows browser-smoke parity is implemented as
`scripts/windows/smoke_flutter_web.ps1`. It follows the same local-only skeleton
API constraints as the Unix wrapper, but it was not executed on the Mac
controller because PowerShell is not installed in this environment.

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

- Production Flutter routing, persisted secure token storage, release packaging,
  and platform-specific distribution.
- Flutter token acquisition and static-auth retirement.
- Unguarded live DB migration execution against Azure PostgreSQL.
- PostgreSQL Flexible Server provisioning and `db-dsn` secret creation.
- Live worker/batch mutation for Azure Functions, Event Hub, and Stream
  Analytics producers.
- Observability dashboards and persistent runtime log aggregation beyond the
  current in-process metrics and readiness gauge surface.
- Replacing or removing the legacy Flask application.

## Next Decision Gate

The next implementation wave should pick one of these lanes explicitly:

- Production Flutter hardening beyond the current app shell and `/api/v1/*`
  integration.
- Flutter client token acquisition and static-auth retirement.
- Live DB rollout and seed/migration procedure beyond the current guarded
  canonical SQL apply path.
- Worker/batch live execution and Azure producer wiring.
- Observability and operations hardening.
