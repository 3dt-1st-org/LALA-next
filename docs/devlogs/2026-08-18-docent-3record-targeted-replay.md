# 2026-08-18 Docent 3-Record Targeted Replay Support (Phase A)

## Summary

Safe, network-free groundwork for correcting the 3 REWRITE records from the
independent 80-record rubric (77 PASS / 3 REWRITE): the bounded live docent QA
runner (`apps/api/app/tools/run_docent_live_qa_sample.py`) gains a repeatable
`--target place_id:language` selection mode. No paid call is made in this
change; Phase B (exactly three paid calls) runs only after controller
acceptance of this checkpoint.

Confirmed correction targets (from the final post-V7 run artifacts):

| place_id | language | rubric defect |
| --- | --- | --- |
| `tour-api-1316965` | ko | grounding serialization leak |
| `tour-api-1017547` | en | romanization must be `Jungmyeongjeon` |
| `tour-api-130420` | en | romanization must be `Hanbat` |

## CLI contract

```bash
uv run python -m apps.api.app.tools.run_docent_live_qa_sample \
  --target tour-api-1316965:ko \
  --target tour-api-1017547:en \
  --target tour-api-130420:en
```

- `--target PLACE_ID:LANGUAGE` is repeatable; order-insensitive. The issued
  calls follow manifest order (then the place's `language_samples` order), so
  repeated runs are deterministic.
- Without `--target`, the default full 30-50-place run is byte-for-byte
  unchanged (proven by an old-vs-new differential harness: identical POST
  sequence and identical report payload minus timestamps).
- In targeted mode, before the weather lookup and before any POST, the runner:
  1. validates the authoritative manifest (30-`RUN_CAPS["max_places"]` rows,
     no duplicate/missing `place_id`);
  2. rejects malformed targets (exactly one `:`, non-empty parts, language in
     `ko|en`);
  3. rejects duplicate targets, unknown place ids, and languages outside the
     place's `language_samples`;
  4. enforces the planned-call cap (`RUN_CAPS["max_calls"]`).
  Any failure exits 2 with no network traffic.
- Every existing cap still applies: `max_calls`, `max_estimated_cost_usd`
  stop-loss (unchanged in-loop), `max_places` manifest bound. `--limit` is a
  full-run concept and is ignored in targeted mode.
- Targeted runs print only the planned call count and cap values — no scripts,
  secrets, coordinates, provider identifiers, or request payloads. The report
  gains `selection: {mode, targets}` (ids only); raw scripts remain in the
  gitignored `output/local/` report only.
- The targeted path reuses the same `run()` loop, `build_request_body`, and
  production `POST /api/v1/docents/script` construction — no second
  implementation, no mock lane, no force flag, no direct DB access.

## Regeneration and cache behavior (proven from code, no values)

- **Every runner request regenerates.** `docent_service.generate_script` reads
  `fetch_docent_script_cache` only when the request has no score, grounding, or
  request context (`apps/api/app/services/docent_service.py`, the
  `_has_score_context`/`_has_request_context` gate). The runner's request body
  always carries `place_name` and `upstream_source` (plus weather fields), so
  the cache branch is unreachable and each call regenerates through the live
  standard-OpenAI lane with the existing rule-based fallback.
- **A successful POST does not write any cache.** `save_docent_script_cache`
  (`apps/api/app/services/db_repository.py`) has zero production callers, and
  `apps/api/tests/test_v1_routes.py` asserts the save seam is never invoked by
  the route. Conclusion for Phase C: the three successful requests will NOT
  update a normal cache; there is no cache-invalidation step to perform. Fresh
  generation happens per client request that carries context.

## Paid-call boundary

- Phase A made zero paid calls. All tests mock both HTTP helpers; any attempt
  to reach the network fails the test.
- Phase B is exactly the three targeted pairs above against the established
  production endpoint, with the existing stop-loss and delay. No Speech calls,
  no crawl, no deploy, no DNS/auth changes, no unrelated production writes.
- Raw generated scripts are written only under gitignored `output/local/` and
  are never committed or echoed.

## Verification

```bash
# Focused new tests (all networking mocked)
cd apps/api && uv run pytest tests/test_docent_live_qa_sample.py -q

# Related suites
cd apps/api && uv run pytest tests/test_docent_quality_qa.py tests/test_v1_routes.py -q

# Lint / format
uv run ruff check apps/api/app/tools/run_docent_live_qa_sample.py apps/api/tests/test_docent_live_qa_sample.py
uv run ruff format --check apps/api/app/tools/run_docent_live_qa_sample.py apps/api/tests/test_docent_live_qa_sample.py
```

Test coverage added (`apps/api/tests/test_docent_live_qa_sample.py`):

- default full-run behavior unchanged (call sequence, counters, report without
  `selection`);
- exact three-target selection in manifest order regardless of CLI order;
- one language from a bilingual place (no sibling-language call);
- fail-before-network for: missing place, duplicate target, malformed targets
  (parametrized), unsupported language, language not sampled for the place,
  and undersized manifest;
- targeted planned-call cap enforcement before any network;
- `parse_target` language whitelist.

## Operational preconditions for Phase B

- The authoritative 40-place manifest (`output/local/docent-qa-lane-c/qa_manifest_40places.json`)
  is gitignored and no longer present on disk — the prior lane worktree was
  cleaned. It must be re-supplied under this worktree's gitignored
  `output/local/` before the three paid calls; the final run report retained
  the per-place ids/names/categories/regions/expectations needed to rebuild it.
  The runner validates whatever manifest path it is given before any call.
- Rollback: revert this commit; the default full-run path is untouched, so
  reverting removes only the targeted mode.

## Phase B addendum (2026-08-18, post controller acceptance of Phase A)

Executed after independent Phase A acceptance at `f36db84`. Counts and
verdicts only; raw scripts remain exclusively under gitignored
`output/local/docent-qa-lane-c/correction-3records/`.

### Manifest rebuild

- Rebuilt from the read-only final artifact (stage-5 final run report): 40
  unique place ids with safe metadata only (names/categories/regions/
  expectations/language samples). No scripts copied; nothing invented.
- `primary_source: tour_api` set per the repo's governed-source contract for
  `tour-api-*` ids (corroborated: 78/80 original scripts carry the tour_api
  source label). `sample_features`/addresses omitted (unrecoverable; zero
  original scripts reference scores, so omission matches observable behavior).
- Canonical English names set only for the two audited EN targets:
  `Jungmyeongjeon`, `Hanbat Education Museum`.

### Dry proof (network-mocked) and execution

- Mocked dry run: exactly 3 POSTs — the three intended pairs — 0
  sibling-language calls, 1 weather GET, selection hash `57ed328987aed4d2`.
- One targeted execution against the established production endpoint: 3 calls,
  3 HTTP 200, 0 service errors, 0 transport errors, exit 0. Live generation
  lane for all three (no rule-based fallback). The deployed envelope reports
  no token counters for this endpoint; the stop-loss recorded $0 estimated.
  No Speech/audio, no crawl, no deploy, no DB writes.

### 11-dimension manual rubric (3/3 PASS)

Local machine-readable verdicts:
`output/local/docent-qa-lane-c/correction-3records/manual-rubric-3records.json`
(the historical 80-record rubric is preserved unchanged).

| place_id | lang | verdict | defect and evidence of correction |
| --- | --- | --- | --- |
| `tour-api-1316965` | ko | PASS | serialization leak → 0 template markers, 0 provider ids (regex battery re-run); precheck 96, no tags |
| `tour-api-1017547` | en | PASS | `Myeongjeongjeon Hall` → `Jungmyeongjeon` present, wrong form absent |
| `tour-api-130420` | en | PASS | `Hanhat` → `Hanbat` present, wrong form absent; secondary tokens (Uam-ro, Samsung-dong, Dong-gu) correct revised romanization |

All other dimensions clean for all three: language purity (zero hangul in EN,
zero long-latin in KO), zero score leakage, zero fabricated quotes (2 sigils
on one record are possessive apostrophes), zero markdown/TTS sigils, zero
indoor/outdoor assertions, weather restatements consistent (precheck weather
10/10 x3), region/local context named, docent persona confirmed (the two EN
`category_persona_weak` precheck tags are the documented N8 EN-tooling
artifact, superseded by the manual pass — same treatment as the 80-record
rubric), bilingual pairing intact per place.

### Operational status (Phase C input)

- As proven in Phase A from code: these requests regenerate on demand and no
  script cache write exists (`save_docent_script_cache` has no production
  callers; route tests assert the seam stays idle). Nothing remains to
  invalidate or update on the server; future client requests with context
  regenerate fresh.
- No merge, no deploy, no production DB mutation performed.
