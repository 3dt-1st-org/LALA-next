# Flutter Handoff Checklist

Use this checklist when handing the shared Windows backend to a Flutter client
developer.

## Required Inputs

- Backend base URL, for example `http://<windows-host-lan-ip>:8080`.
- Client bearer token for `Authorization: Bearer <token>` (static transition
  token or signed OAuth/Entra JWT), or migration API key value for `X-API-Key`.
- Current git commit SHA from the backend operator.
- Backend runtime mode from `/readyz.data.mode.overall`: `skeleton`,
  `public-cache`, `db-backed`, `live-azure`, or `degraded`.

## Public Checks

These routes do not require `X-API-Key`:

```text
GET /healthz
GET /readyz
GET /openapi.json
```

The mobile device must use the Windows host LAN IP, not `localhost`, unless the
API process is running on the same device.
The reference Dart client can call `getHealth()` and `getReadiness()` before
client auth is available, then switch to bearer/API-key auth for `/api/v1/*`
methods.
It exposes `LalaAuthMode` so the app shell can distinguish public-only,
migration API-key, static bearer-token, and OAuth/JWT bearer-token states
without decoding or printing the token.
It also applies bounded client-side timeouts and maps slow requests to
retryable `REQUEST_TIMEOUT` exceptions.

## Authenticated Routes

Every `/api/v1/*` request must include one of:

```text
Authorization: Bearer <client token>
```

or the migration fallback:

```text
X-API-Key: <client api key>
```

Wave 1 Flutter routes:

```text
GET  /api/v1/places?lat=37.2636&lng=127.0286&radius_m=50000
GET  /api/v1/weather?lat=37.2636&lng=127.0286
POST /api/v1/docents/script
POST /api/v1/docents/audio
POST /api/v1/plans/daily
GET  /api/v1/plans/intervention?lat=37.2636&lng=127.0286&radius_m=50000
```

JSON routes return `{ ok, data, meta, error }`. Audio success from
`POST /api/v1/docents/audio` returns `audio/mpeg` bytes.
Generation routes expose deterministic identity values for idempotency-aware
client flows: script and daily-plan JSON include `request_hash` and `cache_key`,
while audio success returns `X-LALA-Request-Hash` and `X-LALA-Cache-Key`
headers.

## Handoff Verification

Ask the backend operator to run:

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl "http://<host>:8080"
.\scripts\windows\export_openapi.ps1 -BaseUrl "http://<host>:8080"
```

If the Flutter developer is validating an OAuth/Entra JWT before full app login
is wired, ask the operator to set `LALA_SMOKE_BEARER_TOKEN` only in the smoke
shell and clear it after the check.

Expected handoff artifacts:

- Smoke result: `/healthz`, `/readyz`, and `/openapi.json` pass.
- Runtime mode: `/readyz.data.mode` matches the intended skeleton, public-cache,
  DB-backed, or live Azure handoff.
- Request correlation: the Flutter app shell shows latest public/API/audio
  request ids from response metadata or headers; use those ids with JSONL access
  logs when debugging a handoff.
- OpenAPI JSON: `artifacts/openapi/lala-next-openapi.json`.
- Human-readable contract: `docs/api/flutter-contract.md`.
- Reference Dart client: `clients/flutter/lib/lala_api_client.dart`.
- Flutter app shell: `apps/flutter_app/lib/main.dart`.

The backend repository verifies that the reference client still points at the
current OpenAPI route set:

```bash
python -m apps.api.app.tools.check_flutter_client_contract
```

When Dart is installed, the reference client also has local unit tests for auth
headers, JSON envelopes, audio bytes, and error handling:

```bash
scripts/unix/verify_flutter_client.sh --require-dart
```

When Flutter is installed, the app shell can also be checked without a live
backend because its widget tests inject a fake backend. The same verifier also
builds a release web bundle to catch browser-target compile errors:

```bash
scripts/unix/verify_flutter_app.sh --require-flutter
```

For an actual browser render smoke on macOS/Linux, run:

```bash
scripts/unix/smoke_flutter_web.sh --require-flutter --require-browser --port 8099
```

For a stronger local handoff check that does not require Azure, Key Vault, or
PostgreSQL:

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

This optional smoke is not part of CI. It uses the Playwright CLI,
captures artifacts under `output/playwright/`, and validates that the Flutter
web bundle renders. With `--start-api`, the wrapper starts a skeleton FastAPI
process, injects a temporary local migration API key at compile time, and checks
the API log for `/healthz`, `/readyz`, places, weather, intervention, daily plan,
and docent script route hits. Without `--start-api`, the app is expected to show
the offline public state when the API is not running and the console artifact
can include a refused `/healthz` request. Use `--api-base-url <url>` to point
the bundle at a separately running backend.

The app shell loads public readiness before auth, shows whether the current
client credential shape is public-only, migration API-key, static bearer-token,
or OAuth/JWT bearer-token, shows latest request ids for backend log
correlation, loads the JSON `/api/v1/*` panels after bearer/API-key auth is
provided, and can fetch docent audio metadata from
`POST /api/v1/docents/audio` after an explicit button tap. That audio action is
not automatic because live Speech-enabled backends may perform a paid Azure
Speech request. If public `/healthz` and `/readyz` succeed but an authenticated
`/api/v1/*` request fails, the shell keeps the public runtime status visible and
shows a bounded error banner for the authenticated panel load.
Use `scripts/unix/inspect_access_log.sh` or
`scripts/windows/inspect_access_log.ps1` to look up those request ids in a local
JSONL access log without exposing query strings, auth headers, request bodies,
or generated content.

## Mode Notes

- Skeleton mode is valid for UI development and deterministic contract tests.
- `DB_DSN` enables PostgreSQL-backed places, weather, planner, and docent-cache
  reads with fallback to skeleton behavior.
- Production, review, and shared dev deployments should keep
  `LALA_PUBLIC_DEMO_MODE=false`; bundled static snapshots are limited to
  offline, read-only DB-outage fallback or isolated local checks.
- `LALA_ENABLE_LIVE_AI=true` enables Azure OpenAI script generation.
- `LALA_ENABLE_LIVE_SPEECH=true` enables Azure Speech MP3 generation.
- `/readyz.data.mode.data` reports `db-backed` only after the canonical DB probe
  succeeds; live AI/Speech report `live-azure` only when explicitly enabled and
  configured.
- Production routing, persisted secure token storage, release packaging, and
  platform-specific distribution remain a later wave.
