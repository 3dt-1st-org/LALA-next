# Task 5 Report: Operations, OpenAPI, Readiness, and Deployment Handoff

## Status

DONE - independent review fixes included.

## Commits

- Initial implementation: `caf4bb6` (`feat(auth): align guest auth operations contracts`)
- Independent review fixes: this commit.

## Independent Review Fixes

- Logto Management readiness now uses the same HTTPS origin validation and
  canonical `LOGTO_ENDPOINT` fallback as the runtime management client. Invalid
  scheme, path, userinfo, query, and fragment values report `partial` rather
  than `configured`.
- Account deletion failures are counted once inside the authenticated deletion
  orchestration boundary. JWT/JWKS 503 responses before deletion starts are not
  counted; identity, Logto, and unexpected deletion-stage failures are counted.
- OpenAPI compatibility compares effective operation security requirements.
  The `/me` auth-header migration exception is limited to the exact OAuth-only
  current contract; anonymous access, static auth reintroduction, unrelated
  header removal, and security drift on other routes remain breaking.
- `GET /api/v1/me` and `DELETE /api/v1/me` expose only `OAuthBearerAuth`, with no
  raw `Authorization` or `X-API-Key` parameters. Their 503 descriptions are
  method-specific.
- The root Vercel Python fallback remains unchanged. Flutter deployment uses the
  tracked `deploy/vercel/flutter-static.vercel.json` template and
  `scripts/prepare_flutter_vercel_static_output.py` to generate ignored
  `static-output/`, followed by `vercel deploy static-output --prod`. The
  effective frontend config is contract-tested to exclude `/api/index.py`.

## RED/GREEN Evidence

1. Management readiness RED: the parameterized endpoint test failed for all five
   invalid endpoint forms (`5 failed, 4 passed`). GREEN: readiness plus Logto
   Management tests passed (`18 passed`).
2. Deletion metric RED: JWKS unavailability was incorrectly counted and an
   unexpected deletion-stage exception was missed (`2 failed, 2 passed`). The
   review also exposed and corrected a false-positive setup in the prior Logto
   failure test. GREEN: metric cases plus `/me` lifecycle tests passed
   (`12 passed`).
3. OpenAPI RED: exact auth-header migration, anonymous/static/general security
   drift, raw auth parameter removal, and GET 503 description produced six
   expected failures. GREEN: all OpenAPI contract and compatibility tests passed
   (`20 passed`).
4. Vercel RED: the isolated static template was absent. GREEN: all deployment
   contract tests passed (`7 passed`).

## Final Verification

- Focused readiness, Logto, `/me`, observability, OpenAPI, deployment, and safety
  tests: `113 passed, 1 deselected`.
- Broad API suite: `458 passed, 1 deselected`, excluding
  `apps/api/tests/test_smoke_api_script.py` and deselecting only
  `apps/api/tests/test_safety_contracts.py::test_unix_scripts_parse_with_bash`
  as required for the accepted CRLF baseline.
- `python -m compileall -q apps/api/app scripts/prepare_flutter_vercel_static_output.py`:
  passed.
- In-process OpenAPI export: passed with 10 paths. CLI compatibility against the
  exported schema passed with zero findings; focused tests cover the known
  migration and negative security cases.
- `git diff --check`: passed.
- Changed-file secret scan: zero matches across 16 files for private keys,
  high-confidence provider tokens, JWTs, credential-bearing PostgreSQL URLs, or
  nonblank production secret/password/token/DSN assignments.

## Warnings and Constraints

- FastAPI's test client emits the existing `StarletteDeprecationWarning` about
  the `httpx` integration; it does not fail tests.
- Git reports the repository's existing LF-to-CRLF conversion warnings. The
  accepted CRLF shell parse test was deselected exactly as required; unrelated
  scripts were not normalized.
- Ruff is not installed or declared in the project dev dependencies, so no Ruff
  result is claimed. Compile and pytest verification completed successfully.
- No Flutter Task 4 file was modified.
- No live Logto, AWS, Vercel, Cloudflare, Apple, Google, or database resource was
  changed. Live connector smoke and Apple upstream revocation verification were
  not performed; Apple verification remains a release gate before launch.
