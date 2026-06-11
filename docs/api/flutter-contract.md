# Flutter API Contract

This document describes the Wave 1 Flutter-facing API for LALA-next.
For generated schema export and interactive docs, see
`docs/api/openapi-usage.md`.

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

Wave 1 service responses are deterministic when live dependencies are disabled.
Azure OpenAI and Azure Speech are available as opt-in live paths. DB-backed
places, weather, planner, and docent-cache reads are also available when
`DB_DSN` points at the canonical schema. If DB access is absent or unavailable,
the same routes return contract-safe skeleton data.

## Route Details

### `GET /api/v1/places`

Query parameters:

| Name | Type | Default | Notes |
|---|---|---|---|
| `lat` | number | `37.2636` | `-90` to `90` |
| `lng` | number | `127.0286` | `-180` to `180` |
| `radius_m` | integer | `1000` | `1` to `50000` |
| `category` | string | `all` | `all`, `attraction`, `restaurant`, `event` |
| `lang` | string | `ko` | `ko`, `kr`, `kor`, `korean`, `en`, `eng`, `english` |

### `GET /api/v1/weather`

Query parameters:

| Name | Type | Default | Notes |
|---|---|---|---|
| `lat` | number | `37.2636` | `-90` to `90` |
| `lng` | number | `127.0286` | `-180` to `180` |
| `force` | boolean | `false` | Reserved for bypassing cached weather later |

### `POST /api/v1/docents/script`

Request:

```json
{
  "place_id": "skeleton-suwon-hwaseong",
  "category": "attraction",
  "language": "ko",
  "mode": "brief"
}
```

`category` must be `attraction`, `restaurant`, or `event`. `mode` accepts
`brief`, `detail`, `standard`, and `deep`.

### `POST /api/v1/docents/audio`

Request:

```json
{
  "script": "Short docent script text.",
  "language": "ko"
}
```

Success returns `audio/mpeg` bytes and an `X-Request-ID` response header.

### `POST /api/v1/plans/daily`

Request:

```json
{
  "lat": 37.2636,
  "lng": 127.0286,
  "language": "ko"
}
```

### `GET /api/v1/plans/intervention`

Query parameters:

| Name | Type | Default | Notes |
|---|---|---|---|
| `lat` | number | `37.2636` | `-90` to `90` |
| `lng` | number | `127.0286` | `-180` to `180` |
| `radius_m` | integer | `10000` | `1` to `50000` |

## Response Data Examples

`GET /api/v1/places`:

```json
{
  "query": {
    "lat": 37.2636,
    "lng": 127.0286,
    "radius_m": 1000,
    "category": "all",
    "language": "ko"
  },
  "places": [
    {
      "place_id": "skeleton-suwon-hwaseong",
      "name": "Suwon Hwaseong",
      "category": "attraction",
      "distance_m": 420,
      "lat": 37.2869,
      "lng": 127.0116
    }
  ],
  "source": "skeleton"
}
```

When the canonical PostgreSQL read model returns rows, this payload keeps the
same shape and uses `source: "db"`. DB rows are radius-filtered and sorted by
approximate distance in the repository query before the skeleton fallback is
considered.

`GET /api/v1/weather`:

```json
{
  "lat": 37.2636,
  "lng": 127.0286,
  "temp": "11",
  "icon": "partly-cloudy",
  "dust": {
    "pm10": "37",
    "pm25": "26",
    "grade": "normal",
    "grade_ko": "보통"
  },
  "forecast": [
    {
      "time": "2026-06-11T12:00:00+09:00",
      "temp": "12",
      "icon": "partly-cloudy"
    }
  ],
  "outdoor_status": "good",
  "force": false,
  "source": "skeleton"
}
```

When `DB_DSN` is configured, weather reads prefer the latest row whose
`location` matches the nearest canonical place region. If no region match is
available, the API falls back to the latest weather row and marks
`location_match: false`.

`POST /api/v1/plans/daily`:

```json
{
  "language": "ko",
  "center": {
    "lat": 37.2636,
    "lng": 127.0286
  },
  "weather": {
    "outdoor_status": "good",
    "source": "skeleton"
  },
  "slots": [
    {
      "period": "morning",
      "title": "Start near a landmark",
      "place": {
        "place_id": "skeleton-suwon-hwaseong",
        "name": "수원화성"
      }
    }
  ],
  "source": "skeleton"
}
```

`GET /api/v1/plans/intervention`:

```json
{
  "center": {
    "lat": 37.2636,
    "lng": 127.0286
  },
  "radius_m": 10000,
  "should_intervene": false,
  "reason": "Weather-aware placeholder intervention from LALA-next skeleton.",
  "recommended_action": "Show nearby indoor or short-walk alternatives.",
  "source": "skeleton"
}
```

## Live AI

Azure OpenAI resources exist for LALA-next, but live generation is opt-in:

```powershell
$env:LALA_ENABLE_LIVE_AI = "true"
```

When live AI is enabled and Key Vault or environment variables provide the OpenAI settings, `POST /api/v1/docents/script` uses the `gpt-4o-mini` deployment and returns `source: "azure_openai"`. Otherwise it returns the deterministic skeleton fallback with `source: "skeleton"`.

If `DB_DSN` is configured and `locallink.docent_cache` has a matching non-expired
entry, the script route returns the cached script before calling Azure OpenAI.
Those cache hits return `source: "db_cache"` and `ttl_sec` as the approximate
remaining seconds until `expires_at`.
When live Azure OpenAI generation succeeds and `DB_DSN` is configured, the route
best-effort writes the generated script back to `locallink.docent_cache`.
Database write failures do not fail the API response.

## Live Speech

Azure Speech resources exist for LALA-next, but live synthesis is opt-in:

```powershell
$env:LALA_ENABLE_LIVE_SPEECH = "true"
```

When live Speech is enabled and Key Vault or environment variables provide the Speech settings, `POST /api/v1/docents/audio` returns Azure-generated MP3 bytes. Otherwise it returns deterministic skeleton MP3-like bytes for contract testing.
