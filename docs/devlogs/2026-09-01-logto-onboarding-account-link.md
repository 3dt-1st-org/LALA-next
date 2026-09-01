# 2026-09-01 Logto onboarding account link

## Confirmed implementation

- Moved Logto session ownership to the app root so map, search, plan, Local
  Signals, and community clients share one access-token provider.
- Added an optional account-link screen after the existing three onboarding
  decisions. It is skipped when public Logto build config is absent and always
  preserves an explicit guest route.
- Separated provider authentication from LALA `/me` synchronization. A backend
  sync failure keeps the Logto session, exposes a bounded retry, and does not
  leak backend error detail.
- Added stale-response suppression so a late `/me` response cannot restore a
  signed-out session.
- Added a public-only Flutter build resolver. It may pass map and Logto public
  client configuration but cannot pass management credentials, API bearer
  tokens, database credentials, or AI/provider secrets.

## Console and local-config audit

- The Logto tenant has separate Web SPA and Native applications.
- The Web application has the production callback and post-sign-out route.
- The Native application has the custom-scheme callback. With no separate
  native post-sign-out value, the SDK returns to that same registered callback.
- The currently trusted dotenv uses legacy Web-shaped shared redirect values.
  The app now prefers platform-specific variables and ignores a valid legacy
  URI that belongs to the other platform, preventing an iOS build from silently
  disabling Logto.
- The inspected tenant is a development tenant. Production-tenant rollout is an
  external operational gate, not a code-completion claim.

## Validation completed before PR

- Focused auth, token-provider, OAuth callback, and onboarding widget tests.
- Build-wrapper shell contract tests, including the negative management-secret
  boundary.
- `flutter analyze`.
- Full Flutter suite: 738 tests passed.
- `uv run pre-commit run --all-files` and `git diff --check` passed.
- Clean Web release and iOS Simulator debug builds passed. Both bundles contain
  only the expected platform public client configuration; the management
  credential sentinel is absent.

## iPhone 17 Pro runtime evidence

- Built code head: `381443a3e7e752c808eaac27d516042802d0e387`.
- Uninstalled the prior app before installing the clean simulator build.
- Completed all three onboarding decisions, reached the optional account-link
  screen, opened the real hosted Logto sign-in surface, cancelled it, and
  recovered through the guest action.
- Guest entry reached the live Naver map with actual place imagery, markers,
  recommendation cards, and weather. Denying location kept explicit retry and
  manual-region recovery actions.
- A full terminate and relaunch skipped onboarding and returned directly to the
  live map, confirming guest onboarding persistence.
- Eight named captures have eight distinct SHA-256 hashes. Captures remain
  local and untracked.

## Remaining runtime gates

- Successful hosted sign-in, token refresh, sign-out, and `/api/v1/me`
  synchronization require an approved test account.
- Web CORS/origin behavior still needs an interactive Web runtime check.
- The inspected tenant is development-only; production-tenant selection and
  connector readiness remain operational decisions.

## 2026-09-02 Google sign-in correction

- A real Google sign-in returned a valid public profile but LALA `/me` sync
  failed. The Logto console showed that the Native app and LALA API Resource
  were configured, while the local Flutter build had requested the Logto
  Management API as its audience instead of the LALA API Resource.
- Corrected the ignored local build configuration without printing its other
  values. The standard build resolver and `LalaAuthConfig` now reject this
  management-audience mix-up so a bad build fails before hosted sign-in.
- Successful `/me` synchronization on a freshly rebuilt iPhone 17 Pro remains
  the runtime acceptance gate for this correction.
