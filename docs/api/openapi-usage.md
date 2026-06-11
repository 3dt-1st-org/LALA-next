# OpenAPI Usage

FastAPI exposes the generated schema and interactive API documentation when the
LALA-next API process is running.

Start the API:

```powershell
.\scripts\windows\start_api.ps1 -Port 8080
```

Open or fetch:

- Swagger UI: `http://127.0.0.1:8080/docs`
- ReDoc: `http://127.0.0.1:8080/redoc`
- OpenAPI JSON: `http://127.0.0.1:8080/openapi.json`

Export a local schema copy for Flutter handoff:

```powershell
.\scripts\windows\export_openapi.ps1 -BaseUrl "http://127.0.0.1:8080"
```

The default output path is
`.\artifacts\openapi\lala-next-openapi.json`.

Notes:

- `/healthz`, `/readyz`, `/docs`, `/redoc`, and `/openapi.json` are public.
- `/api/v1/*` routes require the `X-API-Key` header. The server reads the
  expected value from `IOS_API_KEY`.
- JSON route responses use the `{ ok, data, meta, error }` envelope with
  `meta.request_id`.
- `POST /api/v1/docents/audio` is the success-response exception and returns
  `audio/mpeg` bytes. Validation or service failures still return the JSON
  envelope.
- `docs/api/flutter-contract.md` remains the human-readable contract source for
  Flutter behavior, fallback semantics, and live Azure opt-in notes.
