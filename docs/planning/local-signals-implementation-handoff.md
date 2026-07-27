# Local Signals implementation handoff

> Scope: independent LS-1 session in `lala-local-signals-implementation`.
> This ledger is the continuation contract for the next session. It records
> evidence and decisions; it does not claim DB apply, deployment, or runtime
> publication.

## Current state

- Worktree: `/Users/geondongkim/orca/workspaces/LALA-next/lala-local-signals-implementation`
- Base: `origin/main` `f4fac47989a85be1f2ea6855d1c3037a9d77ac5c`
- Branch: `geondongkim/lala-local-signals-implementation`
- Initial checkout was clean; no other worktree or `/Users/geondongkim/LALA-next` files were touched.
- `AGENTS.md` is absent from this repository and LALA-next workspace tree. The applicable parent guidance at `/Users/geondongkim/orca/AGENTS.md` was read.
- Spec commit `a4083ce9a05b8aebde4189e02fd835d4fcf2962f` was confirmed to contain exactly the two clean-room Local Signals documents and was cherry-picked as the first commit in this branch.

## Confirmed

- Existing `community.posts` is provider-ingestion data; `community.user_posts` and `community.chat_*` are the earlier generic community surfaces. Local Signals uses a separate `community.local_signal_*` family.
- Current canonical SQL ends at `062_review_ingestion_governance.sql`; `063_local_signals_contract.sql` is the next free additive migration number after fetching `origin/main`.
- Existing auth derives identity from `require_client_auth` and Logto user identity from `require_logto_identity`. LS-1 schemas do not accept client-supplied author fields.
- Existing public API uses the `success_envelope` contract and the API router currently serves tourism routes with guest access. LS-2 will own authenticated Local Signals routes and policy enforcement.
- Existing Flutter auth has honest `disabled`, `signedOut`, `busy`, `signedIn`, and `error` states. Existing location uses Kakao map bridges, Geolocator/browser conditional layers, manual region fallback, and exclusive KO/EN labels. LS-3/LS-4 consume these contracts later.
- Existing canonical runner is filename-sorted and safety-scanned. The LS-1 migration is additive and re-runnable; no DB apply or seed was run.

## Assumption

- `author_issuer`/`author_subject` remain an internal composite FK in the private base table but are nullable with `ON DELETE SET NULL` so the existing account deletion path can redact identity without deleting published signal content. Public projections intentionally omit both columns.
- Public Local Signals projection exposes first-party signal body/title only after `published` + `public`; this is not third-party review text. RAG must use only the later aggregate candidate contract and never this body.
- A one-level comment depth is represented by `depth` plus `parent_id`; LS-2 service validation must ensure the parent is depth zero before insert.
- `minimum_signal_count >= 3` is the initial aggregate safety floor and still requires moderation, opt-in, delayed aggregation, provenance, and an approved policy version. Product/legal owners may change it before LS-5.

## External decision

- No live review crawl, Naver/Daangn acquisition, paid translation/OpenAI bulk call, DB migration apply, deployment, or real external review collection is authorized in this session.
- LS-2 cannot be considered started until this LS-1 PR is merged. Before LS-2, product/privacy owners must decide contributor trust labels, locality precision policy, moderation ownership/SLA, translation provider/cost/opt-out, retention/deletion, and aggregate/RAG threshold policy.
- LS-4 must preserve Kakao map, conditional location imports, manual-region fallback, and existing planner/weather contracts rather than introducing a parallel location or map path.

## LS-1 phase evidence

- Planned files: `sql/canonical/063_local_signals_contract.sql`, `apps/api/app/schemas/local_signals.py`, focused contract tests, canonical schema required-relation inventory, and this ledger.
- Not in scope: FastAPI routes, repositories, moderation workers, rate-limit implementation, Flutter tabs, map/planner integration, translation execution, RAG worker changes, fixtures/seeds, DB apply, deployment.

## LS-1 phase closeout

- Implemented additive contract: `063_local_signals_contract.sql` with signal lifecycle, moderation state, visibility, coarse locality, canonical place/opaque route links, translation provenance, reaction/comment/save/report/capability tables, aggregate eligibility, and safe public/aggregate projections.
- Implemented API schema contract: `apps/api/app/schemas/local_signals.py` with `extra=forbid`, KO/EN-only language normalization, opaque references, no client author identity, no coordinates, and no internal score fields.
- Focused verification: `18 passed, 1 warning` for Local Signals, canonical SQL, and DB schema tests.
- Relevant API verification: `994 passed, 1 warning` for `apps/api/tests`.
- Static verification: Ruff check passed, Ruff format check passed, pre-commit all hooks passed after the expected `.secrets.baseline` line-number refresh, and staged `git diff --check` passed.
- No DB apply, migration runner, seed, mock/demo fixture, live crawl, paid AI/translation call, deployment, or external review collection was run.
- Branch is ready for the LS-1 conventional commit and Draft PR step. LS-2 remains blocked on this PR's merge plus the external decisions above; no LS-2 implementation has started.

## Published draft status

- Draft PR: [#69](https://github.com/3dt-1st-org/LALA-next/pull/69)
- Base/head at PR creation: `main` / `geondongkim/lala-local-signals-implementation`.
- Implementation commit before this ledger closeout: `b441b60` (`feat(community): add Local Signals schema contract`); the final branch head includes this ledger update as a separate documentation commit.
- GitHub Actions had not produced a run or check result at the time of this handoff. Local verification above is the available evidence.
- Do not merge this PR from the implementation session. After merge, LS-2 may begin only as a separate review unit and must consume the frozen `063`/Pydantic contracts.

## PR #69 rebase and CI evidence — 2026-07-27

- Fetched `origin/main` at `bf24ff8a48f23b70d6869e5d560789294b9579f5` and rebased this branch onto it without reset/restore/clean.
- `git merge-tree` identified `.secrets.baseline` as the only conflict. Both sides' baseline entries were retained; only the conflicting `generated_at` metadata was normalized, then detect-secrets/pre-commit verified the current line positions.
- Rebase result before this ledger closeout commit: `1a18931`.
- Post-rebase local evidence: focused `18 passed`; full API `1008 passed, 1 warning`; Ruff check/format passed; all pre-commit hooks passed; `git diff --check` passed.
- GitHub Actions run [`30208098327`](https://github.com/3dt-1st-org/LALA-next/actions/runs/30208098327) completed green: API tests and safety contracts, Unix wrapper verification, and Flutter app analyze + test all succeeded.
- Last validated code head `eab348f6f7106e5db23545ad2a4c74f76745c1ee` was pushed with `--force-with-lease`. Follow-up GitHub Actions run [`30208293647`](https://github.com/3dt-1st-org/LALA-next/actions/runs/30208293647) completed green for all three required checks; PR #69 reported `mergeStateStatus=CLEAN`, `state=OPEN`, and `isDraft=true` against `origin/main` `bf24ff8`. This line records the last validated code head; the subsequent ledger-only closeout commit does not change LS-1 functionality and is rechecked by CI before handoff.
- No secret value, source `.env`, live API, DB, crawl, deployment, or paid AI/translation call was read or used. PR remains Draft and merge is prohibited.

## LS-2 API and policy phase — 2026-07-27

### Confirmed

- LS-1 PR #69 is merged into `origin/main` at `a2e1ed939447fb0babedd05fd15a4c48edcc0cae`. LS-2 uses the separate clean worktree `/Users/geondongkim/orca/workspaces/LALA-next/lala-local-signals-ls2` and branch `geondongkim/lala-local-signals-ls2`; the former LS-1 worktree is not reused.
- Public reads use only `community.local_signal_public`, which requires published + approved + public rows. Public schemas omit Logto issuer/subject, private draft/moderation internals, exact location, capability/report tokens, and third-party review fields.
- Mutations use `require_logto_identity`; client payloads contain no author identity or client-controlled status. Draft creation/edit, submit-to-pending, owner deletion, reactions, comments, saves, and reports are covered by ownership, transition, deterministic policy, idempotency, and rate-limit seams.
- `LOCAL_SIGNALS_READ` and `LOCAL_SIGNALS_WRITE` are central registry entries with non-secret default-off values and honest `LOCAL_SIGNALS_DISABLED` responses.
- Approved Naver Blog API or other lawful review evidence remains a separate review/mention ingestion domain. LS-2 does not ingest or join it; raw blog/review text is excluded from Local Signals public responses, RAG, docent, and operational logs, with only a future governed aggregate lane permitted.
- Local verification: focused LS-2/API contract tests `82 passed, 1 warning`; full API suite `1073 passed, 1 warning`; Ruff check/format, pre-commit all-files including detect-secrets, and `git diff --check` passed.
- Implementation commit: `e17d943107129c516103b28318dc845f55a80287` (`feat(community): add Local Signals LS-2 API policy`). Draft PR: [#72](https://github.com/3dt-1st-org/LALA-next/pull/72). CI run `30210921754` completed green: API tests and safety contracts, Unix wrapper verification, and Flutter app analyze + test. PR remained Draft/Open with `mergeStateStatus=CLEAN`; no merge was performed.

### Android real-device build/verification handoff — secret-safe

- This LS-2 review-fix session did not build, install, or call a live Android device. The later device gate must use the existing Flutter/Logto/Kakao boundaries and must not introduce a mock/demo Local Signals path.
- If an explicitly approved device verification needs configured values, load only in a subshell from `/Users/geondongkim/LALA-next/.env` with `set -a; source /Users/geondongkim/LALA-next/.env; set +a`; never copy the file into this worktree, commit it, print it, or save raw logs. Pass only named `--dart-define` values and clear the process environment after the run.
- Secret-safe variable-name handoff: Flutter/API base and auth names are `LALA_API_BASE_URL`, `LALA_API_BEARER_TOKEN`, `LALA_IOS_API_KEY`; native Logto names are `LOGTO_ENDPOINT`, `LOGTO_NATIVE_APP_ID`, `LOGTO_API_AUDIENCE`, `LOGTO_REDIRECT_URI`, and `LOGTO_POST_LOGOUT_REDIRECT_URI`; server JWT names are `OAUTH_ISSUER`, `OAUTH_AUDIENCE`, `OAUTH_JWKS_URL`, and `OAUTH_REQUIRED_SCOPES`; map build configuration is `KAKAO_JAVASCRIPT_KEY`.
- Android evidence should record build variant, app build SHA, API base host, auth mode (`guest/read-only` or `Logto signed-in`), Local Signals flag state, permission-denied/manual-region behavior, and safe response/error outcomes only. Do not record tokens, environment values, raw signal body, or third-party review text; keep screenshots/build outputs under ignored artifacts.

### Assumption

- The current idempotency implementation is a process-local seam for this API slice. A durable distributed idempotency store must replace or back it before multi-instance production rollout.
- Public locale filtering omits a source-language signal when no approved translation exists for the requested KO/EN mode; it does not silently show mixed-language content.

### External decision

- Product/privacy owners still need to decide moderation ownership and SLA, draft/published/report retention and deletion, translation provider/cost/provenance and contributor opt-out, and approved review-evidence retention and aggregate/RAG threshold policy.
- DB migration apply, seed/mock data, deployment, live Naver/OpenAI/translation calls, crawl, and external review collection were not run in LS-2.

## LS-3 Flutter public read phase — 2026-07-27

### Confirmed

- LS-3 uses the clean sibling worktree `/Users/geondongkim/orca/workspaces/LALA-next/lala-local-signals-ls3` from `origin/main` `fc6ffa448ed13c668f6e36d827b95734e803412b5`; the older LS-1 worktree and `/Users/geondongkim/LALA-next` were not edited.
- The main shell now has four branches in the existing order: search, map, plan, and Local Signals. The fourth tab is `/local-signals`; KO/EN labels are exclusive to the configured mode.
- The Flutter reference client calls only `GET /api/v1/community/signals` through the existing Dio/auth/error boundary. Its app model retains only the public projection: first-party title/body, language/translation availability, coarse locality, observation/publication date, canonical place links, and disclosure. Author issuer/subject, private/moderation fields, precise location, capability/report tokens, scores, and third-party review bodies are not represented in client state.
- Guest/public reads remain read-only. LS-3 does not expose write, reaction, save, sign-in, or capability controls because LS-2 write capability is not part of this PR; the screen discloses `Public reading` instead of implying an unavailable action.
- RegionContextStore remains the single location boundary. Only a manually selected coarse `regionId` is sent as `region`; live `current` coordinates and the synthetic `current` id are never sent. The existing ManualLocationSheet remains the region selector. No Kakao map, Geolocator/browser import, planner, weather, or parallel location state was added.
- `LOCAL_SIGNALS_READ` remains default-off. A server `LOCAL_SIGNALS_DISABLED`/503 response renders an honest disabled state; no demo, mock, seed, placeholder card, or fallback signal is used. Enabled responses cover loading, empty, safe error, loaded, and opaque-cursor load-more UI states.

### Assumption

- A visible fourth tab with an honest disabled state is the least surprising readiness behavior: the existing three tabs remain unchanged while the server flag is off, and the Local Signals surface does not claim data readiness. Product may later choose to hide the branch entirely if the central feature-flag/readiness contract gains an explicit client-safe capability signal.
- Translation execution is not part of LS-3. `translation_available` is display metadata only; no paid provider or bulk translation call is made.

### External decision

- LS-4 must define the canonical place-detail/map-selection entry point and plan-action contract before this tab adds any map or schedule action. It must preserve the existing Kakao marker/cluster and planner/weather/location invariants.
- Before enabling `LOCAL_SIGNALS_READ` for a client environment, operations must confirm the published/approved/public data source, safe error/readiness policy, and client-safe feature-flag rollout. LS-3 did not apply migration `063`, seed data, deploy, call live review/translation/OpenAI services, crawl, authenticate a real Logto user, or run a real device.

### LS-3 phase evidence

- Added public client/backend boundary, safe projection parser, four-tab route/nav, coarse manual-region filter, loading/empty/disabled/error/loaded states, and focused safety/route tests.
- Focused Flutter verification: `7 passed` in `test/features/local_signals/local_signals_page_test.dart` and `test/shared/lala_bottom_nav_bar_test.dart`.
- Flutter client verification includes the public Local Signals query/cursor/auth-boundary test in `clients/flutter/test/lala_api_client_test.dart`.
- Full verification: Flutter `analyze` passed and `flutter test` passed with `192` tests; the Flutter reference client suite passed with `27` tests; API suite passed with `1084 passed, 1 warning` under `KEY_VAULT_URL=` offline-safe settings. Ruff check/format, pre-commit including detect-secrets, and `git diff --check` passed.
- Draft PR evidence: commit `c8b3c40872763bda4081aab924e7649011717b73` was pushed to [PR #75](https://github.com/3dt-1st-org/LALA-next/pull/75). Initial CI run [`30221120823`](https://github.com/3dt-1st-org/LALA-next/actions/runs/30221120823) passed API tests and safety contracts, Unix wrapper verification, and Flutter app analyze + test. The PR remains Draft/Open; no merge was performed.

## LS-3 contract correction follow-up — 2026-07-27

### Confirmed

- PR #74 was already merged before this follow-up. The LS-3 branch was rebased onto `origin/main` `fe0026709362e66403c686fd1de520c64c8918864`; the only rebase conflict was `.secrets.baseline`, which was reconciled from both sides and revalidated with `detect-secrets` without reading or printing secret values.
- The Flutter public projection now accepts only the API `kind` enum (`place_tip`, `route_note`, `local_question`, `accessibility_note`, `seasonal_update`, `correction`, `local_story`) and `commercial_disclosure` enum (`none`, `visitor`, `owner_or_staff`, `paid_or_gifted`). Each kind has exclusive KO/EN labels, and every non-`none` disclosure renders an explicit notice. The legacy boolean disclosure shape is rejected.
- Region changes use a request-generation guard so an older in-flight region response cannot replace the latest region's list. The regression test completes the old response first and asserts it remains absent.
- Follow-up local verification: focused Flutter `analyze` and Local Signals widget tests passed (`11` tests); full Flutter tests passed (`195` tests); Flutter reference client tests passed (`27` tests); full API tests passed (`1092 passed, 1 warning`); pre-commit including `detect-secrets` and `git diff --check` passed.

### Assumption

- The existing visible fourth tab remains the client readiness behavior: when the server read flag is off, it shows an honest disabled state and never inserts demo/mock signals. No LS-4 map, place-detail, schedule, or location state was added in this correction.

### External decision

- After the rebased follow-up is pushed, CI must be green before PR #75 is marked ready and squash-merged. LS-4 still owns place/map/plan action contracts; device validation, DB apply, deployment, live external review/translation/OpenAI calls, crawl, and real Logto authentication remain outside this work.

## P1-0 canonical contract reconciliation — 2026-07-28

### Confirmed

- Worktree: `/Users/geondongkim/orca/workspaces/LALA-next/lala-contract-reconciliation-p1-0`
- Branch: `geondongkim/lala-contract-reconciliation-p1-0`
- Base SHA: `906543d71ff03eba7ffdced0dbdb6886f2e6829b` (`origin/main`)
- Validated implementation/document parent head: `def0c43ba84d3f84b51a409fbb1fd17e32581372`
- `apps/api/app/services/canonical_sql.py` now owns an explicit 13-file merged baseline, validates three-digit numeric prefixes, rejects duplicate prefixes, orders custom offline fixtures deterministically, and reports production baseline drift through an unsafe plan.
- `apps/api/tests/test_canonical_sql.py` protects the exact latest baseline `063_local_signals_contract.sql`, duplicate/invalid prefixes, future `064` drift, and fake-runner failure without DB access.
- `docs/planning/p1-contract-reconciliation.md` records SQL/API/worker/Flutter/test ownership and CURRENT/DRAFT_PR/TARGET/BLOCKED_EXTERNAL status for the shared contracts.
- PR #76, #77, and #78 remain Draft and were not modified. The root RAG WIP `064_rag_knowledge_retrieval_metadata.sql` was not added, renamed, applied, rebased, or assigned an owner.

### Not verified

- Real DB schema, migration apply, API runtime, worker execution, AWS Secrets Manager/IAM, official source API, live AI/translation/TTS, crawl, deployment, Flutter runtime, and physical device/browser behavior were not run.
- `064` and later migration ownership remains unresolved by design.

### External decision

- P1-1 is limited to an official data source inventory and coverage dry-run contract: provenance/terms metadata, cursor/dedupe normalization, place identity/region/category/image URL rules, and synthetic coverage fixtures. It must not include bulk ingest or DB apply.
- P1-1 remains blocked on official source terms/license, data-file access, IAM/secret inventory, DB ownership/numbering, cost/quota, and freshness/coverage policy.

### Validation

- `uv sync --extra dev` completed in this clean worktree without reading `.env` or `.env.local`.
- `uv run pytest apps/api/tests/test_canonical_sql.py apps/api/tests/test_openapi_contract.py` -> `24 passed, 1 warning`.
- `uv run ruff check .` -> passed.
- `uv run ruff format --check .` -> passed.
- `uv run pre-commit run --all-files` -> hooks passed after the expected detect-secrets baseline line-number refresh and trailing-whitespace cleanup.
- `git diff --check` -> passed.

### Security and scope

- No secret value, DSN, token, PII, raw review body, precise location, AWS request, DB connection, migration apply, external API, live AI/translation call, crawler, seed/mock data, deployment, or device validation was run or recorded.
- This phase contains only canonical runner/test regression protection, the shared contract ownership document, and this handoff. Nationwide ingest, review batch, RAG `064`, planner, and Flutter UI work remain out of scope.
