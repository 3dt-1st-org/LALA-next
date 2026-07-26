# 2026-07-26 Android Real-device Validation

## Build under test

- Source branch: `codex/general-openai-runtime-main`.
- Package: `cloud.lalanext.lala_next_app`.
- Device: USB-connected Samsung SM-S921N (Android 16).
- Fresh debug APK: previous package uninstalled, then rebuilt and installed with
  the LALA API base URL and Kakao JavaScript key supplied only as build-time
  environment values. No secret value is recorded here.

## Verified user flow

1. Fresh launch showed the three content onboarding steps.
2. Travel type selection enabled the next action; Korean language selection was
   displayed as `KO`/`EN`, without a flag icon.
3. The location consent page rendered a live Kakao map preview and Android
   showed the system location permission prompt. Choosing foreground permission
   reached the map screen.
4. The map rendered live Kakao tiles, category-colored place markers, real
   place names/images, current-location recommendation data, and weather/PM
   values. The compact map weather control rendered the complete
   `26.4°C · 공기 좋음` summary without ellipsis; tapping it remains the path to
   PM10/PM2.5 detail.
5. Search rendered real nearby results with official images. The daily-plan
   tab progressed from its honest loading state to a populated plan with weather
   and PM chips.
6. The daily-plan tab rendered a populated plan with separate PM10 and PM2.5
   chips. After force-stopping and relaunching, onboarding stayed completed and
   the app returned directly to the map with real data before weather settled.

## Boundary

This device run deliberately did not invoke a paid live docent or enrichment
request. General OpenAI runtime behavior is covered by unit/contract tests and
the local readiness configuration check; a paid provider smoke requires the
new API revision to be running with `OPENAI_API_KEY` and
`LALA_ENABLE_LIVE_AI=true`.

No Flutter fatal exception was observed in the captured log window.
