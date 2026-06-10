# Flutter API Contract

This document describes the Wave 1 Flutter-facing API for LALA-next.

Base URL examples:

- Local developer: `http://127.0.0.1:8080`
- Shared Windows backend: `http://<windows-host-lan-ip>:8080`
- Tunnel or staging: `https://<team-domain>`

Mobile clients should not use `localhost` unless the API process runs on the same device.

## Authentication

Wave 1 uses the existing migration guard:

```text
X-API-Key: <client api key>
```

The server reads the expected value from `IOS_API_KEY`. Production bearer auth is a later wave.

## Response Envelope

JSON success:

```json
{
  "ok": true,
  "data": {},
  "meta": {
    "request_id": "generated-per-request"
  },
  "error": null
}
```

JSON failure:

```json
{
  "ok": false,
  "data": null,
  "meta": {
    "request_id": "generated-per-request"
  },
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Invalid client API key.",
    "retryable": false
  }
}
```

`POST /api/v1/docents/audio` is the only Wave 1 exception: success returns `audio/mpeg` bytes, while failures still return the JSON envelope.

## Routes

| Method | Route | Purpose |
|---|---|---|
| GET | `/healthz` | Process liveness |
| GET | `/readyz` | Dependency readiness summary |
| GET | `/api/v1/places` | Nearby place list |
| GET | `/api/v1/weather` | Current weather context |
| POST | `/api/v1/docents/script` | Generate or fetch docent script |
| POST | `/api/v1/docents/audio` | Generate or fetch TTS audio |
| POST | `/api/v1/plans/daily` | Create daily plan |
| GET | `/api/v1/plans/intervention` | Weather/location intervention |

Wave 1 service responses are skeleton-safe and mock-friendly. Azure-backed generation and DB-backed query implementations are later waves.

