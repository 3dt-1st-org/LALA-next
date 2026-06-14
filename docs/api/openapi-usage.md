# OpenAPI Usage

FastAPI exposes the generated schema and interactive API documentation when the
LALA-next API process is running.

Start the API:

```bash
scripts/unix/start_api.sh --port 8080
```

```powershell
.\scripts\windows\start_api.ps1 -Port 8080
```

Open or fetch:

- Swagger UI: `http://127.0.0.1:8080/docs`
- ReDoc: `http://127.0.0.1:8080/redoc`
- OpenAPI JSON: `http://127.0.0.1:8080/openapi.json`

Export a local schema copy for Flutter handoff:

```bash
scripts/unix/export_openapi.sh --base-url "http://127.0.0.1:8080"
```

```powershell
.\scripts\windows\export_openapi.ps1 -BaseUrl "http://127.0.0.1:8080"
```

Or export without starting the API process:

```bash
scripts/unix/export_openapi.sh --in-process
```

```powershell
.\scripts\windows\export_openapi.ps1 -InProcess
```

For local development, omit `--python` or `-Python` so the wrapper can prefer
the local virtual environment. Use the interpreter override only when the chosen
interpreter has the LALA-next package and dependencies installed.

The default output path is
`.\artifacts\openapi\lala-next-openapi.json`.

To check that the current schema remains backward-compatible with a previous
handoff snapshot:

```bash
scripts/unix/export_openapi.sh --check-compat artifacts/openapi/lala-next-openapi.json
```

The compatibility check allows additive schema changes but fails if an existing
path, operation, parameter, response, or response content type disappears.

Notes:

- `/healthz`, `/readyz`, `/docs`, `/redoc`, and `/openapi.json` are public.
- `/api/v1/*` routes require client auth. New clients should send
  `Authorization: Bearer <token>`. During migration this can be the static
  `API_BEARER_TOKEN`; when OAuth/Entra settings are complete it can be a signed
  RS256 JWT. The migration `X-API-Key` header remains accepted while
  `IOS_API_KEY` is configured.
- The generated OpenAPI schema includes `BearerAuth` and `MigrationApiKey`
  security schemes on `/api/v1/*`; operational routes remain public.
- Public contract operations include `x-lala-auth-required` and
  `x-lala-timeout-seconds` vendor extensions so generated clients can keep
  route auth and timeout behavior aligned with the reference Flutter client.
- JSON route responses use the `{ ok, data, meta, error }` envelope with
  `meta.request_id`; generated OpenAPI 200 JSON responses use either the shared
  `ApiSuccessEnvelope` or route-specific success envelope schemas when the
  `data` payload is part of the Flutter contract.
- `/healthz` and `/readyz` use specialized success envelope schemas for their
  public operational payloads. `/readyz` documents `data.mode.overall` and
  component mode labels so Flutter handoff/codegen can distinguish skeleton,
  public-cache, DB-backed, live Azure, and degraded runtime states.
- `/api/v1/places`, `/weather`, `/docents/script`, `/plans/daily`, and
  `/plans/intervention` document their common success `data` fields with
  route-specific schemas that mirror the reference Dart DTOs. The audio route
  remains the binary success exception.
- Generation schemas for `/docents/script` and `/plans/daily` include
  deterministic `request_hash` and `cache_key` fields. The binary
  `/docents/audio` success response documents the same values as
  `X-LALA-Request-Hash` and `X-LALA-Cache-Key` headers.
- `/api/v1/*` 401 and 422 responses are documented with the shared
  `ApiErrorEnvelope` schema so Flutter code generation does not consume the
  default FastAPI validation-error shape by mistake.
- Validation errors may include `error.details`, but raw request `input` values
  are removed from those details before the response is returned.
- Responses include `X-Request-ID` and `X-Request-Duration-Ms` headers for
  client-side debugging and backend log correlation; the generated OpenAPI
  schema documents both headers on operation responses.
- Caller-provided `X-Request-ID` values are preserved only when they are
  1-128 safe correlation characters: letters, digits, `.`, `_`, `:`, or `-`.
  Unsafe values are replaced with a generated id before logs, envelopes, and
  response headers are written.
- `POST /api/v1/docents/audio` is the success-response exception and returns
  `audio/mpeg` bytes. The generated OpenAPI 200 response for that route exposes
  only `audio/mpeg` plus generation identity headers; validation or service
  failures still return the JSON envelope.
- `docs/api/flutter-contract.md` remains the human-readable contract source for
  Flutter behavior, fallback semantics, and live Azure opt-in notes.
- `clients/flutter/lib/lala_api_client.dart` is a checked reference client for
  handoff. Run `python -m apps.api.app.tools.check_flutter_client_contract` to
  verify that it still covers the current `/api/v1/*` route set.
