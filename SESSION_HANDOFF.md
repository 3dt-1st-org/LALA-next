# Session handoff

## Current change

- Branch: `feature/naver-map-migration`
- Base: latest `origin/main` at branch creation
- Scope: replace the Flutter Kakao map surface with Naver Dynamic Map while
  preserving LALA's provider-neutral camera, bounds, clustering, selection, and
  category-color contracts.
- Detailed plan: `docs/planning/naver-map-migration-plan.md`

## Runtime contract

- Flutter consumes only the URL-restricted public map client ID through
  `NAVER_MAP_CLIENT_ID`.
- Server credentials never enter Dart defines, Flutter assets, iframe URLs,
  logs, or commits.
- Build resolution order is managed parameter metadata when explicitly
  configured, then the approved secret manager entry, then an isolated trusted
  local dotenv file.
- The web app loads `web/naver-map-embed.html` from the same origin. Native
  iOS/Android WebViews load the deployed copy from `lala-next.cloud`.
- Configuration and place payloads stay out of URLs. Web uses same-origin
  `postMessage`; native uses the existing JavaScript channel. Both validate a
  per-map bridge ID before accepting camera or place-selection messages.
- Missing configuration, SDK load failure, and authorization failure render an
  honest unavailable state instead of a demo map.

## Verified locally

- Naver tiles, logo, copyright controls, category pins, pin-first clusters,
  camera bounds, and production read-only place/weather data render in the web
  build.
- A real marker click crossed the iframe bridge and changed the selected Flutter
  place.
- The 402x874 responsive capture is stored locally at
  `output/playwright/naver-map-migration/map-mobile-naver-final.png` and remains
  untracked.
- `flutter analyze` and the full Flutter test suite pass.
- Focused API safety/secret-registry tests and the build-env shell contract pass.

## Remaining gates

1. Run repository-wide lint, format, pre-commit, and diff checks.
2. Commit and push in small conventional commits.
3. Open a Draft PR against `main` and verify exact-head CI.
4. Do not merge or deploy from this branch without review. Native runtime proof
   must use a build whose deployed origin contains `naver-map-embed.html`.

## Safety

- Do not print, copy, attach, or commit dotenv or managed-secret values.
- Preserve Kakao REST/login settings; only the map-rendering provider changes.
- Preserve Logto authentication and the Geolocator plus `browser_location`
  conditional-import contract.
