# V4-C — Docent QA Framework (Spec + V7 Manual-QA Checklist)

> Authoritative companion to the V4-C section of
> [`v4-rag-docent-speech-qa-contract.md`](./v4-rag-docent-speech-qa-contract.md).
> V4-C commits the missing eval fixture + a repeatable offline QA harness. The live LLM judge
> and live on-device QA are **V7 BLOCKED_EXTERNAL**; this doc defines the on-device checklist
> for that later phase (not executed in V4).

## 1. Purpose

The cleanroom plan (`cleanroom-rag-docent-speech-qa-contract.md` §12) requires a committed
test/eval fixture of 30–50 representative places so the docent script path can be exercised
deterministically, offline, with no provider call and no product-data ingestion. The existing
sampler (`docent_quality_qa.select_representative_candidates`) is live-DB only; this framework
replaces that gap with a **synthetic, committed** fixture and a **repeatable offline harness**.

## 2. Owned files

| File | Role |
|---|---|
| `apps/api/tests/fixtures/docent_eval_places.json` | Synthetic 30–50-place fixture (`eval_` prefix, all 4 categories, ≥1 honest-empty). |
| `apps/api/app/services/docent_eval.py` | Eval logic: load fixture, build `DocentScriptRequest`, run `docent_service.generate_script`, return structured results. Imports `docent_service` read-only. |
| `apps/api/app/tools/run_docent_eval.py` | CLI harness: load → eval → assert → write `output/local/docent-eval/report.json` → pass/fail exit. |
| `apps/api/tests/test_docent_eval_harness.py` | Fixture schema, harness pass/fail, category coverage, honest-empty, single-language, boundary mock. |
| `docs/planning/v4-docent-qa-framework.md` | This document. |

**Not edited (hard boundary):** `docent_service.py`, `docent_quality_qa.py`,
`run_docent_quality_qa.py`, `ai_service.py`, `apps/api/app/schemas/*`, `openapi.py`, any
Flutter file, `feature_flags.py`.

## 3. Fixture format

A JSON array of 30–50 synthetic place objects. Each object:

```json
{
  "place_id": "eval_attraction_01",
  "category": "attraction",
  "region_ko": "서울",
  "region_en": "Seoul",
  "place_name_ko": "별빛 언덕 전망대",
  "place_name_en": "Starlight Hill Observatory",
  "language_samples": ["ko", "en"],
  "grounding_anchors": ["..."],
  "scores": { "final_score": 0.82, "local_spending_score": 0.7 },
  "weather": { "weather_temp": "21", "weather_icon": "partly-cloudy", "weather_outdoor_status": "good" },
  "expect_nonempty": true
}
```

- `place_id` is always prefixed `eval_` and is **not** product data.
- `category` ∈ {`attraction`, `restaurant`, `event`, `culture_venue`} (mirrors
  `CATEGORY_TARGETS_40` coverage intent).
- ≥1 entry has `expect_nonempty: false` with empty `place_name_*`/`region_*` and no
  `scores`/`weather` — this exercises the honest-empty path (the docent service surfaces its
  `DOCENT_CONTEXT_REQUIRED` unavailable state rather than fabricating a script).

Current committed fixture: **35 places** — attraction 10, restaurant 9, event 7,
culture_venue 9, including 1 honest-empty (`eval_minimal_context_00`).

## 4. Harness behavior

`run_docent_eval.py`:

1. Loads the fixture.
2. Enters `docent_eval.offline_openai_guard()`:
   - Installs a no-network fake `openai` module at the boundary (the established
     `FakeOpenAI`/`monkeypatch` pattern from `tests/test_ai_service.py`).
   - Clears `LALA_ENABLE_LIVE_AI` so `generate_script` takes the **rule-based** path
     (`_rule_based_script`); the fake module is defense-in-depth so the live branch — if ever
     reached — makes zero network calls. A counter proves the live client was never constructed.
3. For each place × `language_samples`, builds a `DocentScriptRequest` and calls
   `docent_service.generate_script`. `ServiceError` is caught and recorded as the
   empty/unavailable state (no crash).
4. Asserts: 30–50 places; all 4 categories covered; each `expect_nonempty` place yields
   non-empty single-language text in BOTH KO and EN with `source == rule_based_curation`; the
   honest-empty fixture yields empty/unavailable with no fabricated content; no internal
   `eval_` ID leaks into any script; no placeholder/mock terms.
5. Writes a deterministic JSON report to `output/local/docent-eval/report.json` (gitignored).
6. Prints a pass/fail summary; exits 0 on all-pass, non-zero otherwise.

Run:

```bash
# from repo root
python -m apps.api.app.tools.run_docent_eval
# or from apps/api
python -m app.tools.run_docent_eval
```

### Offline + honesty discipline (binding)

- No live provider call, no network, no DB read, no crawl, no ingestion.
- `LALA_ENABLE_LIVE_AI` stays False; the OpenAI client is mocked at the boundary only.
- Fixture places are synthetic (`eval_` prefix), never real product data.
- The honest-empty path surfaces (does not crash) for the minimal-context fixture; no
  fabricated content. Standard OpenAI only, never Azure (unchanged).

## 5. Acceptance mapping (V4-C)

| # | Criterion | Where |
|---|---|---|
| C1 | 30–50 synthetic fixture places; `eval_` prefix; all 4 categories; ≥1 honest-empty | fixture + `test_fixture_*` |
| C2 | Offline with OpenAI mocked at boundary; zero live calls; flag stays False | `offline_openai_guard` + `live_client_constructions` counter |
| C3 | Each `expect_nonempty` place yields non-empty KO and EN single-language scripts | `test_nonempty_places_render_single_language_scripts` |
| C4 | Honest-empty fixture yields empty/unavailable, no crash, no fabricated content | `test_honest_empty_yields_unavailable_no_fabrication` |
| C5 | Deterministic JSON report; exit code reflects pass/fail | `run_docent_eval.main` + `test_run_docent_eval_cli_exits_zero_on_pass` |
| C6 | `test_docent_eval_harness.py` green | 14 tests |
| C7 | No edit to `docent_service.py`/`docent_quality_qa.py`/`run_docent_quality_qa.py`/`ai_service.py`/schemas/openapi; no Flutter edit | diff is new-files-only |
| C8 | `ruff check`+`ruff format --check` clean; pytest green (focused + no regression) | verification section below |
| C9 | This doc present with V7 manual-QA checklist | §6 |

---

## 6. V7 manual-QA checklist (on-device — NOT executed in V4)

V7 turns the live LLM judge (`docent_qa_judge`) and live on-device QA on. The 30–50 fixture
places map 1:1 to manual on-device verification samples. For each representative place, a human
QA operator (or the supervisor) performs the steps below on a real device with the live docent
+ speech providers configured.

### 6.1 Pre-conditions (V7 gate)
- [ ] `LALA_ENABLE_LIVE_AI` is ON and a **Standard OpenAI** key is configured (never Azure).
- [ ] `LALA_ENABLE_LIVE_SPEECH` is ON and a TTS provider is configured.
- [ ] `docent_qa_judge` is ON (live LLM judge).
- [ ] Device on a stable network; app signed in; location permission granted.
- [ ] The committed fixture (`docent_eval_places.json`) is available as the sample roster.

### 6.2 Per-place on-device steps (repeat for each of the 30–50 fixture places, KO and EN)
1. [ ] Open the place detail / docent surface for the fixture place.
2. [ ] Trigger docent script generation.
3. [ ] **Non-empty:** the script renders non-empty, single-language text (KO for the KO
      sample, EN for the EN sample); no mixed-language leakage.
4. [ ] **Grounding:** the script does not contradict the fixture's `grounding_anchors` and
      introduces no facts beyond verified context (no fabricated names, hours, prices, history).
5. [ ] **No internal leakage:** no raw `eval_` place ID, no numeric scores, no internal
      table/cache names appear in the user-facing script.
6. [ ] **Honest unavailable (for `expect_nonempty: false`):** the surface shows the empty /
      unavailable state (no crash, no fabricated script, no spinner hang).
7. [ ] **Speech (when live):** tapping play synthesizes audio from real bytes; if bytes are
      absent or speech is off, the honest "Voice guide unavailable" state is shown (V4-B wiring).
8. [ ] **Judge score (when live):** the live `docent_qa_judge` returns a score/reason for the
      generated script and the reason is consistent with the visible script.
9. [ ] Record pass/fail + any honesty violation into the V7 QA ledger.

### 6.3 Category coverage gate
- [ ] All 4 categories (`attraction`, `restaurant`, `event`, `culture_venue`) verified
      on-device across the fixture, mirroring `CATEGORY_TARGETS_40` intent.

### 6.4 Honesty regression checks
- [ ] Toggling the live flags OFF returns the app to the rule-based / honest-unavailable
      behavior exercised in V4-C (no partial live state).
- [ ] No provider other than Standard OpenAI is ever used (Azure firewall holds).

### 6.5 V7 exit criteria
- [ ] Every fixture place passes §6.2 for both languages, OR a documented honesty exception is
      filed; the live judge score distribution is recorded for the fixture set.
