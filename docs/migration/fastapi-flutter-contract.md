# FastAPI and Flutter Contract Migration

Wave 1 creates a new FastAPI public edge instead of copying the legacy Flask route layout.

Decisions:

- Flutter will target `/api/v1/*`.
- Legacy Flask routes are not removed in this wave.
- `/healthz` and `/readyz` are operational endpoints and do not require client auth.
- `/api/v1/*` accepts `Authorization: Bearer <token>` for new clients and
  `X-API-Key` during migration.
- Static migration credentials are normalized, bounded, constant-time compared,
  and excluded from logs/metrics. Signed OAuth/Entra JWT validation is available
  when issuer, audience, JWKS URL, and required scopes are configured.
- JSON responses use `{ ok, data, meta, error }`.
- Audio success returns `audio/mpeg`; audio errors return JSON envelope.

Implemented Wave 1 boundaries:

- FastAPI owns the public API edge and request/response contract.
- Azure Key Vault is used as the secret source when `KEY_VAULT_URL` is set.
- Azure OpenAI and Azure Speech are live-capable but explicitly opt-in with
  `LALA_ENABLE_LIVE_AI=true` and `LALA_ENABLE_LIVE_SPEECH=true`.
- Places, weather, planner, and docent-cache services use PostgreSQL-backed
  repository reads when `DB_DSN` is configured and the canonical schema is
  available, then fall back to deterministic skeleton adapters. Places DB reads
  are radius-filtered and distance-ranked in SQL; docent-cache hits expose
  approximate remaining TTL. Weather DB reads prefer the nearest canonical
  region when a matching weather location exists.
- Canonical SQL includes read-only `compat.*` compatibility views for
  legacy place, docent-cache, and weather handoff shapes.
- Flutter can build against `docs/api/flutter-contract.md` without waiting for
  the Flutter app repository structure.
- `clients/flutter/lib/lala_api_client.dart` provides a checked reference Dart
  client for `/api/v1/*` and exposes `LalaAuthMode` so the app can distinguish
  public-only, migration API-key, static bearer-token, and OAuth/JWT
  bearer-token states without decoding tokens; it is not a full app shell or
  state-management layer.

Next migration boundary:

- Roll out compatibility views to a live dev database only after DB ownership is
  assigned.
- Keep docent-cache write-back best-effort until shared DB migration ownership is
  formally assigned.
- Add Flutter token acquisition for the configured OAuth/Entra identity
  provider, then retire static bearer/API-key credentials after rollback is
  approved.
- Keep live Azure dependencies behind mockable service functions so tests stay
  deterministic.

The source diagnosis lives in the legacy repository at:

```text
C:\Users\EL035\dataschool\08_First_Team_Project\3dt-1st-Project\artifacts\lala-windows-server-diagnosis-2026-06-10
```
