# FastAPI and Flutter Contract Migration

Wave 1 creates a new FastAPI public edge instead of copying the legacy Flask route layout.

Decisions:

- Flutter will target `/api/v1/*`.
- Legacy Flask routes are not removed in this wave.
- `/healthz` and `/readyz` are operational endpoints and do not require client auth.
- `/api/v1/*` requires `X-API-Key` during migration.
- JSON responses use `{ ok, data, meta, error }`.
- Audio success returns `audio/mpeg`; audio errors return JSON envelope.

The source diagnosis lives in the legacy repository at:

```text
C:\Users\EL035\dataschool\08_First_Team_Project\3dt-1st-Project\artifacts\lala-windows-server-diagnosis-2026-06-10
```

