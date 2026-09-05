# LALA-next Flutter App

This is the first Flutter app shell for the LALA-next Wave 1 API contract. It
uses the checked reference client from `clients/flutter` through a local path
dependency.

Current app surface:

- Public `/healthz` and `/readyz` status before auth is available.
- Runtime mode display from `/readyz.data.mode`.
- Runtime editable backend base URL.
- Naver Dynamic Map background for the Korean locale, loaded with
  `NAVER_MAP_CLIENT_ID` at Flutter web build time and through the registered
  `https://lala-next.cloud` `naver-map-embed.html` page for native iOS/Android
  WebView builds.
- Locale-aware open-vector map for `en`/`ja`/`zh-Hans`/`zh-Hant`: the
  self-contained `assets/map/open-map-embed.html` (version-pinned MapLibre GL
  JS v3.6.2 inlined via `tool/build_open_map_embed.sh`) renders
  OpenFreeMap/OpenMapTiles/OSM data with data-driven label localization. The
  style URL is the single replaceable provider boundary
  (`LALA_OPEN_MAP_STYLE_URL` dart-define); the public instance has no SLA.
- 3 km current-location recommendation radius for the Seoul/Gyeonggi launch dataset.
- Bearer token or migration API key input for `/api/v1/*`.
- Recommendation-first home surface that highlights the top place, local-value
  score, local spending, demand dispersion, weather fit, culture relevance, and
  review-quality readiness from `/api/v1/places`.
- Places, weather, intervention, daily plan, live-context docent script, and
  manual docent audio metadata panels for operator handoff and offline snapshot
  fallback checks.
- Daily plan and intervention share the same editable radius as places, so the
  selected recommendation dataset remains consistent across panels.
- Partial-failure handling that keeps public health/readiness visible when an
  authenticated `/api/v1/*` request fails.

Docent audio fetch is deliberately manual. In local contract or public-cache
mode it verifies the binary `audio/mpeg` contract, while a live Speech-enabled
backend may create a paid Azure Speech request.

Run from the repository root:

```bash
scripts/unix/verify_flutter_app.sh --require-flutter
```

The verifier runs `flutter pub get`, Dart format check, `flutter analyze`,
widget tests, and a release `flutter build web`. Build outputs stay under
`apps/flutter_app/build/` and should not be committed.

Optional browser render smoke from the repository root:

```bash
scripts/unix/smoke_flutter_web.sh --require-flutter --require-browser --port 8099
```

For a stronger local smoke that also starts the local FastAPI process and
preloads a temporary migration API key into the web bundle:

```bash
scripts/unix/smoke_flutter_web.sh \
  --require-flutter \
  --require-browser \
  --start-api \
  --fail-on-console-error \
  --port 8099 \
  --api-port 18080
```

Windows equivalent:

```powershell
.\scripts\windows\smoke_flutter_web.ps1 `
  -RequireFlutter `
  -RequireBrowser `
  -StartApi `
  -FailOnConsoleError `
  -Port 8099 `
  -ApiPort 18080
```

The smoke builds the web bundle, serves it locally, opens it through the
Playwright CLI, validates the Flutter entrypoint, and captures snapshot,
screenshot, console, and runtime-state artifacts under `output/playwright/`.
With `--start-api`, it keeps the API in local contract mode, avoids Key Vault,
DB, OpenAI, and Speech, grants a test browser geolocation, reloads into the
first-run location request flow, and verifies that the browser requested places,
weather, intervention, and daily plan routes with the granted latitude and longitude.
The route check requires places, weather, and intervention to each use the granted
location, and fails if the old default Suwon coordinate appears in those API logs.
With `--api-base-url <url>`, the same location-flow request check runs against a
separately running backend that allows the selected local web origin. For the deployed contest site, use
`--web-url https://lala-next.cloud/?qa=<label>` so the smoke opens the registered
Naver Maps/CORS origin directly and verifies the same location-driven API requests,
then verifies a live-context docent script from the same place/weather data. The macOS/Linux smoke also captures
`flutter-web-api-responses.json` and fails if the browser received non-DB
places, a non-PostGIS location engine, weather without AirKorea PM10/PM2.5
values, a docent script that omits live place/local value/official grounding or
the captured PM10/PM2.5 context, raw score/internal labels in docent copy, or a
map state that renders only clusters without real place pins.
Without
`--start-api`, the app still renders its offline public state when the API is
not running and the console artifact records the expected `/healthz`
connection refusal.

Run directly:

```bash
cd apps/flutter_app
flutter pub get
flutter run -d chrome
```

Optional compile-time defaults:

```bash
flutter run \
  --dart-define LALA_API_BASE_URL=http://127.0.0.1:8080 \
  --dart-define NAVER_MAP_CLIENT_ID="$NAVER_MAP_CLIENT_ID"
```

During the public contest review window, shared dev can set
`LALA_PUBLIC_CONTEST_ACCESS=true`; in that case web and simulator builds should
call the Azure API without bundling `LALA_API_BEARER_TOKEN`. Production,
contest, and reviewer-facing Flutter web builds should use
`flutter build web --release --pwa-strategy=none` so a browser does not keep an
older service-worker cached app shell after deployment.
Production, review, and shared dev backends should still keep
`LALA_STATIC_SNAPSHOT_FALLBACK=false` and use the PostgreSQL read model. The
bundled static snapshot is only an offline, read-only fallback for DB outage
handling or isolated local checks.

Do not commit client tokens or API keys. After the contest window, replace
public contest access with OAuth or a backend-for-frontend proxy rather than
shipping static credentials in the web bundle.
## Build Input Resolution

Build inputs (API keys, service endpoints, and configuration values) are resolved
at **build time** in the following priority order:

1. **SSM First:** AWS Systems Manager Parameter Store is the preferred **build-time**
   injection source for guest builds and CI/CD pipelines. Build systems inject these values
   as compile-time dart-defines; the Flutter client itself does not retrieve SSM parameters.

2. **Secrets Manager Fallback:** If the operator-supplied SSM parameter is not
   configured or available, the restricted `lala-next/naver-map-client-id`
   entry is checked.

3. **Local Fallback:** If the managed sources are unavailable, local `.env` or `.env.local` files
   may be used **only inside an isolated build subshell** for development builds.
   These files must never be committed, copied, or referenced in production builds.

4. **No Temporary/Fake Values:** Build systems should not invent or substitute placeholder
   values. If a required configuration value is unavailable and no safe default exists,
   the build should fail. For `LALA_API_BASE_URL`, a safe public default is provided.

5. **Safe Public Default:** The `LALA_API_BASE_URL` configuration has a safe static
   default (`https://api.lala-next.cloud`) as a guest-safe fallback for public read-only
   flows. This default allows the app to function without requiring explicit configuration.
   Explicit dart-define values always override this default unchanged, including
   `http://127.0.0.1:8080` for local development.

**Security:** Never print, grep, copy, attach, log, commit, or expose secret values,
secret paths, secret names, AWS identifiers, or environment variable content in
build output or documentation.

`NAVER_MAP_CLIENT_ID` is embedded in web and native WebView map loads by design
and must be protected by the Naver Cloud Dynamic Map URL allowlist. It is not
the server-side `NAVER_CLIENT_ID`, and `NAVER_CLIENT_SECRET` must never enter a
Flutter build, browser bundle, screenshot, or client log.
