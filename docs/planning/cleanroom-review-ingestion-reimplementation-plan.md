# Clean-Room Reimplementation Plan — Review & Mention Ingestion / Enrichment

> Status: **PLAN-ONLY**. This document changes no product source and no
> infrastructure. It is a design and acceptance blueprint for the review/mention
> ingestion and enrichment pipeline in LALA-next, written clean-room from
> behavior/interface evidence. Nothing here licenses copying legacy code,
> prompts, review text, assets, secrets, resource identifiers, or undocumented
> data (see §5).
>
> Companion evidence base (read-only, separate workspace): the audited
> `legacy-3dt-first-technical-spec.md` and `legacy-3dt-first-feature-inventory.md`
> (slice **R1 — Review ingestion**) in the `lala-legacy-technical-spec`
> workspace. This plan cites their findings by symbol and re-verifies against the
> read-only legacy tree at `/Users/geondongkim/3dt-1st-Project` and the current
> LALA-next tree in this worktree.
>
> Reconciliation note (2026-08-19, corrected 2026-08-22): this revision aligns
> the plan with the approved contract decisions and with PR #60's **merged**
> foundation (`062_review_ingestion_governance.sql` +
> `apps/api/app/services/review_ingest_governance.py`). Locked facts it enforces:
> the registry is `ingest.review_sources` (there is no `ingest.source_registry`);
> 062 does **not** retain raw review bodies; `community.posts_raw` is
> **BLOCKED_EXTERNAL** (no raw review text stored, served, logged, or embedded
> before a separate legal/retention/access decision); the next review-specific
> implementation adds only aggregate-only receipt/dedupe records, source
> registration lookup, a transaction boundary, and typed safe quarantine
> metadata, with **no external-provider calls**; and the bulk (`gpt-5.4-nano`) vs
> recheck/docent (`gpt-5.4-mini`) model roles are unchanged. Reconciliation edits
> are confined to this note, the §1 glossary row, §4.5, §7, §9, §10, §11, §19,
> §20, §24, §25, the §29 milestone markers, and the §32 related-links list; the
> remaining clean-room evidence and history sections (§0, §2–§3, §5–§6, §8,
> §12–§18, §21–§23, §26–§28, §30–§31) are retained unchanged in substance.
> §25.1 is additionally corrected so that no canonical migration number — and no
> list position that could be read as one — is reserved for any
> not-yet-implemented item.

## 0. Provenance & Method

- Legacy source (read-only): `/Users/geondongkim/3dt-1st-Project` (`3dt-project`,
  "LALA" / Local Area, Local Answer). Evidence cites **legacy-relative paths**
  and **symbol names** only.
- Current LALA-next (writable, this worktree): `apps/api`, `apps/workers`,
  `sql/canonical`, `docs/operations`. All "current state" claims cite paths that
  exist in this worktree and were read directly.
- Presentation (read-only, product promise): `LALA-발표자료-v2.pptx.pdf`,
  slides 1, 5, 7, 8 (emphasis), plus 9–19 for business/economy/privacy context.
  Slides are treated as a **mandatory product promise**, not decoration.

### Legend

| Tag | Meaning |
| --- | --- |
| **CONFIRMED** | Read directly in legacy code/SQL/docs or in current LALA-next code/SQL. Path + symbol cited. |
| **INFERRED** | Deduced from structure or absence of evidence; plausible, not directly observed. |
| **CONFLICT** | Two sources disagree. The stronger source wins; the disagreement is recorded. |
| **TARGET** | A future-state design decision this plan proposes (not yet implemented). |

### Redaction policy (same as the audited spec)

This plan cites only **paths, symbol names, and non-sensitive contract shapes**
(route paths, JSON envelope fields, SQL DDL shapes, config *behavior* such as
cron schedules, model role assignments, numeric thresholds). Concrete deploy
identifiers — cloud resource names, registry/vault/resource-group names,
queue/event-hub/consumer-group names, Key Vault secret names, connection-bearing
setting names, subscription/tenant/client identifiers, and literal service
endpoints — are written as **role-based placeholders** (e.g. `[review-source API]`,
`[mention queue]`, `[docent deployment]`). Public third-party open-API services
(e.g. Naver, Korea Meteorological Administration, data.go.kr public datasets)
are named in prose with literal endpoints redacted. Public model names
(`gpt-5.4-nano`, `gpt-5.4-mini`, `text-embedding-3-small`) and universal env-var
names (`DB_DSN`, `KEY_VAULT_URL`) are retained as interface evidence.

## 1. Domain Scope & Glossary

This plan owns the **review/mention ingestion and enrichment pipeline**: the
path that turns approved local review/mention/community inputs into trustworthy,
aggregate recommendation evidence — sentiment, aspect attributes,
`review_quality_score`, and RAG grounding — **without ever surfacing raw user
review text** to end users.

| Term | Meaning in this plan |
| --- | --- |
| **Review** | A blog/portal review snippet (e.g. Naver blog) about a place. |
| **Mention** | A community/local-SNS post or comment that references a place. |
| **Signal** | A retained, ad-filtered, place-matched, confidence-scored review/mention. |
| **Aggregate evidence** | Weekly, place-level rolled-up counts/sentiment/attributes — the only form that feeds scoring/RAG/UI. |
| **Docent lane** | `AZURE_OPENAI_DOCENT_DEPLOYMENT` (`gpt-5.4-mini`) — generation, QA, recheck. Unchanged by this plan (§16, §22). |
| **Bulk lane** | `AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT` (`gpt-5.4-nano`) — extraction, normalization, ad classification. Unchanged by this plan (§14, §15, §22). |
| **Governance foundation** | `062_review_ingestion_governance.sql` + `apps/api/app/services/review_ingest_governance.py` (PR #60) — source registry, run ledger, aggregate-only receipts/dedupe, typed quarantine. DB governance only; **no external-provider calls**. |

Out of scope (owned by sibling plans, consumed only via their contracts):
scoring weights (`local-value-v2`), day-plan scheduling, map clustering,
docent copy, TTS. This plan's contract boundary is the **aggregate-evidence
write** into `community.place_mentions_weekly`, `travel.place_enrichments`,
`analytics.place_score_snapshots.review_quality_score`, and
`rag.knowledge_chunks`.

## 2. Confirmed Legacy Evidence (review ingestion)

| Aspect | Legacy path · symbol | Finding | Tag |
| --- | --- | --- | --- |
| Review-ingest trigger | `src/functions/review_pipeline_func/function_app.py::review_pipeline_daily(timer)` decorated `@app.timer_trigger(schedule=...)` | **Timer trigger**, default `"0 0 17 * * *"` (~02:00 KST), overridable via `REVIEW_PIPELINE_SCHEDULE`. `host.json` `functionTimeout "02:00:00"`. **No queue binding.** | CONFIRMED |
| Review-ingest queue | — | **None.** Review ingestion reads no Azure Queue. | CONFIRMED (absence) |
| Trigger conflict | `docs/lala-business-logic-phase4-handoff-2026-03-06.md` vs `function_app.py` | Phase-4 handoff says "Storage Queue trigger"; shipped code is timer. **Treat review ingest as timer/CLI batch; do not assume a review-ingest queue contract.** | CONFLICT |
| Attraction pipeline | `src/collectors/load_review_pipeline.py::run_batch_for_area(lat, lng, radius_m=10_000)`; `fetch_attractions_in_area(lat, lng, radius_m)`; `run_review_pipeline(target_attraction)` | Naver search → HTML clean → food-review filter → per-review batch extract → keyword extract → embedding → pgvector insert into `locallink.attraction_reviews`. | CONFIRMED |
| Cleaning | `load_review_pipeline.clean_html(raw_html)`; `process_attractions.clean_and_filter_text(raw_html)` | HTML-tag strip + entity decode + UTF-8 safety. **Method confirmed; exact food-keyword list is content — paraphrase, do not copy.** | CONFIRMED |
| Food-contamination guard | `load_review_pipeline.is_valid_attraction_review(text)`; `extract_attraction_content_batch(attraction_name, reviews_list, batch_size=10)` | Rejects attraction reviews that are food-only; strips ads/comparisons/food per review in batches of 10 before analysis. | CONFIRMED |
| Keyword extraction | `load_review_pipeline.extract_keywords_with_llm(attraction_name, clean_reviews_list)` | LLM adjective/noun keyword extraction from review batches. | CONFIRMED |
| Embeddings | `load_review_pipeline.generate_embeddings_batch(texts)`; `process_attractions.generate_embeddings(text)` | Azure OpenAI `text-embedding-3-small`, **1536-d**, batch generation for cost; stored via `%s::vector`. | CONFIRMED |
| Restaurant pipeline | `src/collectors/load_restaurant_review.py::run_restaurant_pipeline(target_restaurant, sigun_nm)`; `process_restaurants.get_ranked_restaurants`, `analyze_reviews_with_llm`, `save_analysis_result` | Naver query `"{sigun_nm} {name} 후기"`; clean → LLM keywords → batch embeddings → `locallink.restaurant_reviews`. Food/taste/menu/service retained (food is product evidence for restaurants). | CONFIRMED |
| Idempotent upsert | collector INSERTs | `INSERT ... ON CONFLICT (<name_col>) DO UPDATE SET ... = EXCLUDED.<col>, embedding = EXCLUDED.embedding` keyed on place name. *(Pattern described, not copied — see §5.)* | CONFIRMED |
| Queue fan-out reference | `src/functions/daangn_weekly_crawler/` `daangn_crawl_worker` `@app.queue_trigger`, `daangn_place_mentions_worker`; `host.json` `batchSize=1`, `maxDequeueCount=8`, `visibilityTimeout=00:05:00` | The queue fan-out pattern belongs to the **community crawler**, not review ingestion. Retained only as a *behavior reference* for how a queue-based job declares retry/poison policy. | CONFIRMED |

## 3. Inferred / Conflict Items

- **INFERRED:** The legacy review pipeline had no quarantine/dead-letter store —
  failed LLM extractions could fall back to original review text in some paths.
  LALA-next must instead quarantine or mark low-confidence (no raw-text
  fallback). (Consistent with `docs/operations/review-mention-preprocessing-strategy.md`
  "Legacy LALA Touchpoints".)
- **CONFLICT:** Timer (shipped code) vs "Storage Queue trigger" (phase-4 doc).
  Resolution: review ingest is **timer/CLI batch**. If LALA-next later wants
  event-driven ingestion, it uses the portable worker contract (§8) on its own
  queue — it does **not** import a legacy review-queue contract.
- **INFERRED:** Legacy stored `VECTOR(1536)` but **never queried it** at runtime
  (keyword/SQL RAG only). LALA-next already declares an ivfflat cosine index on
  `rag.knowledge_chunks` — wiring real semantic retrieval is an intentional
  uplift, documented as TARGET, not legacy parity.

## 4. Current LALA-next State (implemented evidence)

All paths below exist in this worktree and were read directly.

### 4.1 Deterministic preprocessing — `apps/api/app/services/review_mention_ingest.py`

| Symbol / constant | Behavior | Tag |
| --- | --- | --- |
| `clean_review_text(*parts)` | HTML unescape, tag strip, URL/hashtag removal, repeated-punct collapse, whitespace normalize. | CONFIRMED |
| `classify_post(post, places)` | Computes `content_sha256 = sha256(provider\|external_key\|normalized_text)`; `_match_place` exact-name-in-text (`0.92` strong / `0.7` ambiguous); `AD_MARKERS` substring ad detection; `_category_policy` (restaurant→retain food; attraction→reject food-only unless place-evidence present). | CONFIRMED |
| `MIN_MATCH_CONFIDENCE = 0.85`; `PROMPT_VERSION="review-mention-preprocess-v1"`; `JOB_NAME="review-mention-ingest"` | Confidence gate, version stamp, job-run name. | CONFIRMED |
| `aggregate_decisions(...)` | Groups by `(week_start, place_id, place_name_ko, provider, category)`; deterministic `_sentiment_score`, `_review_attributes_summary` (`review-attributes-deterministic-v1`), `_review_quality_summary` (`review-quality-deterministic-v1`). | CONFIRMED |
| `insert_review_mention_aggregates(...)` | `ON CONFLICT (week_start, place_name_ko, provider, category) DO UPDATE`; **preserves** AI-derived `review_attributes`/`review_quality` when only deterministic metadata is rewritten. | CONFIRMED |
| `fetch_review_mention_inputs(...)` | Reads `community.posts` (+`travel.places` for matching). **Source = already-collected `community.posts`; no live review-source acquisition.** | CONFIRMED |

### 4.2 AI attribute/enrichment lane — `apps/api/app/services/review_attribute_batch.py`

| Symbol / constant | Behavior | Tag |
| --- | --- | --- |
| `selected_review_batch_model(settings)` | Prefers `AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT`, falls back to `AZURE_OPENAI_DEPLOYMENT`. **= bulk lane (gpt-5.4-nano).** | CONFIRMED |
| `generate_ai_enrichments(...)` | Azure OpenAI chat, `temperature=0.1`, `max_tokens=4000`, `response_format={"type":"json_object"}`. | CONFIRMED |
| `_create_chat_completion_with_retry`; `_is_retryable_ai_error` | Retries on 408/409/429/5xx and rate-limit/timeout markers. | CONFIRMED |
| Category attribute sets | `RESTAURANT_ATTRIBUTES` (taste/service/price/atmosphere/cleanliness/wait_crowding), `ATTRACTION_ATTRIBUTES` (cultural_story/atmosphere/walking_comfort/photo_view/practical_tip/crowding), `EVENT_ATTRIBUTES`. | CONFIRMED |
| `review_quality_payload(...)` | Formula `0.35·attribute_mean + 0.25·sentiment_norm + 0.20·organic_coverage + 0.10·ad_quality + 0.10·confidence`; `<3 organic → null`; `<10 organic → confidence≤0.65`; `ad ratio>0.50 → score≤0.60`. | CONFIRMED |
| `apply_review_attribute_enrichments(...)` | `UPDATE community.place_mentions_weekly SET sentiment_score=COALESCE(...), attributes = attributes \|\| {review_attributes, review_quality, review_attribute_batch}`. | CONFIRMED |

### 4.3 Embeddings / RAG hand-off — `apps/api/app/services/rag_index.py`

| Symbol / constant | Behavior | Tag |
| --- | --- | --- |
| `VECTOR_DIMENSIONS = 1536`; `build_embedding(method)` | `local-hash` / `azure-openai` / `openai`; `build_local_embedding` deterministic hash fallback for offline/CI. | CONFIRMED |
| `upsert_knowledge_chunks(...)` | `ON CONFLICT (source_type, source_id) DO UPDATE`; `source_type ∈ {place_profile, culture_event, community_post, place_mention, weather_context}`. | CONFIRMED |
| `query_knowledge_chunks(...)` | Cosine `1 - (embedding <=> query)::vector`; ivfflat index present. | CONFIRMED |
| `_community_post_chunk(row)` | **Embeds the raw `community.posts` body/title into a `community_post` chunk.** ⚠️ Privacy gap: raw post text reaches RAG grounding. See §17, §21. | CONFIRMED |

### 4.4 Worker contracts (dry-run) — `apps/workers/app/contracts.py`

| Job id | Trigger | Idempotency key | Poison | Tag |
| --- | --- | --- | --- | --- |
| `community-post-ingest` | queue/manual | `event_hub_partition + sequence_number` or source `external_key` | threshold 5 → "future dead-letter store" | CONFIRMED (dry-run) |
| `community-keyword-watchlist` | schedule/manual | `iso_week + keyword + region_slug` | mark ingest run failed | CONFIRMED (dry-run) |

`run_worker_job(...)` returns `not_implemented` for live execution in Wave 1;
`evaluate_worker_live_preflight(...)` reports blockers (`DB_DSN`,
`KEY_VAULT_URL`, queue binding, live retry/poison impl). This is the
**portable worker contract** this plan builds on (§8).

### 4.5 Schema (canonical) — `sql/canonical/*`

- `community.posts` (provider, external_key UNIQUE, keyword, region_slug, title,
  body, post_url, created_at_source, collected_at) — `030_community_core_tables.sql`.
- `community.place_mentions_weekly` (UNIQUE week_start/place_name_ko/provider/category;
  mention_count, organic_mention_count, sentiment_score numeric(5,4), attributes
  jsonb) — `030`.
- `community.ingest_runs` / `ingest_tasks` / `keyword_watchlist` — `030`.
- `ingest.source_files` (source_name, dataset_name, file_name, file_sha256,
  downloaded_at) — `035_data_pipeline_tables.sql`.
- `rag.knowledge_chunks` (vector(1536), ivfflat cosine lists=32, UNIQUE
  source_type/source_id) — `036_rag_knowledge_tables.sql`.
- `travel.place_enrichments` (enrichment_type, attributes jsonb, confidence,
  source_method, model_name, prompt_version) — `010_travel_core_tables.sql`.
- `travel.docent_scripts` (UNIQUE place_id/category/language/mode) — `020`.
- `analytics.place_score_snapshots` (review_quality_score numeric(7,4)) — `035`.
- `ops.job_runs` (job_name, status, started_at, finished_at, duration_ms,
  error_message) — `040_ops_core_tables.sql`.
- **Review-ingestion governance foundation (PR #60, merged to `main`,
  `062_review_ingestion_governance.sql`, additive/re-runnable; none of these
  tables retains raw review bodies):**
  `ingest.review_sources` (source_name PK, provider, license_class ∈ {licensed,
  public_processed, approved_export, rejected}, terms_version,
  collection_method, retention_policy, redaction_policy, source_status); a
  governance extension to `community.ingest_runs` (run_key partial unique index,
  source_name, license_class, terms_version, schema_version, received/processed/
  duplicate/quarantined counters, failure_category);
  `ingest.review_ingest_receipts` (the aggregate-only persistent receipt/dedupe —
  PK `source_name`/`external_key`/`content_sha256`, first/last run id + seen-at,
  **no raw text**); and `community.ingest_quarantine` dead-letter (provider,
  external_key, content_sha256, reason_category, reason_code, reason,
  safe_metadata jsonb — **no raw-body column by design**). Service boundary:
  `apps/api/app/services/review_ingest_governance.py`, which performs the
  DB-authoritative source-registration lookup and runs receipt dedupe →
  quarantine insert → run finalize inside a single transaction boundary, with no
  external-provider calls. Tests:
  `apps/api/tests/test_review_ingest_governance.py`.
  > Note: this plan-only branch predates PR #60's merge; the authoritative
  > source of truth for the foundation is the merged `main` history
  > (PR #60, `062_review_ingestion_governance.sql` +
  > `apps/api/app/services/review_ingest_governance.py`), which is what this
  > plan is reconciled against and cites above.

### 4.6 Config & API surface — `apps/api/app/core/config.py`, `apps/api/app/routers/v1.py`

- Model-role vars: `AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT`,
  `AZURE_OPENAI_DOCENT_DEPLOYMENT`, `AZURE_OPENAI_DEPLOYMENT` (generic fallback);
  `LALA_ENABLE_LIVE_AI` (default **off**); `NAVER_CLIENT_ID`/`NAVER_CLIENT_SECRET`
  present but **no Naver ingestion worker exists**.
- Runtime guard: `apps/api/app/services/ai_service.py::_ATTRACTION_NOISE_GUARD_KO`
  prevents food/cafe text from contaminating attraction docent context at serve
  time. No API endpoint exposes raw review text; `/api/v1/places`, `/weather`,
  `/docents/script`, `/plans/daily`, `/plans/intervention` are read-only over
  canonical relations.

### 4.7 Gap map (this domain → target)

| # | Gap | Current evidence | Target |
| --- | --- | --- | --- |
| G1 | No licensed/public **review-source acquisition** lane | Ingest only consumes `community.posts`; Naver keys unused | A guarded, terms-compliant review/mention acquisition worker (§9) |
| G2 | No **raw / normalized / provenance** split | `community.posts` holds title/body inline; `ingest.review_sources` (062) now provides per-source provenance; raw-body isolation still open | Provenance: **IMPLEMENTED in 062** (`ingest.review_sources`). Raw-body isolation: **BLOCKED_EXTERNAL** (§10) — no `posts_raw` until a separate legal/retention/access decision |
| G3 | No **quarantine / dead-letter** store | "future dead-letter store" placeholder in contract (now superseded by 062) | **IMPLEMENTED in 062:** `community.ingest_quarantine` (no raw payload). Replay still TARGET (§19/§20) |
| G4 | No **replay / backfill** CLI | Batch reads newest rows only | `--since/--window` deterministic re-run (§20) |
| G5 | Ad suspicion is **deterministic-only** | `AD_MARKERS` substring; AI classifier marked Pending (M3) | Deterministic first-pass + bulk-lane AI classifier (§14) |
| G6 | No **low-confidence recheck** escalation | Bulk lane only; no gpt-5.4-mini recheck | Uncertainty→recheck hand-off to docent lane (§16) |
| G7 | **Raw post text reaches RAG** | `_community_post_chunk` embeds body/title | Embed aggregate summaries only (§17, §21) |
| G8 | Review enrichments not mirrored to `travel.place_enrichments` | Attributes live only in `place_mentions_weekly.attributes` | Write `enrichment_type='review_attributes'/'sentiment'` rows (§25) |
| G9 | No **KO/EN language normalization** for signals | KO-centric; no KO→EN place-term normalization | Normalize + tag language; KO/EN mutually exclusive at serve (§13) |

## 5. Clean-Room Boundary (do-not-carry for this domain)

This plan is **behavior/interface only**. Do **not** carry from legacy into
LALA-next:

- **Code:** no legacy Python/SQL (re-implement; LALA-next already owns
  `review_mention_ingest.py`, `review_attribute_batch.py`, `rag_index.py`).
- **Prompts/persona:** no docent/extraction system-prompt text or few-shot
  examples. Re-derive the JSON contract from behavior; LALA-next owns its copy in
  `review_attribute_batch.SYSTEM_PROMPT`. This plan describes the *contract*
  (fields, rules), not the wording.
- **Review text / crawl payloads:** no Naver review content, no Daangn crawl
  payloads, no user rows. The pipeline stores only **approved/summarized**
  signals and aggregate counts.
- **Food-filter keyword list:** the exact legacy Korean exclusion terms are
  content. Paraphrase the *method* (category-aware food-noise rejection); do not
  copy the list. LALA-next already owns its own term sets in
  `review_mention_ingest.FOOD_ONLY_TERMS`.
- **Secrets/identifiers:** no connection strings, API keys, Key Vault values,
  or legacy resource names (vault/registry/resource-group/subscription/tenant/
  client IDs, queue/event-hub/consumer-group names). Use role-based placeholders.
- **Data sources as truth:** legacy *relied on* unauthenticated Naver/Daangn
  scraping. LALA-next does **not** inherit that reliance — see §9.

What **may** be re-implemented: interface/schema/contract shapes already present
(`community.posts`, `place_mentions_weekly`, `rag.knowledge_chunks`), the
upsert/on-conflict *method*, the two-stage clean→extract *idea*, and the
category-aware retention *policy*.

## 6. Presentation-Derived Capability Gates (mandatory)

These are **required product promises**, verified against
`LALA-발표자료-v2.pptx.pdf`. Each gate is binding on this plan; acceptance
criteria are concrete and screen/API/DB-tied.

> Note on fidelity: slide text was captured via vision and is noisy (Korean OCR
> artifacts). Gates below state the **capability intent** confirmed across
> slides; exact on-screen Korean strings must be re-verified from the real device
> (§29), not transcribed from OCR.

| Gate | Slide evidence (capability intent) | Binding requirement for this pipeline | Acceptance |
| --- | --- | --- | --- |
| **G-DATA: domestic daily data → AI → foreigner guidance** | Slide 7 "Data/AI structure": Input 내국인 신호 (5억 건 카드, 로컬 SNS 라이브 신호, 기상청 API) → LALA AI 엔진 (LLM 학습 요약, RAG 맥락 분석, **속성 기반 분류**) → Output 외국인 안내 | This pipeline owns the **로컬 SNS/리뷰 신호** ingestion + **속성 기반 분류** + **RAG 맥락** hand-off. Signals must be verifiable, attribute-structured, and RAG-grounded. | DB: each retained signal has `match_confidence`, category-typed `attribute_scores`, and a `place_mention` RAG chunk. |
| **G-TRUST: trustworthy local signals, no raw review text** | Slides 7 ("LLM 학습 요약"/"속성 기반 분류") + 19 (privacy guardrail) | End users and docents see **aggregate/summarized** evidence only; raw review text never leaves the enrichment boundary. | UI/API: no endpoint returns raw `community.posts.body`; RAG `community_post` raw-text embedding removed or replaced by summary (§17). |
| **G-SITUATION: weather/air-aware reasoned recommendations** | Slide 8 "상황 대응 추천" (rain→indoor, clear→alley walk; context not just list) | `review_quality_score` (this pipeline's output) is a scored input the planner swaps on. The pipeline must expose *why* a place is trusted (attribute evidence), feeding the "reasoned" substitution. | API: `/api/v1/plans/daily` and `/plans/intervention` consume `review_quality_score`; DB: score is null when evidence < 3 organic (honest absence). |
| **G-ECONOMY: aggregate evidence, not personal tracking** | Slides 10 ("지역 상권에 닿는 방법" — recommendation→visit/spend/stay) + 16 ("외국인의 다양 행동을 지역 소비로 연결") | Card/official data and review signals are **aggregate place/area-level evidence**. No per-user tracking; no joinable user identity in review signals. | DB: `place_mentions_weekly`/`economy.*` carry no user ids; provenance is source-level, not person-level. |
| **G-LEGAL: legal data-source + privacy guardrail** | Slide 19 "데이터 활용의 합법성 및 프라이버시 가드레일": (1) 합법적 수집 — 공공 API + 비식별/가명·가공 데이터; (2) 명시적 동의 — 온보딩 위치정보 Opt-in UI | Review/mention acquisition uses only **licensed/public or processed/de-identified** sources; no scraping that violates terms. Location consent is the app's concern, but this pipeline stores **no raw PII** and only **aggregate** signals. | Ops: `ingest.review_sources` (062) marks each source `licensed`/`public_processed`/`approved_export`/`rejected`; secrets-contract test forbids review-text/PII in outputs. |
| **G-REALDATA: no demo/mock in normal flows** | Slides 5–8 show real user-facing screens ("아이디어가 아닙니다. 경기도 테스트베드에서 이미 구현했습니다") | Normal UI uses live DB/API data with explicit honest loading/failure states. No mock review fixtures in non-test paths. | Tests: `test_safety_contracts.py` covers no-mock/no-fallback; smoke against live DB/PostGIS places. |
| **G-I18N: KO/EN mutually exclusive** | Slide 7 output is foreigner guidance (EN-facing); slide 8 shows EN plan labels | UI is one language at a time; signals are language-tagged; no mixed-language public labels. | Schema: `language` tag on enrichments; serve-time `display_language` picks one mode. |
| **G-CROSSPLATFORM: Android + iOS/Web preserve workflow** | Slides 5/8 mockups are device-agnostic screens | The review-evidence contract (aggregate JSON) is platform-neutral; consumed identically by Flutter (Android/iOS) and Web. | API: same `/api/v1/*` envelope serves all clients. |

## 7. Target Architecture (not an Azure Functions port)

LALA-next keeps its current topology; the legacy Azure Functions timer/queue
runtime is **not** ported. Review ingestion runs as **guarded batch CLI tools +
a portable worker contract**, reading/writing PostgreSQL/PostGIS/pgvector,
serving reads via FastAPI, rendering via Flutter/Kakao.

```
[licensed/public sources] --(terms-checked)--> acquire (governed by ingest.review_sources, §9.3)
                                                              |
                                              normalize -> dedup -> ad-suspicion
                                                              |
                                    place-match (confidence) -> language-normalize
                                                              |
                          bulk lane (gpt-5.4-nano): sentiment + aspect extraction
                                                              |
                    low-confidence? --yes--> recheck lane (gpt-5.4-mini, §16)
                                                              |
                          aggregate (weekly, place-level) -- idempotent upsert
                                                              |
            community.place_mentions_weekly  travel.place_enrichments
            analytics.place_score_snapshots.review_quality_score
                                                              |
                              embeddings hand-off (summary only) -> rag.knowledge_chunks
                                                              |
                              FastAPI /api/v1/* (read) --> Flutter / Web (aggregate only)
```

> **No RAW store exists or is planned** (§10): the approved policy is that raw
> review text is not stored, served, logged, or embedded before a separate
> legal/retention/access decision. The governance foundation already delivers
> the raw-free spine — `ingest.review_sources` registration, the idempotent
> `community.ingest_runs` ledger, `ingest.review_ingest_receipts`
> aggregate-only dedupe, and `community.ingest_quarantine` typed metadata — so
> the normalize/dedupe stages operate on already-normalized records (§11).

**Separation of concerns (preserved):** FastAPI request handlers **never**
become crawlers, schedulers, or streaming consumers (see
`docs/operations/worker-batch-boundary.md`). All writes are operator-run guarded
batches or approved workers; the API only reads.

## 8. Portable Worker Contract (timer vs queue fan-out)

A review/mention ingestion job is declared through the existing
`WorkerJobDefinition` shape (`apps/workers/app/contracts.py`) so it can run as
**schedule/manual** (parity with the legacy timer) **or** later as **queue/manual**
(parity with the community-crawler fan-out) without changing its write contract.

**Proposed job definition (TARGET, to add to `contracts.py`):**

| Field | Review-ingest job (`review-mention-ingest`) | Attribute/recheck job (`review-attribute-batch`) |
| --- | --- | --- |
| trigger | schedule/manual (cron, e.g. nightly) or queue/manual | schedule/manual (follows ingest) or queue/manual |
| writes | `ingest.review_sources` (lookup), `community.ingest_runs` (062 governance cols), `community.ingest_quarantine`, `community.posts`, `community.ingest_tasks`, `ops.job_runs` — **no `posts_raw`** (BLOCKED_EXTERNAL, §10) | `community.place_mentions_weekly`, `travel.place_enrichments`, `analytics.place_score_snapshots`, `rag.knowledge_chunks`, `ops.job_runs` |
| retry | exp `30s,2m,5m`; retryable `db_connection_error,source_api_timeout,rate_limited,transient_5xx`; non-retryable `invalid_event_schema,terms_violation` | exp `10s,30s,1m,2m,5m`; retryable `429,timeout,5xx`; non-retryable `schema_validation_error` |
| idempotency | `run_key = source_name + window + schema_version` (062 run-ledger receipt) / `iso_week + place_id + provider + category` (aggregate) | `(place_id, week_start, schema_version)` |
| poison | threshold → `community.ingest_quarantine` + `ops.job_runs(failed)` | threshold → leave prior enrichment, log to quarantine |
| dependencies | `DB_DSN`, `KEY_VAULT_URL`, source credential env | `DB_DSN`, `KEY_VAULT_URL`, `[bulk deployment]`, `[docent deployment]` |

The contract is **runtime-agnostic**: the same job runs behind a cron (Linux
`systemd` timer / AWS EventBridge / container scheduled task / macOS launchd)
or behind a queue (SQS / Event Hub / Redis). The dispatch brief's "describe a
portable worker contract if a timer/queue is needed" is satisfied by this
declaration plus the guarded CLI entrypoints that already exist
(`run_review_mention_ingest`, `run_review_attribute_batch`, `run_rag_index`).
Live mutation stays behind `ALLOW_*_APPLY=1` + `--confirm` gates and the Wave-1
`not_implemented` guard until DB/queue approval.

## 9. Data Acquisition: Licensed/Public vs Prohibited

### 9.1 Allowed (preferred) sources

- **Licensed APIs:** a review/portal Search API used **within its terms**
  (e.g. Naver Search API with `NAVER_CLIENT_ID/SECRET`) for *discovery* of
  review/blog URLs and metadata — **not** for re-publishing review text. Store
  only metadata + a pointer; summarize content via the bulk lane; never store
  verbatim review bodies unless the license explicitly permits retention.
- **Public/processed datasets:** public-data community indicators that can be
  legally stored and summarized (the same discipline as
  `docs/operations/card-spending-source-inventory.md`).
- **Approved exports:** contracted or operator-approved review/mention exports
  with stable source URL, timestamp, and collection method.

### 9.2 Prohibited sources (hard rule — maps to slide 19 G-LEGAL)

- **Unauthenticated scraping** that violates site terms (the legacy reliance on
  raw Naver/Daangn scraping is **not** carried over).
- Screenshots or manually copied reviews without source metadata.
- Content with no stable source URL, timestamp, or collection method.
- Any raw secret, token, private user identifier, or PII.

### 9.3 Source registry (IMPLEMENTED in 062 as `ingest.review_sources`)

**The current registry is `ingest.review_sources` — not
`ingest.source_registry` (no such table exists or is proposed).** PR #60 landed
`ingest.review_sources` (in `062_review_ingestion_governance.sql`, merged to
`main`) as the provenance backbone — it is **not** an extension of
`ingest.source_files`. One row per approved source records:
`source_name` (PK), `provider`, `license_class ∈ {licensed, public_processed,
approved_export, rejected}`, `terms_version`, `collection_method`,
`retention_policy`, `redaction_policy`, `source_status ∈ {active, disabled}`.
The governance boundary (`apps/api/app/services/review_ingest_governance.py`)
refuses any source whose `license_class` is not in `{licensed,
public_processed, approved_export}` — the `rejected` class is registrable (so an
operator can record a blocked source) but is never accepted for ingestion. The
DB-authoritative source gate (`load_active_review_source`) loads the row from
`ingest.review_sources` and **aborts** the batch **before any record is
accepted**, emitting a distinct governance code per source-level failure
(`source_not_registered` for an absent source, `source_disabled`,
`source_license_rejected` for a `rejected` license class,
`source_provider_mismatch`, `source_terms_mismatch`); source-level failures do
not route records to quarantine. Per record, `classify_review_records`
quarantines any record whose `source_name`/`provider`/`license_class`/
`terms_version` does not exactly match the loaded registration under the
`terms_violation` category (`source_identity_mismatch` reason code), so the
`terms_violation` category is live for per-record provenance mismatches rather
than deferred to a future lane. Registration itself is internal/admin only
(`register_review_source`, idempotent upsert, own transaction, deliberately no
public endpoint). This closes the provenance gap noted in
`docs/operations/review-mention-preprocessing-strategy.md`.

## 10. Storage Model: Provenance / Normalized (raw retention BLOCKED)

### 10.1 Layered separation (provenance IMPLEMENTED; raw retention BLOCKED_EXTERNAL)

| Layer | Status | Holds | Privacy posture |
| --- | --- | --- | --- |
| **Provenance** | **IMPLEMENTED (062)** — `ingest.review_sources` + `community.ingest_runs` governance extension | Source identity, license class, terms version, run lifecycle (run_key receipt), received/processed/duplicate/quarantined counters, failure_category. | Public-safe counts + identity only; no bodies. |
| **Normalized** | CURRENT — `community.posts` (existing) | Cleaned text (HTML-stripped, whitespace-normalized), language tag, dedup hash — the working set for enrichment. | Cleaned but still source text; not served to users. This is **pre-existing** LALA-next state, not something this plan or PR #60 adds; no review-body text is written into it by the governance slice. |
| **Raw retention** | **BLOCKED_EXTERNAL** — no `community.posts_raw` table is created by this plan or by PR #60. | Original acquired payload / review bodies. | Raw review text is **not stored, served, logged, or embedded** anywhere in the current pipeline. A future `posts_raw`-style table requires a separate legal/retention/access decision (§10.2) and is explicitly out of scope until then. |

062 deliberately ships **no raw-body column** on `community.ingest_quarantine`
and no `posts_raw` table. The governance service
(`review_ingest_governance.py::ApprovedReviewAggregate`) emits an aggregate-only
payload with no body/title/url fields, enforced by `extra="forbid"` on the model
and the `enforce_no_raw_review_text` runtime guard. The earlier "Raw layer (new)"
design that proposed backfilling `community.posts` into `posts_raw` is
superseded — do not introduce such a table under this plan.

### 10.2 Why raw retention is blocked (approved-before-legal policy)

Per the approved contract decision, LALA-next does **not** create
`community.posts_raw` now. Until a separate legal sign-off covers (a) which
sources permit retention, (b) the retention/purge schedule, and (c) the access
model, raw review text is never persisted. Consequences for the rest of this
plan:

- **Replay/backfill (§20)** cannot re-read raw payloads (none are retained); it
  re-runs from the pre-existing normalized `community.posts` rows plus the 062
  run ledger, and only re-normalizes/re-enriches what is already in the
  normalized layer. A `--reacquire` lane is doubly gated behind both the worker
  `ALLOW_*` env and the unresolved raw-retention decision.
- **Quarantine (§19)** carries `content_sha256` + identity + `safe_metadata`
  only (as 062 already enforces) — never a body, never a `raw_payload_ref`.
- **Privacy posture is strongest by construction:** there is no raw store to
  leak. This is stricter than the earlier "isolated raw layer" design and
  supersedes any §5/§21 reference to a retained raw layer.
- **Auditability** still holds: every aggregate resolves to a `source_run_id` +
  `license_class` + `prompt_version` via the 062 provenance layer (G-LEGAL,
  G-TRUST), without any raw body being kept.

## 11. Pipeline Stages (end-to-end contract)

1. **Govern** (§9; DB-only, IMPLEMENTED in 062/PR #60): the governance boundary
   validates each already-normalized record against `ingest.review_sources`
   (062), opens/resumes an idempotent `community.ingest_runs` ledger row keyed
   by `run_key`, records an aggregate-only `ingest.review_ingest_receipts` row
   for cross-run dedupe, routes malformed/unsafe records to
   `community.ingest_quarantine` with typed `safe_metadata`, and produces an
   aggregate-only `ApprovedReviewAggregate` (no raw body stored — §10) — all in
   one transaction. **The next review-specific implementation must add only:
   aggregate-only persistent receipt/dedupe records, source-registration lookup,
   a transaction boundary, and typed safe quarantine metadata — and must not
   call external providers.** Live acquisition is a separate, later lane.
2. **Normalize** (§13): `clean_review_text`-style HTML/entity/whitespace cleanup;
   language detection/tagging; KO/EN place-term normalization.
3. **Deduplicate** (§12): normalized-text + source + URL + content hash.
4. **Ad suspicion** (§14): deterministic first-pass → bulk-lane AI classifier
   (`is_ad`, `ad_confidence`, `reason`, `organic_excerpt`).
5. **Place match** (existing `_match_place`): exact-name → alias → address/geocode
   → nearby coordinate → manual review; persist `match_confidence`/`match_method`.
   Below `MIN_MATCH_CONFIDENCE=0.85` → quarantine/manual, **never** auto-scored.
6. **Category policy** (existing): restaurant retains food terms; attraction/
   culture rejects food-only unless place-evidence present.
7. **Sentiment + aspect extraction** (§15): bulk lane, category-typed attributes,
   JSON-only.
8. **Uncertainty / recheck** (§16): low-confidence → docent-lane recheck or
   quarantine.
9. **Aggregate + idempotent upsert** (§18): weekly place-level roll-up into
   `place_mentions_weekly`; mirror to `travel.place_enrichments`.
10. **Embeddings hand-off** (§17): summary-only chunks into `rag.knowledge_chunks`.
11. **Scoring hand-off**: `review_quality_score` → `analytics.place_score_snapshots`.
12. **Record** `ops.job_runs` + provenance counts.

## 12. Deduplication

- **In-batch:** `content_sha256 = sha256(provider|external_key|normalized_text)`
  (existing); duplicates flagged `duplicate_content`, not deleted (audit).
- **Cross-batch / source:** dedup by normalized title + URL + source + text hash
  (TARGET). Add `content_sha256` + `source_url` + `source_provider` +
  `collected_at` + `created_at_source` to the normalized layer; enforce a unique
  partial index on `(provider, content_sha256)` and `(source_url)` where present.
- **Place-level:** aggregation naturally collapses by `(week, place, provider,
  category)`; ambiguous same-name places/franchise branches go to manual review
  (existing `ambiguous_match` path), never silently counted.

## 13. Language Normalization (KO/EN mutual exclusivity)

- **Detect + tag** each signal's language at normalize time; store `language` on
  the normalized row and on enrichments.
- **KO→EN place-term normalization** is an *interface* need (re-derive minimal
  maps; **do not** copy legacy 88-entry suffix tables — see `legacy-3dt-first...`
  §17). LALA-next already has `apps/api/app/services/normalization.py`; extend it
  for place/menu nouns used as evidence phrases only.
- **Serve-time mutual exclusivity:** `display_language` picks one mode per
  request; attribute labels are emitted in that language only (no mixed KO/EN in
  a public label — a guardrail already stated in the attribute contract).
- Evidence *phrases* fed to RAG/docent are short and language-tagged; the docent
  lane re-renders in the requested language rather than concatenating KO+EN.

## 14. Advertisement Suspicion (deterministic + AI)

- **First pass — deterministic** (existing `AD_MARKERS`: 광고/협찬/원고료/체험단/
  쿠폰/할인코드/…). Cheap, no tokens, catches sponsor markers. Paraphrase the
  *method*; LALA-next owns its own term set.
- **Second pass — AI classifier (bulk lane, gpt-5.4-nano):** JSON-only
  `{is_ad, ad_confidence, reason, organic_excerpt}`. Runs **only after**
  deterministic filters, only on candidates. This closes strategy milestone M3
  ("AI classifier — Pending"). The `organic_excerpt` must be a **short** phrase,
  never a verbatim review body (G-TRUST).
- **Policy:** high ad-ratio (>0.50) caps `review_quality_score≤0.60` (existing);
  suspected ads are excluded from organic counts but their *metadata* is retained
  for the aggregate `filtered_ad_count`/`ad_ratio`.

## 15. Sentiment & Aspect Extraction (model policy)

- **Lane:** bulk `AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT` (`gpt-5.4-nano`),
  `temperature≈0.1`, `response_format=json_object`. Reuse the **contract**
  already in `review_attribute_batch.py` (category attribute sets, 0–1 scores
  with `count`/`confidence`, short evidence phrases, `rejected_evidence` with
  hashed text only).
- **Category schemas (existing, confirmed):**
  - Restaurant: taste/service/price/atmosphere/cleanliness/wait_crowding.
  - Attraction/culture: cultural_story/atmosphere/walking_comfort/photo_view/
    practical_tip/crowding.
  - Event: program_quality/family_friendliness/foreign_visitor_fit/access/
    weather_indoor_fit/crowding.
- **Guardrails (behavioral, not prompt copy):** no invented facts (hours/prices/
  history/weather); no attributes without retained organic evidence; no long
  verbatim text in evidence phrases; no food attributes for non-food places.
- **`review_quality_score` formula** is owned by LALA-next
  (`review_quality_payload`); this plan keeps it, documents it as a
  *deliberate* LALA-next design (not legacy 40/60 truth), and only adjusts
  thresholds with version bump (`formula_version`).

## 16. Uncertainty / Recheck (gpt-5.4-mini escalation) — TARGET, fixes G6

- **Trigger:** a signal is *uncertain* if any of: attribute `confidence < 0.6`,
  `organic_review_count` in the 3–9 band, ambiguous place match resolved by
  manual approval, ad-classifier margin small, or sentiment/attribute disagree.
- **Escalation:** route to the **docent lane** (`AZURE_OPENAI_DOCENT_DEPLOYMENT`,
  `gpt-5.4-mini`) for a single recheck pass, **not** the bulk lane. This is the
  brief's "low-confidence recheck and all docent generation/QA" role.
- **Outcomes:** (a) confirmed → upsert with raised confidence (cap rules apply);
  (b) still uncertain → quarantine for manual review; (c) rejected → excluded
  from organic counts, metadata retained. Uncertain signals **never** auto-enter
  scoring/RAG.
- **No silent trust:** unlike legacy paths that could fall back to raw text on
  LLM failure, LALA-next marks low-confidence and quarantines — it does not paste
  raw review text as a fallback.

## 17. Embeddings Hand-off (summary only; no raw text) — fixes G7

- **Embed aggregates, not raw posts.** The `community_post` chunk path in
  `rag_index.py::_community_post_chunk` currently embeds the raw
  `community.posts` body/title. **TARGET change:** either (a) retire the
  `community_post` source type for serving and embed only `place_mention`
  aggregate chunks (counts/sentiment/attributes/top_terms), or (b) replace its
  `body_ko` with the *summarized* attribute summary, never the raw body.
- **Why:** RAG chunks are docent grounding (G-TRUST, slide 7 "RAG 맥락 분석").
  Docents must ground in *aggregate evidence*, not in a single user's review
  text. This also closes the privacy exposure surface.
- **Dimensions/index:** keep `vector(1536)` + ivfflat cosine (`lists=32`,
  existing). Model `text-embedding-3-small` (or Azure equivalent deployment);
  `local-hash` remains the deterministic CI/offline fallback so tests never call
  live AI.
- **Hand-off contract:** `rag.knowledge_chunks` rows of `source_type='place_mention'`
  with `metadata` = `{week_start, provider, category, mention_count,
  organic_mention_count, sentiment_score, attributes}`. Idempotent on
  `(source_type, source_id)` via existing `ON CONFLICT`.

## 18. Idempotent Upsert

| Target | Conflict key | Strategy |
| --- | --- | --- |
| `community.ingest_runs` (062 run ledger) | `run_key = source_name + window + schema_version` (partial unique where `run_key IS NOT NULL`) | insert-or-resume (062 `ON CONFLICT (run_key) DO UPDATE SET received_count ... RETURNING id`); finalized once per batch |
| `community.ingest_quarantine` (062) | `(provider, external_key, reason_category) WHERE resolved_at IS NULL` | insert; on conflict skip (one dead-letter row per reason while unresolved) |
| `community.posts` | `(provider, external_key)` | update cleaned fields + language tag |
| `community.place_mentions_weekly` | `(week_start, place_name_ko, provider, category)` | **existing** upsert; **preserves** higher-tier AI `review_attributes`/`review_quality` when deterministic metadata is rewritten |
| `travel.place_enrichments` | `(place_id, enrichment_type, prompt_version)` (TARGET unique) | insert new version row; keep history (`generated_at`) so recheck/replay is auditable |
| `rag.knowledge_chunks` | `(source_type, source_id)` | existing upsert; re-embed on content change |
| `ops.job_runs` | n/a | append-only provenance |
| ~~`community.posts_raw`~~ | n/a | **BLOCKED_EXTERNAL** (§10) — no raw-retention table; no upsert strategy until legal decision |

All upserts are **keyed and replay-safe**: re-running a window with the same
inputs yields the same rows (no duplicates, no lost higher-tier enrichments).

## 19. Quarantine / Dead-Letter (IMPLEMENTED in 062; typed metadata only)

- **Table (IMPLEMENTED in 062):** `community.ingest_quarantine` —
  `(id, source_run_id, source_name, provider, external_key, content_sha256,
  reason_category ∈ {schema_invalid, terms_violation, source_api_failure,
  duplicate_suspect, low_confidence, ambiguous_match}, reason_code, reason,
  safe_metadata jsonb, received_at, quarantined_at, resolved_at, resolution ∈
  {approved, rejected, retried})`. **No `raw_payload_ref` and no body column by
  design** — a record is diagnosable from identity + content hash + the
  code-backed `reason_code`/`reason` + the typed `safe_metadata` jsonb alone.
  This is the "typed safe quarantine metadata" the next slice persists via
  `review_ingest_governance.py::_insert_quarantine_entries`. (The earlier
  draft's `ai_failure` reason and `raw_payload_ref` pointer are removed: neither
  exists in 062.)
- **Idempotent dead-letter:** partial unique index on
  `(provider, external_key, reason_category) WHERE resolved_at IS NULL` means
  retrying a failed batch does not duplicate dead-letter rows.
- **Poison path (contract):** after the job's poison threshold (§8), malformed/
  unrecoverable events land here instead of crashing the batch. Replaces the
  "future dead-letter store" placeholder in `contracts.py` (§4.4).
- **Operator action:** review queue (manual) — matches the existing
  `ambiguous_match` discipline. Nothing in quarantine reaches scoring/RAG until
  `resolution='approved'` with a recorded approver/run.
- **Observability:** quarantine depth is a metric/alert (§23).
- **IMPLEMENTED in PR #60 (merged to `main`):** source-gate → run create/resume
  → receipt dedupe → quarantine insert → run finalize run inside a **single
  transaction boundary** (`persist_review_ingest_run`'s `with conn:` block) so a
  partial failure rolls back and cannot leave the ledger, receipts, and the
  dead-letter out of sync. A late failure rolls the whole batch back and never
  exposes accepted aggregates. No external-provider calls.

## 20. Replay / Backfill

- **CLI flags (TARGET):** extend the guarded tools with `--since`,
  `--until`/`--window`, `--provider`, `--place-id`, `--force-prompt-version`.
  Replay re-reads from the pre-existing normalized `community.posts` rows plus
  the 062 run ledger (§10) — **no raw store exists to read from**
  (BLOCKED_EXTERNAL) — and re-enriches/re-upserts idempotently (§18).
- **Determinism:** same raw inputs + same `prompt_version` → same outputs (bar
  model non-determinism, mitigated by low temperature + JSON schema). Each
  replay records a new `ops.job_runs` row and a new `place_enrichments`
  generation (history preserved).
- **Scope guard:** replay never re-acquires from external sources unless an
  explicit `--reacquire` (separately gated) is passed — protecting rate limits
  and terms.

## 21. Aggregate Evidence vs Personal Tracking (G-ECONOMY, G-LEGAL)

- **Card/official data stays aggregate.** `economy.card_spending_area_monthly`/
  `card_spending_demographics` are **area + month + industry** aggregates (no
  cardholder ids); `analytics.place_business_identity`/`place_score_snapshots`
  are place-level. Review/mention signals are likewise **place + week** roll-ups.
  No table in this pipeline stores a user/person id; provenance is
  **source-level**, not person-level.
- **No joinable user identity.** Even community user content
  (`community.user_posts`) is kept on a separate identity axis and **never**
  joined into scoring evidence. Review signals derive from provider-scraped/
  exported posts keyed by `(provider, external_key)`, not by LALA user.
- **Raw text minimization.** No raw review bodies are persisted at all
  (BLOCKED_EXTERNAL, §10); the serve path sees counts, sentiment, attributes,
  and short evidence phrases only. This is the operational expression of slide
  19's "비식별/가명·가공 데이터 활용" (de-identified/processed data) — and it is
  stricter than an "isolated raw store" design because there is no raw store to
  leak.
- **Provable trust.** Because every aggregate carries `source_run_id` +
  `license_class` + `prompt_version` + confidence, a recommendation can explain
  *why* a place is trusted (attribute evidence + sample size) without revealing
  any individual's review — satisfying G-TRUST and the slide-10/16 local-economy
  promise.

## 22. Model Policy, Costs & Quotas

| Role | Deployment var | Backing model | Use |
| --- | --- | --- | --- |
| Bulk (high-volume) | `AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT` → fallback `AZURE_OPENAI_DEPLOYMENT` | **gpt-5.4-nano** | review extraction, normalization, ad classification, keyword/attribute first pass |
| Docent/QA/recheck | `AZURE_OPENAI_DOCENT_DEPLOYMENT` → fallback `AZURE_OPENAI_DEPLOYMENT` | **gpt-5.4-mini** | low-confidence recheck, all docent generation/QA |
| Embeddings | `AZURE_OPENAI_EMBEDDING_DEPLOYMENT` | `text-embedding-3-small` (1536-d) | summary chunk embedding |

- **Cost controls:** batch review extraction in groups (legacy batched in 10;
  keep batching, size tuned to token budget); deterministic first-pass filters
  run **before** any AI call so only retained candidates cost tokens; embeddings
  batched; `local-hash` fallback in CI/offline so tests spend nothing.
- **Quota resilience:** retry on 429/5xx with exponential backoff (existing
  `_is_retryable_ai_error`); a live `429` is treated as an external capacity
  condition (per `sentiment-attribute-scoring-strategy.md`), retried before
  judging; persistent quota failure quarantines the batch, never silently trusts.
- **Live-AI gate:** `LALA_ENABLE_LIVE_AI=false` by default; all live AI behind
  this + the guarded `--apply` gates, so a misconfigured environment cannot
  spend or mutate.
- **Monitoring:** per-lane token spend, call count, 429 rate, p95 latency →
  `ops` metrics (§23) and rolled into cost tracking (`ops.daily_costs` pattern).

## 23. Observability

- **Job provenance:** every run writes `ops.job_runs` (job_name, status,
  started/finished, duration_ms, error_message) — already implemented for both
  tools.
- **Run/task lifecycle:** `community.ingest_runs`/`ingest_tasks` carry per-source
  run status and errors.
- **Aggregate quality counters** in `place_mentions_weekly.attributes`:
  `organic_review_count`, `filtered_ad_count`, `filtered_irrelevant_count`,
  `match_confidence_avg`, `source_mix`, `prompt_version` (existing shape).
- **Metrics/alerts (TARGET):** ingestion lag (newest `collected_at` vs now),
  quarantine depth, ad-ratio per provider, match-confidence distribution,
  429/timeout rate per lane, embedding freshness (`last_embedded_at`).
- **No-secret logging:** tools already redact (`redact_secret_text`); never log
  `DB_DSN`, API keys, review-source tokens, Key Vault URLs, or review bodies.
  `test_safety_contracts.py` enforces this.

## 24. Retry / Idempotency Matrix (consolidated)

| Stage | Retry | Idempotency key | On poison |
| --- | --- | --- | --- |
| Govern (062, DB-only) | none (single transaction; any failure rolls back the whole batch) | `run_key = source_name + window + schema_version`; receipts `(source_name, external_key, content_sha256)` | rollback + `ops.job_runs(failed)`; no external-provider call is made |
| Acquire (source API) | exp 30s/2m/5m; 429/timeout/5xx retryable | `(provider, external_key)` | quarantine (`source_api_failure`) |
| Normalize/dedup | none (pure function) | `content_sha256` | quarantine (`schema_invalid`) |
| Ad/classify (bulk) | exp 10s/30s/1m; 429/5xx | `(place_id, week, schema_version)` | keep deterministic result, flag `source_api_failure` on the run ledger (062 has no `ai_failure` reason) |
| Attribute (bulk) | exp 10s/30s/1m/2m/5m | `(place_id, week, schema_version)` | quarantine; preserve prior enrichment |
| Recheck (docent) | 2 attempts linear | `(place_id, week, schema_version)` | quarantine (`low_confidence`) |
| Embed | exp 30s/2m | `(source_type, source_id)` | leave prior embedding, alert |
| Upsert | transactional | per table (§18) | rollback + `ops.job_runs(failed)` |

## 25. Schema / API / Migration Contracts

### 25.1 Migrations (additive; canonical numbering is never reserved here)

**Landed by PR #60 (governance foundation, merged to `main`):**

- **`062_review_ingestion_governance.sql`** — **the only migration PR #60 ships,
  and the only numbered item in this section.** It is IMPLEMENTED, merged to
  `main`, additive, and re-runnable
  (`CREATE TABLE IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS` /
  `CREATE INDEX IF NOT EXISTS`). It creates `ingest.review_sources` (§9.3) +
  `ingest.review_ingest_receipts` (the aggregate-only persistent receipt/dedupe
  described in §12/§19), extends `community.ingest_runs` with the governance
  columns + the `review_source_name` FK → registered source + the `run_key`
  partial unique idempotency index, and creates `community.ingest_quarantine`
  (§19) with **no raw-body column**. It **does not retain raw review bodies** —
  no table or column it creates stores body/title/URL text. Backed by the typed
  governance boundary in
  `apps/api/app/services/review_ingest_governance.py`, which runs the
  DB-authoritative source gate + register → run → receipt → quarantine →
  finalize inside one transaction. The aggregate-only receipt/dedupe is
  **implemented by this same migration**, not held for a separate one: receipts
  key cross-batch dedupe on (source, external_key, `content_sha256`), so an
  exact replay (same triple, any run) yields `rowcount 0` and does not re-emit
  an aggregate, while a content revision (new hash) inserts a fresh row and
  does. No external-provider calls.

**Remaining TARGET migrations (deliberately unnumbered):**

- **`travel.place_enrichments` uniqueness** (§18): add unique
  `(place_id, enrichment_type, prompt_version)` (or accept append-only history
  with a `latest` flag) to support replay auditing.
- **`rag.knowledge_chunks` source-type policy** (§17): no schema change needed,
  but add a CHECK/CI rule that `community_post` rows must not embed raw bodies
  (enforced in code + test).

> **Migration-numbering rule (locked):** `062` is already in use by
> `062_review_ingestion_governance.sql` on `main`, and `063`/`064` are also
> already taken (`063_local_signals_contract.sql`,
> `064_planning_action_tables.sql`). The TARGET items above therefore carry
> **no number — not even a document-list position that could be misread as one**:
> each takes the next free canonical number at the time it is implemented,
> chosen against `sql/canonical/` on `main` — never a pre-assigned value from
> this document. Nothing in this plan reserves a migration slot.

**BLOCKED_EXTERNAL (not a migration at all — no raw-retention table):**

- `community.posts_raw` (or any raw review-body table) is **BLOCKED_EXTERNAL**:
  not created by this plan, not created by PR #60, and not assigned a migration
  number (or a numbered list position) until a separate
  legal/retention/access decision (§10.2). Earlier drafts of this plan listed it
  as migration item 1 and backfilled `community.posts` into it; that proposal is
  superseded and must not be renumbered into the canonical sequence (it would
  collide with the already shipped `062`). It is recorded here as
  **BLOCKED_EXTERNAL, not as a CURRENT or TARGET implementation item** — no part
  of this plan implements it, and no migration number is held open for it.

All migrations remain additive (`CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT
EXISTS`) and backward-compatible with the canonical baseline as it exists on
`main` (`sql/canonical/000_extensions_and_schemas.sql` and the subsequently
merged canonical sequence, including `062_review_ingestion_governance.sql`).
No destructive change to `community.place_mentions_weekly`.

### 25.2 API contracts (read-only; no raw-text exposure)

- Existing: `/api/v1/places`, `/weather`, `/docents/script`, `/plans/daily`,
  `/plans/intervention`. This pipeline adds **no** new user-facing endpoint; it
  only enriches the data those endpoints read.
- **Forbidden:** any endpoint returning `community.posts.body` (and, should a
  raw table ever land, `posts_raw.*` — none exists today, §10). The only
  review-derived user-facing fields are aggregate (e.g. a place's top attribute
  labels + `review_quality_score` presence/absence).
- **Honest states (G-REALDATA):** loading skeletons while batch/DB read is in
  flight; explicit failure UI when the source is unavailable; `null`
  `review_quality_score` (not a fake number) when evidence < 3 organic.

### 25.3 Schema versioning

`prompt_version` / `schema_version` stamps already exist
(`review-mention-preprocess-v1`, `review-attributes-v1`,
`review-quality-deterministic-v1`, `review-attributes-deterministic-v1`,
`review-quality-v1`). Bump on any formula/threshold/prompt change; preserve
history via `place_enrichments` generations.

## 26. Test / Eval Fixtures

- **Unit (existing, extend):** `test_review_mention_ingest.py`,
  `test_review_attribute_batch.py`, `test_rag_index.py`,
  `test_safety_contracts.py`. Add: quarantine routing, replay idempotency,
  raw-text-not-in-RAG assertion, license-class gate, KO/EN language-tag
  exclusivity.
- **Eval fixtures (TARGET):** a small **synthetic, operator-authored** fixture
  set (not real user reviews) covering: ad vs organic, food-only attraction
  (reject), restaurant food terms (retain), ambiguous same-name, low-confidence
  recheck, duplicate across providers. Used to score extraction quality across
  prompt versions (regression guard).
- **Safety contracts:** extend `test_safety_contracts.py` to assert no endpoint
  emits raw review text, no RAG `community_post` chunk contains a raw body, no
  PII/user-id in aggregate tables, no secrets in logs.
- **DB/PostGIS smoke:** `scripts/unix/verify_db_schema.sh`, `verify_repo.sh`
  with live PostGIS places and no mock/fallback data (G-REALDATA).

## 27. Rollout / Rollback

- **Rollout (gated, mirrors `worker-batch-boundary.md`):**
  1. Land schema migrations (additive) + dry-run worker contract updates.
  2. Promote `review-mention-ingest` and `review-attribute-batch` behind
     `ALLOW_*_APPLY=1` + `--confirm` on shared-dev.
  3. Wire one **licensed/public** source (e.g. Naver Search API discovery within
     terms) as the first approved acquisition lane; broaden later.
  4. Enable the bulk-lane AI classifier (M3) then the docent-lane recheck (G6).
  5. Cut RAG to summary-only embeddings (§17) last, after docent QA confirms
     grounding quality holds.
- **Rollback:** every stage is additive and idempotent. Roll back by disabling
  the `ALLOW_*` env / cron and re-running the prior `prompt_version`; prior
  `place_enrichments` generations and `place_mentions_weekly` rows remain. The
  raw-text RAG change is reversible by re-embedding from the prior chunk set.

## 28. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Review-source terms forbid retention/summarization | Legal exposure, G-LEGAL breach | `ingest.review_sources` (062) + license-class gate; default to metadata-only; no raw retention (BLOCKED_EXTERNAL, §10); legal review per source before `licensed` |
| Raw review text leaks into RAG/docent | Privacy breach, G-TRUST breach | Retire/replace `community_post` raw-body embedding (§17); safety-contract test |
| Ambiguous place matches contaminate scoring | Wrong place credited | `ambiguous_match` → quarantine; manual approval before scoring |
| Bulk-lane quota (429) stalls nightly batch | Stale evidence | Retry + quarantine; deterministic fallback keeps pipeline moving |
| Model drift changes attribute scores silently | Score instability | Versioned prompts; eval-fixture regression; history in `place_enrichments` |
| Over-reliance on AI ad classification | Organic signals dropped | Deterministic first-pass always runs; AI is second pass only |
| Replay cost (re-embedding large corpus) | Cost spike | Replay scoped by window; `--reacquire` separately gated |
| Scraping temptation (legacy muscle memory) | Terms violation | Hard rule §9.2; code review gate; no scraping code in repo |

## 29. Phased Milestones (with acceptance criteria + real-device screenshots)

> Each milestone lists **implemented evidence vs future target** and requires
> screenshots from a **real device** (Android physical, and iOS/Web parity) for
> the user-facing surfaces that consume this pipeline's output — not mock data.

### M1 — Deterministic ingest hardened (mostly IMPLEMENTED)

- **Implemented:** `review_mention_ingest.py` deterministic clean/dedup/ad/
  category/match/aggregate; `community.posts` → `place_mentions_weekly`;
  `ops.job_runs` provenance; guarded plan/preview/apply CLI.
- **Implemented (062/PR #60, merged to `main`):** provenance split
  (`ingest.review_sources` + governance run ledger) and cross-run aggregate
  dedupe (`ingest.review_ingest_receipts`), persisted in one transaction with
  typed quarantine (`community.ingest_quarantine`) — the full aggregate-only
  governance slice with no external-provider calls and no raw-text retention.
- **Target:** normalized-layer cross-batch dedup index (§12); raw retention
  remains BLOCKED_EXTERNAL (§10).
- **Acceptance (DB):** `place_mentions_weekly` has organic counts + attributes
  for representative attraction/restaurant/event/culture places; ambiguous
  matches excluded from organic counts.

### M2 — Licensed/public acquisition lane (TARGET)

- **Target:** one terms-compliant source governed via the worker contract
  (§8/§9) using the `062` `ingest.review_sources` registry + DB-backed
  `review_ingest_governance.py` gate. The aggregate-only receipt + persistent
  dedupe (§25.1, **LANDED in `062`/PR #60**) is already the persistence
  floor; this lane adds only live acquisition. **No `posts_raw`**
  (BLOCKED_EXTERNAL, §10). Live acquisition that calls external providers remains
  BLOCKED_EXTERNAL until the legal/retention/access decision.
- **Acceptance (Ops/DB):** an approved source runs plan→preview→apply; every
  aggregate has a resolvable `source_run_id` + `license_class`.

### M3 — Bulk-lane AI classifier + attributes (PARTIALLY implemented)

- **Implemented:** `review_attribute_batch.py` AI lane + deterministic fallback;
  category schemas; `review_quality_score`.
- **Target:** standalone AI ad-classifier second pass (§14); attributes mirrored
  to `travel.place_enrichments` (G8); broader source coverage.
- **Acceptance (DB):** `review_quality_score` non-null for eligible places, null
  where evidence < 3 organic; attributes present in both `place_mentions_weekly`
  and `place_enrichments`.

### M4 — Uncertainty/recheck + quarantine + replay (PARTIALLY implemented)

- **Implemented (062/PR #60, merged to `main`):** `community.ingest_quarantine`
  dead-letter table
  + typed `safe_metadata` persistence and the single-transaction quarantine
  insert boundary (§19) — quarantine is a live surface, not a future table.
- **Target:** gpt-5.4-mini recheck lane (§16); `--since/--window` replay (§20).
- **Acceptance (Ops/DB):** low-confidence signals quarantined, not scored;
  replay of a window is idempotent and audited.

### M5 — Trustworthy RAG hand-off (TARGET, fixes G7)

- **Target:** summary-only embeddings (§17); remove raw-body `community_post`
  exposure; docent grounding verified on aggregate evidence.
- **Acceptance (API/UI + screenshot):** `/api/v1/docents/script` grounds in
  aggregate signals; **real-device screenshot** of a docent/reason view that
  shows attribute evidence + "why trusted" without any verbatim review text.

### M6 — End-to-end presentation tie (cross-slice)

- **Target:** the slide-7 promise (domestic signals → attribute classification →
  RAG → foreigner guidance) demonstrable end-to-end; slide-8 situation swap
  consumes `review_quality_score`.
- **Acceptance (real-device screenshots required):**
  - **Map screen:** live PostGIS places, honest loading/failure states, no
    mock markers — screenshot from a physical Android device + iOS/Web parity.
  - **Daily plan screen:** weather/air-aware substitution with a *reasoned*
    explanation that references trusted local signals; KO mode **and** EN mode
    shown separately (mutual exclusivity).
  - **Place reason/"why this place" view:** short, user-requested explanation of
    why the recommendation helps local experience/local economy, backed by
    aggregate evidence (sample size + top attributes), no raw review text.

## 30. Presentation Tie — Verified Signals as Trustworthy Inputs

Slides 7, 8, 10, 16, 19 together define the pipeline's product purpose:

- **Slide 7 (Input→AI→Output):** domestic daily data — including **로컬 SNS/리뷰
  신호** — flows through the LALA AI engine's **속성 기반 분류** (attribute
  classification) and **RAG 맥락 분석**, becoming foreigner travel-decision
  guidance. This pipeline is the ingestion + classification + RAG-hand-off half
  of that arrow.
- **Slide 8 (situation-responsive):** the daily plan swaps on context; this
  pipeline supplies the `review_quality_score` and attribute evidence that make a
  substitution *reasoned*, not arbitrary.
- **Slides 10/16 (local economy):** recommendations connect to real local
  visit/spend. This pipeline guarantees the connection rests on **aggregate
  place-level evidence** (card spending is already aggregate; review signals are
  weekly place roll-ups) — never personal tracking.
- **Slide 19 (legal/privacy):** 합법적 수집 (licensed/public + de-identified,
  processed data) and 명시적 동의 (location Opt-in). This pipeline implements
  the data half: only licensed/public or processed sources, no raw PII, raw text
  minimized and purged on schedule, aggregate-only serve path.

**Net:** a recommendation can truthfully say "this place is trusted because N
organic local signals rated it highly on [attributes], from [approved sources]"
— **without ever exposing any individual's review text**. That is the single
most important acceptance criterion for this domain.

## 31. Acceptance Criteria Summary

| Surface | Criterion | Source |
| --- | --- | --- |
| **DB** | `place_mentions_weekly` has organic counts + versioned attributes across categories; ambiguous/low-confidence rows excluded from organic counts | M1, M3 |
| **DB** | Every aggregate resolves to `source_run_id` + `license_class`; no user/person id in any review-evidence table | M2, §21 |
| **DB** | `review_quality_score` is null when evidence < 3 organic (honest absence); non-null only with sufficient organic evidence | M3, §15 |
| **DB** | `rag.knowledge_chunks` contains no raw review bodies; only `place_mention` aggregate summaries | M5, §17 |
| **DB** | `community.ingest_quarantine` holds low-confidence/ambiguous/poison rows; none enter scoring/RAG until approved | M4, §19 |
| **API** | No endpoint returns raw `community.posts.body`; no `posts_raw` table exists (BLOCKED_EXTERNAL); only aggregate fields | §10, §25.2 |
| **API** | `/api/v1/plans/daily` + `/plans/intervention` consume `review_quality_score` | G-SITUATION |
| **UI** | Honest loading/failure states; no demo/mock in normal flows | G-REALDATA |
| **UI** | KO and EN are mutually exclusive modes; same workflow on Android, iOS, Web | G-I18N, G-CROSSPLATFORM |
| **Screenshots** | Real-device (Android physical + iOS/Web parity): map, daily plan (KO+EN), place reason/"why" view — no raw review text, aggregate evidence only | M6 |
| **Safety** | `test_safety_contracts.py` asserts no raw review text in any output, no PII in aggregates, no secrets in logs | §26 |
| **Ops** | Replay of a window is idempotent; per-lane cost/429 metrics emitted | §20, §22, §23 |

## 32. Open Questions

1. Which **first licensed source** to wire (Naver Search API discovery within
   terms, vs an approved export)? Needs legal sign-off on retention/summarization
   before `license_class='licensed'`.
2. Should `community_post` RAG chunks be **retired** entirely or **re-summarized**?
   (§17 — recommend retire for serving, keep only `place_mention` aggregates.)
3. Confirm the `travel.place_enrichments` uniqueness policy for replay: append-only
   history with a `latest` flag, vs unique `(place_id, enrichment_type,
   prompt_version)`? (§18/§25.)
4. Where does the **manual review queue UI** for quarantine/ambiguous matches
   live (operator console vs CLI report)? Out of this plan's scope but blocks M4
   closure.
5. Quota/cost ceiling for the bulk lane per nightly run — needs a budget number
   before M3 scale-up.
6. **Raw-retention external gate (blocks any `community.posts_raw`-style table):**
   a separate legal/retention/access decision must settle (a) which sources
   permit retention, (b) the purge schedule, and (c) the access model before the
   BLOCKED_EXTERNAL flag in §10/§25.1 can be lifted. Until then raw review text
   is not stored, served, logged, or embedded, and the next review-specific
   slice is aggregate-only by construction.

---

### Related (in-worktree)

- Strategy: [`docs/operations/review-mention-preprocessing-strategy.md`](../operations/review-mention-preprocessing-strategy.md),
  [`docs/operations/sentiment-attribute-scoring-strategy.md`](../operations/sentiment-attribute-scoring-strategy.md),
  [`docs/operations/rag-regeneration-strategy.md`](../operations/rag-regeneration-strategy.md),
  [`docs/operations/worker-batch-boundary.md`](../operations/worker-batch-boundary.md),
  [`docs/operations/card-spending-source-inventory.md`](../operations/card-spending-source-inventory.md),
  [`docs/operations/observability-plan.md`](../operations/observability-plan.md).
- Code: [`apps/api/app/services/review_mention_ingest.py`](../../apps/api/app/services/review_mention_ingest.py),
  [`apps/api/app/services/review_attribute_batch.py`](../../apps/api/app/services/review_attribute_batch.py),
  [`apps/api/app/services/rag_index.py`](../../apps/api/app/services/rag_index.py),
  [`apps/api/app/services/ai_service.py`](../../apps/api/app/services/ai_service.py),
  [`apps/workers/app/contracts.py`](../../apps/workers/app/contracts.py).
- Code (PR #60 governance foundation, merged to `main` — **not present in this
  plan-only branch's tree**, so cited as paths rather than links):
  `apps/api/app/services/review_ingest_governance.py`,
  `apps/api/tests/test_review_ingest_governance.py`.
- Schema: [`sql/canonical/030_community_core_tables.sql`](../../sql/canonical/030_community_core_tables.sql),
  [`sql/canonical/035_data_pipeline_tables.sql`](../../sql/canonical/035_data_pipeline_tables.sql),
  [`sql/canonical/036_rag_knowledge_tables.sql`](../../sql/canonical/036_rag_knowledge_tables.sql),
  [`sql/canonical/010_travel_core_tables.sql`](../../sql/canonical/010_travel_core_tables.sql).
- Schema (PR #60, merged to `main` — **not present in this plan-only branch's
  tree**, so cited as a path rather than a link):
  `sql/canonical/062_review_ingestion_governance.sql`.
- Visual contract: [`docs/planning/lala-mobile-visual-contract/README.md`](./lala-mobile-visual-contract/README.md).
