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
| `09_fastapi_flutter_contract_design.md` | Flutter should use one versioned public API family, `/api/v1/*`, plus `/healthz` and `/readyz`. | `apps/api/app/routers/v1.py`, `apps/api/app/routers/health.py`, `docs/api/flutter-contract.md` |
| `09_fastapi_flutter_contract_design.md` | Migration auth keeps `X-API-Key` while production bearer auth remains a later wave. | `apps/api/app/core/auth.py`, `docs/api/flutter-contract.md` |
| `09_fastapi_flutter_contract_design.md` | JSON routes use `{ ok, data, meta, error }`, with `meta.request_id`; audio success is the exception. | `apps/api/app/core/responses.py`, `apps/api/app/routers/v1.py` |
| `09_fastapi_flutter_contract_design.md` | Azure Key Vault remains managed outside Windows and must not accidentally point at the ONMU vault. | `apps/api/app/core/key_vault.py`, `docs/operations/azure-resources.md` |
| `10_windows_shared_backend_runbook_draft.md` | Windows owns the API edge, env injection, health/readiness, smoke, and handoff; Azure managed services stay in Azure. | `scripts/windows/start_api.ps1`, `scripts/windows/smoke_api.ps1`, `docs/operations/windows-shared-backend.md` |
| `10_windows_shared_backend_runbook_draft.md` | Paid Azure dependency checks are opt-in and separate from fast smoke. | `scripts/windows/smoke_api.ps1`, `docs/operations/verification.md` |
| `11_sql_migration_canonicalization_plan.md` | Shared SQL belongs in non-destructive `sql/canonical`; destructive reset/seed logic belongs in `sql/dev_reset`. | `sql/canonical/*.sql`, `sql/dev_reset/README.md`, `docs/migration/sql-canonicalization.md` |

## Current Wave 1 State

- FastAPI route skeleton is implemented and tested.
- Azure Key Vault, Azure OpenAI, and Azure Speech are configured as managed
  dependencies.
- Live OpenAI/Speech calls are opt-in and have a paid smoke path.
- PostgreSQL-backed places, weather, planner, and cache reads are not yet wired;
  deterministic service adapters hold the Flutter-facing contract stable.
- SQL canonical files are a review baseline only. No live DB migration has been
  executed from this repository.

## Remaining Backlog

| Backlog item | Why it remains |
|---|---|
| DB repository layer for places/weather/planner/docent cache | Wave 1 froze the API contract before touching live DB behavior. |
| Production mobile auth | Static `IOS_API_KEY` is acceptable only for the migration window. |
| Compatibility views for legacy Flask route data shapes | Not needed until FastAPI reads from the shared PostgreSQL schema. |
| Worker/batch boundary implementation | Azure Functions/Event Hub/Stream Analytics remain external producer systems. |
| Flutter app implementation | Explicitly out of scope for Wave 1. |
