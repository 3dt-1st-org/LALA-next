# Flutter Handoff Checklist

Use this checklist when handing the shared Windows backend to a Flutter client
developer.

## Required Inputs

- Backend base URL, for example `http://<windows-host-lan-ip>:8080`.
- Client API key value for the `X-API-Key` header.
- Current git commit SHA from the backend operator.
- Whether the backend is running in skeleton, DB-backed, or live Azure demo mode.

## Public Checks

These routes do not require `X-API-Key`:

```text
GET /healthz
GET /readyz
GET /openapi.json
```

The mobile device must use the Windows host LAN IP, not `localhost`, unless the
API process is running on the same device.

## Authenticated Routes

Every `/api/v1/*` request must include:

```text
X-API-Key: <client api key>
```

Wave 1 Flutter routes:

```text
GET  /api/v1/places?lat=37.2636&lng=127.0286&radius_m=1000
GET  /api/v1/weather?lat=37.2636&lng=127.0286
POST /api/v1/docents/script
POST /api/v1/docents/audio
POST /api/v1/plans/daily
GET  /api/v1/plans/intervention?lat=37.2636&lng=127.0286&radius_m=1000
```

JSON routes return `{ ok, data, meta, error }`. Audio success from
`POST /api/v1/docents/audio` returns `audio/mpeg` bytes.

## Handoff Verification

Ask the backend operator to run:

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl "http://<host>:8080"
.\scripts\windows\export_openapi.ps1 -BaseUrl "http://<host>:8080"
```

Expected handoff artifacts:

- Smoke result: `/healthz`, `/readyz`, and `/openapi.json` pass.
- OpenAPI JSON: `artifacts/openapi/lala-next-openapi.json`.
- Human-readable contract: `docs/api/flutter-contract.md`.

## Mode Notes

- Skeleton mode is valid for UI development and deterministic contract tests.
- `DB_DSN` enables PostgreSQL-backed places, weather, planner, and docent-cache
  reads with fallback to skeleton behavior.
- `LALA_ENABLE_LIVE_AI=true` enables Azure OpenAI script generation.
- `LALA_ENABLE_LIVE_SPEECH=true` enables Azure Speech MP3 generation.
- Production bearer auth and the actual Flutter app implementation are later
  waves.
