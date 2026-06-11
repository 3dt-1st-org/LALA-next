# FastAPI and Flutter Contract Migration

Wave 1 creates a new FastAPI public edge instead of copying the legacy Flask route layout.

Decisions:

- Flutter will target `/api/v1/*`.
- Legacy Flask routes are not removed in this wave.
- `/healthz` and `/readyz` are operational endpoints and do not require client auth.
- `/api/v1/*` requires `X-API-Key` during migration.
- JSON responses use `{ ok, data, meta, error }`.
- Audio success returns `audio/mpeg`; audio errors return JSON envelope.

Implemented Wave 1 boundaries:

- FastAPI owns the public API edge and request/response contract.
- Azure Key Vault is used as the secret source when `KEY_VAULT_URL` is set.
- Azure OpenAI and Azure Speech are live-capable but explicitly opt-in with
  `LALA_ENABLE_LIVE_AI=true` and `LALA_ENABLE_LIVE_SPEECH=true`.
- Places, weather, planner, and docent-cache services use PostgreSQL-backed
  repository reads when `DB_DSN` is configured and the canonical schema is
  available, then fall back to deterministic skeleton adapters.
- Flutter can build against `docs/api/flutter-contract.md` without waiting for
  the Flutter app repository structure.

Next migration boundary:

- Deepen PostgreSQL-backed repository functions with exact ranking, freshness,
  and compatibility views.
- Keep docent-cache write-back best-effort until shared DB migration ownership is
  formally assigned.
- Introduce production mobile auth after the shared Windows backend workflow is
  stable.
- Keep live Azure dependencies behind mockable service functions so tests stay
  deterministic.

The source diagnosis lives in the legacy repository at:

```text
C:\Users\EL035\dataschool\08_First_Team_Project\3dt-1st-Project\artifacts\lala-windows-server-diagnosis-2026-06-10
```
