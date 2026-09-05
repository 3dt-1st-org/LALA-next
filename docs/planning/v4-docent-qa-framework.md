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
| `apps/api/tests/fixtures/docent_eval_places.json` | Synthetic fixture — P6A: exactly 40 places (10 per category, `eval_` prefix, ≥1 honest-empty), every place exercising exactly `["ko","en"]` → 80 language cases. |
| `apps/api/app/services/docent_eval.py` | Eval logic: load fixture, build `DocentScriptRequest`, run `docent_service.generate_script`, return structured results incl. `total_places` / `total_language_cases` / per-dimension audit summary. Imports `docent_service` read-only. |
| `apps/api/app/services/docent_qa_dimensions.py` | P6A: deterministic per-dimension audits (source attribution, local context, language purity, usefulness, safety, repetition, grounding, advertising leakage, hallucination) over evidence already present in QA records; pass / flagged / not-applicable only — never a silent pass without evidence. Each audit certifies only its named narrow proxy (e.g. safety = no secret-like text, hallucination = no raw-score leakage, source attribution = clean label presence); broad factual truth, content safety, and source rights are external model/human gates. |
| `apps/api/app/tools/run_docent_eval.py` | CLI harness: load → eval → assert → write `output/local/docent-eval/report.json` → pass/fail exit. |
| `apps/api/app/tools/sanitize_docent_qa_report.py` | Lane C sanitizer; P6A: aggregates the deterministic dimension audits and preserves pass/flagged/not-applicable counts in the report schema and markdown. |
| `apps/api/tests/test_docent_eval_harness.py` | Fixture schema (40/80, exact KO+EN pairing, 10-per-category balance), harness pass/fail, honest-empty, single-language, boundary mock, honest dimension accounting. |
| `apps/api/tests/test_docent_qa_dimensions.py` | P6A: dimension evidence gating, pass/flag/N-A accounting, sanitizer schema, adversarial repetition cases. |
| `apps/api/app/services/docent_judge.py` | P6B: strict fail-closed model-judge contract (one `PASS`/`REWRITE` decision + 11 bounded dimension results, both contradiction directions fail closed), the double live gate (existing live-AI gate + separate `docent_qa_judge` opt-in, resolving the `docent_qa` role separately from docent generation), the provider boundary (injected fake offline, gated live client with `max_retries=0`), sanitized/bounded prompt input (no raw place id, whitelisted metadata, P6A redaction), and the bounded batch policy/runner (hard 80-record cap, sequential canary, finite concurrency, per-record wait timeout, no retries, malformed/failure/usage stop-loss with clamped usage, pre-submission honest-empty skip, fail-closed `INCOMPLETE` aggregate, `SIMULATED` labeling for fake runs). |
| `apps/api/tests/test_docent_judge.py` | P6B: strict parsing, every fail-closed class (both contradiction directions), gate-off behavior, injected fake-provider batches, canary sequencing, 80-record cap fail-closed, stop-loss, timeout/no-retry accounting, honest-empty pre-submission skip with invocation counts, KO+EN examples, prompt/persistence sanitizer safety, stable aggregates, simulated report labeling, and the report's separate judge gate (`NOT_RUN` default). |
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

Current committed fixture (P6A): **exactly 40 places** — 10 in each of `attraction`,
`restaurant`, `event`, `culture_venue`, including 1 honest-empty
(`eval_minimal_context_00`). Every place exercises exactly `["ko", "en"]`, yielding
**exactly 80 language cases**; `evaluate_docent` fails any place whose
`language_samples` is not exactly KO+EN.

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
4. Asserts: exactly 40 places / 80 language cases with exact KO+EN pairing per place; all 4
   categories at 10 each; each `expect_nonempty` place yields non-empty single-language text
   in BOTH KO and EN with `source == rule_based_curation`; the honest-empty fixture yields
   empty/unavailable with no fabricated content; no internal `eval_` ID leaks into any
    script; no placeholder/mock terms. The report also carries
    `dimension_summary` — deterministic per-dimension audits
    (`docent_qa_dimensions`) over the generated scripts with honest
    pass/flagged/not-applicable counts (honest-empty language cases are counted as
    not-applicable, never as pass). Grounding passes are evidence-backed: each
    language-case record carries its fixture's `grounding_anchors` count, so a
    generated case passes grounding only on a proven positive anchor count
    (absent evidence → not-applicable, explicit zero → flagged).
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
| C1 | Exactly 40 synthetic fixture places (10 per category); `eval_` prefix; exactly KO+EN per place (80 language cases); ≥1 honest-empty | fixture + `test_fixture_*` |
| C2 | Offline with OpenAI mocked at boundary; zero live calls; flag stays False | `offline_openai_guard` + `live_client_constructions` counter |
| C3 | Each `expect_nonempty` place yields non-empty KO and EN single-language scripts | `test_nonempty_places_render_single_language_scripts` |
| C4 | Honest-empty fixture yields empty/unavailable, no crash, no fabricated content | `test_honest_empty_yields_unavailable_no_fabrication` |
| C5 | Deterministic JSON report; exit code reflects pass/fail | `run_docent_eval.main` + `test_run_docent_eval_cli_exits_zero_on_pass` |
| C6 | `test_docent_eval_harness.py` + `test_docent_qa_dimensions.py` green | 21 + 40 tests (P6A + correction) |
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

---

## 7. P6A checkpoint status (2026-09-05)

**Offline 40/80 is reproducible after this change.** Exactly:

- `apps/api/tests/fixtures/docent_eval_places.json` holds exactly 40 synthetic `eval_`
  places (10 per category, ≥1 honest-empty, no real account data / coordinates / raw
  reviews / secret or cloud identifiers / unsupported factual claims), each exercising
  exactly `["ko","en"]` → exactly 80 language cases.
- `docent_eval.evaluate_docent` exposes and enforces `total_places == 40`,
  `total_language_cases == 80` (per-language counts included), fails non-KO+EN pairing,
  and keeps the honest-empty path plus the live-client prohibition
  (`live_client_constructions == 0` under `offline_openai_guard`).
- Deterministic QA dimensions (source attribution, local context, language purity,
  usefulness, safety, repetition — plus grounding, advertising leakage, hallucination)
  are machine-checkable via `docent_qa_dimensions`: pass / flagged / not-applicable only.
  A dimension without enough evidence is reported `not_applicable`, never silently
  counted as pass. Grounding is evidence-gated: absent `grounding_count` evidence is
  `not_applicable`, an explicit zero/invalid count is `flagged`, and every offline
  grounding pass traces to a positive committed `grounding_anchors` count carried
  deterministically into each language-case record (honest-empty stays N/A). Repetition
  checks are deterministic, linear-bounded, and immune to short/common particles
  (compact-length floors; 20,000-char scan bound), with adversarial tests in
  `test_docent_qa_dimensions.py`.
- **Scope honesty:** each offline audit certifies only its named narrow proxy —
  `safety` proves absence of secret-like text, `hallucination` absence of raw-score
  leakage, `source_attribution` presence of a clean source label. A regex non-hit
  never proves broad content safety, factual truth, or source-rights usability;
  those judgments remain model/human external gates (below).
- The Lane C sanitizer report schema preserves pass / flagged / not-applicable counts
  for every dimension; sanitized artifacts carry verdict/reason codes and bounded,
  visibly elided, redacted excerpts — at most the first 240 redacted characters of a
  script, never a byte-complete script, with secret-like text, coordinate pairs,
  emails, and phone numbers redacted from excerpts and manual notes. They are not
  raw-text-free by construction: bounded redacted excerpts remain, and raw run
  reports stay gitignored under `output/local/`.

**Remaining separate external gates (out of scope for P6A):**

- Paid live generation against the deployed API (Lane C runner, capped).
- Model-judge scoring (`docent_qa` LLM judge — explicitly not implemented here),
  including broad factual-hallucination review beyond the raw-score proxy.
- Broad content-safety review beyond the secret-leakage proxy (manual/model gate).
- Source-rights usability verification beyond label presence (manual gate).
- Voice playback / on-device speech QA (V4-B/V7).
- Manual human QA rubric review (`docent-quality-manual-qa-strategy.md`).

---

## 8. P6B checkpoint status (2026-09-05): offline-tested model-judge contract

P6B adds the smallest coherent **offline-testable, fail-closed model-judge
boundary** for the established `docent_qa` role. It changes no P6A behavior:
40 synthetic places / 10 per category / exact KO+EN pairing / 80 language
cases / honest-empty / no-live-client guard / evidence-gated deterministic
audits / sanitized artifacts are preserved exactly.

**Implemented scope (exactly):**

- **Strict judge result** (`apps/api/app/services/docent_judge.py`): one
  overall decision `PASS` or `REWRITE`, plus exactly one bounded result per
  dimension — language purity, factual grounding, local context, persona fit,
  useful visitor guidance, unsafe or unsupported claims, source-rights
  caution, Markdown/TTS suitability, weather contradiction, repetition, and
  internal-score leakage — each with a machine-readable status
  (`pass`/`flagged`) and a concise reason code. Parsing is strict: missing,
  malformed, duplicate, unknown, non-finite, out-of-range, or contradictory
  fields fail closed to `REWRITE` with a machine-readable failure reason
  code, in **both** contradiction directions — `PASS` with any flagged
  dimension and `REWRITE` with every dimension `pass` (correction);
  dimension results from an untrusted payload are discarded.
- **Separate role resolution:** the judge resolves the established
  `docent_qa` model role via the existing `model_client.resolve`
  (standard-OpenAI firewall included). No new provider, Azure path, raw-key
  path, or direct-token path was added.
- **Live judging OFF by default:** a production call requires the existing
  explicit live-AI gate (`LALA_ENABLE_LIVE_AI` + API key + base-URL
  firewall) **and** the separate `docent_qa_judge` feature flag
  (`LALA_DOCENT_QA_JUDGE`, default False — the existing registry entry, no
  flag edits). The live client is constructed only inside
  `build_live_provider` behind the double gate, with `max_retries=0`.
  Tests and the offline evaluator inject a fake provider at the boundary and
  make zero network or paid calls.
- **Sanitized, bounded provider input (correction):** the judge prompt never
  carries a raw internal place identifier (identity stays in the record for
  accounting only); language/category are whitelist labels (anything else
  becomes the bounded literal `unknown`); and the script is P6A-redacted
  (secret-like text, coordinate pairs, email/phone) before the 4000-character
  bound. Every public serialization path — including
  `JudgeResult.to_public_dict` — sanitizes or omits model-authored reasons
  and raw identifiers.
- **Bounded batch policy** (`JudgeBatchPolicy`, pure data, provider-free and
  independently unit-testable): hard maximum 80 language records (the
  existing 40-place × KO+EN roster; no policy may exceed it), a small
  sequential canary before the remainder, finite concurrency (≤16, executor
  bounded), a per-record timeout, exactly one provider call per judgeable
  record (no automatic retries that could multiply spend), and a stop-loss
  halting the batch on malformed responses, repeated provider failures
  (timeouts included), or a configured cumulative token/usage ceiling
  (reported usage clamped to ≥ 0 so it can never reduce stop-loss accounting
  — correction). **Honest-empty records are classified and recorded before
  any executor submission in both canary and remainder phases (correction),
  so provider invocations equal the judgeable records.** The batch wait
  timeout abandons only the wait — it never terminates an already-running
  call; the live client's own timeout is authoritative. Halted batches mark
  every unjudged record explicitly skipped — never silently passed.
- **Sanitized persistence only:** outcomes carry the sanitized record
  identity (`eval_` place id + language), the decision, failure/error codes,
  dimension statuses with redacted bounded reason codes, a bounded redacted
  script excerpt reused from the P6A sanitizer (same 240-char visibly elided
  route; secrets/coordinates/email/phone redacted), and aggregate counters.
  Raw provider payloads, raw review text, secrets, personal data, precise
  coordinates, and cloud identifiers are never logged or persisted.
- **Separate optional report gate with fail-closed aggregate (correction):**
  the offline QA report carries a `judge_gate` section. Default (no judge
  run): exactly `{"status": "NOT_RUN"}`, provider-free — never `PASS`. The
  aggregate real-judge gate returns `PASS` only when every judgeable in-cap
  record has a valid `PASS` and there are no provider failures, timeouts,
  incomplete outcomes, halted skips, or cap drops; mixed PASS+error and any
  `dropped_by_cap > 0` report the explicit non-PASS status `INCOMPLETE`.
  Honest-empty skips stay explicit and neutral. Precedence:
  `REWRITE` > `HALTED` > `INCOMPLETE` > `PASS` > `NO_VERDICTS`.
  `run_docent_eval --judge-fake` is simulation-only and is labeled
  unmistakably: top status `SIMULATED` with `provider: OFFLINE_FAKE`,
  `simulated: true`, and the run aggregate nested under
  `simulated_result` — visible in both the report JSON and the CLI summary
  (`judge_gate=SIMULATED`), so a fake run can never satisfy or be mistaken
  for the real model-judge acceptance gate (78 judged, 2 honest-empty skips
  on the committed fixture, nested). The judge gate never modifies the
  deterministic P6A results or the CLI exit code.

**Scope honesty:** the model-judge gate evaluates only what the (live or
fake) provider returns under the strict schema. A simulated offline run is
labeled `SIMULATED` precisely because it says nothing about model quality;
even a live `PASS` is a narrow structured verdict, not proof of broad factual
truth, content safety, source rights, or production readiness. Those remain
external gates below.

**Remaining separate external gates (explicitly NOT executed in P6B):**

1. **Paid canary** — a real paid live-judge canary run against the deployed
   API with the double gate on, under the batch stop-loss.
2. **Real 40-place/80-script regeneration** — regenerating real production
   docent scripts (Lane C) and judging those, not the synthetic roster.
3. **Human manual QA** — the manual rubric review
   (`docent-quality-manual-qa-strategy.md`).
4. **Source-rights review** — usability verification beyond label presence.
5. **On-device audio QA** — voice playback / speech QA (V4-B/V7).
6. **Production runtime wiring** — wiring the judge gate into any production
   runtime/routing surface (none exists; the offline report gate is the only
   consumer).
