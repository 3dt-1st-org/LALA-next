# LALA-next Flutter App

This is the first Flutter app shell for the LALA-next Wave 1 API contract. It
uses the checked reference client from `clients/flutter` through a local path
dependency.

Current app surface:

- Public `/healthz` and `/readyz` status before auth is available.
- Runtime mode display from `/readyz.data.mode`.
- Runtime editable backend base URL.
- 50 km default public MVP radius for the Suwon/Gyeonggi demo snapshot.
- Bearer token or migration API key input for `/api/v1/*`.
- Recommendation-first home surface that highlights the top place, local-value
  score, local spending, demand dispersion, weather fit, culture relevance, and
  review-quality readiness from `/api/v1/places`.
- Places, weather, intervention, daily plan, first-place docent script, and
  manual docent audio metadata panels for operator handoff and public-demo
  fallback checks.
- Partial-failure handling that keeps public health/readiness visible when an
  authenticated `/api/v1/*` request fails.

Docent audio fetch is deliberately manual. In skeleton or public-cache mode it
verifies the binary `audio/mpeg` contract, while a live Speech-enabled backend
may create a paid Azure Speech request.

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

For a stronger local smoke that also starts the skeleton FastAPI process and
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
With `--start-api`, it keeps the API in skeleton mode, avoids Key Vault, DB,
OpenAI, and Speech, and verifies that the browser hit `/healthz`, `/readyz`,
places, weather, intervention, daily plan, and docent script routes. Without
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
  --dart-define LALA_API_BASE_URL=http://127.0.0.1:8080
```

The public MVP backend can run with `LALA_PUBLIC_DEMO_MODE=true`, so the app
loads places from the bundled public snapshot plus weather, intervention, daily
plan, and docent script panels even when no bearer token or migration API key is
entered. If the backend disables public demo mode, the server returns the normal
JSON auth error and the app keeps readiness visible.

Do not commit client tokens or API keys. For local testing, prefer entering
short-lived credentials in the app UI or using an operator-owned environment.
