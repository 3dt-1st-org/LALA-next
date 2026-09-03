# Round 2 broad product expansion — integration devlog and handoff

Status: consolidated Draft PR on `feature/round2-broad-product-expansion`, awaiting
independent review. Not merged; `main` untouched.

## 1. Base and inputs

- Product integration base: `origin/integration/canonical-screen-completion-20260903`
  @ `f6067a4a5f9fb3a54399c36f3bdb359be97bc02e`.
- All four lane remote heads were re-fetched before integration and matched the
  controller-accepted SHAs exactly:

| Lane | Branch | Accepted head | Verified |
| --- | --- | --- | --- |
| A — visitor access, language, a11y | `origin/feature/round2-visitor-access` | `93df36d9787c58e01aeb87535e05a3b12306befc` | yes |
| B — Local Signals + community honesty | `origin/geondongkim/feature-round2-signals-community` | `fe3f7012a427d8749fa3add97aa3dceddc04e141` | yes |
| C — plan resilience, trip library, visit conversion | `origin/feature/round2-plan-resilience-visit-conversion` | `d63064225ea69f5007e20381721ffdc69aa90176` | yes |
| D — S-30 docent player polish | `origin/geondongkim/feature-round2-docent-polish` | `45fda2d2b8ebeb9290bdcd29d7a9d8371c9e4b2d` | yes |

- Integration method: the 15 lane commits were cherry-picked A → B → C → D onto
  the base with zero conflicts. The lanes own disjoint file sets, and the
  combined tree was verified byte-identical to each lane's accepted content for
  every file that lane owns (`git diff HEAD <lane-head> -- <lane files>` is
  empty for all four lanes). Conventional commit history is preserved; no
  squash or wholesale ours/theirs resolution was needed.
- Combined shape: 40 files, +5294/−758, entirely inside `apps/flutter_app/`
  (lib, test, docs). No API, SQL, client, or routing changes.

## 2. Included behavior by lane

### Lane A — visitor access, language, and place/preference a11y (4 commits)

- Real ja/zh-Hans/zh-Hant copy in place widgets (empty state, event info card,
  event status pill, featured panel, rail, proof row, signal grid, place
  detail notices) via `lalaCopyMulti`; visitor locales never show Hangul.
- Hangul minute-unit leak fixed on visitor-locale preference screens; privacy
  subtitle kept in the app-wide Korean register.
- Text-scaling-safe and semantics-gated S-12/S-13/S-53..S-57: loading/stale
  notices become labelled `Semantics` containers (live regions where
  appropriate), action buttons keep ≥68dp touch targets with 2-line clamped
  labels, and layout survives large text scales.

### Lane B — Local Signals and community honest states (3 commits)

- S-32 comment load failure renders an explicit failure notice with retry
  instead of masquerading as an empty list; reaction/save/report flows covered.
- Mutation receipts label status/moderation/visibility from the exact API
  Literal values, localized in five languages; unknown wire values render as
  the raw contract value rather than an invented moderation claim.
- Community feed refresh clears a retained load-more failure row; ok-envelope
  with null data is treated as honest failure (like rolls back with notice,
  comment keeps typed text); single-language (Korean) surfaces made honest
  rather than machine-translated; chat room list failure handling added.

### Lane C — plan resilience, trip library, visit conversion (5 commits)

- `TripLibraryStore._reconcileDate` stages `putOverride` results and re-checks
  the captured sync epoch before mutating local state, so a PUT completing
  after disconnect/reconnect cannot clobber a newer epoch's reconciliation
  (Completer-gated regression tests verified to fail on unguarded code).
- S-21 intervention comparison shows real change reasons, per-slot constraint
  chips, and closure chips; balanced slots render neutrally; unrecognized
  `indoor_outdoor` wire values never render as "mixed".
- Plan timeline shares saved state (`_SavedMarkerChip`) and surfaces sync
  retry; visit confirmation gets a real retry path; trip-library sync guarded
  against stale completions.

### Lane D — S-30 docent player honest state hierarchy (3 commits)

- Design contract tracked at
  `apps/flutter_app/docs/round2-docent-player-polish-design-contract.md`.
- One playback status card driven only by real `DocentExperienceController`
  phases (checking → preparing script → preparing audio → ready/playing/
  paused/completed, plus honest `unavailable` and `failed`), with a single
  caption source (`safeMessage` else phase label), 44dp controls, live-region
  captions, and 200%-text-scale stacking. No simulated playback, no invented
  timing, readiness gate unchanged. Mini player shares the same copy helpers.

## 3. Cross-lane review results

- No duplicate top-level helpers or copy families across lanes (verified by
  diff scan; each lane's helpers live in its own feature).
- No fake/demo/placeholder/mock normal paths added in `lib/`; retries and
  failure notices bind to real repository/API results.
- All new UI strings route through `lalaCopyMulti`/`lalaCopy` with ko/en/ja/
  zh-Hans/zh-Hant; no raw `Text('...')` locale leaks found in the added code.
- No changes outside the four lanes' owned scopes; no unrelated churn (base
  tree untouched except the 40 owned files).
- The two comparison/reconciliation documents exist on the base
  (`docs/product/lala-stitch-vs-runtime-screen-comparison-v2-20260903.md`,
  `docs/product/lala-canonical-screen-reconciliation.md`). An earlier lane-A
  `/tmp` report claiming they were missing was incorrect; this integration
  does not repeat that claim.

## 4. Local validation at the consolidated head

All run in a clean Orca worktree (no `.env`), before push:

- `git diff --check f6067a4..HEAD` — clean.
- `dart format --output=none --set-exit-if-changed` over the 39 changed Dart
  files — 0 changed.
- `flutter analyze` — No issues found.
- `flutter test` — 916 passed, 0 failed (base tree: 832; the lanes add 84
  widget/unit tests across 7 new focused test files).
- `uv run ruff check .` — all checks passed; `uv run ruff format --check .` —
  243 files already formatted.
- `uv run pytest apps/api/tests -q` — 1895 passed, 1 pre-existing deprecation
  warning, 0 failed.
- `uv run pre-commit run --all-files` — every hook passed, including Detect
  secrets.
- Dart client tests: `clients/` is unchanged by this PR, so no local client
  run was required; CI's reference-client verification job still runs on the
  PR regardless.

## 5. Honest runtime gaps and external gates

Nothing in this PR was validated on a device, against production, or with a
live provider. Concretely:

- All Lane A–D evidence is widget/unit-test level. No simulator or real-device
  capture was performed at the consolidated head.
- Docent voice remains behind the operations readiness gate (paid speech,
  pronunciation QA); S-30 runtime-state capture and a manual VoiceOver/
  TalkBack pass remain open (design contract §7).
- Community and public user-signal feeds remain honestly empty in production;
  no demo content was inserted, and the tab-entry/role-overlap product
  decision for community (functional spec F-080) is still open.
- Local Signals authoring UX remains incomplete as a user feature (F-071
  status unchanged); Lane B only made existing participation surfaces honest.
- Intervention extension fields (temporary-closure windows, forecast windows)
  stay behind their existing flags; real-time routing and temporary-closure
  authority sources remain external.
- Migrations, production writes, deploy, crawl, paid AI/Speech calls: none
  performed, none introduced.
- Promotion of `integration/canonical-screen-completion-20260903` → `main`
  stays a separate explicit release gate (main CI triggers production API
  deploy).

## 6. Documentation reconciliation

- Functional-spec statuses (F-030, F-051, F-070, F-071, F-080, F-081, F-100)
  were re-read against the merged code; none is made stale by it — the lanes
  deepen states and honesty within already-implemented surfaces rather than
  completing the externally gated items those statuses track. No status text
  was changed, to avoid overclaiming.
- Map runtime is Naver Dynamic Map. Tracked `AGENTS.example.md` already says
  so. Stale **local-only** `AGENTS.md` copies (gitignored, predating the
  migration) still carry the old Kakao invariant — recorded here as the
  documentation defect; regenerate local copies from `AGENTS.example.md`.
  Historical design contracts and QA notes that mention Kakao describe past
  phases and are intentionally not rewritten.
- Stitch material referenced by the comparison doc is generated design input
  (conceptual), not runtime truth; runtime claims in that doc and the
  reconciliation doc remain the authority for what is actually verified.

## 7. Five-tab product map (quick teammate orientation)

| Tab | Shell route | Feature families |
| --- | --- | --- |
| 지도 Map | `MapRoutePage` (S-10) | Naver Dynamic Map, place rail, weather/tour sheets, docent dock |
| 검색 Search | `SearchPage` (S-11) | region-scoped API search → S-12 detail |
| 일정 Plan | `PlanPage` (S-20) | four-slot plan, S-21 intervention, S-22 settings, S-25 visit confirmation |
| 로컬신호 Local Signals | `LocalSignalsPage` (S-31) | governed public aggregates, S-32 detail |
| 내정보 My Info | `ProfilePage` (S-50) | account (Logto), S-23/S-24 trip library, community S-40..44, preferences S-52..59 |

Canonical flows and per-screen truth tables: `docs/product/lala-canonical-screen-reconciliation.md`
and `docs/product/lala-service-functional-spec.md`. Auth boundary is Logto for
all writes/chat; reads stay public. Generated docent scripts are RAG text;
voice is a gated representation of the same script.

## 8. Local run/test steps

```bash
uv sync --extra dev
uv run pytest apps/api/tests -q
uv run ruff check . && uv run ruff format --check .
uv run pre-commit run --all-files
cd apps/flutter_app && flutter pub get && flutter analyze && flutter test
```

Run in a worktree without `.env` (a main-checkout `.env` can hang some tests
at import).

## 9. Next slice candidates (for team review)

1. Decide community's permanent entry point and its role split vs. Local
   Signals (F-080 product decision), then wire the chosen surface.
2. Exact-head on-device capture of the S-30 state matrix (and a screen-reader
   pass) to close the comparison doc's open runtime items.
3. Local Signals authoring UX completion (F-071) behind the existing
   moderation/governance contract.
4. Intervention extension fields (closure/forecast windows) once authority
   sources are approved.
