# V4 — RAG Docent + Speech + QA Framework Design Contract (D1–D9 per lane)

> Phase V4 contract off the V3 head `6eac790` (PR #134). One V4 branch + one Draft PR.
> Authoritative for V4. **Offline + CI only.** Live docent/speech/QA-on-device = **V7 BLOCKED_EXTERNAL**.

## 0. V4 is a reconcile + offline-verify phase (not greenfield)

Three read-only maps of the tree at `6eac790` establish that the RAG docent, speech, and
QA-judge surfaces **already exist and are flag-gated OFF**. V4's roadmap scope is therefore
mostly **VERIFIED_OFFLINE**, with exactly two small greenfield code lanes (V4-B, V4-C).

### 0.1 VERIFIED_OFFLINE (no code lane — carry-in for V4-F verifier)
| Requirement | In-tree evidence @ `6eac790` | Gate |
|---|---|---|
| RAG knowledge store + fail-closed firewall | `sql/canonical/036_rag_knowledge_tables.sql:20-28` `source_type IN (place_profile, culture_event, community_post, place_mention, weather_context)` — `community_signal_aggregate` excluded **by absence** | schema-enforced |
| Hybrid retrieval seam | `apps/api/app/services/rag_retrieval.py:125` `fetch_hybrid_candidates` (ANN+keyword+RRF) | `rag_retrieval_mode` default `legacy` |
| Docent grounding | `db_repository.fetch_docent_knowledge_context*` (`:726/:854/:927`), `fetch_docent_place_profile_context` (`:791`) | — |
| Docent script generation | `POST /api/v1/docents/script` (`routers/v1.py:125`), `docent_service.generate_script` (`:63`), `ai_service.generate_docent_script_text` (`:75`, docent role `gpt-5.4-mini`) | `LALA_ENABLE_LIVE_AI` default **False** → `_rule_based_script` (`:135/:138`) deterministic fallback |
| Citations + retrieval metadata (§13) | `docent_service.py:160-169` (`citations`, `retrieval.{selected,reranker,candidate_pool,fallback_reason}`) | hybrid-mode opt-in only (provenance-safe) |
| Docent QA judge | `apps/api/app/services/docent_quality_qa.py`, `apps/api/app/tools/run_docent_quality_qa.py` | `docent_qa_judge` default **False** |
| Speech (TTS) endpoint | `POST /api/v1/docents/audio` (`routers/v1.py:139`), `speech_service.synthesize_docent_audio` | `LALA_ENABLE_LIVE_SPEECH` default **False** → `SPEECH_NOT_CONFIGURED` 503 |
| Standard OpenAI, never Azure (LLM paths) | `_build_openai_client` (`review_attribute_batch.py:458` `base_url=https://api.openai.com/v1`), Azure firewall `config.py:313-328` | enforced at every resolution |
| Flutter already calls docent + audio | `clients/flutter/lib/lala_api_client.dart:274` (script) + `:339` (audio); `LalaDocentScript.fromJson` (`:1297`), `LalaAudioResponse` (`:1650`) | — |

### 0.2 external_decision (flagged for supervisor/user — NOT a V4 code action)
- **Speech provider choice (Azure Speech vs Standard OpenAI TTS):** the existing `/docents/audio`
  uses Azure Speech (raw HTTP, `speech_service.py`). The hard invariant says "Standard OpenAI
  only, never Azure." Because live speech is OFF + offline-only in V4, V4 does **not** activate
  or port either provider. The live provider decision is **BLOCKED_EXTERNAL (V7)**. V4 builds
  the offline playback wiring (V4-B) that is provider-agnostic.
- `/api/v1/docents/reason` (cleanroom §13): ABSENT in tree. It is an on-demand score/reason
  surface (a V1 invariant concern), **out of V4-roadmap scope** → DEFERRED, not a V4 lane.

### 0.3 Greenfield code lanes (the V4 build)
- **V4-B (Flutter, contract-first):** docent narration **playback** — the app fetches docent
  audio bytes (`home_page.dart:557-648`) and renders a `volume_up` CTA in 5 widgets but
  **never plays them** (no audio package in any pubspec). V4-B adds a player + wires
  `LalaAudioResponse.bytes` + honest-unavailable gating + offline tests.
- **V4-C (Python, disjoint from B):** the "30–50 representative places" **eval fixture is not
  committed** (the sampler `select_representative_candidates` is live-DB only;
  `cleanroom-rag-docent-reimplementation-plan.md` §12 requires a committed test/eval fixture).
  V4-C commits a synthetic 30–50-place fixture + a repeatable offline QA harness + a V7
  manual-QA checklist.

## 1. Dependency DAG
```
VERIFIED_OFFLINE base (docent pipeline + retrieval + firewall + gating)  ── already @ 6eac790
        │
        ├── V4-B  (Flutter playback)      ─┐  disjoint (Flutter vs Python)
        ├── V4-C  (QA fixture + harness)   ─┘  ≤2 parallel lanes
        │
        └── V4-F  offline verifier (fresh by-SHA subagent) → V4_PHASE_PASS
```
- V4-B ∥ V4-C run in parallel (Wave 1). No edge between them.
- V4-C is authored against the **existing** `docent_service.generate_script` interface (rule-based
  path); it does **not** depend on V4-B or on any new backend field.
- Integration = ONE integrator cherry-picks V4-B + V4-C into `geondongkim/lala-v4-rag-docent-speech`
  (batch CI). No lane PRs.

---

# V4-B — Docent Narration Playback Contract (Flutter-only)

> Consumes the existing `LalaAudioResponse.bytes` (`lala_api_client.dart:1650`) and the existing
> fetch flow (`home_page.dart`). **Provider-agnostic:** plays whatever bytes the backend returns;
> when speech is off the backend 503s and V4-B shows an honest unavailable state.

## B1. Scope
Add real audio playback for docent narration behind the existing voice affordances, gated on
`liveSpeechEnabled`, with an honest unavailable state. Keep all existing fetch/state/UI scaffolding.

**NOT in V4-B:** any backend/api/schema/feature_flags edit, any provider (Azure/OpenAI) call, the
QA harness (V4-C owns), `plan_slot_tile.dart`/`intervention_toast.dart` (V3 owns).

## B2. Data bindings (existing, unchanged)
- `LalaAudioResponse.bytes: Uint8List?`, `requestHash`, `cacheKey` (`lala_api_client.dart:1650`).
- `LalaReadiness`/`LalaRuntimeMode` → `isLiveSpeechEnabled(readiness)` (`home_view_helpers.dart:368`):
  `readiness?.mode?.speech == 'live-azure' || readiness?.checks['live_speech'] == 'enabled'`.
- State owner: `home_page.dart` (`_docentAudio`, `_tourAudio`, `_voiceEnabled`, `_audioLoading`).

## B3. ASCII wireframe (playback surface, widens existing affordances)
```
┌─────────────────────────────────────────────────────┐
│ 🔊 <docent script line, single-language KO or EN>    │
│   [ ▶ 재생/Play ]   [ ⏸ 일시정지/Pause ]              │  ← liveSpeechEnabled AND bytes present
│   ─ bytes absent / speech off ─                       │
│   (음성을 사용할 수 없어요 / Voice guide unavailable) │  ← honest unavailable
└─────────────────────────────────────────────────────┘
```

## B4. Render decision (Mermaid)
```mermaid
flowchart TD
  A[voice affordance tapped] --> B{liveSpeechEnabled?}
  B -- no --> Z[honest 'unavailable' state, no fetch]
  B -- yes --> C[fetch script+audio (existing flow)]
  C --> D{bytes present?}
  D -- no --> Z
  D -- yes --> E[▶ Play → player.play(bytes)]
  E --> F[playing ↔ pause toggle]
  F --> G[done/error → reset to ▶]
```

## B5. Exclusive file ownership
- NEW `apps/flutter_app/lib/features/docent/playback/docent_audio_player.dart` — thin player
  wrapper (interface + impl). Exposes `play(Uint8List)`, `pause()`, `resume()`, `stop()`,
  `dispose()`, and a `ValueListenable<DocentPlaybackState>` (`idle|loading|playing|paused|done|error`).
- NEW `apps/flutter_app/lib/features/docent/playback/docent_playback_controller.dart` — owns the
  per-surface playback state; fed `LalaAudioResponse?`; emits state for the widget. Keeps the
  widget presentational.
- EDIT `apps/flutter_app/lib/features/docent/widgets/docent_subtitle.dart` — render ▶/⏸ from the
  controller; honest unavailable line when `!liveSpeechEnabled` or bytes null. Additive optional
  params only (backward-compat with `FeaturedPlacePanel:127`).
- EDIT `apps/flutter_app/lib/features/docent/widgets/tour_audio_bar.dart` — same wiring.
- EDIT `apps/flutter_app/pubspec.yaml` — add `audioplayers` (stable, pub.dev-resolvable; CI
  already resolves existing pub deps, so network is available). Pin a concrete version.
- NEW `apps/flutter_app/test/features/docent/playback/docent_audio_player_test.dart` —
  controller + widget tests with a FAKE player (no real audio device; offline-safe).

**DO NOT TOUCH:** `home_page.dart` fetch flow (reuse as-is), `dashboard.dart`, any
`apps/api/` or `clients/` file, `feature_flags*.dart`, `widget_test.dart`,
`plan_slot_tile.dart`, `intervention_toast.dart`.

## B6. Backward-compatibility constraint (critical)
`docent_subtitle.dart` / `tour_audio_bar.dart` are consumed by `FeaturedPlacePanel`,
`RouteAndDocentPanel`, `tour_sheet_content`, `map_bottom_dock`. All new params **additive optional
with defaults**; existing callers compile and behave unchanged (today they fetch-only; with V4-B
they additionally play when bytes exist and speech is live — but speech is OFF by default so
runtime behavior is unchanged unless a live provider is configured).

## B7. Responsive + a11y
- Surfaces already `maxWidth: 430`; playback row must wrap/ellipsis, never overflow.
- Play/pause tap targets ≥44dp; `Semantics(label:)` KO/EN on every control; announce state changes
  (`playing`/`paused`/`unavailable`) via `Semantics(liveRegion:)`.
- **No new color tokens.** Reuse existing toast/docent tokens.

## B8. Single-language (KO/EN)
All new copy via `lalaCopy(language, ko:, en:)` (`shared/l10n/lala_copy.dart`). Each mode renders
exactly one language.

## B9. Honesty constraints (BLOCKED_EXTERNAL — V7)
- Never fabricate audio. Play ONLY real `LalaAudioResponse.bytes`.
- `!liveSpeechEnabled` OR bytes null → honest "음성을 사용할 수 없어요 / Voice guide
  unavailable"; hide play control; never auto-fetch when speech is off.
- No live provider call from V4-B (the backend owns synthesis; V4-B only plays returned bytes).
- Offline tests use a FAKE player + sample bytes; never a real audio device or live call.

## B10. Acceptance matrix (V4-B)
| # | Criterion |
|---|---|
| B1 | ▶/⏸ playback of `LalaAudioResponse.bytes` works (offline test with fake player + sample bytes). |
| B2 | `!liveSpeechEnabled` → honest unavailable state, play control hidden, no fetch. |
| B3 | bytes null after fetch → honest unavailable state (no fabricated audio). |
| B4 | Playback state machine `idle→loading→playing↔paused→done/error` emits via `ValueListenable`. |
| B5 | Existing callers (`FeaturedPlacePanel`, `tour_sheet_content`, `map_bottom_dock`) compile + behave unchanged (additive optional params). |
| B6 | `audioplayers` pinned in pubspec; `flutter pub get` + `flutter analyze` + `flutter test` green. |
| B7 | All controls ≥44dp, overflow-safe ≤430, `Semantics` KO/EN labels + live-region announces. |
| B8 | All copy single-language per active mode via `lalaCopy`. |
| B9 | No backend/api/schema/feature_flags edit; no live provider call; no new color tokens; `toJson`=0. |

---

# V4-C — Docent QA Framework Contract (30–50 representative places; Python-only)

> Commits the missing eval fixture + a repeatable offline harness + a V7 manual-QA checklist.
> Disjoint from V4-B. Operates on the **existing** docent interface (rule-based path); no new
> backend field, no edit to `docent_quality_qa.py`/`run_docent_quality_qa.py`.

## C1. Scope
- A committed **synthetic** eval fixture of **30–50 representative places** (NOT product data):
  `place_id` (synthetic, prefixed `eval_`), `category` ∈ {attraction, restaurant, event,
  culture_venue}, `region`, grounding anchors, optional scores/weather context. Category coverage
  mirrors the existing `CATEGORY_TARGETS_40` (`docent_quality_qa.py:12`) intent.
- A **repeatable offline QA harness** that, for each fixture place, runs the docent script path
  **with the LLM mocked at the boundary** (rule-based path / fake OpenAI), and asserts:
  category coverage, KO+EN both produce non-empty single-language text, grounding anchors are
  respected (no fabricated facts beyond the fixture), and honest empty/unavailable states when
  context is missing. Emits a deterministic JSON report.
- A **V7 manual-QA checklist doc** (on-device steps; not executed in V4).

**NOT in V4-C:** any Flutter edit, any live provider call, any edit to
`docent_service.py`/`docent_quality_qa.py`/`run_docent_quality_qa.py`/schemas/openapi, any
product-data ingestion.

## C2. Fixture format
`apps/api/tests/fixtures/docent_eval_places.json` — a JSON array of 30–50 objects:
```json
{ "place_id": "eval_attraction_01", "category": "attraction", "language_samples": ["ko","en"],
  "region_ko": "…", "region_en": "…", "place_name_ko": "…", "place_name_en": "…",
  "grounding_anchors": ["…"], "scores": { …optional… }, "weather": { …optional… },
  "expect_nonempty": true }
```
Plus ≥1 fixture with `expect_nonempty: false` (minimal context) to exercise the honest-empty path.

## C3. Harness behavior
NEW `apps/api/app/tools/run_docent_eval.py`:
- Loads the fixture; for each place + language, calls `docent_service.generate_script` with the
  OpenAI client mocked at the boundary (reuse the established `FakeOpenAI`/monkeypatch pattern
  from `tests/test_ai_service.py`) so **no live call**. `LALA_ENABLE_LIVE_AI` stays False → the
  rule-based path is exercised; the mock covers the live path without a network call.
- Asserts: non-empty when `expect_nonempty`; category coverage across the set; KO and EN each
  render exactly one language; no grounding anchor contradiction.
- Writes `output/local/docent-eval/report.json` (deterministic; gitignored output) + prints a
  pass/fail summary. Exit 0 on all-pass, non-zero otherwise.

## C4. Exclusive file ownership
- NEW `apps/api/tests/fixtures/docent_eval_places.json`.
- NEW `apps/api/app/tools/run_docent_eval.py`.
- NEW `apps/api/app/services/docent_eval.py` (eval logic; imports `docent_service` read-only; does
  NOT edit it).
- NEW `apps/api/tests/test_docent_eval_harness.py` (fixture schema + harness pass/fail + category
  coverage + honest-empty).
- NEW `docs/planning/v4-docent-qa-framework.md` (framework spec + V7 manual-QA checklist).

**DO NOT TOUCH:** `docent_service.py`, `docent_quality_qa.py`, `run_docent_quality_qa.py`,
`ai_service.py`, `schemas/`, `openapi.py`, any Flutter file.

## C5. Honesty constraints (BLOCKED_EXTERNAL — V7)
- Fixture places are **synthetic** (`eval_` prefix), never real product data. No DB read, no live
  crawl, no ingestion.
- The live LLM judge (`docent_qa_judge`) and live on-device QA are V7; V4-C is offline-only with
  the provider mocked at the boundary.
- Honest-empty path must surface (not crash) for the minimal-context fixture.

## C6. Acceptance matrix (V4-C)
| # | Criterion |
|---|---|
| C1 | 30–50 synthetic fixture places committed; `eval_` prefix; category coverage across all 4 categories; ≥1 honest-empty case. |
| C2 | `run_docent_eval.py` runs offline with the OpenAI client mocked at the boundary; **zero live provider calls**; `LALA_ENABLE_LIVE_AI` stays False. |
| C3 | Each `expect_nonempty` place yields non-empty script in BOTH KO and EN (single-language each). |
| C4 | Honest-empty fixture yields the empty/unavailable state, no crash, no fabricated content. |
| C5 | Deterministic JSON report written; exit code reflects pass/fail. |
| C6 | `test_docent_eval_harness.py` green (fixture schema, category coverage, pass/fail, honest-empty). |
| C7 | No edit to `docent_service.py`/`docent_quality_qa.py`/`run_docent_quality_qa.py`/`ai_service.py`/schemas/openapi; no Flutter edit. |
| C8 | `ruff check`+`ruff format --check` clean; pytest green (focused + no regression in full suite). |
| C9 | `docs/planning/v4-docent-qa-framework.md` present with V7 manual-QA checklist. |

---

## Hard invariants (unchanged — do not violate)
No merge/deploy/prod-DB/migration-apply/crawl/DNS-auth/paid-AI/device-browser-sim/secret-output;
no mock/demo on the normal path (mock ONLY at the gated provider boundary for offline tests);
one V4 branch + one Draft PR (no lane/RC/checkpoint PRs); preserve dirty root
(`/Users/geondongkim/LALA-next`) + all safety boundaries (Kakao map, Logto, Geolocator +
browser_location conditional imports, KO/EN single-language, on-demand score/reason, category
colors, pin-first clustering); workers glm-5.2 only; **Standard OpenAI only, never Azure**;
never expose keys. RAG firewall must remain fail-closed (`community_signal_aggregate` excluded).
AI generation + TTS flag-gated **OFF by default**; live docent/speech/QA-on-device = V7 BLOCKED_EXTERNAL.

## V4-F verifier carry-in (re-derive — do NOT trust controller claims)
1. Firewall `036:20-28` excludes `community_signal_aggregate` (§0.1).
2. All AI/TTS/QA flags default OFF (`LALA_ENABLE_LIVE_AI`, `LALA_ENABLE_LIVE_SPEECH`,
   `docent_qa_judge`, `docent_audio_cache`, `docent_reason_enabled`, `rag_retrieval_mode`=legacy,
   `rag_embedding_method`=local-hash); flag-off = no normal-path change.
3. `_build_openai_client` + Azure firewall → standard OpenAI, never Azure (LLM paths).
4. V4-B: playback plays only real bytes; honest unavailable when `!liveSpeechEnabled`/bytes null;
   no live provider call; offline tests use a fake player; existing callers unchanged.
5. V4-C: fixture synthetic (`eval_` prefix, 30–50, category-covered); harness offline with provider
   mocked at boundary; no edit to existing docent/QA services; honest-empty path works.
6. Integration delta = V4-B files (Flutter) + V4-C files (Python), disjoint; no off-limits files;
   `toJson`=0; no schema migration; CI 3/3 green.
