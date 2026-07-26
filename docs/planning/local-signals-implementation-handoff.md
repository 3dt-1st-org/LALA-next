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
- Local verification: focused LS-2/API contract tests passed; full API suite `1073 passed, 1 warning`; Ruff/format and `git diff --check` passed. Pre-commit/CI evidence is recorded when available.

### Assumption

- The current idempotency implementation is a process-local seam for this API slice. A durable distributed idempotency store must replace or back it before multi-instance production rollout.
- Public locale filtering omits a source-language signal when no approved translation exists for the requested KO/EN mode; it does not silently show mixed-language content.

### External decision

- Product/privacy owners still need to decide moderation ownership and SLA, draft/published/report retention and deletion, translation provider/cost/provenance and contributor opt-out, and approved review-evidence retention and aggregate/RAG threshold policy.
- DB migration apply, seed/mock data, deployment, live Naver/OpenAI/translation calls, crawl, and external review collection were not run in LS-2.
