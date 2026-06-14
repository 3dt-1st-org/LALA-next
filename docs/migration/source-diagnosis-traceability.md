# Source Diagnosis Traceability

This document maps the legacy diagnosis artifacts into the current LALA-next
Wave 1 implementation.

Source bundle:

```text
C:\Users\EL035\dataschool\08_First_Team_Project\3dt-1st-Project\artifacts\lala-windows-server-diagnosis-2026-06-10
```

## Imported Decisions

| Source doc | Decision carried into LALA-next | Implemented in |
|---|---|---|
| `09_fastapi_flutter_contract_design.md` | Flutter should use one versioned public API family, `/api/v1/*`, plus `/healthz` and `/readyz`. | `apps/api/app/routers/v1.py`, `apps/api/app/routers/health.py`, `docs/api/flutter-contract.md`, `clients/flutter/lib/lala_api_client.dart` |
| `09_fastapi_flutter_contract_design.md` | Migration auth keeps `X-API-Key`; LALA-next now also accepts `Authorization: Bearer` as the next client auth step. | `apps/api/app/core/auth.py`, `docs/api/flutter-contract.md` |
| `09_fastapi_flutter_contract_design.md` | JSON routes use `{ ok, data, meta, error }`, with `meta.request_id`; audio success is the exception. | `apps/api/app/core/responses.py`, `apps/api/app/routers/v1.py` |
| `09_fastapi_flutter_contract_design.md` | Azure Key Vault remains managed outside Windows and must not accidentally point at the ONMU vault. | `apps/api/app/core/key_vault.py`, `apps/api/app/tools/plan_key_vault_reuse.py`, `docs/operations/azure-resources.md`, `docs/operations/key-vault-reuse.md` |
| `10_windows_shared_backend_runbook_draft.md` | Windows owns the API edge, env injection, health/readiness, smoke, and handoff; Azure managed services stay in Azure. | `scripts/windows/start_api.ps1`, `scripts/windows/smoke_api.ps1`, `docs/operations/windows-shared-backend.md` |
| `10_windows_shared_backend_runbook_draft.md` | Paid Azure dependency checks are opt-in and separate from fast smoke. | `scripts/windows/smoke_api.ps1`, `docs/operations/verification.md` |
| `11_sql_migration_canonicalization_plan.md` | Shared SQL belongs in non-destructive `sql/canonical`; destructive reset/seed logic belongs in `sql/dev_reset`. | `sql/canonical/*.sql`, `sql/dev_reset/README.md`, `docs/migration/sql-canonicalization.md` |
| `08_future_flutter_fastapi_refactor.md` | Flask retirement is a later decision after mobile contract, consumer inventory, and rollback evidence; do not delete Flask as a Flutter prerequisite. | `apps/api/app/tools/plan_legacy_retirement.py`, `docs/migration/legacy-flask-retirement.md` |

## Current Wave 1 State

- FastAPI route skeleton is implemented and tested.
- Azure Key Vault, Azure OpenAI, and Azure Speech are configured as managed
  dependencies.
- LALA-next runtime remains restricted to the LALA-next Key Vault host. The only
  ONMU-vault value intentionally mirrored into LALA-next is the optional
  `cors-allow-origins` setting for browser-based contract checks. A non-mutating
  Key Vault reuse plan classifies `int-cors-origins` as the only current
  candidate and rejects ONMU DB, OAuth/social-provider, storage, Redis, API
  token, OpenAI, and Speech values for LALA runtime wiring.
- Live OpenAI/Speech calls are opt-in and have a paid smoke path.
- PostgreSQL-backed places, weather, planner, and docent-cache reads are wired
  behind `DB_DSN`, with deterministic skeleton fallback when DB access is absent
  or unavailable.
- Places DB reads are radius-filtered and distance-ranked in SQL; docent-cache
  reads expose approximate remaining TTL when `expires_at` is present.
- Weather DB reads prefer rows whose `location` matches the nearest canonical
  place region, then fall back to the latest available weather row.
- Canonical SQL includes `compat.*` compatibility views for legacy
  place/docent/weather handoff shapes without shadowing old table names.
- SQL canonical files have a guarded dry-run/apply tool. The default path only
  prints the sorted plan and hashes; apply mode requires explicit operator
  confirmation and an environment guard.
- DB rollout has a separate non-mutating plan command that records proposed
  Azure PostgreSQL steps, resource names, canonical SQL hashes, and approval
  gates before any resource is created.
- A reference Dart client under `clients/flutter` tracks the OpenAPI route set
  and handles bearer/API-key auth, request ids, JSON envelopes, and MP3 audio
  success responses for handoff into the later Flutter app. It also exposes
  a local auth-mode classifier for public-only, migration API-key, static
  bearer-token, and OAuth/JWT bearer-token states without decoding or printing
  tokens. Dart unit tests cover those client behaviors without live network
  calls.
- A first Flutter app shell under `apps/flutter_app` consumes that reference
  client, shows public health/readiness before auth, and loads the Wave 1
  places/weather/plan/docent panels after bearer/API-key auth is provided. It
  can also fetch docent audio metadata after an explicit user action, keeping
  live Speech costs out of automatic startup refreshes. The Flutter verifier
  now covers analyze, widget tests, and a release web build.
- Flutter-facing generation calls now expose deterministic `request_hash` and
  `cache_key` values for idempotency-aware clients without leaking raw secrets
  or audio/script payloads in logs.
- OAuth/Entra identity rollout has a non-mutating plan, readiness fields, and
  API-side signed RS256 JWT validation when issuer, audience, JWKS URL, and
  required scopes are configured. Flutter token acquisition remains separate.
- Worker/batch producer responsibilities are represented by an executable
  dry-run registry under `apps/workers`; retry, idempotency, and poison-message
  policies are contract data in the registry, while live mutation remains
  blocked until a later Azure Functions/Event Hub rollout decision.
- Observability has process-local logs, readiness gauges, metrics, and a
  non-mutating alert/dashboard plan before persistent ops resources are
  created.
- Legacy Flask replacement/removal is represented by a non-mutating retirement
  plan that maps legacy mobile routes to `/api/v1/*`, keeps web/dashboard
  surfaces behind owner inventory, and requires rollback approval before any
  removal.
- The current requirement-by-requirement completion evidence is tracked in
  `docs/migration/wave1-completion-audit.md`.

## Remaining Backlog

| Backlog item | Why it remains |
|---|---|
| DB repository depth | Current repository layer has read fallbacks, radius-ranked places, cache TTL, weather region preference, docent-cache write-back, and compatibility view baselines; live DB rollout remains separate. |
| Production identity provider | API-side signed JWT validation exists behind OAuth/Entra configuration, but Flutter token acquisition and static-auth retirement remain separate approval-gated work. |
| Compatibility views for legacy Flask route data shapes | Baseline views and guarded SQL apply tooling exist, but live DB rollout evidence and consumer migration are intentionally separate. |
| Worker/batch live execution | Dry-run contracts exist for job ids, write targets, dependencies, retry policy, idempotency policy, and poison handling; actual Azure Functions/Event Hub/Stream Analytics mutation remains a later rollout. |
| Flutter app hardening | The reference Dart API client and first app shell exist; production routing, persisted secure token storage, packaging, and platform distribution remain outside Wave 1. |
| Legacy Flask route removal | A non-mutating retirement plan exists, but real removal waits for web/dashboard/action-log owner inventory, client migration evidence, and rollback approval. |
