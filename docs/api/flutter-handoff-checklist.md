# Flutter Handoff Checklist

Use this checklist for the current Flutter web/native handoff. Flutter web runs
on Vercel. FastAPI runs on AWS EC2 behind nginx and Cloudflare, with PostgreSQL
on RDS.

## Required Public Configuration

Provide these through local dart-defines or the Vercel build environment:

- `LALA_API_BASE_URL`
- `LOGTO_ENDPOINT`
- `LOGTO_API_AUDIENCE`
- `LOGTO_NATIVE_APP_ID`
- `LOGTO_WEB_APP_ID`
- `LOGTO_REDIRECT_URI`
- `LOGTO_POST_LOGOUT_REDIRECT_URI`

Application IDs, endpoint, audience, and redirect URIs are public configuration.
Do not hand off a Logto client secret, M2M secret, connector credential, static
API token, API key, database value, or DSN to Flutter.

The backend must set `LALA_GUEST_ACCESS=true` for the guest-first rollout. It
must also configure a complete canonical `LOGTO_ENDPOINT` plus
`LOGTO_API_AUDIENCE` pair, or a complete legacy issuer/audience/JWKS tuple.

## Guest Tourism Routes

These routes work without credentials:

```text
GET  /healthz
GET  /readyz
GET  /openapi.json
GET  /api/v1/places
GET  /api/v1/weather
POST /api/v1/docents/script
POST /api/v1/docents/audio
POST /api/v1/plans/daily
GET  /api/v1/plans/intervention
```

Bearer and migration API-key credentials remain optional on tourism routes for
transition clients. Any presented credentials are validated. An invalid or
malformed header returns 401 and must never silently downgrade to guest.

The app starts guest tourism requests without waiting for Logto. After sign-in,
the reusable client asks its access-token provider for a fresh API token before
each authenticated request.

## OAuth Account Routes

Account operations are Bearer-only OAuth operations:

```text
GET /api/v1/me
DELETE /api/v1/me
```

- Static bearer and `X-API-Key` credentials are not accepted.
- `GET /api/v1/me` returns `user_id`, `created_at`, and `authenticated=true` in
  the standard JSON envelope.
- `DELETE /api/v1/me` sends exactly
  `{"confirmation":"delete-my-account"}` and returns an empty 204 response.
- Deletion is retry-safe after an upstream failure.
- The Flutter UI must not display, log, persist, or report provider identity or
  access-token values.

Apple upstream revocation remains a live release gate described in
`docs/operations/aws-deployment-runbook.md`; a passing local deletion response
does not waive that gate.

## Runtime Checks

Before handing off a build:

1. Confirm `/healthz` returns 200.
2. Confirm `/readyz` reports `client_auth=configured`,
   `client_identity=guest`, `guest_access=enabled`, `jwt_validation=configured`,
   and the intended RDS/PostGIS data mode.
3. Confirm `logto_management=configured` for account deletion rollout.
4. Confirm guest places and weather succeed without headers.
5. Confirm a deliberately invalid presented credential returns 401.
6. Confirm Native and Web hosted sign-in each acquire a LALA API access token.
7. Confirm `GET /api/v1/me` succeeds after sign-in and rejects static
   credentials.
8. Confirm sign-out returns the app to guest mode without hiding tourism data.
9. Confirm account deletion requires UI confirmation and handles 204 without
   parsing JSON.

Do not paste response bodies from account routes into tickets or chat. Correlate
failures using the safe `X-Request-ID` value.

## Repository Verification

```bash
python -m apps.api.app.tools.check_flutter_client_contract
scripts/unix/export_openapi.sh --in-process
scripts/unix/verify_flutter_client.sh --require-dart
scripts/unix/verify_flutter_app.sh --require-flutter
```

When browser tooling is available:

```bash
scripts/unix/smoke_flutter_web.sh \
  --require-flutter \
  --require-browser \
  --fail-on-console-error \
  --web-url "$DEPLOYED_WEB_URL" \
  --expect-build-sha "$EXPECTED_BUILD_SHA"
```

Expected artifacts:

- OpenAPI JSON at `artifacts/openapi/lala-next-openapi.json`.
- Human-readable API contract at `docs/api/flutter-contract.md`.
- Reference client at `clients/flutter/lib/lala_api_client.dart`.
- Flutter session integration at `apps/flutter_app/lib/auth/`.

## Failure Handoff

- Guest route 401 with no headers: verify `LALA_GUEST_ACCESS` and readiness.
- Invalid credential unexpectedly succeeds: block rollout; guest fallback must
  not accept presented invalid credentials.
- `/me` accepts static auth: block rollout; account operations are OAuth-only.
- JWT validation partial: restore the complete canonical or legacy tuple as one
  unit.
- Deletion 503: retain the local deleting state and retry after the dependency
  recovers.
- Apple upstream authorization remains present: block launch and follow the AWS
  runbook release gate.
