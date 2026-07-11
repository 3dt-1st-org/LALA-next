# Logto Social Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Every production behavior must follow red-green-refactor TDD.

**Goal:** Add guest-first Logto authentication with Google/Apple-ready Flutter sessions, verified API identities, local user lifecycle, and account deletion.

**Architecture:** Flutter uses Logto's public-client Authorization Code + PKCE flow and supplies a refreshed LALA API access token. FastAPI validates Logto JWTs through issuer, audience, JWKS, algorithm, and expiry checks, distinguishes public/static/OAuth callers, and provisions a minimal local identity keyed by issuer and subject. Existing tourism APIs stay guest-accessible while `/api/v1/me` requires OAuth.

**Tech Stack:** FastAPI, PyJWT, PostgreSQL/PostGIS, httpx, Flutter, Logto Dart SDK, pytest, flutter_test.

## Global Constraints

- Guest access remains available for all existing places, weather, docent, and planner routes.
- Any presented bearer token must be validated even when guest access is enabled; invalid credentials never silently become guest access.
- Email, nationality, and social tokens must not be persisted; provider subjects are stored only as the identity key and must never be logged or used as metric labels.
- Local users are uniquely identified by `(issuer, subject)` and provisioned idempotently.
- Static bearer and API-key credentials may access transition routes but never `/api/v1/me`.
- `GET /api/v1/me` returns `user_id`, `created_at`, and `authenticated=true` in the existing JSON envelope.
- `DELETE /api/v1/me` requires explicit confirmation, is retry-safe, removes local data, deletes the Logto user and sessions, and returns HTTP 204.
- Flutter supports iOS, Android, and Web public clients with no embedded client secret.
- Tokens and provider identifiers must never appear in logs or metrics labels.
- Existing CRLF failures in `scripts/unix/*.sh` are an accepted pre-existing baseline; do not normalize unrelated scripts in this branch.

---

### Task 1: Backend request identity and guest policy

Refactor API authentication into a typed `RequestIdentity` with `public`, `static`, and `oauth` modes. Add `LALA_GUEST_ACCESS`, Logto-compatible environment aliases, optional OAuth scopes, and JWT claim validation. Existing `/api/v1` routes remain available to guests, but malformed or rejected presented credentials return 401. Add focused pytest coverage first and preserve static-auth transition tests.

### Task 2: Local user lifecycle and account API

Add canonical `identity.users` SQL with UUID primary key, issuer/subject uniqueness, timestamps, and deletion state. Implement a repository/service boundary that stores the provider subject only in this identity table, provisions on first OAuth `/me`, and updates `last_seen_at`. Add `GET /api/v1/me` and confirmation-protected, idempotent `DELETE /api/v1/me`. Implement an injectable Logto Management API client that obtains M2M tokens, revokes sessions/grants where supported, deletes the Logto user, and leaves retryable deletion state on upstream failure. Cover all behavior with pytest before production code.

### Task 3: Flutter API client authentication contract

Extend the reusable Dart client to accept an asynchronous access-token provider while retaining static test credentials. Refresh the token before each authenticated request and add typed `getMe` and `deleteMe` calls. Public methods must continue without a token. Write Dart tests first for fresh-token use, missing-token behavior, response parsing, deletion confirmation, and 204 handling.

### Task 4: Flutter Logto session and account UI

Add Logto Dart SDK configuration for native and web public clients, a focused `AuthController`/`AuthSession` boundary, and platform-safe redirect configuration. Keep an explicit disabled state when compile-time Logto settings are absent so existing local development works. Add a compact account section in settings for sign-in, signed-in state, sign-out, and destructive account deletion confirmation. Follow Google/Apple button branding through Logto's hosted sign-in page rather than custom provider buttons. Add controller and widget tests before implementation.

### Task 5: Contracts, operations, and rollout

Update OpenAPI/readiness fields, `.env.example`, AWS deployment documentation, Flutter handoff docs, and smoke tooling for guest access plus Logto settings. Document the external console steps for Native/Web app registration, API audience, Google/Apple connectors, redirect URIs, M2M deletion permissions, Apple authorization-revocation verification, rollout, metrics, and rollback. Add or update contract tests first where documentation/configuration is machine-checked.

### Task 6: Integrated verification and review

Run focused auth/API tests, all non-CRLF Python tests, Dart analyze/tests, Flutter analyze/tests, and release web build. Verify no secret or raw subject is logged. Package the branch diff for final independent review and resolve every Critical or Important finding before completion.
