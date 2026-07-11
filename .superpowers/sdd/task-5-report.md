# Task 5 Report: Operations, OpenAPI, Readiness, and Deployment Handoff

## Status

IMPLEMENTED - final symlink review fix and verification included.

## Commits

- Initial implementation: `caf4bb6` (`feat(auth): align guest auth operations contracts`)
- First independent review fixes: `620c78e` (`fix(auth): address Task 5 review findings`)
- Second independent re-review fixes: `f081970` (`fix(auth): address Task 5 second review`)
- Final symlink review fix: this commit.

## Final Symlink Review Fix

- Preserved the lexical Flutter source path until `lstat()` rejects a symlinked
  source root, then resolved it only for source/output boundary comparison.
- Walked the complete source tree with non-following `os.scandir()` metadata and
  rejected every nested file or directory symlink before replacing
  `static-output/`.
- Required all five source and staged release artifacts to be non-symlink regular
  files according to `lstat()` metadata. Deploy-time project-binding verification
  therefore also rejects a tampered required-artifact symlink.
- Added source-root, required-file, nested-file, and nested-directory symlink
  tests. Every staging rejection preserves the existing output marker and proves
  no external payload path was copied into the fixed output boundary.

## Second Re-review Fixes

- Added the complete OpenAPI schema exported from the real pre-Task-5 revision
  `f9551bb` (`caf4bb6^`) as a compatibility fixture. A fresh export is
  byte-for-byte identical to the fixture.
- Limited the Task 5 security migration to exact operation fingerprints. The six
  guest operations must move from the legacy Bearer/static alternatives to the
  exact anonymous/Bearer/static contract. `GET /api/v1/me` and
  `DELETE /api/v1/me` must move from the exact legacy security and generated auth
  headers to header-free `OAuthBearerAuth` only.
- Kept anonymous removal, static removal, scope drift, unrelated strengthening,
  unrelated header removal, and incomplete `/me` migration as compatibility
  findings. The generic comparator remains active for every non-migration
  operation and for response/parameter changes.
- Removed the staging script's arbitrary `--output` option. The script accepts
  only the repository `static-output/` target and rejects symlinks, files,
  parent/source paths, and resolved paths outside that boundary before deletion.
- Required the minimum Flutter 3.44 release artifacts before output replacement:
  `index.html`, `flutter_bootstrap.js`, `main.dart.js`,
  `assets/AssetManifest.bin.json`, and `auth-callback.html`. Flutter 3.44.0 was
  checked locally; it emits `AssetManifest.bin.json`, not `AssetManifest.json`.
- Required validated `VERCEL_ORG_ID` and `VERCEL_PROJECT_ID` environment values.
  Staging recreates exact `{orgId, projectId}` metadata at
  `static-output/.vercel/project.json` on every run without printing either ID.
- Added `--verify-project-binding` to validate the fixed deploy root, all required
  artifacts, the exact tracked Flutter `vercel.json`, and the exact project
  binding before `vercel deploy static-output --prod`.

## RED/GREEN Evidence

1. OpenAPI RED: the real baseline produced 12 compatibility findings and CLI
   exit 2. The positive function/CLI tests failed, and the legacy-security
   anonymous-removal regression was not reported. GREEN: all 15 compatibility
   tests pass, including exact migration and negative fingerprint cases.
2. Staging boundary/artifact RED: arbitrary output, symlink targets, parent
   traversal, and absolute siblings could be replaced, while four non-index
   release artifacts were not required. GREEN: the fixed-output and artifact
   contract passed all 20 tests before project binding was added.
3. Project binding RED: staging did not require either Vercel ID, did not create
   `.vercel/project.json`, and had no pre-production verification mode. GREEN:
   the complete deployment contract now passes all 28 tests; its negative subset
   passes 21 tests covering missing/invalid IDs, tampered config/binding, unsafe
   outputs, and every missing artifact.
4. Symlink RED: all five new cases failed because staging followed source-root,
   required-file, nested-file, and nested-directory links, while deploy-time
   verification accepted a required-file link (`5 failed`). GREEN: all five
   regression cases pass, including marker preservation and external-copy checks.

## Final Verification

- Focused deployment contract: `33 passed`.
- Focused OpenAPI compatibility and deployment contracts: `48 passed`.
- Broad API suite: `490 passed, 1 deselected`, excluding
  `apps/api/tests/test_smoke_api_script.py` and deselecting only
  `apps/api/tests/test_safety_contracts.py::test_unix_scripts_parse_with_bash`
  for the accepted CRLF baseline.
- Fresh `f9551bb` OpenAPI export: 10 paths and SHA-256
  `2e59c8659d145fce9224ec239ebfce452aeb7ecdfc70873f4b526c943294179e`;
  byte-for-byte fixture comparison passed.
- Actual compatibility CLI against that fresh export: exit 0, 10 baseline paths,
  10 current paths, and zero findings.
- Symlink regression subset: `5 passed, 28 deselected`.
- `python -m compileall -q apps/api/app scripts/prepare_flutter_vercel_static_output.py`:
  passed.
- Changed-file secret scan: zero matches across 3 files for private keys,
  high-confidence provider tokens, JWTs, credential-bearing PostgreSQL URLs, and
  nonblank secret/password/token/DSN assignments.

## Warnings and Constraints

- FastAPI's test client emits the existing `StarletteDeprecationWarning` about
  the `httpx` integration; it does not fail tests.
- Git reports the repository's existing LF-to-CRLF conversion warnings. The
  accepted CRLF shell parse test was deselected exactly as required; unrelated
  scripts were not normalized.
- Ruff is not installed or declared in the project dev dependencies, so no Ruff
  result is claimed.
- No Flutter Task 4 file was modified. The pre-existing untracked
  `docs/superpowers/` directory was not modified.
- No live Logto, AWS, Vercel, Cloudflare, Apple, Google, or database resource was
  changed. Vercel CLI was not invoked. Live connector smoke and Apple upstream
  revocation verification were not performed; Apple verification remains a
  release gate before launch.
