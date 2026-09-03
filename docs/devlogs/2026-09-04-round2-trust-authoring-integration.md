# Round 2 trust + authoring integration — finalize devlog (2026-09-04)

Status: consolidated Draft PR on `feature/round2-trust-authoring-integration`
→ `integration/canonical-screen-completion-20260903`, awaiting independent
review. Not merged; `main` untouched. Product code was implemented and tested
on two accepted lanes; this finalize pass reconciled the secrets baseline,
product docs, and this devlog, re-ran the focused validation suite, and opened
the single integration PR.

## 1. Base and lane heads (verified exact before finalize)

| Input | Branch | Exact SHA | Integrated as |
| --- | --- | --- | --- |
| Base | `origin/integration/canonical-screen-completion-20260903` | `f97215d097acf402f5d41a566916e1cde2298eae` | — |
| Lane F — Local Signals authoring | `origin/feature/round2-local-signals-authoring` | `f269c4feef2a0c66b26c9dd9d91f36d773f60cd2` | merge `a3469c4` (`--no-ff`) |
| Lane trust — community trust | `origin/feature/round2-community-trust` | `32b13974943152959acd0ba8bfc383ce22cf4ce0` | merge `502fd80` (`--no-ff`) |
| Correction 1 | — | `9f3a501` | S-31 contribution route refresh/deep-link stability |
| Correction 2 | — | `9f61e3b` | neutral localized author label; internal UUIDs never rendered |

Lane heads were fetched and matched the controller-accepted SHAs exactly; lane
files are byte-identical to their lane heads after merge (disjoint file sets).

## 2. What landed (product scope, unchanged by finalize)

- **S-31 authoring (F-071)**: the private-draft composer was extracted (not
  copied) into `LocalSignalContributionComposer`; S-31 gained a visible
  share-experience entry routing through the S-32 detail route in contribute
  mode with the auth gate first. Entry-state matrix, context truthfulness
  (manual coarse region or canonical place; never precise coordinates), input
  protection (dismiss confirm, busy guard, per-field validation, retry-safe
  failures, delete confirm, API-only receipt), and five-locale copy are pinned
  by focused tests. Design contract:
  `apps/flutter_app/docs/round2-local-signals-authoring-design-contract.md`.
- **S-40/S-41 community trust**: author follow by internal user UUID
  (`viewer_following` on reads), governed post reports (bounded six-code
  reason vocabulary, no free text, self-report rejected, idempotent
  duplicate handling), canonical SQL `067_community_post_reports`, and Dart
  client endpoints. Display surfaces render a neutral localized author label
  (여행자/Traveler/…); internal UUIDs are action identifiers only.
- **Corrections**: `9f3a501` makes the contribution route refresh/deep-link
  stable (`/local-signals/contribute` reflected via `context.go`, no
  coordinates/ids in the URL, close-after-restore returns to the feed);
  `9f61e3b` removes the short-UUID author label everywhere (feed, detail,
  comments, chat × five locales) and fixes the vacuous 200% text-scale test.

## 3. Secrets baseline reconciliation

- `uv run pre-commit run --all-files` at the final tree: every hook passed,
  including Detect secrets. No baseline edit was needed in finalize.
- Baseline diff vs base is exactly the trust lane's accepted refresh:
  `line_number` 184→209 in `apps/api/tests/test_canonical_sql.py` plus
  `generated_at`. Version 1.5.0, 27 `plugins_used`, 13 `filters_used`, and
  per-file result counts are unchanged. The new Dart files introduced no
  findings. (Probing was done without `--baseline` writes; the baseline was
  never regenerated in place.)

## 4. Validation at the finalize head

Run in this Orca worktree (no `.env`), product head `9f61e3b` plus docs-only
commits:

| Check | Result |
| --- | --- |
| `git diff --check` (base…HEAD) | clean |
| `dart format --output=none --set-exit-if-changed` over the 21 changed Dart files (19 app + 2 client) | 0 changed |
| `flutter analyze` | No issues found |
| Focused Flutter tests (routing + local_signals + community) | 103 passed, 0 failed |
| Dart client tests (`clients/flutter`) | 42 passed, 0 failed |
| `uv run ruff check .` / `uv run ruff format --check .` | all checks passed / 451 files already formatted |
| Focused API/SQL (`test_community.py` 37, `test_canonical_sql.py` 15, `test_local_signals_contract.py` 6) | 58 passed, 0 failed |
| `uv run pre-commit run --all-files` | every hook passed |

The coordinator independently verified at the same product head: full Flutter
suite 970/970, full API suite, client 42/42, focused API/SQL 121/121, flutter
analyze, and Ruff.

## 5. Documentation updated by finalize

- `docs/product/lala-service-functional-spec.md`: F-071 →
  `IMPLEMENTED_NOT_RUNTIME_VERIFIED` (feature table and section, with the
  S-31 entry/composer described); F-080 gains explicit follow/report rows and
  the same not-runtime-verified qualifier; the priority table now asks for
  authoring **runtime verification** instead of "complete the Flutter flow";
  API map mentions post reports.
- `docs/product/lala-stitch-vs-runtime-screen-comparison-v2-20260903.md`:
  platform-evidence row corrected from 26 to **23** screens lacking final-tree
  captures, matching the verified current-tree list elsewhere in that doc.
- `docs/product/lala-canonical-screen-reconciliation.md`: S-30–S-32 and
  S-40–S-44 snapshot rows and the S-31/S-32/S-40/S-41 route rows now describe
  the round 2 additions as implemented-not-runtime-verified; the verification
  paragraph separates the canonical-tree simulator evidence (832 tests) from
  the current tree (970 tests, no runtime verification of the new flows).
- The 36-canonical-logical-screens fact is preserved: `/local-signals/contribute`
  is the S-32 route in contribute mode, not a new logical screen.

## 6. Honest remaining gates

- The new flows are `IMPLEMENTED_NOT_RUNTIME_VERIFIED`: no simulator/device
  run of S-31 authoring or S-40/S-41 follow/report at this head.
- No live account, no operational data: community and public user-signal
  feeds remain honestly empty; nothing was inserted to demo them.
- `sql/canonical/067_community_post_reports.sql` is tracked code only — no
  migration apply ran against any database.
- No production readiness claim: `main` merge/deploy, production writes,
  crawl, paid AI/Speech, DNS/auth/device/browser/simulator operations all
  stay behind their gates. Runtime map is Naver Dynamic Map.
- Pre-existing, out of scope, recorded not fixed:
  `apps/flutter_app/test/widget_test.dart` carries an older hit-test warning
  on the "Show signals" tap that predates this branch; the root-checkout
  local `AGENTS.md` Kakao-map sentence is stale (tracked `AGENTS.example.md`
  is current).

## 7. Combined-diff review (base…HEAD)

An independent read-only review of all 31 changed files (verified against
`git show f97215d:<path>` for pre-existing behavior) found **no correctness,
security, honesty, or test-weakening defects**: no fake/demo/placeholder data
on normal paths (the `signalId: 'contribute'` router sentinel is inert;
authentication is never simulated; unconfirmed envelopes roll back), no
localization leakage (all new copy routes through `lalaCopyMulti`; zero raw
CJK literals outside `ko:` slots), no raw UUID/PII/review/URL/coordinate
exposure beyond the known accepted wire contract, and no weakened or deleted
tests (follow tests were rewritten at equal or greater strength for the new
contract). SQL/migration spot-checks pass (report reason CHECKs match the
Python `Literal` vocabulary and Flutter options 1:1; idempotent upsert keeps
the original report, matching UI copy).

Confirmed follow-up debt (quality, not defects — product code was **not**
edited in finalize, per scope):

1. `local_signal_auth_gate.dart` is a near-verbatim parameterizable fork of
   the pre-existing `community_auth_guard.dart` (~250 lines: same outcome
   enum, flow, and 6/7 byte-identical copy families). One parameterized
   guard should replace both.
2. The discard-confirmation dialog exists twice — detail page
   `_closeContribution` and composer `_confirmDiscard` — with identical
   ValueKeys and 5-locale copy; the composer should expose the confirmation
   publicly.
3. The follow-toggle sequence (auth gate → optimistic flip →
   `toggleCommunityFollow` → null-data guard → confirm/rollback) is
   duplicated between feed and detail pages; the handler belongs in the
   shared `community_post_actions.dart`.
4. Low: the S-32 composer context line renders the raw locality code as the
   region label (`label: localityCode`); the S-31 path localizes properly.
   Base already showed raw codes in detail metadata, so this follows
   existing practice rather than introducing a new class of exposure.
5. Low: formatting-only re-wraps outside lane scope (`chat_ws_client.dart`,
   `chat_ws_client_test.dart`, parts of `lala_api_client.dart` and
   `local_signals_page.dart`) — consistent with a `dart format` pass over
   whole files; content is byte-identical to the accepted lane heads.
6. Low: the '경험 공유' action-label copy map is defined in both the detail
   page and the auth gate.

## 8. Local run/test steps

```bash
uv sync --extra dev
uv run pytest apps/api/tests -q
uv run ruff check . && uv run ruff format --check .
uv run pre-commit run --all-files
cd apps/flutter_app && flutter pub get && flutter analyze && flutter test
cd ../../clients/flutter && flutter test
```
