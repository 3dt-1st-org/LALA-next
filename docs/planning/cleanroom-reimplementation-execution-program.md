# Clean-Room Reimplementation — Execution Program

> **Status: PLAN-ONLY (documentation).** This document changes no product source,
> SQL, infrastructure, CI, deployment configuration, or the legacy repository. It
> is the single integration layer over five independently authored clean-room
> plans: it fixes **execution order, per-contract ownership, collision rules, and
> acceptance** so implementation cannot drift. It is a **contract between
> implementers**, not a restatement of the plans.
>
> **Authoritative over its inputs on conflicts.** Where two source plans overlap,
> this document's wave order, ownership table, and collision rules win. The five
> plans remain the detailed design references; this program decides *who ships
> what, in which wave, behind which gate*.

## 0. Inputs, Method, and How to Read This Document

### 0.1 Inputs (read-only evidence)

The five clean-room plans are authored in sibling worktrees and are **not** in
this repo's tree, so they are cited by name rather than linked. They land at
`docs/planning/` on `main` once their own PRs merge.

| Plan (sibling worktree) | Domain | Slices owned |
| --- | --- | --- |
| `cleanroom-review-ingestion-reimplementation-plan.md` | Review/mention ingestion + enrichment | R1 |
| `cleanroom-rag-docent-reimplementation-plan.md` | RAG → docent / TTS | V1, D1, T1 |
| `cleanroom-day-planner-weather-location-reimplementation-plan.md` | Day plan + weather/air + location | P1, W1, L1, WA1 |
| `cleanroom-dashboard-map-reimplementation-plan.md` | Map/dashboard/onboarding | M1, O1, onboarding |
| `cleanroom-restaurant-economy-reimplementation-plan.md` | Restaurant discovery + local-economy | R2, economy |

The audited reverse-engineering evidence those plans extend
(`legacy-3dt-first-technical-spec.md`, `legacy-3dt-first-feature-inventory.md`)
lives in the `lala-legacy-technical-spec` sibling worktree and is cited by name.
The read-only legacy tree is `/Users/geondongkim/3dt-1st-Project`; **no** legacy
source, prompt, asset, secret, or resource identifier is copied (see §4 and the
plans' clean-room boundaries).

The product presentation (`/Users/geondongkim/Downloads/LALA-발표자료-v2.pptx.pdf`,
19 slides; slides 5–8 are the mandatory product promise) is read for capability
intent only. **No artwork is copied into the repo**; the capability gates in §6
are paraphrased intent confirmed across the five plans' OCR.

### 0.2 What an implementer reads first

1. **§1 (scope/status legend)** — before claiming any capability is "done".
2. **§2 (wave plan + dependency graph)** — to know what must land before your
   slice can merge.
3. **§3 (ownership table)** — to know who owns each contract surface you touch;
   never edit another owner's surface without coordinating.
4. **§4 (collision rules)** — the non-negotiable integration rules.
5. **§10 (backlog + decision gates)** — what is actually queued and what is
   blocked on an external/human decision.

## 1. Scope and Status Legend

Every capability statement in this program carries one tag. Implementers must
tag their own PR descriptions the same way. **Unit tests alone never promote a
row from TARGET to CURRENT.**

| Tag | Meaning | Evidence required to assert |
| --- | --- | --- |
| **CURRENT** | Implemented and live on `main` behind a real DB/API path (or an explicit, honest fallback). | Path + symbol cited; confirmed by direct read of this worktree. |
| **TARGET** | Net-new design proposed by a plan and adopted by this program. Not yet implemented. | Wave + owning PR slice in §5. |
| **BLOCKED_EXTERNAL** | Cannot proceed until an external or human gate clears (legal sign-off, ToS decision, data-access approval, cost ceiling). | Decision-gate ID in §10; no work assumed solved. |
| **GATE** | A presentation-derived or clean-room product rule that is mandatory and blocks "done." | Section in §6 / §8; acceptance evidence in §5 per slice. |

**Hard rule — no mock/demo data on normal user paths.** Normal flows
(`/api/v1/places`, `/weather`, `/docents/*`, `/plans/*`, `/intervention`) must
serve live DB/API data or an explicit honest fallback (loading / loaded / empty
/ error with retry). Deterministic dev fixtures live only under `sql/dev_reset/`
and test paths; they are never shipped as "live." A map fallback, a missing
Kakao key, or a placeholder docent is a **blocked** state, never a passing one.
This is enforced by `apps/api/tests/test_safety_contracts.py` (extended per
§5.0) and by the visual-contract forbidden-shortcut rule.

## 2. Dependency Graph and Wave Plan

The five plans overlap on proposed schema, API fields, worker jobs, and UI
contracts. Sequencing them into waves makes the prerequisite chain unambiguous:
each wave publishes the **contracts** the next wave consumes, so downstream work
can begin against a frozen interface even before upstream implementation
finishes.

### 2.1 Dependency graph

```
WAVE 0 — shared data contracts / governance ─────────────────────────────────┐
  canonical migration runner ordering · model-role router · source registry   │
  feature-flag registry · safety-contract test spine · OpenAPI-compat gate    │
  └────────────────────────────────────────┬──────────────────────────────────┘
                                           │ (freezes contracts everyone reads)
        ┌──────────────────────────────────┼──────────────────────────────────┐
        ▼                                  ▼                                  ▼
WAVE 1 — place data + location/weather     WAVE 2 — review ingestion/         (WAVE 3 reads 1+2)
  region_catalog, place_operating_hours,     enrichment                       RAG/docent/TTS
  weather_threshold_config, ASA flags,        review_sources (062, landed) +       (reads Wave 2
  Open-Meteo fallback, is_indoor provenance   aggregate receipt (062), quarantine summary chunks;
  (reads Wave 0 migration runner)             bulk ad classifier, summary-only     reads Wave 1
                                              RAG hand-off (raw retention
                                              BLOCKED_EXTERNAL — no posts_raw)
        │                                      │                                  weather/region metadata)
        │                                      ▼                                        │
        │                             WAVE 3 — RAG → docent / TTS                        │
        │                               embedding_generation + reindex,                  │
        │                               hybrid retrieval + mini rerank,                  │
        │                               inline guards, citations, reason, audio cache ────┘
        ▼                                              │
WAVE 4 — 4-slot planner / weather substitutions ◄──────┘ (consumes docent narration + Wave 1 weather/region/hours)
  full 4 slots, weather_aware_substitute, regenerate, intervention history, travel-time
        │
        ▼
WAVE 5 — map/dashboard + restaurant discovery (consumes Wave 1 viewport+region, Wave 2 review quality, Wave 4 plan slots)
  viewport bounds, pin-first policy hardening, cuisine facets, Local Restaurant Tour, franchise confidence surfacing, dispersion eval
        │
        ▼
WAVE 6 — device/runtime E2E + rollout (consumes all)
  30–50-place eval set, real-device captures, funnel metrics, worker rollout, flags on
```

### 2.2 Wave plan — why each prerequisite blocks the next

| Wave | Scope | Why it must precede the next |
| --- | --- | --- |
| **W0** | Shared data contracts + governance: migration ordering, model-role router, source registry, flag registry, safety-contract spine, OpenAPI-compat check. | Every later wave edits canonical SQL, the API surface, and models. Without a frozen migration owner (§3), flag namespace (§5.0), and one source of truth per field (§4.2), the five plans' overlapping migrations and API deltas collide. W0 publishes the **interfaces** (table DDL shapes, flag names, model-role contract) so W1–W5 can be designed against them in parallel. |
| **W1** | Official/static place data + location/weather reliability: region resolution to 시/군, operating hours, weather thresholds as config, explicit ASA flags + summary, Open-Meteo fallback tier, `is_indoor` provenance. | W2's review enrichments are **place-scoped**; W3's RAG chunks and docent grounding need region/category/`is_indoor` filter metadata; W4's substitutions need flag-level weather + indoor labels + hours; W5's viewport query needs a canonical region key. None of these can harden until place identity, region, and weather reliability exist. |
| **W2** | Review ingestion/enrichment: **062 governance foundation landed** via PR #60 (`ingest.review_sources` + DB-backed source gate, `community.ingest_runs` run-accounting extension + `review_source_name` FK, `ingest.review_ingest_receipts` aggregate-only persistent receipt/dedupe, `community.ingest_quarantine` — no raw-body column), bulk-lane ad classifier, summary-only RAG hand-off, recheck escalation. **Raw review-body retention is BLOCKED_EXTERNAL** (no `community.posts_raw`, §4.4/DG-11). | W3 grounds docents in **aggregate evidence only** — impossible while raw review text still reaches RAG (`_community_post_chunk` CURRENT gap, §3). W5's `review_quality_score` and restaurant attributes depend on quarantined-low-confidence discipline from W2. |
| **W3** | RAG/docent/TTS: real embeddings + `embedding_generation` reindex, hybrid retrieval + mini rerank in the live path, inline guardrails + language lock, per-chunk citations, on-demand reason, audio cache, offline mini QA judge. | W4's planner narration and "why now" reasons call `docent_service`; W5's Tour and "why this place" panel call docent/reason. They cannot ship honest, grounded, single-language narration until W3's guardrails, citations, and reason endpoint exist. |
| **W4** | 4-slot planner + weather substitutions: full timed slots, `weather_aware_substitute`, `POST /plans/regenerate`, intervention history + diff, travel-time cache + provider + Haversine fallback. | W5's Daily Plan screen and situation-aware toast consume `/plans/daily` slots + `/plans/intervention` proposals. The Tour (W5) reuses the planner's meal-facet + anchor logic. Shipping the planner after RAG/docent lets slot narration be real, not stubbed. |
| **W5** | Map/dashboard + restaurant discovery: viewport-bounds query, pin-first cluster policy hardening, cuisine/meal/diet/indoor facets, Local Restaurant Tour, franchise confidence surfacing, anonymous feedback + dispersion eval. | The map is the **integration surface** that renders every upstream contract: places (W1 geo/facets), weather pill (W1), docent sheet (W3), plan/intervention (W4). It must land after its data dependencies so a screenshot can be backed by live data end-to-end. |
| **W6** | Device/runtime E2E + rollout: 30–50-place eval set, real Android/iOS/Web captures, discover→detail→plan funnel metrics, promote workers off dry-run one at a time, flip flags on per region/category. | Acceptance is not unit tests; it is a real device running live API/DB (§6 G5, §9 DoD). This wave cannot start until W1–W5 are mergeable, and it is the gate that promotes TARGET rows to CURRENT. |

**Parallelism inside a wave:** the contracts W0 publishes (table/field/flag/model
names) let W1's data spine, W2's ingestion, and W3's retrieval be **designed**
concurrently. Only the *merge order* is serialized as above; design and
dry-run/preview work overlap.

## 3. Contract Ownership Table

For every cross-domain concept, exactly **one** owner per layer. "Owner" means
the only PR that may change that surface; other waves coordinate via the
contract pin in §3.1. Migration owners all flow through the shared canonical
runner (§3.2). A blank cell means the concept does not touch that layer.

Legend for owners: **SQL** = canonical migration file + `canonical_sql.py`; **API**
= `routers/v1.py` route + `schemas/` model + `openapi`; **Worker** =
`apps/workers/app/contracts.py` job + `apps/api/app/tools/run_*.py`; **Flutter**
= `apps/flutter_app/lib/...`; **Test/eval** = `apps/api/tests/` + flutter tests +
eval fixtures.

### 3.1 Ownership matrix

| Cross-domain concept | SQL migration owner | API schema/router owner | Worker owner | Flutter owner | Test/eval owner |
| --- | --- | --- | --- | --- | --- |
| **Place identity / geo / category** | `010_travel_core_tables.sql` (`travel.places`, GIST `idx_places_geog_expr`, category CHECK) | `places_service.list_places` / `db_repository.fetch_places` (`/api/v1/places`) | `place_score_batch` (score snapshots) | `features/map/map_helpers.dart`, `features/home/home_page.dart` | `test_places_service.py`, `generated_client_places_poc_test.dart` |
| **Localized content (KO/EN exclusive)** | (`place_enrichments` attributes jsonb, `010`) | `normalization.display_language` + docent `language` enum | (bulk lane translation of summary lines) | `shared/l10n/lala_copy.dart`, `features/docent/docent_helpers.dart` (`singleLanguageText`) | `test_i18n`-style + inline language-lock test |
| **Weather / air snapshot** | `020_travel_domain_tables.sql` (`travel.weather_observations`) + `065` wind_speed/flags (TARGET) | `weather_service.current_weather` (`/api/v1/weather`) | `weather-refresh` job (`weather_observation_refresh`) | `features/weather/widgets/*` | `test_weather_observation_refresh.py`, `weather_map_pill_test.dart` |
| **Review provenance / raw retention** | `030_community_core_tables.sql` + `062` `ingest.review_sources` (+ DB-backed source gate), `community.ingest_runs` run-accounting ext. (+ `review_source_name` FK), `ingest.review_ingest_receipts` aggregate receipt/dedupe, `community.ingest_quarantine` (**PR #60, landed**); `063` `travel.place_enrichments` replay-audit uniqueness (TARGET); raw retention **BLOCKED_EXTERNAL** (no `posts_raw`, §4.4/DG-11) | `review_ingest_governance` boundary (no raw-text endpoint — forbidden, §4.4) | `review-mention-ingest` job (`review_mention_ingest`, `run_review_mention_ingest`) | (none — aggregate only) | `test_safety_contracts.py` (no-raw-text), `test_review_ingest_governance.py` (in PR #60) |
| **Review normalized attributes** | `030` `community.place_mentions_weekly.attributes` + `010` `travel.place_enrichments` mirror (TARGET G8) | `review_attribute_batch` (internal; surfaced as aggregate fields on `/places`) | `review-attribute-batch` job (`run_review_attribute_batch`) | (aggregate fields only) | `test_review_attribute_batch.py` |
| **Franchise / small-merchant classification** | `035_data_pipeline_tables.sql` (`economy.franchise_brands`, `analytics.place_business_identity`) | `franchise_identity.classify_place_business` (surfaced via `place_score_snapshots`) | `franchise-reference-ingest` + `place-score-batch` jobs | (confidence surfacing in W5) | `test_franchise_identity.py` |
| **Local-value score + optional reason** | `035` `analytics.place_score_snapshots` (`formula_version=local-value-v2`) | `recommendation_scoring.build_place_score` (score) + `docent_service` reason (`/docents/reason`, TARGET) | `place-score-batch` job | `features/place/widgets/*` (`점수/근거` action, on demand) | `test_recommendation_scoring.py`, reason eval subset |
| **RAG chunk / citation / embedding version** | `036_rag_knowledge_tables.sql` + `064` `embedding_generation` + filter metadata (TARGET) | `rag_index.query_knowledge_chunks` + hybrid fetch (TARGET) | `rag-reindex` worker (TARGET) | (citations rendered in docent sheet/reason) | `test_rag_index.py`, retrieval recall@3 eval |
| **Docent cache / audio** | `020` `travel.docent_scripts` + `064` `travel.docent_audio_cache` (TARGET) | `docent_service.generate_script/audio` + `/docents/reason` (TARGET) | (offline QA job `run_docent_quality_qa`) | `features/docent/widgets/*`, `tour_audio_bar` | docent eval set (30–50 places), `test_docent_*` |
| **Plan slot / substitution / intervention** | `020` + `065` `travel.plan_snapshots`, `weather_state_cache`, `place_operating_hours`, `travel_time_cache`, `weather_threshold_config`, `region_catalog` (TARGET) | `planner_service.daily_plan/intervention` + `/plans/regenerate` (TARGET) | (none — synchronous request path) | `features/planner/*`, `features/plan/*`, `features/intervention/*` | `test_planner_service.py` (extended) |
| **Marker / cluster / viewport query** | (no change — `idx_places_geog_expr` + `idx_places_lat_lng`) | `places_service`/`db_repository.fetch_places` `bounds` param (TARGET) | (none) | `features/map/map_helpers.dart::clusterMapPlacesForMap` | `test/features/map/map_clustering_test.dart`, viewport-bounds test |
| **User location / manual nationwide region** | `065` `travel.region_catalog` (TARGET; today in-code `region_catalog.py`) | `weather_service` region resolution + `/plans`/`/weather` region key | (none) | `core/location/lala_location.dart`, `features/location/widgets/manual_location_sheet.dart`, `manual_location_options.dart` | region-resolution test (GPS→시/군) |

### 3.2 Shared migration runner (one SQL owner)

All migrations flow through `apps/api/app/services/canonical_sql.py`
(`load_canonical_sql_plan`, `scan_sql_safety`, `execute_canonical_sql`), which
loads the ordered `sql/canonical/*.sql` set (baseline `000`→`062`; `062` is the
review-governance foundation that lands via the sibling PR #60 worktree
`lala-review-ingestion-foundation` and is the authoritative baseline this program
reconciles against) and rejects unsafe statements. New additive migrations take
the **next free number** and are proposed here (file names are TARGET, owned by
the wave's SQL owner):

- `062_review_ingestion_governance.sql` (**PR #60, landed**) — additive,
  re-runnable. Owns `ingest.review_sources` (source_name PK, provider,
  `license_class`, terms/collection/retention/redaction policy, status), the
  run-accounting extension on `community.ingest_runs` (`review_source_name` FK →
  registered source, `run_key` partial-unique idempotency index,
  received/processed/duplicate/quarantined counters, `failure_category`),
  `ingest.review_ingest_receipts` (persistent aggregate-only cross-batch dedupe
  keyed on source + external_key + `content_sha256` — no raw text), and
  `community.ingest_quarantine` dead-letter. **This is not an immutable ledger
  and it stores no raw review text** (quarantine has no body column by design).
  Backed by the typed governance boundary in
  `apps/api/app/services/review_ingest_governance.py`, which loads the source
  row from `ingest.review_sources` as the DB-authoritative license gate (a
  `rejected`/disabled/absent source aborts the whole batch with a
  `source_license_rejected` governance error before any record is accepted) and
  runs register → run → receipt → quarantine → finalize inside one transaction.
- `063_place_enrichments_replay_audit.sql` (W2) — **the aggregate receipt,
  cross-batch dedupe, and DB-backed source gate originally proposed here shipped
  inside `062` with PR #60**, so no separate receipt migration is reserved. This
  migration is now scoped to the remaining additive unique
  `(place_id, enrichment_type, prompt_version)` on `travel.place_enrichments`
  (G8 mirror auditing) only. **No `community.posts_raw` table (raw retention is
  BLOCKED_EXTERNAL, §4.4/DG-11) and no external-provider calls** — the slice
  accepts already-normalized records only.
- `064_rag_docent_targets.sql` (W3) — `rag.knowledge_chunks.embedding_generation`
  + filter-grade `metadata`; `travel.docent_audio_cache`.
- `065_planner_data_spine.sql` (W1+W4) — `travel.region_catalog`,
  `travel.place_operating_hours`, `travel.travel_time_cache`,
  `travel.plan_snapshots`, `travel.weather_state_cache`,
  `travel.weather_threshold_config`, `travel.weather_observations.wind_speed`.
- `066_place_facets.sql` (W5) — `travel.places.cuisine_taxonomy`/`cuisine_code`,
  `analytics.recommendation_feedback`, optional `tour_route_cache`.

**BLOCKED_EXTERNAL (not a migration — no raw-retention table):**
`community.posts_raw` (or any raw review-body table) is **not created by any
slice in this program** and is not assigned a migration number until the
legal/retention/access decision (DG-11) clears. Earlier drafts listed it as a W2
migration; that proposal is superseded — do not renumber it into the canonical
sequence (it would collide with the already-shipped `062`).

No wave may introduce a migration out of this order or bypass `scan_sql_safety`.

### 3.3 Cross-cutting contract pins (published interfaces)

Each wave must publish these stable names so siblings can depend on them:

- **Region key** = `(province_code, city_code)` from `travel.region_catalog`
  (W1). Weather, places, planner all consume this key.
- **Alert-flag envelope** = explicit booleans `is_rain_snow / is_bad_dust /
  is_heatwave / is_coldwave / is_strong_wind` **plus** summary `outdoor_status`
  in `/api/v1/weather` and inside the plan envelope (W1).
- **Aggregate-evidence write** = the row shapes in
  `community.place_mentions_weekly`, `travel.place_enrichments`,
  `analytics.place_score_snapshots.review_quality_score`, and
  `rag.knowledge_chunks(source_type='place_mention')` (W2).
- **Docent contract** = `DocentScriptData` + additive `citations[]?`/`retrieval?`
  + `POST /api/v1/docents/reason` (W3). Flutter codegen regenerated;
  `check_openapi_compat.py` guards backward compatibility.
- **Plan slot schema** = `{period, window, role, place?, weather_fit,
  distance_m, travel_time_min, reason}` in `LalaDailyPlan.slots` (W4).
- **Viewport/cluster contract** = server returns **places**; clustering is the
  Flutter policy `clusterMapPlacesForMap` (`places ≥ 80 && mapLevel ≥ 10`;
  selected pin always individual) (W5).

## 4. Collision-Resolution Rules (non-negotiable)

These resolve the overlaps the five plans would otherwise drift on. Every PR is
reviewed against them.

### 4.1 Migrations: additive-only and ordered

- Additive and idempotent only (`CREATE TABLE/INDEX IF NOT EXISTS`, `ADD COLUMN
  IF NOT EXISTS`). `scan_sql_safety` forbids `DROP`, destructive `ALTER`, and
  unguarded renames. No exception, no `-- force`.
- One ordering authority: `canonical_sql.py` over `sql/canonical/000…066`. A new
  migration takes the next free number per §3.2 and declares its wave.
- No wave redefines a table another wave already shipped. Conflicting additive
  columns on the same table are resolved in this program before either merges
  (e.g., `travel.place_enrichments` uniqueness is owned by W2's `063`).

### 4.2 One source of truth per OpenAPI/schema field

- Every field has exactly one owning service (§3.1). A field added by two plans
  is unified here: e.g. `weather.alert_flags` is owned by `weather_service`
  (W1) and **read** by `planner_service` (W4) and the map pill (W5), never
  re-emitted by them.
- The Flutter client consumes **one** generated OpenAPI
  (`clients/flutter_generated/`); hand-edited duplicates are forbidden.
  `export_openapi.py` regenerates; `check_openapi_compat.py` blocks breaking
  changes.

### 4.3 API backward compatibility

- New fields are **additive and nullable** (e.g. `citations[]?`, `retrieval?`,
  `slots[].travel_time_min`). Existing clients keep working.
- New endpoints are additive (`/docents/reason`, `/plans/regenerate`,
  `/taxonomies`, optional `/places?bounds=`).
- Version stamps (`prompt_version`, `schema_version`, `formula_version`,
  `embedding_generation`) bump on any behavioral change and preserve history
  (`travel.place_enrichments` generations).

### 4.4 No raw review text in RAG (privacy + grounding)

- `rag_index._community_post_chunk` CURRENTLY embeds the raw `community.posts`
  body/title into `body_ko` (CONFIRMED gap). W2/W3 retire/replace this: RAG
  grounds in **aggregate** `place_mention` summaries (counts, sentiment bands,
  attribute scores) only — never a reviewer's verbatim text.
- No endpoint returns `community.posts.body`. **No `community.posts_raw` table
  exists or is created by any current slice** — until the legal/retention/access
  decision (DG-11) clears, raw review text is **not stored, served, logged, or
  embedded** anywhere (BLOCKED_EXTERNAL); should a raw table ever land, it would
  be forbidden on the serve path too. Citations expose source **type/table +
  record pointer**, not embedded content.
- Enforced by `test_safety_contracts.py` (no-raw-text, no-PII-in-aggregates) and
  the `enforce_no_raw_review_text` guard + `extra="forbid"` models in
  `review_ingest_governance.py` (062, PR #60).

### 4.5 No direct Naver/Daangn scraping without approved source/legal sign-off

- The legacy reliance on unauthenticated Naver/Daangn scraping is **not** carried
  over. Review/mention acquisition uses only sources marked
  `licensed | public_processed | approved_export` in `ingest.review_sources`
  (062, PR #60; enforced by the `review_ingest_governance.py` boundary), after
  legal sign-off on retention/summarization per source.
- No scraping code ships in the repo. This is a code-review gate and a
  BLOCKED_EXTERNAL decision (DG-1, §10) until a first licensed source is
  approved. Community-crawl live execution remains approval-gated (DG-6).
- **Raw review bodies are not stored at all** until DG-11 (raw-retention
  legal/retention/access) clears: no `community.posts_raw` table is created by
  any currently planned slice; `062` ships no raw-body column and already lands
  the aggregate-only receipt/dedupe + DB-backed source gate (PR #60); the next
  review migration (`063`) adds only `travel.place_enrichments` replay-audit
  uniqueness (no external-provider calls).

### 4.6 No Azure Function blind port

- The legacy Azure Functions timer/queue runtime is **not** ported. Where a
  timer/queue is needed, declare a **portable worker contract** in
  `apps/workers/app/contracts.py` (`WorkerJobDefinition`: trigger, idempotency
  key, retry policy, poison policy, dry-run). The scheduler (container cron /
  hosted scheduler / queue) is chosen at deploy, not in code.
- Live worker mutation stays behind `ALLOW_WORKER_MUTATION=1` and per-job
  `--confirm`/`ALLOW_*_APPLY=1` gates; the Wave-1 `not_implemented` guard for
  live execution is only lifted in W6, one worker at a time (weather first).

## 5. Per-Wave PR Slices

Each slice is the **smallest independently mergeable scope**: additive schema or
additive API only, behind a flag, with tests, live-data acceptance, and a
rollback. PRs are narrow enough for review (one contract surface per PR where
possible). All migrations are listed in §3.2.

### 5.0 Wave 0 — shared contracts / governance (prerequisite for all)

| Slice | Scope (smallest mergeable) | Tests | Live-data acceptance | Rollback / flag | Risk / dependency |
| --- | --- | --- | --- | --- | --- |
| **W0-a Migration-runner contract** | Document/lock the canonical ordering (§3.2); add a CI assertion that `canonical_sql.py` loads `000…066` and `scan_sql_safety` passes on every PR. No new table. | `scan_sql_safety` runs in CI; ordering test green. | N/A (no data). | None (governance only). | Low. Blocks W1–W5 from shipping migrations. |
| **W0-b Model-role router** | `config.py` `model_role_overrides` (env `LALA_MODEL_ROLE_<ROLE>`) + pure `model_client.resolve(role)` for `review_bulk`, `review_recheck`, `docent`, `docent_qa`, `place_enrichment`, and `embedding`; existing selectors become thin callers. **No prompt copy or SDK client creation during resolve.** | Router resolves each role to standard-OpenAI `(provider, model_id, client metadata)`; defaults remain `gpt-5.4-nano`, `gpt-5.4-mini`, and `text-embedding-3-small`; legacy `OPENAI_*_MODEL` inputs remain compatible. | `LALA_ENABLE_LIVE_AI=false` and no key keep resolution deterministic; Azure OpenAI base URLs are rejected. | No live-call behavior changes until the existing caller boundary is enabled. | Medium. Touched by W2/W3/W4; must land first. |
| **W0-c Feature-flag registry** | One registry (config + doc table) of every flag this program introduces (§5.x flags), each defaulting to current behavior. | Flag-default test asserts no-op deploy. | N/A. | Flags off = today. | Low. Prevents flag-name collisions across waves. |
| **W0-d Safety-contract test spine** | Extend `test_safety_contracts.py` with the cross-cutting assertions every wave adds to: no-raw-text-in-RAG, no-PII-in-aggregates, no-secrets-in-logs, no-mock-on-normal-paths, no-scraping-code. | Tests red on the gaps they will close; green on CURRENT invariants. | N/A (contract). | None. | Low. Becomes the §9 DoD backbone. |
| **W0-e OpenAPI-compat gate in CI** | Wire `check_openapi_compat.py` into CI so any breaking schema delta fails the build. | Compat check runs on schema PRs. | N/A. | None. | Low. Enforces §4.2/§4.3. |

#### W0-c flag registry contract

`apps/api/app/core/feature_flags.py::FEATURE_FLAG_REGISTRY` is the single
namespace for the rollout controls named by the W1–W6 slices below. The
registry is configuration-only in W0-c: an absent variable resolves to the
listed current behavior and does not enable a new consumer. Values are
non-secret; invalid typed overrides fail closed before a future consumer can
run.

| Program key | Environment input | Default | Current behavior | Owner |
| --- | --- | --- | --- | --- |
| `REGION_SIGUN_RESOLUTION` | `LALA_REGION_SIGUN_RESOLUTION` | `false` | province-level resolution | W1-a |
| `WEATHER_EXPLICIT_FLAGS` | `LALA_WEATHER_EXPLICIT_FLAGS` | `false` | legacy weather summary | W1-b |
| `WEATHER_OPEN_METEO_FALLBACK` | `LALA_WEATHER_OPEN_METEO_FALLBACK` | `false` | current weather source chain | W1-c |
| `PLACE_OPEN_HOURS` | `LALA_PLACE_OPEN_HOURS` | `false` | legacy operating-state behavior | W1-d |
| `PLACE_INDOOR_CLASSIFY` | `LALA_PLACE_INDOOR_CLASSIFY` | `false` | current place enrichment | W1-e |
| `REVIEW_QUARANTINE` | `LALA_REVIEW_QUARANTINE` | `false` | current governed review path | W2-c |
| `REVIEW_AI_CLASSIFIER` | `LALA_REVIEW_AI_CLASSIFIER` | `false` | deterministic review classification | W2-d |
| `REVIEW_RECHECK` | `LALA_REVIEW_RECHECK` | `false` | no selective recheck | W2-e |
| `LALA_ENABLE_LIVE_AI` | `LALA_ENABLE_LIVE_AI` | `false` | offline AI and fixtures | W2-d |
| `rag_embedding_method` | `LALA_RAG_EMBEDDING_METHOD` | `local-hash` | deterministic local-hash embeddings | W3-a |
| `rag_embedding_generation` | `LALA_RAG_EMBEDDING_GENERATION` | `1` | embedding generation 1 | W3-a |
| `rag_retrieval_mode` | `LALA_RAG_RETRIEVAL_MODE` | `legacy` | legacy retrieval mode | W3-b |
| `docent_inline_guards` | `LALA_DOCENT_INLINE_GUARDS` | `false` | current docent response path | W3-c |
| `docent_reason_enabled` | `LALA_DOCENT_REASON_ENABLED` | `false` | no on-demand reason route | W3-d |
| `docent_audio_cache` | `LALA_DOCENT_AUDIO_CACHE` | `false` | current docent audio path | W3-e |
| `LALA_ENABLE_LIVE_SPEECH` | `LALA_ENABLE_LIVE_SPEECH` | `false` | no live Azure Speech requests | W3-e |
| `docent_qa_judge` | `LALA_DOCENT_QA_JUDGE` | `false` | deterministic docent QA precheck | W3-f |
| `PLAN_FULL_SLOTS` | `LALA_PLAN_FULL_SLOTS` | `false` | current planner slot count | W4-a |
| `PLAN_WEATHER_SUBSTITUTE` | `LALA_PLAN_WEATHER_SUBSTITUTE` | `false` | no weather substitution | W4-b |
| `PLACES_VIEWPORT_BOUNDS` | `LALA_PLACES_VIEWPORT_BOUNDS` | `false` | circle-based places query | W5-a |
| `PLACE_FACETS` | `LALA_PLACE_FACETS` | `false` | current place filters | W5-c |
| `LOCAL_TOUR` | `LALA_LOCAL_TOUR` | `false` | no local restaurant tour | W5-d |
| `PLACE_CONFIDENCE_SURFACE` | `LALA_PLACE_CONFIDENCE_SURFACE` | `false` | current place response metadata | W5-e |
| `RECOMMENDATION_FEEDBACK` | `LALA_RECOMMENDATION_FEEDBACK` | `false` | no recommendation feedback writes | W5-f |
| `MAP_FUNNEL_METRICS` | `LALA_MAP_FUNNEL_METRICS` | `false` | current metrics surface | W6-c |

### 5.1 Wave 1 — place data + location/weather reliability

| Slice | Scope | Tests | Live-data acceptance | Rollback / flag | Risk / dependency |
| --- | --- | --- | --- | --- | --- |
| **W1-a Region resolution to 시/군** | `065` `travel.region_catalog` (from in-code `region_catalog.py`/`manual_location_options.dart`); extend resolution past province to `(province_code, city_code)`. No external geocoder (PostGIS-only parity). | GPS→city resolution test; manual-selection maps to same key. | `/weather`/`/places`/`/plans` return a real 시/군 key for a live coordinate. | Flag `REGION_SIGUN_RESOLUTION`; off = province-level. | Medium. Depends W0-a. Blocks W4/W5 region key. |
| **W1-b Weather thresholds as config + explicit ASA flags** | `065` `travel.weather_threshold_config`; emit explicit `is_rain_snow/is_bad_dust/is_heatwave/is_coldwave/is_strong_wind` **plus** `outdoor_status` in `/weather` and plan envelope. Resolve PM2.5 cutoff (35 vs 36) and the two-tier wind decision (`discomfort_wind_ms`/`advisory_wind_ms`, DG-3). | Threshold-config resolution test; flag-vector test; priority `rain>cold>heat>pm`. | `/weather` returns real flag vector for a live region. | Flag `WEATHER_EXPLICIT_FLAGS`. | Medium. DG-3 decision gate. |
| **W1-c Open-Meteo fallback tier + `wind_speed`** | `065` adds `travel.weather_observations.wind_speed`; restore DB→Open-Meteo→KMA chain (Open-Meteo as fallback tier only, within quota). | Fallback-chain test; stale-reuse test. | Live weather survives a KMA blip via Open-Meteo. | Flag `WEATHER_OPEN_METEO_FALLBACK`. | Medium. Legal: Open-Meteo quota/attribution (§8). |
| **W1-d Operating hours** | `065` `travel.place_operating_hours`; `open_during(slot.window)` predicate (replaces legacy `bsn_state_nm='영업'`). Unknown hours → down-rank + honest flag, never silent drop. | `open_during` predicate test; unknown-hours down-rank test. | A real restaurant is filtered out of a slot it is closed for. | Flag `PLACE_OPEN_HOURS`. | Medium. DG-9 source-priority decision. Consumed by W4. |
| **W1-e `is_indoor` provenance** | Re-derive indoor/outdoor labels via model policy (nano classify + mini recheck) into `travel.place_enrichments`; do **not** copy legacy `classify_tourist_indoor.py`. | Classification confidence test; mini-recheck-on-low-confidence test. | A real attraction carries a grounded `is_indoor` label. | Flag `PLACE_INDOOR_CLASSIFY`. | Medium. Consumed by W4 substitution + W3 RAG filter. |

### 5.2 Wave 2 — review ingestion / enrichment

| Slice | Scope | Tests | Live-data acceptance | Rollback / flag | Risk / dependency |
| --- | --- | --- | --- | --- | --- |
| **W2-a Review-ingest governance foundation (`062`, landed)** | **PR #60 ships this** (`062_review_ingestion_governance.sql` + `review_ingest_governance.py`): `ingest.review_sources` provenance registry + the DB-authoritative source gate, the `community.ingest_runs` run-accounting extension (`review_source_name` FK → registered source, `run_key` idempotency, counters, `failure_category`), `ingest.review_ingest_receipts` persistent aggregate-only cross-batch dedupe, and `community.ingest_quarantine` dead-letter. The boundary loads the source row from `ingest.review_sources` and **aborts** a `rejected`/disabled/absent source with a `source_license_rejected` governance error (not a quarantine) before any record is accepted; register → run → receipt → quarantine → finalize runs in one transaction. **Not an immutable ledger; no raw-body column.** Emits an aggregate-only `ApprovedReviewAggregate` (`extra="forbid"`, `enforce_no_raw_review_text`). | Governance tests in PR #60 (license-gate rejection, cross-run dedupe, quarantine routing, transaction rollback, no-raw-text). | A governed batch produces a receipted, counted ledger row without storing raw text. | None (additive schema; PR #60 draft). | High (privacy/legal). Foundation for W2-c/d/e. |
| **W2-b `travel.place_enrichments` replay-audit uniqueness (`063`)** | **The aggregate receipt + cross-batch dedupe + DB-backed source gate originally proposed here shipped inside `062`/PR #60 (folded into W2-a)** — `ingest.review_ingest_receipts` dedupes on source + external_key + `content_sha256` (no raw text), and the `ingest.review_sources` license gate (`license_class ∈ {licensed, public_processed, approved_export, rejected}`) aborts a `rejected`/disabled/absent source up front (`source_license_rejected`), so this slice is reduced to its remaining target: the additive unique `(place_id, enrichment_type, prompt_version)` on `travel.place_enrichments` (G8 mirror auditing). **No `posts_raw`; no external-provider calls.** | Cross-batch dedupe + transaction-rollback + license-gate-rejection + no-raw-text tests already in PR #60; this slice adds the place_enrichments uniqueness test. | An aggregate resolves to a `source_run_id` + `license_class`; a `rejected` source is recorded but never processed. | Flags `REVIEW_AGGREGATE_RECEIPT` / `REVIEW_LICENSE_GATE` not needed (landed). | Medium. Live acquisition stays BLOCKED_EXTERNAL (DG-1); the gate/receipt are landed. |
| **W2-c Quarantine / dead-letter (landed) + replay** | `062` ships `community.ingest_quarantine` (typed metadata only — no body column; idempotent dead-letter dedupe via partial unique `(provider, external_key, reason_category) WHERE resolved_at IS NULL`); `review_ingest_governance.py::insert_quarantine_entries` persists. Replay is TARGET: `--since/--window/--provider/--place-id` on the guarded tools, re-reading normalized `community.posts` + the 062 run ledger (**never a raw store** — BLOCKED_EXTERNAL). | Quarantine-routing test (062); replay idempotency test. | A low-confidence/ambiguous signal is quarantined, not scored. | Flag `REVIEW_QUARANTINE`. | Medium. DG-4 review-queue UI owner. |
| **W2-d Bulk-lane AI ad classifier + attribute mirror** | Second-pass nano classifier `{is_ad, ad_confidence, reason, organic_excerpt}` after deterministic `AD_MARKERS`; mirror attributes to `travel.place_enrichments` (G8). `review_quality_score` null when <3 organic (honest absence). | Ad-classifier test; <3-organic-null test; mirror test. | `place_mentions_weekly` + `place_enrichments` carry aligned attributes. | Flag `REVIEW_AI_CLASSIFIER`; `LALA_ENABLE_LIVE_AI`. | Medium. Cost/quota (DG-10). |
| **W2-e Low-confidence recheck (mini) + summary-only RAG hand-off** | Uncertain signals → mini recheck (`resolve("review_recheck")`) or quarantine; retire/replace `_community_post_chunk` raw-body embedding with `place_mention` aggregate chunks. | Recheck-escalation test; no-raw-text-in-RAG test (closes G7). | `rag.knowledge_chunks` has no raw review bodies; docent grounds in aggregates. | Flag `REVIEW_RECHECK`; RAG cut last after docent QA (W3). | High. Depends W0-b router, W3 grounding QA. |

### 5.3 Wave 3 — RAG / docent / TTS

| Slice | Scope | Tests | Live-data acceptance | Rollback / flag | Risk / dependency |
| --- | --- | --- | --- | --- | --- |
| **W3-a Real embeddings + reindex generation** | `064` `rag.knowledge_chunks.embedding_generation` + filter `metadata`; serving default = semantic (config-gated); `rag-reindex` worker (stale-only, idempotent). `local-hash` stays dev/offline-only. | Startup asserts semantic method when AI on; stale-predicate test; recall@3 ≥ baseline. | Backfill complete; stale=0; recall@3 holds on eval subset. | Flag `rag_embedding_method`/`rag_embedding_generation`. | High (backfill cost/quota). Depends W0-b. |
| **W3-b Hybrid retrieval + mini rerank** | `fetch_docent_knowledge_context_hybrid` (ANN ∪ keyword ∪ metadata filter) → reciprocal-rank fusion → mini rerank → top-3; wired behind `rag_retrieval_mode`. Keyword leg retained. | Hybrid-vs-legacy recall test; latency p95 within budget. | Canary region: recall@3 up vs legacy mode; latency OK. | `rag_retrieval_mode={legacy,hybrid}`. | Medium. |
| **W3-c Inline guardrails + language lock** | Promote offline QA to inline: language lock (one mini regen, then same-language fallback), no robot-emoji/filler strip, score/secret-leak block, length contract, weather-verb honesty. | robot-emoji=0; language-purity=100% on eval (hard gates). | A generated script is single-language and filler-free. | Flag `docent_inline_guards`. | Medium. G4/G6 hard-zero gates. |
| **W3-d Citations + on-demand reason** | Additive `citations[]?`/`retrieval?` on `DocentScriptData`; `POST /api/v1/docents/reason` (on-demand local-economy/experience rationale, ≤4 sentences, no private scores). OpenAPI regenerated + compat-checked. | Citation-correctness test; reason-no-score-leak test. | Reason endpoint returns a grounded rationale on demand. | Flag `docent_reason_enabled`. | Medium. G2/G5. |
| **W3-e Audio contract** | `064` `travel.docent_audio_cache`; char-limit guard + idempotent retry + honest 503-with-retry + SSML prosody; `X-LALA-Audio-Cache` header. | Char-limit test; 503-on-failure test; cache-hit test. | Audio cache-hit ≥ target; honest failure state. | Flag `docent_audio_cache`; `LALA_ENABLE_LIVE_SPEECH`. | Medium. G1/G7. |
| **W3-f Offline mini QA judge** | `evaluate_docent_script` gains a mini LLM-judge pass (offline batch over eval set + production sample): grounding faithfulness, local-economy relevance, filler, language purity, route action. Regex stays the cheap pre-filter. | Judge stamps `judge_model`/`judge_version`; QA pass-rate metric. | QA runs on eval set; blocker rate within budget. | Flag `docent_qa_judge`. | Medium. Depends W0-b. |

### 5.4 Wave 4 — 4-slot planner / weather substitutions

| Slice | Scope | Tests | Live-data acceptance | Rollback / flag | Risk / dependency |
| --- | --- | --- | --- | --- | --- |
| **W4-a Full 4-slot planner** | Restore 4 timed slots/roles (`plan.slot_windows` config), greedy anchor + `used_place_names` dedup + stable tie-break, meal roles, `build_place_score` + `weather_fit` + travel-time wired into slot ranking. | Slot-builder test; anchor+dedup test; determinism `(request,seed)`. | `/plans/daily` returns 4 real slots from live places. | Flag `PLAN_FULL_SLOTS`; off = 2-slot stub. | High. Depends W1 (hours/region/weather flags). |
| **W4-b Indoor/outdoor substitution** | `weather_aware_substitute(active_flags, slot)` → ranked indoor/outdoor proposals, each with reason/location/travel-time/preference (the slide-8 two situations). | Rain→indoor, clear→outdoor fixture test. | Slide-8 substitution pair on a real device. | Flag `PLAN_WEATHER_SUBSTITUTE`. | Medium. G1 marquee. Depends W1-e indoor + W3 reason. |
| **W4-c Regenerate + accept** | `POST /api/v1/plans/regenerate` (seed bump, deterministic re-roll, valid constraints); accept persists `travel.plan_snapshots` (W4-d) and seeds intervention baseline. | Regenerate-determinism test; changed-slot diff test. | Before/after regenerate changes ≥1 slot, still valid. | Flag (within `PLAN_FULL_SLOTS`). | Low. |
| **W4-d Intervention history + travel-time** | `065` `travel.weather_state_cache` + `travel_time_cache`; `/plans/intervention` proposals + diff + history token; travel-time provider + Haversine fallback. | Intervention-diff test; travel-time-fallback test. | Mid-session weather change visibly updates the plan. | Flags `PLAN_INTERVENTION_HISTORY`, `PLAN_TRAVEL_TIME`. | Medium. DG-2 provider choice (BLOCKED_EXTERNAL). |

### 5.5 Wave 5 — map/dashboard + restaurant discovery

| Slice | Scope | Tests | Live-data acceptance | Rollback / flag | Risk / dependency |
| --- | --- | --- | --- | --- | --- |
| **W5-a Viewport-bounds query** | Optional `bounds=minLat,minLng,maxLat,maxLng` on `/places` (index-covered; circle query retained for rail). Pin-first: API returns places, clustering stays client-side. | In-rectangle-only test; circle-parity test. | Panning re-queries the visible rectangle as individual pins. | Flag `PLACES_VIEWPORT_BOUNDS`. | Low. No schema change. |
| **W5-b Pin-first + cluster-policy hardening** | Re-affirm `clusterMapPlacesForMap` (`≥80/≥10`); selected-pin-individual invariant; `<80 ⇒ pins`. | Clustering-policy test (selected stays individual). | Map renders individual pins until threshold. | None (current truth). | Low. G6. |
| **W5-c Cuisine/meal/diet/indoor facets + taxonomies** | `066` `travel.places.cuisine_taxonomy`/`cuisine_code` (re-derived, not legacy term list); `/places?cuisine&meal&diet&indoor`; `/api/v1/taxonomies` for data-driven chips. Invalid facet → `400`. | Facet-filter test; invalid-facet-400 test; empty=honest `count:0`. | Restaurants+Cafes chips show ≥3 live café pins. | Flag `PLACE_FACETS`. | Medium. Depends W1 geo. |
| **W5-d Local Restaurant Tour** | First-class "지역 식당 투어" screen: data-driven chips (W5-c), ≤5-stop walking route from live `/places`, per-stop grounded narration + tour-mode docent reason. | Tour screen test; honest-empty test; bilingual test. | Tour screen: chip selected, ≥3 live stops, rationale visible. | Flag `LOCAL_TOUR`. | Medium. Depends W3-d reason, W5-c facets. |
| **W5-e Franchise confidence surfacing** | Expose data-basis/`missing_signals` + `franchise_match_confidence`/`unknown` in `/places` so UI shows "partial signals"/"limited review signal" honestly. | Confidence-surfacing test; unknown-fallback test. | A low-signal place shows an honest basis note. | Flag `PLACE_CONFIDENCE_SURFACE`. | Low. |
| **W5-f Anonymous feedback + dispersion eval** | `066` `analytics.recommendation_feedback` (session-anonymous, `(place_id,category,day,action_counts)`); offline dispersion eval (Gini/Herfindahl vs card-spend baseline). Privacy: aggregate-only, never joined to identity. | Aggregate-only invariant test; dispersion metric test. | Dispersion eval report artifact (offline). | Flag `RECOMMENDATION_FEEDBACK`. | Medium. Privacy-sensitive. |

### 5.6 Wave 6 — device/runtime E2E + rollout

| Slice | Scope | Tests | Live-data acceptance | Rollback / flag | Risk / dependency |
| --- | --- | --- | --- | --- | --- |
| **W6-a 30–50-place eval set** | Curated bilingual eval set (≤40 places stratified by category/region/language/indoor/context), with grounding anchors and per-case GATE expectations. No golden prompts; no real review text. | CI runs eval on every pipeline change; recall@3/faithfulness regressions block merge. | Baseline numbers recorded. | None (test fixture). | Medium. Backbone of §9 DoD. |
| **W6-b Real-device captures** | Android physical + iOS/Web parity captures per §6.5: map (live pins), daily plan (KO+EN, weather pair), intervention, regenerate, location-denied, docent/reason, honest states. | Each capture backed by live API (`source`/`grounding_*`/`X-LALA-Audio-Cache`). | Captures stored under ignored `output/`; no keys/secrets committed. | None. | High. G5. The DoD gate. |
| **W6-c Funnel metrics** | Privacy-safe, region-level, session-scoped discover→detail→plan funnel (`map_view→category_filter→place_select→detail_view→docent_request→audio_play→add_to_plan→plan_generate`). | Metric-emission test; no-PII test. | Funnel visible in ops datamart contract. | Flag `MAP_FUNNEL_METRICS`. | Low. |
| **W6-d Worker rollout (one at a time)** | Promote workers off dry-run behind `ALLOW_WORKER_MUTATION=1`, **weather first** (lowest risk, public data), then `place-score-batch`, then review/ingest (after DG-1). | Per-worker live preflight (`evaluate_worker_live_preflight`) green; rollback drill. | One worker live; metrics within budget. | Per-worker `ALLOW_*_APPLY`. | High. DG-1/DG-6 gates. |
| **W6-e Flag rollout + rollback drill** | Enable flags per region then category (one `sigun` first; attraction before restaurant); monitor latency, fallback rate, QA blocker rate, cost. Verify rollback = flip flags. | Rollback-drill test. | All flags on for one region; metrics within budget. | Flags. | Medium. |

## 6. Product Quality Gates (from presentation / UI requirements)

Derived from `LALA-발표자료-v2.pptx.pdf` (slides 5–8 mandatory; 1–4, 9–19
context) and the in-repo
[`lala-mobile-visual-contract/`](./lala-mobile-visual-contract/README.md). These
are **binding**; a PR/screen that violates one is blocked. Acceptance is by
real-device capture on live API/DB — never a mock, never a fallback map.

| Gate | Requirement (capability intent) | Owning waves | Acceptance evidence |
| --- | --- | --- | --- |
| **G-DATA / GATE-C** | Domestic daily data (card spend, local SNS/review signals, weather) → LALA AI engine (LLM summary, RAG context, **attribute-based classification**) → foreigner guidance. | W1, W2, W3 | Each retained signal has `match_confidence`, category-typed attributes, and an aggregate `place_mention` RAG chunk. |
| **G-TRUST** | Trustworthy local signals; **no raw review text** to users or docents. | W2, W3 | No endpoint emits `community.posts.body`; RAG has no raw-body chunks; `test_safety_contracts.py` green. |
| **G-SITUATION / GATE-D** | Weather/air-aware **reasoned** recommendations; same day visibly swaps indoor↔outdoor; substitutions carry *why/where/how-far/which-preference*. | W1, W4 | `/plans/daily` + `/plans/intervention` consume flag-level weather + `review_quality_score`; slide-8 substitution pair captured. |
| **G-ECONOMY** | Aggregate place/area-level evidence; no per-user tracking; no joinable user identity in evidence. | W2, W5 | No user/person id in any review-evidence or economy table; feedback is session-anonymous and never joined for scoring. |
| **G-LEGAL** | Licensed/public or processed/de-identified sources only; explicit location consent; **raw review text not stored** (BLOCKED_EXTERNAL). | W2, W6 | `ingest.review_sources` (062) license gate; secret-contract test; location Opt-in (onboarding S3). |
| **G-REALDATA / G1** | Normal flows use **live DB/API data** with explicit honest loading/loaded/empty/error states; **no demo/mock** on normal paths. | All | `test_safety_contracts.py` no-mock/no-fallback; smoke against live DB/PostGIS. |
| **G-I18N / G3** | KO and EN are **mutually exclusive** UI modes (sole bilingual surface = S2 language choice); signals language-tagged. | W2, W3, W5 | Inline language lock + client `singleLanguageText`; eval 100% single-language. |
| **G-CROSSPLATFORM / G4** | Android, iOS, and Web preserve the same workflow; Kakao conditional-import bridge is the single map path. | W5, W6 | Same `/api/v1/*` envelope serves all clients; platform smoke in `smoke_api_matrix.py`. |
| **G-MAPLOOP / G6** | Map loop legible on first use: locate → category-aware places → grounded recommendation → add to plan; no permanent score/reason panels (behind `점수/근거`). | W5 | Rail/sheet default shows no score; widget tests assert absence. |
| **G5 — real-device evidence** | Acceptance requires **real Android/iOS/Web captures** from live API; a map fallback or mock is `blocked`, never `passed`. | W6 | Captures in §5.6/W6-b, each tied to a live API call. |
| **Location + nationwide manual selection** | Current location is opt-in; **manual nationwide selection is always reachable**, never hidden behind a permission failure; denial still yields a valid plan from the selected region. | W1, W5 | Denial path → compact notice with `재시도`/`지역 선택`; valid plan returns. |
| **Kakao map: pin-first then genuine clustering** | Individual category-colored pins first; clusters only under the re-derived policy; selected pin always individual. | W5 | `<80 ⇒ pins`; `≥80 && level≥10 ⇒ cluster`; selected-individual test. |
| **Weather/air visible, no placeholder dash** | Compact pill (`outdoor_status` + temp + dust grade); unavailable → concise unavailable state with retry, never a fake value. | W1, W5 | `weather_map_pill` good/bad/unknown/unavailable states. |
| **Four-slot day plan w/ indoor/outdoor substitution + explicit reason** | Full timed day; weather-driven swap; per-slot reason in the active language. | W4 | `/plans/daily` 4 slots; slide-8 pair. |
| **Score/reason only on demand** | Scores and reasons behind a user action; never always-on. | W3, W5 | `점수/근거` action is the only trigger; default UI has no score. |
| **Restaurant experience filter without invented food mock data** | Cuisine/meal/diet/indoor facets from real taxonomy; honest empty states; no fabricated stops/names. | W5 | Facet query returns live rows or honest `count:0`. |
| **Docent citations/quality + 30–50-place eval** | Per-chunk citations on demand; offline mini QA judge; 30–50-place bilingual eval with recall/faithfulness meters. | W3, W6 | Citations correct on eval; QA pass-rate within budget; eval in CI. |

### 6.1 Honest-state contract (applies to every async surface)

Per [`01-flow-and-runtime-contract.md`](./lala-mobile-visual-contract/01-flow-and-runtime-contract.md)
§F4 and "Forbidden Shortcuts": **loading** (skeleton + non-blocking badge, no
fake pins/tiles), **loaded** (real data), **empty** (honest zero + `지역
선택`/`재시도`), **error** (retry banner; DB-unavailable → `503
PLACES_DB_UNAVAILABLE` with labeled static-snapshot fallback **only if**
enabled). No timer-driven "completed" UI; no spinner-only pages; no skeleton
after data arrives.

## 7. Model Policy

Mandated assignment (do not re-derive). Implemented via the W0-b model-role
router (`resolve(role)`); deployment ids/keys are role-based placeholders, never
in docs or code.

| Role | Model | Used for | Why this tier |
| --- | --- | --- | --- |
| `review_bulk` | **gpt-5.4-nano** | High-volume review extraction, normalization, ad classification, keyword/attribute first pass, franchise taxonomy normalization, **indoor/hours classification** (W1-e) | High volume, low marginal value per call → cheapest tier. |
| `review_recheck` | **gpt-5.4-mini** | Re-extract/re-classify when nano confidence < threshold; uncertain review signals; ambiguous ad calls | Nuance where nano is uncertain. |
| `docent` | **gpt-5.4-mini** | All docent script + reason + planner narration + tour-mode rationale generation | Quality/persona + grounding faithfulness. |
| `docent_qa` | **gpt-5.4-mini** | Offline LLM-judge QA; hybrid rerank; summary-line translation | Judge/reranker must outrank or match the generator tier. |
| `place_enrichment` | **gpt-5.4-mini** | Place English/indoor enrichment | Quality for structured place fields. |
| `embedding` | **text-embedding-3-small** (1536-d) | Chunk + query embeddings | Matches existing `vector(1536)` schema. |

**Fallback ladder.** Every role degrades deterministically, never to raw text or
a fabricated value:
- Extraction/attributes: nano → mini recheck → `build_deterministic_enrichments`
  floor → quarantine (low-confidence never auto-enters scoring/RAG).
- Docent: mini generation → one inline regen on guard violation →
  `rule_based_curation` (same language) → **fallback is never cached/reused**
  (legacy invariant, W3-c guarantees + test).
- Embeddings: semantic (`openai`) → `local-hash` **dev/offline
  fixture only** (never silently used in a live serving path; startup asserts
  semantic method when AI is on).
- Weather: DB latest → KMA+AirKorea → AirKorea-only → Open-Meteo fallback tier →
  unavailable (honest, no fabricated weather).

**Quota.** Retry on 408/409/429/5xx with exponential backoff
(`_is_retryable_ai_error`); a persistent 429 is an external capacity condition —
retried before judging, then the batch quarantines (never silently trusts).
Deterministic first-pass filters run **before** any AI call so only retained
candidates cost tokens.

**Cost.** Batch review extraction in groups; embeddings batched; reindex worker
stale-only with a per-run cap; offline QA on a sample, not the full corpus;
script cache 7 d / audio cache 30 d / reason cache to amortize mini calls.
Budget guard: `enforce_public_contest_paid_route_limit` on
`/docents/{script,audio}`. A per-lane nightly cost ceiling is a decision gate
(DG-10) before W2-d scale-up.

**Human review.** Quarantined/`ambiguous_match` signals and `unknown` franchise
classifications enter a manual approval queue (DG-4 owner) before scoring. LLM
hallucination guards (no invented hours/prices/history/weather) are enforced
inline (W3-c) and by the mini judge (W3-f). `LALA_ENABLE_LIVE_AI=false` by
default; all live AI behind this plus the guarded `--apply` gates, so a
misconfigured environment cannot spend or mutate.

## 8. Security / Legal / Operations Gates

| Gate | Requirement | Owner / enforcement |
| --- | --- | --- |
| **Licensed data provenance** | Each source recorded in `ingest.review_sources` (062) with `license_class ∈ {licensed, public_processed, approved_export, rejected}`; the governance boundary aborts `rejected`/disabled/absent sources up front with a `source_license_rejected` governance error (before any record is accepted). Card data = public aggregates only (region×industry×month×demographic); community = mention aggregation only; weather = KMA/AirKorea public APIs. | W2-a (landed); `review_ingest_governance.py` (062); code-review gate (§4.5). |
| **Retention / deletion** | **Raw review bodies are not stored at all** (BLOCKED_EXTERNAL, §4.4/DG-11) — no `community.posts_raw` table exists or is created by any current slice; the serve path sees counts/sentiment/attributes/short evidence phrases only. Should a future legal/retention/access decision (DG-11) permit retention, a separate purge schedule applies. | W2-a (`062` aggregate-only, landed); DG-11. |
| **Secret injection, not docs** | Secrets via Key Vault + env (`DB_DSN`, `KEY_VAULT_URL`, model deployment keys); OIDC secret-zero deploy. No connection strings, keys, vault/registry/resource-group/subscription/tenant/client IDs, queue/event-hub names, DSNs, tokens, or private URLs in docs or code. ONMU vault isolation; `int-cors-origins` is the only mirrored value. | `test_secret_config_contract.py` / `test_aws_secrets.py`; `test_safety_contracts.py`. |
| **Idempotency / dedupe** | Every write keyed and replay-safe: governance run `run_key = source_name + window + schema_version` (062); normalized posts `content_sha256`; aggregates `(week, place, provider, category)`; enrichments `(place_id, enrichment_type, prompt_version)`; chunks `(source_type, source_id)`; scores `(place_id, formula_version)`; weather `(location, observed_at)`; feedback `(place_id, day)`. No raw layer is keyed because no raw layer exists (BLOCKED_EXTERNAL). | Per-wave upsert tests (§5). |
| **Quarantine / replay** | `community.ingest_quarantine` dead-letter with typed `reason_category` (062, **no raw-body column**); `--since/--window` deterministic replay from the normalized layer + the 062 run ledger (**never a raw store** — BLOCKED_EXTERNAL); nothing in quarantine reaches scoring/RAG until `resolution='approved'`. | 062 (landed); W2-c replay. |
| **Schema migration / backup restore** | Additive-only, ordered (§4.1); every migration has a backup-restore check before apply; rollback = flip flags (additive schema needs no destructive reversal). | `canonical_sql.py`; W0-a. |
| **Observability** | `ops.job_runs` per run; `community.ingest_runs/tasks`; aggregate quality counters in `place_mentions_weekly.attributes`; metrics: ingestion lag, quarantine depth, ad-ratio, match-confidence, 429/timeout rate, embedding freshness, per-lane cost, plan/weather/substitution funnel. No-secret logging (`redact_secret_text`). | `observability_plan.py` (non-mutating); W6-c. |
| **Release flags** | Every behavior change behind a flag defaulting to current behavior (W0-c registry); canary by region then category; rollback drill per W6-e. | W0-c, W6-e. |
| **Privacy** | Raw GPS not persisted (region key + non-identifying session id only); no user/person id in any evidence/economy table; feedback session-anonymous and never joined to identity for scoring; session-UUID DAU parity. | `test_safety_contracts.py` (no-PII); W5-f aggregate-only test. |
| **Contest-access transition** | Public-contest vs paid route rate limits (`enforce_public_contest_paid_route_limit`); auth `require_client_auth` (bearer or iOS key) on docent endpoints; identity behind Logto. | `routers/v1.py`. |

## 9. Definition of Done — "at or beyond the legacy user experience"

A human verifies each item before declaring LALA at/above legacy UX. **Unit
tests alone are never sufficient**; every user-facing row requires a real-device
capture on live API/DB.

- [ ] **Data spine:** region resolves to 시/군 (W1-a); operating hours drive slot
      fit (W1-d); weather emits explicit ASA flags + summary from live KMA/
      AirKore with Open-Meteo fallback (W1-b/c). Captures: weather pill good/bad/
      unavailable; a closed restaurant excluded from its slot.
- [ ] **Trustworthy evidence:** every aggregate resolves to `source_run_id` +
      `license_class`; no raw review text in RAG or any API response; no
      `community.posts_raw` table exists (raw retention BLOCKED_EXTERNAL);
      ambiguous/low-confidence signals quarantined, not scored. Verified by
      `test_safety_contracts.py` + `test_review_ingest_governance.py` (PR #60) +
      a DB spot check.
- [ ] **Grounded docent:** `/docents/script` returns a single-language script
      grounded in ≥1 citation; `/docents/reason` returns a ≤4-sentence local-
      economy rationale on demand; zero robot-emoji; 30–50-place eval recall@3
      and faithfulness within budget. Captures: docent KO + EN; reason view.
- [ ] **Audio:** cached, char-limited, retried, honest-503 on failure (W3-e).
- [ ] **Four-slot plan + substitution:** `/plans/daily` returns 4 real slots;
      slide-8 indoor/outdoor **substitution pair** captured on a real device
      under two weather fixtures, with per-slot reason in the active language;
      regenerate changes ≥1 slot validly; mid-session intervention transitions
      the live plan.
- [ ] **Map loop:** locate → category-aware places → grounded recommendation →
      add to plan, legible on first use; pin-first then genuine clustering;
      viewport pan re-queries; Restaurants+Cafes facet shows ≥3 live pins; score/
      reason only behind `점수/근거`. Captures: map default + sheet + facet.
- [ ] **Local Restaurant Tour:** chip selected → ≥3 live stops → per-stop
      grounded rationale; honest empty when none match.
- [ ] **Bilingual + cross-platform:** KO and EN mutually exclusive end-to-end;
      same workflow on Android, iOS, Web. Captures: KO-only and EN-only screens;
      platform smoke.
- [ ] **Honest states:** loading/loaded/empty/error with retry across map/search/
      plan/weather/docent; no timer-driven "completed"; no mock on normal paths.
- [ ] **Ops readiness:** workers promoted one at a time (weather first) with live
      preflight green; flags on for one region with metrics within budget;
      rollback drill passed; observability emits the §8 metric set.
- [ ] **Clean-room + secret hygiene:** `git diff --check` clean; no legacy
      source/prompt/asset/secret/resource-id copied; secret-pattern scan over the
      diff clean; `check_openapi_compat.py` green.

"Passed" is not a permitted implementer verdict for visual/capability
acceptance — only the design owner may accept (per the visual-contract review
gate).

## 10. Implementation Backlog (P0 / P1 / P2) with Owners and Decision Gates

Ordered by priority and by the wave dependency in §2. Owners are subsystem leads;
a single PR may carry slices from one owner only (coordinate via §3 pins).
**Decision gates (DG)** are external/human and are **not** assumed solved.

### 10.1 P0 — foundation and unblocking contracts (Waves 0–1)

| # | Slice | Owner subsystem | Dependency / decision gate |
| --- | --- | --- | --- |
| P0-1 | W0-a migration-runner contract + CI ordering assertion | SQL / platform | None. |
| P0-2 | W0-b model-role router (`resolve(role)`) | AI / config | None. |
| P0-3 | W0-c feature-flag registry | Platform / config | None. |
| P0-4 | W0-d safety-contract test spine | QA / test | None. |
| P0-5 | W0-e OpenAPI-compat CI gate | API / platform | None. |
| P0-6 | W1-a region resolution to 시/군 (`region_catalog`) | Location / DB | None. |
| P0-7 | W1-b weather thresholds as config + explicit ASA flags | Weather | **DG-3** wind two-tier defaults. |
| P0-8 | W1-c Open-Meteo fallback tier + `wind_speed` | Weather | Open-Meteo quota/attribution (legal). |
| P0-9 | W1-d operating hours (`place_operating_hours`) | Places / enrichment | **DG-9** hours source priority. |
| P0-10 | W1-e `is_indoor` provenance (nano + mini recheck) | Enrichment / AI | W0-b. |

### 10.2 P1 — trustworthy evidence, grounding, and the full plan (Waves 2–4)

| # | Slice | Owner subsystem | Dependency / decision gate |
| --- | --- | --- | --- |
| P1-1 | W2-a review-ingest governance foundation (`062`, PR #60) | Ingest / DB | PR #60 merge (draft); then **DG-1** for any live acquisition (**BLOCKED_EXTERNAL**). |
| P1-2 | W2-b `travel.place_enrichments` replay-audit uniqueness (`063`) — receipt + DB-backed gate landed in `062`/W2-a | Ingest / DB | Gate/receipt landed (no external gate); **DG-11** only if raw retention ever reopens. |
| P1-3 | W2-c quarantine/dead-letter (`062` landed) + replay | Ingest / QA | **DG-4** manual-review-queue UI owner. |
| P1-4 | W2-d bulk AI ad classifier + attribute mirror (G8) | Enrichment / AI | **DG-10** nightly bulk cost ceiling. |
| P1-5 | W2-e mini recheck + summary-only RAG hand-off (closes G7) | Ingest / RAG | W0-b; W3 grounding QA. |
| P1-6 | W3-a real embeddings + reindex generation | RAG / AI | W0-b; backfill budget. |
| P1-7 | W3-b hybrid retrieval + mini rerank | RAG / AI | W3-a. |
| P1-8 | W3-c inline guardrails + language lock | Docent / QA | None. |
| P1-9 | W3-d citations + on-demand reason | Docent / API | W3-b. |
| P1-10 | W3-e audio contract (cache/limit/retry) | TTS / API | None. |
| P1-11 | W3-f offline mini QA judge | Docent / QA | W0-b. |

| P1-12 | W4-a full 4-slot planner | Planner | W1-a/d + W1-b flags. |
| P1-13 | W4-b indoor/outdoor substitution (G1 marquee) | Planner / weather | W1-e + W3-d. |
| P1-14 | W4-c regenerate + accept | Planner / API | W4-a. |
| P1-15 | W4-d intervention history + travel-time | Planner / DB | **DG-2** travel-time provider choice (**BLOCKED_EXTERNAL**). |

#### W0-b implementation record

- **Start — 2026-07-26:** clean sibling worktree
  `/tmp/lala-w0b-model-role-router`, branch `codex/w0b-model-role-router`,
  based on `origin/codex/general-openai-runtime-main` (Draft PR #67).
- **Scope:** standard OpenAI role metadata resolution only; no SDK client is
  created by `resolve()`, no live request or deployment is performed, and
  Azure Speech remains outside this slice.
- **End — 2026-07-26:** P2 commit `21de48b` was rebased to head `4907efc` and
  merged through [PR #68](https://github.com/3dt-1st-org/LALA-next/pull/68)
  with merge commit `bf24ff8a48f23b70d6869e5d560789294b9579f5`. Clean no-`.env`
  full API suite after P2 was `1002 passed, 1 warning`; ruff, format,
  pre-commit, and diff check passed. The merged-head CI run was
  `30207059823` (API, Flutter, and Unix all successful).

#### W0-c implementation record

- **Start — 2026-07-26:** clean sibling worktree
  `/private/tmp/lala-w0c-feature-flag-registry`, branch
  `codex/w0c-feature-flag-registry`, based on fresh `origin/main` after PR
  #67/#68.
- **Draft evidence — 2026-07-26:** commit `ade7fc4` in
  [Draft PR #70](https://github.com/3dt-1st-org/LALA-next/pull/70) adds the
  typed `FEATURE_FLAG_REGISTRY`, `Settings.feature_flags`, the §5.x key/env
  table, and no-op/default/override/fail-closed tests. Clean no-`.env` API
  suite `1043 passed, 1 warning`; OpenAPI compatibility + safety tests `29
  passed, 1 warning`; W0-c targeted tests `41 passed, 1 warning`; ruff,
  format, pre-commit, and diff check passed.
- **Boundary:** this Draft does not claim W0-c is CURRENT until review/CI and
  merge; no flag consumer is enabled by this slice.

### 10.3 P2 — discovery surfaces, measurement, rollout (Waves 5–6)

| # | Slice | Owner subsystem | Dependency / decision gate |
| --- | --- | --- | --- |
| P2-1 | W5-a viewport-bounds query | Places / API | None. |
| P2-2 | W5-b pin-first + cluster-policy hardening | Flutter / map | None. |
| P2-3 | W5-c cuisine/meal/diet/indoor facets + `/taxonomies` | Places / Flutter | W1 geo; **DG-?** cuisine taxonomy authority. |
| P2-4 | W5-d Local Restaurant Tour | Flutter / docent | W3-d + W5-c. |
| P2-5 | W5-e franchise confidence surfacing | Places / Flutter | None. |
| P2-6 | W5-f anonymous feedback + dispersion eval | Analytics / privacy | Privacy review (aggregate-only). |
| P2-7 | W6-a 30–50-place eval set | QA / eval | W1–W3 merged. |
| P2-8 | W6-b real-device captures (Android + iOS/Web) | QA / Flutter | All user-facing slices merged. |
| P2-9 | W6-c funnel metrics | Observability | None. |
| P2-10 | W6-d worker rollout (weather → score → ingest) | Ops / workers | **DG-1**, **DG-6** community-crawl approval (**BLOCKED_EXTERNAL**). |
| P2-11 | W6-e flag rollout + rollback drill | Ops / platform | All above. |

### 10.4 Decision gates (external / human — not assumed solved)

| ID | Decision | Why it blocks | Default if unresolved |
| --- | --- | --- | --- |
| **DG-1** | First **licensed review/mention source** + legal sign-off on retention/summarization (e.g. Naver Search API discovery within terms, or an approved export). | No source may be marked `licensed` without it and W6-d ingest rollout cannot call external providers. **BLOCKED_EXTERNAL.** | 062 governance foundation landed (PR #60) — DB-backed source gate + aggregate receipt are in place, but no live acquisition; pipeline consumes already-collected `community.posts`; `062`/`063` accept already-normalized records only. |
| **DG-2** | Travel-time provider: Kakao Mobility vs OSRM (self-hosted). ToS/cost differ. | W4-d travel-time cache + provider. **BLOCKED_EXTERNAL** (vendor/ToS). | Haversine straight-line fallback (legacy parity). |
| **DG-3** | Wind-threshold two-tier defaults (`discomfort_wind_ms`, `advisory_wind_ms`). | W1-b emits flags using them. | Config values documented as deliberate; flag off. |
| **DG-4** | Manual-review-queue UI owner for quarantine/ambiguous matches (operator console vs CLI). | W2-c closure. | CLI report; no UI. |
| **DG-5** | Manual-region granularity for v1: 시/군 (richer) vs province (simpler). | W1-a selection UX. | Province-level selection; 시/군 resolution still internal. |
| **DG-6** | Community-crawl (Daangn) live execution approval. | W6-d ingest rollout beyond weather/score. **BLOCKED_EXTERNAL** (legal/ToS). | Stay dry-run; consume existing aggregates only. |
| **DG-7** | Power BI / ops dashboard parity: defer or schedule? | Not in any wave (legacy O1 deferred). | Defer; non-mutating `observability_plan` + `ops.*` datamart contract only. |
| **DG-8** | Plan persistence scope: per-session only, or per-user (identity coupling)? | W4 plan_snapshots identity coupling. | Per-session only. |
| **DG-9** | Opening-hours source priority: public open-data vs LLM-extracted (which is authoritative on conflict?). | W1-d data authority. | License/official first; LLM-extracted with confidence + honest flag. |
| **DG-10** | Per-lane nightly cost ceiling (bulk lane) before W2-d scale-up. | W2-d quota/cost. | Stay batched + capped; no scale-up. |
| **DG-11** | Raw review-body retention legal/retention/access decision: (a) which sources permit retention, (b) the purge schedule, and (c) the access model. | Any `community.posts_raw`-style table and any slice that stores raw review text. **BLOCKED_EXTERNAL.** | No raw review text stored, served, logged, or embedded; `062` ships no raw-body column and is aggregate-only (landed); `063` (place_enrichments uniqueness) is additive aggregate-only; raw retention stays BLOCKED_EXTERNAL. |

---

### Related (in-repo)

- Visual contract (authoritative screen ground truth):
  [`lala-mobile-visual-contract/README.md`](./lala-mobile-visual-contract/README.md),
  [`00-visual-ground-truth.md`](./lala-mobile-visual-contract/00-visual-ground-truth.md),
  [`01-flow-and-runtime-contract.md`](./lala-mobile-visual-contract/01-flow-and-runtime-contract.md),
  [`03-visual-acceptance-matrix.md`](./lala-mobile-visual-contract/03-visual-acceptance-matrix.md).
- Shared migration runner: [`apps/api/app/services/canonical_sql.py`](../../apps/api/app/services/canonical_sql.py);
  canonical schema: [`sql/canonical/`](../../sql/canonical/).
- Worker contract: [`apps/workers/app/contracts.py`](../../apps/workers/app/contracts.py);
  OpenAPI tools: [`apps/api/app/tools/check_openapi_compat.py`](../../apps/api/app/tools/check_openapi_compat.py),
  [`export_openapi.py`](../../apps/api/app/tools/export_openapi.py).
- Safety contracts: [`apps/api/tests/test_safety_contracts.py`](../../apps/api/tests/test_safety_contracts.py),
  [`test_aws_secrets.py`](../../apps/api/tests/test_aws_secrets.py).

> The five domain plans and the two legacy-evidence docs are authored in sibling
> worktrees (`lala-plan-review-ingestion`, `lala-plan-rag-docent`,
> `lala-plan-day-planner`, `lala-plan-dashboard-map`,
> `lala-plan-restaurant-economy`, `lala-legacy-technical-spec`) and land at
> `docs/planning/` on `main`; they are cited by name here, not linked, until
> those PRs merge.
