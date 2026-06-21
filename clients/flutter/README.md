# LALA Flutter Client Reference

This folder contains a reference Dart client for the Wave 1 LALA-next API
contract. It is not a full Flutter app. Copy or adapt `lib/lala_api_client.dart`
inside the future Flutter application and provide runtime configuration for:

- API base URL, for example `http://<windows-host-lan-ip>:8080`.
- `Authorization: Bearer <client token>` for new clients, or `X-API-Key` during
  migration.

The client can call public `getHealth()` and `getReadiness()` without client
auth, which is useful when a Flutter developer needs to confirm the backend URL
and runtime mode before a token is available. `/api/v1/*` methods attach
`bearerToken` or `apiKey` when provided. Production, review, and shared dev
deployments should keep server-side client auth configured; offline static
snapshot fallback is reserved for DB outage handling or isolated local checks.

JSON routes return the shared `{ ok, data, meta, error }` envelope. The
reference client parses common API payloads into typed DTOs such as
`LalaPlacesResponse`, `LalaPlace`, `LalaWeather`, `LalaDocentScript`,
`LalaDailyPlan`, and `LalaIntervention`. `getReadiness()` parses
`/readyz.data.mode` into `LalaRuntimeMode` so the app or handoff tooling can
distinguish DB-backed, read-only public-cache, live Azure, and degraded states.
`POST /api/v1/docents/audio` is the success exception and returns `audio/mpeg`
bytes.

Location-based methods require explicit `lat` and `lng` arguments. Production
and review clients should pass the browser/device location after user consent,
or an explicit user-selected coordinate; the API no longer carries a default
recommendation location.

Default client-side timeouts are intentionally bounded:

- Health/readiness: 3 seconds.
- Places/weather/intervention reads: 12 seconds.
- Daily plan: 20 seconds.
- Docent script/audio generation: 30 seconds.

Every method accepts an optional `timeout:` override. Timeouts become a
retryable `LalaApiException` with code `REQUEST_TIMEOUT`; response bodies and
credentials are not included in the exception string.

Add the HTTP package in the Flutter app:

```yaml
dependencies:
  http: ^1.2.0
```

Verify this reference package locally:

```bash
cd clients/flutter
dart pub get
dart analyze lib/lala_api_client.dart
dart test
```

From the repository root, the wrapper below runs `dart pub get`, format check,
analyze, and tests when Dart is installed:

```bash
scripts/unix/verify_flutter_client.sh --require-dart
```

Minimal usage:

```dart
final api = LalaApiClient(baseUri: Uri.parse('http://<windows-host-lan-ip>:8080'));

final readiness = await api.getReadiness();
print(readiness.data?.mode.overall);

final authedApi = LalaApiClient(
  baseUri: Uri.parse('http://<windows-host-lan-ip>:8080'),
  bearerToken: clientToken,
);

final places = await authedApi.getPlaces(lat: 37.2636, lng: 127.0286);
print(places.data?.places.first.name);

final audio = await authedApi.createDocentAudio(
  script: 'Short docent script text.',
  language: 'ko',
  timeout: const Duration(seconds: 30),
);
```

Do not commit client tokens or API keys in the Flutter app repository.
