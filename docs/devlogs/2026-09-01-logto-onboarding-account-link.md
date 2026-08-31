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

## Remaining runtime gates

- Hosted sign-in cancellation, refresh, sign-out, and `/api/v1/me` against an
  approved test account.
- Web CORS/origin behavior and production-tenant decision.
- iPhone and Web runtime captures after the exact PR head is built.
