# LALA-next Flutter App

This is the first Flutter app shell for the LALA-next Wave 1 API contract. It
uses the checked reference client from `clients/flutter` through a local path
dependency.

Current app surface:

- Public `/healthz` and `/readyz` status before auth is available.
- Runtime mode display from `/readyz.data.mode`.
- Runtime editable backend base URL.
- Kakao Maps background map, loaded with `KAKAO_JAVASCRIPT_KEY` at Flutter web
  build time and through the registered `https://lala-next.cloud`
  `kakao-map-embed.html` page for native iOS/Android WebView builds.
- 50 km default recommendation radius for the Suwon/Gyeonggi launch dataset.
- Bearer token or migration API key input for `/api/v1/*`.
- Recommendation-first home surface that highlights the top place, local-value
  score, local spending, demand dispersion, weather fit, culture relevance, and
  review-quality readiness from `/api/v1/places`.
- Places, weather, intervention, daily plan, first-place docent script, and
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
separately running backend that allows the selected local web origin and also
expects a docent script route when place data exists. For the deployed contest site, use
`--web-url https://lala-next.cloud/?qa=<label>` so the smoke opens the registered
Kakao/CORS origin directly and verifies the same location-driven API requests,
including the first-place docent script.
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
  --dart-define KAKAO_JAVASCRIPT_KEY="$KAKAO_JAVASCRIPT_KEY"
```

During the public contest review window, shared dev can set
`LALA_PUBLIC_CONTEST_ACCESS=true`; in that case web and simulator builds should
call the Azure API without bundling `LALA_API_BEARER_TOKEN`. Production,
review, and shared dev backends should still keep
`LALA_STATIC_SNAPSHOT_FALLBACK=false` and use the PostgreSQL read model. The
bundled static snapshot is only an offline, read-only fallback for DB outage
handling or isolated local checks.

Do not commit client tokens or API keys. After the contest window, replace
public contest access with OAuth or a backend-for-frontend proxy rather than
shipping static credentials in the web bundle.
The Kakao JavaScript key is embedded in web and native WebView map loads by
design and must be protected by Kakao's JavaScript SDK domain allowlist.
