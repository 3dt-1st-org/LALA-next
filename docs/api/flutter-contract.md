# Flutter API Contract

This document describes the Wave 1 Flutter-facing API for LALA-next.
For generated schema export and interactive docs, see
`docs/api/openapi-usage.md`.
For handoff steps, see `docs/api/flutter-handoff-checklist.md`.

Base URL examples:

- Local developer: `http://127.0.0.1:8080`
- Shared Windows backend: `http://<windows-host-lan-ip>:8080`
- Tunnel or staging: `https://<team-domain>`

Mobile clients should not use `localhost` unless the API process runs on the same device.

Flutter mobile clients do not need browser CORS. Flutter Web or browser-based
contract checks should set `CORS_ALLOW_ORIGINS` on the API process, for example:

```powershell
$env:CORS_ALLOW_ORIGINS = "http://localhost:3000,http://127.0.0.1:3000"
```

When the API runs with `KEY_VAULT_URL=https://lala-next-kv-27db5e.vault.azure.net/`,
it can also load the optional `cors-allow-origins` secret into
`CORS_ALLOW_ORIGINS`.

## Authentication

The preferred client auth header for new clients is:

```text
Authorization: Bearer <client token>
```

During the migration window, the server accepts the exact static bearer token
from `API_BEARER_TOKEN`. When OAuth/Entra settings are complete
(`OAUTH_ISSUER`, `OAUTH_AUDIENCE`, `OAUTH_JWKS_URL`, and
`OAUTH_REQUIRED_SCOPES`), the same header can carry a signed RS256 JWT. The JWT
must match issuer and audience and include all required scopes in `scp` or
`roles`.

The existing migration guard is still accepted:

```text
X-API-Key: <client api key>
```

The server reads the expected API key from `IOS_API_KEY`. Configure static
credentials or complete OAuth/Entra JWT validation settings; if none are
available, `/api/v1/*` returns `CLIENT_AUTH_NOT_CONFIGURED`.
Credentials are trimmed at the header edges, compared with a constant-time
digest comparison, and rejected when the header value is oversized or when a
bearer token contains internal whitespace. Auth values and JWT validation
errors are never logged into response bodies.

## Response Envelope

Clients may send `X-Request-ID` for correlation. The server preserves only
1-128 character IDs containing letters, digits, `.`, `_`, `:`, or `-`; otherwise
it generates a new request id so arbitrary header values are not echoed or
logged.

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
Authentication failures and validation failures use the same failure envelope;
the OpenAPI schema documents `/api/v1/*` 401 and 422 responses as
`ApiErrorEnvelope`. Validation failures may include `error.details`, but raw
request `input` values are removed before the response is returned.

## Routes

| Method | Route | Purpose |
|---|---|---|
| GET | `/healthz` | Process liveness |
| GET | `/readyz` | Dependency readiness summary plus `data.mode` runtime mode |
| GET | `/metrics` | Operator metrics, readiness gauges, and runtime mode gauges in Prometheus text format |
| GET | `/api/v1/places` | Nearby place list |
| GET | `/api/v1/weather` | Current weather context |
| POST | `/api/v1/docents/script` | Generate or fetch docent script |
| POST | `/api/v1/docents/audio` | Generate or fetch TTS audio |
| POST | `/api/v1/plans/daily` | Create daily plan |
| GET | `/api/v1/plans/intervention` | Weather/location intervention |

Wave 1 service responses are deterministic when live dependencies are disabled.
Azure OpenAI and Azure Speech are available as opt-in live paths. DB-backed
places, weather, planner, and docent-cache reads are also available when
`DB_DSN` points at the canonical schema. If DB access is absent but
`LALA_PUBLIC_DEMO_MODE=true`, places use the bundled `public_mvp_snapshot`;
otherwise the same routes return contract-safe skeleton data.
Flutter can read `/readyz.data.mode.overall` for a compact handoff label:
`skeleton`, `public-cache`, `db-backed`, `live-azure`, or `degraded`. Component
labels are also available at `data.mode.data`, `data.mode.ai`,
`data.mode.speech`, and `data.mode.worker`.
The reference Dart client exposes public `getHealth()` and `getReadiness()`
methods without requiring client auth; `/api/v1/*` client methods still require
`Authorization: Bearer <token>` or `X-API-Key`.
The first Flutter app shell displays latest readiness, `/api/v1/*`, and audio
request ids from response metadata/headers so handoff testers can correlate a
screen state with server JSONL access logs without exposing credentials or
request bodies.
It also parses the main `/api/v1/*` JSON payloads into typed DTOs
(`LalaPlacesResponse`, `LalaWeather`, `LalaDocentScript`, `LalaDailyPlan`, and
`LalaIntervention`) so Flutter screens do not have to index raw maps for the
common contract fields.
The generated OpenAPI schema mirrors those common DTO fields through
route-specific success envelope schemas for places, weather, docent script,
daily plan, and intervention responses.
The first Flutter app shell in `apps/flutter_app` uses that reference client
for public readiness and authenticated `/api/v1/*` panels.
Generation routes expose deterministic client-safe identity values: JSON
generation responses include `request_hash` and `cache_key`; the binary audio
success response exposes the same information through `X-LALA-Request-Hash` and
`X-LALA-Cache-Key` headers. Hashes are derived from normalized request fields
and do not expose raw credentials.
Client-side timeout expectations are bounded in the reference client:
health/readiness 3s, places/weather/intervention reads 5s, daily plan 20s, and
docent script/audio generation 30s. Each method accepts a `timeout:` override;
timeouts are reported as retryable `LalaApiException(code: REQUEST_TIMEOUT)`
without exposing response bodies or credentials. The generated OpenAPI schema
mirrors these defaults through `x-lala-timeout-seconds`; it also marks
`/api/v1/*` operations with `x-lala-auth-required: true`.

## Route Details

### `GET /api/v1/places`

Query parameters:

| Name | Type | Default | Notes |
|---|---|---|---|
| `lat` | number | `37.2636` | `-90` to `90` |
| `lng` | number | `127.0286` | `-180` to `180` |
| `radius_m` | integer | `1000` | `1` to `50000` |
| `category` | string | `all` | `all`, `attraction`, `restaurant`, `event`, `culture_venue` |
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
  "place_name": "수원화성",
  "category": "attraction",
  "language": "ko",
  "mode": "brief"
}
```

`category` must be `attraction`, `restaurant`, `event`, or `culture_venue`.
`place_name` is optional but recommended so fallback docent copy can use the
user-facing localized place name instead of an internal source id.
`mode` accepts `brief`, `detail`, `standard`, and `deep`.
Success data includes `request_hash` and `cache_key` for idempotency-aware
client flows.

### `POST /api/v1/docents/audio`

Request:

```json
{
  "script": "Short docent script text.",
  "language": "ko"
}
```

Success returns `audio/mpeg` bytes plus `X-Request-ID`,
`X-LALA-Request-Hash`, and `X-LALA-Cache-Key` response headers.

### `POST /api/v1/plans/daily`

Request:

```json
{
  "lat": 37.2636,
  "lng": 127.0286,
  "radius_m": 50000,
  "language": "ko"
}
```

Success data includes `request_hash` and `cache_key` for idempotency-aware
client flows.

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
    "radius_m": 50000,
    "category": "all",
    "language": "ko"
  },
  "places": [
    {
      "place_id": "tour-api-129765",
      "name": "호암미술관",
      "category": "culture_venue",
      "distance_m": 14857,
      "lat": 37.293314781,
      "lng": 127.1923454131,
      "score": {
        "final_score": 0.8562,
        "formula_version": "local-value-v1",
        "components": {
          "local_spending_score": null,
          "demand_dispersion_score": 0.95,
          "weather_fit_score": null,
          "review_quality_score": null,
          "culture_relevance_score": 0.7
        },
        "data_basis": "public_mvp_snapshot",
        "features": {
          "primary_source": "tour_api",
          "missing_signals": [
            "card_spending_area_monthly",
            "review_attribute_analysis",
            "weather_observations"
          ]
        }
      }
    }
  ],
  "source": "public_mvp_snapshot"
}
```

When the canonical PostgreSQL read model returns rows, this payload keeps the
same shape and uses `source: "db"`. DB rows are radius-filtered, joined to the
latest `analytics.place_score_snapshots` row, then sorted by final score before
distance. When a DB-backed score is present, `score.data_basis` is
`analytics.place_score_snapshots`. The public MVP cache uses
`score.data_basis=public_mvp_snapshot`; final skeleton fallback scores are
explicitly marked `demo_fallback` and must not be described as real
card-spending evidence.

`GET /api/v1/weather`:

```json
{
  "lat": 37.2636,
  "lng": 127.0286,
  "location": "기상청 격자",
  "temp": "22.3",
  "icon": "partly-cloudy",
  "dust": {
    "pm10": "",
    "pm25": "",
    "grade": "unknown",
    "grade_ko": "확인 중"
  },
  "forecast": [
    {
      "time": "2026-06-18T23:00:00+09:00",
      "temp": "22.3",
      "icon": "partly-cloudy"
    }
  ],
  "outdoor_status": "good",
  "force": false,
  "location_match": true,
  "record_time": "2026-06-18T23:00:00+09:00",
  "source": "kma_ultra_srt_ncst"
}
```

When `DB_DSN` is configured, weather reads prefer the latest row whose
`location` matches the nearest canonical place region. If no region match is
available, the API falls back to the latest weather row and marks
`location_match: false`. If DB weather is unavailable, the API uses the public
data portal `기상청_단기예보 조회서비스` `getUltraSrtNcst` endpoint with
`PUBLIC_DATA_SERVICE_KEY`, converting the map center to the KMA 5 km forecast
grid. If both DB and KMA reads are unavailable, the route returns the existing
`source: skeleton` pending shape.

`POST /api/v1/plans/daily`:

```json
{
  "language": "ko",
  "center": {
    "lat": 37.2636,
    "lng": 127.0286
  },
  "radius_m": 50000,
  "weather": {
    "outdoor_status": "good",
    "source": "skeleton"
  },
  "slots": [
    {
      "period": "morning",
      "title": "Start near a landmark",
      "place": {
        "place_id": "tour-api-129765",
        "name": "호암미술관",
        "source": "public_mvp_snapshot"
      }
    }
  ],
  "source": "mixed"
}
```

`GET /api/v1/plans/intervention`:

```json
{
  "center": {
    "lat": 37.2636,
    "lng": 127.0286
  },
  "radius_m": 50000,
  "should_intervene": false,
  "reason": "Weather is suitable, so keep the current route toward 호암미술관.",
  "recommended_action": "Keep 호암미술관 as the primary local stop.",
  "place": {
    "place_id": "tour-api-129765",
    "name": "호암미술관",
    "source": "public_mvp_snapshot"
  },
  "source": "mixed"
}
```

## Live AI

Azure OpenAI resources exist for LALA-next, but live generation is opt-in:

```powershell
$env:LALA_ENABLE_LIVE_AI = "true"
```

When live AI is enabled and Key Vault or environment variables provide the OpenAI settings, `POST /api/v1/docents/script` uses the `gpt-4o-mini` deployment and returns `source: "azure_openai"`. Otherwise it returns the deterministic skeleton fallback with `source: "skeleton"`.

If `DB_DSN` is configured and `travel.docent_scripts` has a matching non-expired
entry, the script route returns the cached script before calling Azure OpenAI.
Those cache hits return `source: "db_cache"` and `ttl_sec` as the approximate
remaining seconds until `expires_at`.
When live Azure OpenAI generation succeeds and `DB_DSN` is configured, the route
best-effort writes the generated script back to `travel.docent_scripts`.
Database write failures do not fail the API response.

## Live Speech

Azure Speech resources exist for LALA-next, but live synthesis is opt-in:

```powershell
$env:LALA_ENABLE_LIVE_SPEECH = "true"
```

When live Speech is enabled and Key Vault or environment variables provide the Speech settings, `POST /api/v1/docents/audio` returns Azure-generated MP3 bytes. Otherwise it returns deterministic skeleton MP3-like bytes for contract testing.
