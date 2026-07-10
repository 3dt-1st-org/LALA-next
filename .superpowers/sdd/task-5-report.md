# Task 5 Report: Operations, OpenAPI, Readiness, and Deployment Handoff

## Status

DONE

## Commits

- Implementation: `caf4bb6` (`feat(auth): align guest auth operations contracts`)
- This report is committed separately so it can record the implementation hash.

## Implementation

- Readiness treats `LALA_GUEST_ACCESS=true` as configured guest client access,
  uses the runtime JWT validation tuple, and reports OAuth and Logto Management
  configuration as `configured`, `partial`, or `skipped` without exposing values.
- OpenAPI marks tourism routes guest-accessible through an empty security
  alternative while retaining optional validated bearer/API-key credentials.
- `GET /api/v1/me` and `DELETE /api/v1/me` advertise only OAuth bearer auth and
  include account success, deletion request, empty 204, and error schemas.
- Added fixed, label-free counters for OAuth success, JWT rejection, and account
  deletion service failures.
- Updated `.env.example`, AWS, Vercel, OpenAPI, and Flutter handoff documents for
  Flutter web on Vercel, FastAPI on AWS EC2 behind nginx/Cloudflare, and RDS.
- Removed the AWS runbook's plaintext RDS password example and live AWS resource
  identifiers. Runtime database credentials are resolved through Secrets
  Manager without printing them.
- Documented Logto API, Native, Web, M2M, Google, and Apple setup, identity SQL,
  EC2/Vercel rollout, smoke checks, rollback, and metrics.
- Documented Apple upstream authorization revocation as a live connector release
  gate. The server has no supported provider-token fallback; failure blocks
  launch pending a separately reviewed supported design.

## RED/GREEN Evidence

1. Initial focused RED:
   `python -m pytest apps/api/tests/test_health_auth.py apps/api/tests/test_openapi_contract.py apps/api/tests/test_observability.py apps/api/tests/test_task5_deployment_contract.py -q`
   failed at the new guest readiness, atomic OAuth status, OpenAPI guest/account,
   observability, environment, topology, Apple gate, and plaintext-password
   assertions.
2. Guest metric and account error accuracy RED:
   `test_metrics_treats_guest_identity_as_ready` and
   `test_openapi_documents_account_operations` failed before guest was a ready
   metric status and before 409 was limited to account GET.
3. OpenAPI compatibility RED:
   the HEAD baseline reported removal of `X-API-Key` from both `/api/v1/me`
   operations. A focused regression test failed before the compatibility checker
   allowed only this correction of previously inaccurate account documentation.
4. GREEN:
   all focused and broad commands below passed after the minimum implementation
   changes.

## Final Verification

- Focused readiness/OpenAPI/compatibility/observability/docs tests:
  `64 passed`.
- Broad API suite:
  `441 passed` with `apps/api/tests/test_smoke_api_script.py` excluded and
  `apps/api/tests/test_safety_contracts.py::test_unix_scripts_parse_with_bash`
  deselected as required by the brief.
- `python -m compileall -q apps/api/app`: passed.
- In-process OpenAPI export: passed with 10 paths.
- Compatibility against an OpenAPI schema exported from pre-Task-5 HEAD:
  passed with zero findings.
- `git diff --check` on Task 5 files: passed.
- Changed production/docs secret scan: zero matches for private keys, API-key
  shapes, JWT shapes, credential-bearing PostgreSQL URLs, or nonblank secret,
  password, token, and DSN assignments.
- AWS runbook live-identifier scan: zero matches for account IDs, EC2/VPC/SG/EIP
  IDs, IPv4 addresses, or RDS hostnames.

## Warnings and Constraints

- FastAPI's test client emits the existing `StarletteDeprecationWarning` about
  the `httpx` integration; it does not fail tests.
- Git reports the repository's existing LF-to-CRLF conversion warnings. The two
  accepted CRLF shell-test failures were excluded exactly as required; unrelated
  scripts were not normalized.
- The worktree's `.python-version` requests an unavailable local Python 3.13.
  Verification used uv-managed Python 3.11, which satisfies `requires-python >=
  3.11`.
- No tracked OpenAPI snapshot exists or is required by current repository tests;
  exports were written only to `/tmp` for verification.
- No Flutter Task 4 file was modified or committed by Task 5.
- No live Logto, AWS, Vercel, Cloudflare, Apple, Google, or database resource was
  changed. Live connector smoke and Apple upstream revocation verification were
  not performed; Apple verification remains a release gate before launch.
