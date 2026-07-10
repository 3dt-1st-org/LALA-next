# Backend Final Review Fix Report

Date: 2026-07-10
Base HEAD: `2d9adfa8ad0f8339bca981a1f59ba79dd409f4e0`
Scope: backend findings I2-I5 only

## Implemented Fixes

### I2: Optional Logto Collections

- A 404 from the grants or sessions collection now skips only that collection.
- The final Logto user DELETE always runs.
- A 404 from the final user DELETE remains an idempotent success.
- Separate tests cover grants collection 404, sessions collection 404, and user DELETE 404.

### I3: Persistent Deletion Tombstones

- Added `identity.deleted_users` with only a 32-byte `identity_digest` and
  `deleted_at`. It stores no issuer, subject, email, or token.
- The digest is SHA-256 over the canonical Logto issuer, a NUL separator, and
  the subject.
- Provision and deletion finalization take the same digest-derived PostgreSQL
  transaction advisory lock.
- Provision checks the tombstone before inserting or updating `identity.users`.
- Finalization deletes the active/deleting local row and inserts the tombstone
  in one transaction. The unique digest and `ON CONFLICT DO NOTHING` make
  retries idempotent.
- A stale JWT receives `410 ACCOUNT_DELETED`; a different Logto subject has a
  different digest and can provision normally.
- Upstream failure still leaves the existing local row in `deleting` state so a
  later retry can complete.

### I4: Logto-Only Account Operations

- `GET /api/v1/me` and `DELETE /api/v1/me` now require an OAuth issuer exactly
  matching the issuer derived from the current valid `LOGTO_ENDPOINT`.
- `LOGTO_API_AUDIENCE` must also be configured for this dependency to pass.
- Legacy OAuth, issuer mismatch, and partial Logto configuration return the
  same safe 401 response.
- Legacy OAuth remains accepted by the existing tourism-route authentication
  path.
- Issuer rejection happens before the Logto Management client receives a
  subject.
- OpenAPI descriptions document the Logto-only issuer boundary and the GET 410
  response.

### I5: Identity Schema Deployment Gates

- The canonical verifier now requires the `identity` schema,
  `identity.users`, `identity.deleted_users`, all identity columns with expected
  types/nullability, and both required unique constraints.
- `/readyz` now reports `identity_schema` separately from the existing `db` and
  `postgis` checks. Missing identity storage degrades overall readiness without
  changing the meaning of the general DB status.
- The OpenAPI readiness schema includes `identity_schema`.
- The AWS runbook now runs the schema verifier explicitly and requires
  `identity_schema=configured` before promotion.

## TDD Evidence

RED failures reproduced all requested defects:

- optional collection 404 stopped before the final user DELETE;
- tombstone relation, repository methods, 410 mapping, and atomic finalization
  were absent;
- legacy and partial Logto identities passed the generic OAuth dependency;
- identity schema objects, columns, unique constraints, readiness status, and
  runbook gate were absent.

Each production change was made only after its focused test failed for the
expected reason. Focused I2-I5 and cross-contract tests then passed.

## Verification

- Focused backend integration: 179 passed.
- Broad API suite: 506 passed, 1 deselected. Exclusions match the accepted
  baseline: `test_smoke_api_script.py` omitted and only the CRLF shell parse
  test deselected.
- Python compile: `python -m compileall -q apps/api/app` passed.
- Fresh OpenAPI export: 10 paths.
- OpenAPI compatibility against `openapi-f9551bb.json`: zero findings.
- Added-line high-confidence secret scan: zero matches for private keys, JWTs,
  provider tokens, AWS access keys, or credential-bearing PostgreSQL URLs.
- Production logging scan found no subject, digest, token, DSN, or issuer log
  emission in the changed backend paths.
- `apps/flutter_app` was not modified.

## Residual Verification Boundary

No live Logto tenant or PostgreSQL instance was used. PostgreSQL transaction
and constraint behavior is covered by repository/query contract tests, but the
AWS rollout must still apply the canonical SQL and pass the documented live
schema verifier and readiness checks before promotion.
