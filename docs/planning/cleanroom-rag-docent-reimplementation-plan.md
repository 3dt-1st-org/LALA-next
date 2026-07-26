# Clean-Room Reimplementation Plan — RAG → Docent / TTS Pipeline

> **Status:** PLAN-ONLY. This document adds no product source, infrastructure, prompts,
> assets, secrets, or data. It records **behavior/interface** evidence (file path +
> symbol) so the pipeline can be **re-implemented, not ported**, against the current
> LALA-next stack. It is the RAG/docent/TTS companion to the audited clean-room specs
> `legacy-3dt-first-technical-spec.md` and `legacy-3dt-first-feature-inventory.md`
> (authored on sibling worktree `geondongkim/lala-legacy-technical-spec`; cited by
> filename rather than linked because those files are not in this repo's tree).
>
> Scope of this plan: the **slices V1 (vector/RAG retrieval) → D1 (docent generation) →
> T1 (TTS audio)**, plus the upstream review-extraction/normalization model policy that
> feeds them (R1 attributes). It does **not** own map clustering (M1), ranking weights
> (R2), or day-plan scheduling (P1) — those are referenced only as contracts this
> pipeline consumes.

---

## 0. Provenance, Method, Clean-Room Boundary

### 0.1 What was read

- **Legacy (read-only):** `/Users/geondongkim/3dt-1st-Project` — behavior/interface only.
- **LALA-next (this worktree, read-only audit):** `apps/api/app/services/{rag_index,ai_service,docent_service,docent_quality_qa,speech_service,review_attribute_batch,review_mention_ingest,db_repository,normalization}.py`, `apps/api/app/routers/v1.py`, `apps/api/app/schemas/docent.py`, `apps/api/app/core/config.py`, `sql/canonical/*.sql`, `apps/flutter_app/lib/features/docent/docent_helpers.dart`, `clients/flutter_generated/lib/src/model/docent_script_data.dart`.
- **Presentation (mandatory product promise):** `/Users/geondongkim/Downloads/LALA-발표자료-v2.pptx.pdf`, slides **5–8** (visually inspected; transcription below is product intent, cross-checked against code, not pixel ground truth).

### 0.2 Evidence legend

| Tag | Meaning |
| --- | --- |
| **CONFIRMED** | Read directly in legacy code/SQL or in current LALA-next code. Path/symbol cited. |
| **INFERRED** | Deduced from structure or absence of evidence; plausible, not directly observed. |
| **CONFLICT** | Two sources disagree; recorded with the stronger source winning. |
| **TARGET** | A future-state decision this plan proposes. Not yet implemented. |

### 0.3 Clean-room do-not-carry list (explicit)

The following are **not** copied from legacy into LALA-next (mirrors spec §17):

- **Code:** no legacy Python/SQL source. LALA-next already owns FastAPI/psycopg/pgvector equivalents.
- **Prompts/persona/few-shots:** no legacy docent system-prompt wording. LALA-next `ai_service._docent_system_prompt` already owns its own copy; this plan re-derives only **behavior** (sentence counts, guards, language lock).
- **Assets:** no `.pbix`/`.tmdl`, no `stations.json` beyond public KMA grid data, no images.
- **Secrets/identifiers:** no connection strings, keys, vault/registry/resource-group/subscription names. Azure resource names are role-based placeholders.
- **Data:** no review text, no Naver/Daangn payloads, no `user_action_log` rows. The food-keyword and ad-marker **lists are content** — only the **method** is re-implemented.
- **Public model/voice names** (`gpt-5.4-nano`, `gpt-5.4-mini`, `text-embedding-3-small`, public Azure neural voice IDs, `audio-16khz-128kbitrate-mono-mp3`) are **interface facts**, retained as evidence.

### 0.4 Presentation-derived capability gates (MANDATORY product promise)

Slides 5–8 are a **required product promise, not decorative inspiration**. They bind this plan:

| Gate | Evidence (slide) | Binding consequence for this pipeline |
| --- | --- | --- |
| **G1 — Audio-narrated, concise, locally grounded docent** | s8 "Listen" section; "이어폰으로 듣는 상황" framing (legacy `restaurant_docent`) | TTS is a first-class output; scripts are earphone-paced, not marketing copy. |
| **G2 — On-demand "why this place" reason** | s8 "단순 리스트가 아닌 맥락(Context)을 반영하여 방문해야 할 장소를 추천합니다"; s7 "추천 근거 배정"; s6 "Each step is selected for a clear reason to visit" | A user-requested, context-grounded rationale must be available. It is **not** always-on (per the visual contract: scores/reasons live behind a `점수/근거` action). |
| **G3 — Context-aware (weather/air, location, travel time, preference)** | s8 indoor-vs-outdoor scenario swap; s6 "Sunny 25°C" in plan slots | Grounding must carry weather/air/place signals; docent must reflect them without inventing conditions. |
| **G4 — No robot emoji / generic AI filler** | s5–s8 visually and explicitly avoid "AI-powered" buzzwords and emojis | An enforceable output contract (inline + QA). |
| **G5 — Local experience / local economy rationale** | s5 "경제 아이디어 기반 명소 추천 완료"; s7 "생활 밀착형 AI 도슨트 큐스" | The reason should connect to local-economy/local-experience signals (small-merchant, local-spending) without exposing private numeric scores. |
| **G6 — Bilingual, mutually exclusive** | s8 shows EN docent for foreigners; premise "내국인의 일상 데이터가 외국인의 여행 결정이 됩니다" | KO and EN are exclusive UI modes; one script = one language. |
| **G7 — No demo/mock data in normal flows** | s5 "실제 구현 화면…사용자가 보는 화면 위주" | Normal docent/audio/reason flows use live DB/API data with explicit honest loading/failure states. Mock scripts are a non-shipping fixture only. |

These gates are referenced as **G1–G7** throughout. Acceptance criteria that fail any gate are blocking.

---

## 1. Domain Technical Specification — Confirmed Legacy Evidence

All items below are **CONFIRMED** (path:symbol), behavior/interface only. They establish what parity/divergence this plan targets.

### 1.1 Docent generation (legacy D1)

| Capability | Evidence | Behavior | Tag |
| --- | --- | --- | --- |
| Attraction docent | `src/services/attraction_docent.py::generate_docent_script(attraction_name, mode="basic", language="English")` | 2 modes `basic`/`history`; context from `locallink.attraction_details` (summary_ko/atmosphere_ko/tips_ko) + `locallink.attraction_descriptions` (history/overview); KO/EN via "Response must be in {language}"; **returns only `script` — no citation metadata**. | CONFIRMED |
| Restaurant docent | `src/services/restaurant_docent.py::fetch_top10_context`, `fetch_tour_context`, `rank_restaurants` | **SQL/keyword retrieval (`WHERE name=%s`), NOT ANN**; context hierarchy `restaurant_details → gg_restaurant_info → restaurant_reviews`; reuses IQR/MinMax/40-60 rank; target ~2 min / 300–400 words. | CONFIRMED |
| Planner docent | `src/services/daily_planner.py::_get_smart_weather_instruction`, `_get_slot_style_hint`; `src/services/weather_planner.py` | 2–3 sentence per-slot narration; weather mentioned **only in first morning slot**; multi-reason concatenation; tone hints (morning/cafe/default); KO 존댓말 / EN polite-friendly. | CONFIRMED |
| Docent cache | `sql/migration/Script-ios-docent-cache-260305.sql`; `src/frontend/web/services/docent_service.py` | `locallink.docent_script_cache`: cols `place_id,category,language,mode,script,source,created_at,expires_at`; CHECK category∈{attraction,restaurant,event}, language∈{ko,en}, mode∈{brief,detail}, source∈{llm,fallback,cache}; UNIQUE(place_id,category,language,mode); **TTL 7 days**; lookup `expires_at > now()`; **fallback rows are deleted on read → force LLM retry next request**. | CONFIRMED |

**Legacy conflicts to NOT import (canonicalize to LALA-next):**

- **Mode naming CONFLICT:** `attraction_docent` uses `basic`/`history`; cache CHECK uses `brief`/`detail`. → LALA-next canonical = `brief`/`detail` (`docent.py::DocentScriptRequest.mode`, `docent_script_data.dart`). This plan keeps `brief`/`detail`.
- **Language format CONFLICT:** `attraction_docent` accepts the full word `"English"`; cache CHECK wants `ko`/`en`. → LALA-next canonical = ISO `ko`/`en` (`normalization.display_language`). This plan keeps ISO codes.

### 1.2 Vectors / RAG (legacy V1)

| Aspect | Evidence | Finding | Tag |
| --- | --- | --- | --- |
| Embeddings | `locallink.attraction_reviews.embedding VECTOR(1536)`, `generate_embeddings(_batch)` | Azure OpenAI `text-embedding-3-small` (1536-d), batched. | CONFIRMED |
| Vector index | none in legacy DDL | **No ivfflat/HNSW**; vectors stored with default indexing. | CONFIRMED (absence) |
| Retrieval path | `restaurant_docent.fetch_top10_context`, `sql/analytics/hybrid_place_matching.sql` | **Legacy RAG is keyword/SQL**, not ANN. Vectors were *stored but never queried* by the runtime docent path. | CONFIRMED |

> This is the central **opportunity** for LALA-next: legacy never used semantic retrieval. LALA-next already declares an ivfflat index; the target is to **exceed** legacy by wiring hybrid retrieval into the live docent path.

### 1.3 TTS (legacy T1)

| Aspect | Evidence | Behavior | Tag |
| --- | --- | --- | --- |
| Engine | `src/services/speech_synthesizer.py`; `src/frontend/web/services/speech_service.py` | Azure Speech **REST** (no SDK); SSML; output `audio-16khz-128kbitrate-mono-mp3`; per-language neural voices (public Azure voice IDs); **max ~6000 chars** (enforced pre-call in `speech_service.py:31`); timeout 20s; retry 0; env→vault credential fallback; MP3 written to file (no audio dedup cache). | CONFIRMED |

### 1.4 Review extraction/normalization (legacy feeding D1) — method only

| Aspect | Evidence | Behavior | Tag |
| --- | --- | --- | --- |
| LLM attributes | `src/collectors/process_restaurants.py::analyze_reviews_with_llm`, `load_review_pipeline.extract_attraction_content_batch` | Azure OpenAI, `response_format=json_object`, low temp (~0.2–0.3), ≤20 reviews concatenated; persisted summary/atmosphere(3–5 adj)/tips KO+EN; **no explicit sentiment score**. | CONFIRMED |
| Food guard | `process_attractions.clean_and_filter_text`, `load_review_pipeline.is_valid_attraction_review` | Substring exclusion so restaurant reviews don't contaminate attraction context. **Method only — keyword list is content (§0.3).** | CONFIRMED |
| Ad/organic split | inferred from `daangn.place_mentions_weekly` dedup + `organic_mention_count` | Weekly aggregation separates organic vs promotional mentions. | INFERRED |

---

## 2. Domain Technical Specification — Current LALA-next State

This is the implemented baseline this plan extends. All **CONFIRMED** by direct read.

### 2.1 RAG knowledge store — `sql/canonical/036_rag_knowledge_tables.sql` + `rag_index.py`

**Schema (CONFIRMED):** `rag.knowledge_chunks` — `id, source_type, source_id, source_table, place_id FK→travel.places, title_ko, body_ko, body_en, metadata jsonb, embedding vector(1536), embedding_model, embedding_method DEFAULT 'local_hash', content_sha256, last_embedded_at, updated_at`; UNIQUE(source_type, source_id); CHECK source_type ∈ {`place_profile, culture_event, community_post, place_mention, weather_context`}; indexes on `place_id`, `(source_type, updated_at DESC)`, `content_sha256`; **ivfflat cosine (lists=32) WHERE embedding IS NOT NULL**.

**Chunk builders (`rag_index.py`):** `_place_profile_chunk` (from `travel.places`+`analytics.place_score_snapshots`), `_culture_event_chunk` (`culture.events`), `_community_post_chunk` (`community.posts`), `_place_mention_chunk` (`community.place_mentions_weekly`), `_weather_context_chunk` (`travel.weather_observations`). Each emits Korean `body_ko`.

**Embedding (`rag_index.py::build_embedding`):** two methods — `local-hash`, `openai`. The hash variant `build_local_embedding` is a **feature-hashing trick (blake2b token/char/pair hashing)**, **NOT a semantic model**; it is the **default** and the only one that runs with `enable_live_ai=false`.

**Query (`rag_index.py::query_knowledge_chunks`):** ANN via `1-(embedding <=> q::vector)`, ORDER BY `embedding <=> q`, filters by `source` scope + `place_id`. **CONFIRMED: used only by the CLI `run_rag_index.py --query`; NOT called by the live docent path.**

**Provenance keys:** `content_sha256 = sha(source_type, source_id, title_ko, body_ko, body_en, metadata)`; upsert `ON CONFLICT (source_type, source_id) DO UPDATE`.

### 2.2 Docent orchestration — `docent_service.py` + `db_repository.py`

**Flow (`docent_service.py::generate_script`, ≈L63–141):**

1. Grounding fetch via `db_repository.fetch_docent_knowledge_context(place_id, limit=3)` — **direct SQL by `place_id`, NOT ANN**; priority `place_profile(0)>culture_event(1)>place_mention(2)>weather_context(3)>other(4)`; fallback `fetch_docent_place_profile_context`.
2. `_prepare_docent_grounding_context` filters/sorts.
3. `script_identity(request, grounding)` → cache key + request hash.
4. If **no context at all** → `fetch_docent_script_cache` (the only cache-read path; used as last resort when context is empty).
5. If AI enabled → `ai_service.generate_docent_script_text(request, grounding)`; on retryable failure → `_rule_based_script()`.
6. Sanitize + `_ensure_docent_quality_context` + `_docent_output_needs_rule_fallback`.
7. Response dict: `place_id, category, language, mode, script, source, generated_at, ttl_sec=604800, grounding_meta, identity`.

**Cache (`travel.docent_scripts`, CONFIRMED):** cols `id, place_id, category, language, mode, script, source_method, generated_at, expires_at`; UNIQUE(place_id, category, language, mode). Cache key (`script_identity`, ≈L1013–1057) = base `{place_id, category, language, mode}` + score fields (if any) + `grounding_hash` (sha of `source_type+source_id+content_sha256` per chunk) + request/weather fields (if any). **TTL 604800s (7 days) is hardcoded** at ≈L129. `source` ∈ {`openai`, `rule_based_curation`, `db_cache`} (note: diverges from legacy's `llm/fallback/cache` enum).

**AI client (`ai_service.py::generate_docent_script_text`):** Standard OpenAI, model `OPENAI_DOCENT_MODEL` (default `gpt-5.4-mini`); temp 0.4, max_tokens 500, timeout 5s, max_retries 0. Already has LALA-next's own (clean-room) persona copy per category, an attraction food-noise guard (`_ATTRACTION_NOISE_GUARD_KO`), and prompt-level hallucination guards (don't infer weather conditions; don't quote numeric scores/internal names). Grounding injected as top-3 snippets, body truncated to 260 chars (`_grounding_context_prompt`).

### 2.3 QA — `docent_quality_qa.py::evaluate_docent_script` (≈L422–485)

**CONFIRMED: regex/heuristic only — no LLM judge.** Checks: fallback/mock wording, raw-score leakage, secret-like text, missing place name, missing PM context (when weather present), missing route action, weak category persona, missing review context (when evidence exists), zero RAG chunks, language purity (`_language_purity_failed` ≈L718–733: KO rejects ≥3 long ASCII words; EN rejects any Hangul). Returns `blocker: bool`, `issue_tags`, `auto_precheck_score` (0–100), `rubric_scores`. **OFFLINE batch only** (`run_docent_quality_qa.py`); **NOT inline**. **No robot-emoji/filler-specific check.**

### 2.4 TTS — `speech_service.py::synthesize_docent_audio`

Azure Speech REST, SSML, `audio-16khz-128kbitrate-mono-mp3`; voices `{ko: ko-KR-SunHiNeural, en: en-US-JennyNeural}`; `live_speech_enabled` gate; timeout 20s. **GAPS vs legacy/contract: no char-limit guard (legacy had 6000), no retry, no audio cache/dedup.**

### 2.5 Review extraction — `review_attribute_batch.py` + `review_mention_ingest.py`

- `review_mention_ingest.py`: reads `community.posts` + `travel.places`; writes `community.place_mentions_weekly` via `ON CONFLICT (week_start, place_name_ko, provider, category) DO UPDATE`.
- `review_attribute_batch.py`: input `community.place_mentions_weekly` + `community.posts`; output `ReviewAttributeEnrichment` (sentiment_score/confidence, attribute_scores/confidence_avg, evidence_terms, summary_ko, `schema_version="review-attributes-v1"`); model `OPENAI_REVIEW_BATCH_MODEL` (default `gpt-5.4-nano`) with `OPENAI_REVIEW_RECHECK_MODEL` (default `gpt-5.4-mini`) for low-confidence cases; deterministic fallback `build_deterministic_enrichments` (confidence `min(0.78, 0.45 + organic/18)`); food guard `_category_policy`; ad classification `classify_post` + `AD_MARKERS` (keyword markers → `is_ad`, `retained=False`); idempotent via `UPDATE WHERE id`.

### 2.6 Routes + schemas — `routers/v1.py`, `schemas/docent.py`

- `POST /api/v1/docents/script` → `success_envelope(data, meta.source)`; auth `require_client_auth` (API bearer or iOS key, **no JWT**); rate limit `docent_script_rate_limit_per_minute` (default 60).
- `POST /api/v1/docents/audio` → **binary MP3** (`audio/mpeg`, not base64/presigned); same auth; rate limit `docent_audio_rate_limit_per_minute` (30); headers `X-Request-ID, X-LALA-Request-Hash, X-LALA-Cache-Key`.
- **No "why this place" / reason endpoint.**
- `DocentScriptRequest`: `place_id` (req), `place_name, address, region_ko/en, distance_m, source, upstream_source`, six score fields, eight weather/dust fields, `category` Literal, `language="ko"`, `mode="brief"`. `DocentAudioRequest`: `script` (req), `language="ko"`.
- Wire `DocentScriptData` (`docent_script_data.dart`): `cache_key, category, generated_at, grounding_count, grounding_sources, language, mode, place_id, request_hash, script, source, ttl_sec`; enums category{attraction,restaurant,event,culture_venue}, language{ko,en}, mode{brief,detail}, source{rule_based_curation,db_cache,openai}.

### 2.7 Flutter client — `docent_helpers.dart`

Client-side single-language enforcement: `usableDocentScript` rejects migration-skeleton/placeholder scripts; `singleLanguageText` returns text only if it matches the active language (so KO/EN mixing is suppressed on display); `unavailableDocentBody` gives honest KO/EN loading/unavailable copy. (Aligns with G6/G7.)

---

## 3. Gap Analysis → Binding Targets

Each target is keyed to the task's domain checklist and to a presentation gate.

| # | Domain item | Current state (CONFIRMED) | Target (this plan) | Gate |
| --- | --- | --- | --- | --- |
| **3.1** | Chunk provenance | `source_type/source_id/source_table/place_id/content_sha256` exist; per-chunk citations **not exposed**; `metadata` lacks retrieval-filter fields | Expose per-chunk **citation objects** on demand; add filter-grade `metadata` (region, category, is_indoor, language, time-decay) | G1, G2 |
| **3.2** | Bilingual knowledge representation | `body_en` populated only for `place_profile`+`culture_event`; `community_post/place_mention/weather_context` are **KR-only** | EN parity for every source_type via deterministic-first + mini translation; bilingual embedding text | G6 |
| **3.3** | Embedding/version/reindex lifecycle | Default `local_hash` (**non-semantic**); real embeddings gated off; **no reindex generation/version** column; ANN query not in live path | Real embeddings (config-gated) as the default for serving; `embedding_generation` + `content_sha256`-driven **idempotent reindex** worker; ANN wired into grounding | G1 |
| **3.4** | Hybrid retrieval filters/reranking | Live grounding = SQL-by-place_id; `query_knowledge_chunks` ANN unused; **no rerank** | **Hybrid retrieval** (ANN ∪ keyword ∪ metadata filter) → **reranker** (mini cross-check) feeding the top-3 grounding set | G1, G3 |
| **3.5** | Citations/grounding | Aggregated `grounding_count`/`grounding_sources` only | Per-chunk citation list (source_type, source_id, title, url/snippet ref, similarity band) in a new **on-demand** field/endpoint | G2 |
| **3.6** | Cache keys/TTL | Rich `script_identity`, 7-day TTL **hardcoded**; fallback-not-cached rule unverified; **audio has no cache** | TTL → config; **guarantee** fallback never persisted/reused (legacy rule, with test); script cache keyed on `embedding_generation`; **new audio cache** keyed `(script_hash, language, voice, format)` | G1, G7 |
| **3.7** | Hallucination + unsafe-data fallback | Prompt guards + offline QA; **no inline gate**; no unsafe-data (PII/secret/ad-text) scrubber; **no robot-emoji/filler check** | Inline lightweight guardrails (language lock, emoji/filler, length, score-leak) before serve; offline **LLM-judge QA (mini)**; **unsafe-data filter** at ingest + grounding | G3, G4, G6 |
| **3.8** | Scripted + audio output contracts | Script contract solid; audio thin (no char-limit, no retry, no cache, no honest-unavailable state) | Char-limit guard + idempotent retry + audio cache + honest 503-with-retry + SSML prosody contract | G1, G7 |
| **3.9** | Language routing | No inline mutual-exclusivity gate (only offline QA + client `singleLanguageText`) | **Inline language lock**: validate single-language before serve; violate → regenerate or fallback | G6 |
| **3.10** | gpt-5.4-mini generation/QA | General OpenAI model path; **no model-role routing**; QA regex-only | **Portable model-role router**: `nano`→extract/normalize/ad-classify; `mini`→docent gen + low-confidence recheck + QA judge | G1, G4 |
| **3.11** | Evaluation set (30–50 places) | None | Curated bilingual eval set (30–50 places × category/region/language) + golden rubric + retrieval/faithfulness meters | all |

---

## 4. Target Architecture (current stack, no blind port)

Stack is fixed by the task: **FastAPI + PostgreSQL/PostGIS/pgvector + Flutter/Kakao map + scheduled/container workers**. The legacy Azure Functions timer/queue pattern is **not** ported; where a timer/queue is needed we define a **portable worker contract** (below).

### 4.1 Pipeline data flow (target)

```
INGEST (offline workers, portable contract §4.6)
  community.posts ─► review_mention_ingest ─► community.place_mentions_weekly
        │                                            │
        └────────► review_attribute_batch            │
                   (nano extract+normalize,          │
                    mini low-conf recheck,           │
                    keyword ad-classify + unsafe-data filter)
                                                   │
  travel.places / culture.events / travel.weather_observations
        │
        ▼
  rag_index chunk builders (bilingual body_ko/body_en, §5.2)
        │
        ▼
  rag.knowledge_chunks (+ embedding vector(1536), embedding_generation, content_sha256)
        │   (reindex worker: content_sha256-change → re-embed, §5.3)
        ▼
SERVE (online, FastAPI)
  POST /api/v1/docents/script
   ├─ hybrid retrieve (ANN ∪ keyword ∪ metadata filter) → rerank (mini) → top-3 grounding (§6)
   ├─ script_identity cache lookup (keyed on embedding_generation) (§7)
   ├─ mini generation (ai_service) with inline guardrails (§8)
   ├─ inline language lock + emoji/filler/length/score-leak gate (§8)
   └─ response: script + on-demand citations + grounding_meta (§9)
  POST /api/v1/docents/reason   (NEW, on-demand "why this place", §9.2)
  POST /api/v1/docents/audio    (cached, char-limited, retried, §10)
        │
        ▼
  Flutter (singleLanguageText display; Listen button; 점수/근거 action)
```

### 4.2 Model policy (portable, config-driven)

A new **model-role router** maps logical roles → concrete model ids via config (so the backend is not wedded to one vendor/deployment and the legacy Azure-Functions-only assumption is not replicated). The mandated policy:

| Role | Model (target) | Used for | Why this tier |
| --- | --- | --- | --- |
| `review_bulk` | `gpt-5.4-nano` | high-volume review extraction, normalization, ad classification | high volume, low marginal value per call → cheapest tier |
| `review_recheck` | `gpt-5.4-mini` | re-extract/re-classify when nano confidence < threshold | nuance where nano is uncertain |
| `docent` | `gpt-5.4-mini` | all docent script generation (script + reason) | quality/persona + grounding faithfulness |
| `docent_qa` | `gpt-5.4-mini` | LLM-judge QA (offline) | judge must outrank the generator tier |
| `place_enrichment` | `gpt-5.4-mini` | place English/indoor enrichment | quality for structured place fields |
| `embedding` | `text-embedding-3-small` (1536-d) | chunk + query embeddings | matches existing `vector(1536)` schema |

**Contract (W0-b):** `config.py` provides `model_role_overrides: dict[role,str]` from non-secret env overrides `LALA_MODEL_ROLE_<ROLE>`. A pure `model_client.resolve(role)` returns standard-OpenAI `(provider, model_id, client metadata)` without importing the SDK or creating a client. Existing `OPENAI_*_MODEL` settings remain compatible, and the current selectors are thin callers of `resolve("docent")` / `resolve("review_bulk")`. **No prompts are copied** — only the routing changes; `ai_service`'s clean-room persona copy is reused.

**Clean-room note:** `gpt-5.4-nano`/`gpt-5.4-mini`/`text-embedding-3-small` are public model names (interface facts). Deployment ids/keys remain role-based placeholders.

### 4.3 Portable worker contract (replaces Azure Functions timers/queues)

Where a background job is needed (reindex, nightly QA, review batch, embedding backfill), it is a **container worker** scheduled by the existing `apps/workers` + `ops.job_runs` machinery, not an Azure Function. Contract (TARGET, mirrors existing `run_*` tools):

- **Invocation:** scheduled (cron-like) **or** CLI `--apply`; every run records a row in `ops.job_runs` with `job_id`, `started_at`, `finished_at`, `status`, `rows_affected`, `error`.
- **Idempotency key:** each worker is **rerun-safe** via `content_sha256`/`ON CONFLICT`/`UPDATE WHERE id`; a retry never double-writes.
- **Confirm + env gate:** mutating workers require `--confirm <TOKEN>` and `ALLOW_<JOB>_APPLY=1` (the existing pattern in `run_rag_index.py`/`run_review_attribute_batch.py`).
- **At-least-once + dedup:** assume a run may execute twice; the idempotency key makes this safe.
- **Rollout gate:** live execution of community-crawl-derived ingestion stays **approval-gated** (matches the inventory's C1/MON1 "rollout-gated" verdict); dry-run contracts ship first.

This is the single place where "don't blindly port Azure Functions" lands concretely.

---

## 5. Knowledge Representation, Embedding, Reindex (V1)

### 5.1 Chunk provenance (target extends §2.1)

Keep the existing `source_type/source_id/source_table/place_id/content_sha256` keys. **Add** retrieval-grade `metadata` so hybrid filters (§6) can run without re-joining source tables:

```jsonc
// rag.knowledge_chunks.metadata (target)
{
  "region_slug": "suwon",            // for region filter
  "category": "restaurant",          // for category filter
  "is_indoor": true,                 // for weather-aware indoor filter
  "language_avail": ["ko","en"],     // which body langs are non-empty
  "time_kind": "static"|"dynamic",   // static=profile, dynamic=event/post/mention/weather
  "fresh_window_hours": 72,          // dynamic decay hint
  "provenance": { "source_table": "community.posts", "source_record_id": "..." }
}
```

**Provenance rule (G7/legal):** only **aggregated/normalized** signals (mention counts, sentiment bands, attribute scores, official field values) are embedded — never raw review text, ad text, PII, or secrets (see §8.4 unsafe-data filter). `source_table`/`source_record_id` are pointers for citation, not embedded content.

### 5.2 Bilingual knowledge representation (G6, target §3.2)

Every chunk must have a usable `body_en` so EN mode is fully grounded (not KR-only).

- **Deterministic-first:** for structured fields (`travel.places`, `culture.events`, `weather_observations`), build `body_en` directly from existing EN columns / numeric-to-phrase templates (the `place_profile`/`culture_event` builders already do this; extend to `weather_context`).
- **Mini translation for free-text:** for `community_post`/`place_mention` `body_ko` summaries (already normalized, not raw), translate the **summary line only** with `resolve("docent_qa")` mini tier (not nano — translation quality matters for grounding). Cache by `content_sha256`.
- **Embedding text (`KnowledgeChunk.text_for_embedding`):** keep current `title_ko + body_ko + body_en`. With real embeddings, bilingual text improves cross-lingual recall for EN queries against KO-heavy sources.
- **No raw review text** is ever placed in `body_*`; only the normalized summary/atmosphere/attribute phrases produced by §5.4.

### 5.3 Embedding + version + reindex lifecycle (§3.3, target)

**Problem:** default `local_hash` is non-semantic; live docent doesn't use ANN; no reindex generation. **Targets:**

1. **Real embeddings as serving default.** `embedding_method` for serving = `openai` (config-gated by `enable_live_ai`); `local-hash` remains a **dev/offline fixture** mode only (so tests run without keys). The live path must not silently fall back to hash embeddings when AI is enabled — a startup check asserts the configured method is semantic.
2. **Version column (migration, additive):** add `embedding_generation int NOT NULL DEFAULT 0` to `rag.knowledge_chunks`, and a config `rag_embedding_generation` (bumped on model/method/dim change). A chunk is "stale" when `embedding_generation < config` **or** `content_sha256` changed since `last_embedded_at`.
3. **Reindex worker (portable contract §4.3):** selects stale chunks in batches, re-embeds with `build_embedding(method=resolve("embedding"))`, upserts via the existing `ON CONFLICT (source_type, source_id) DO UPDATE` (idempotent). Records `ops.job_runs`. **Bounded cost** via batch size + per-run chunk cap; partial progress is resumable (stale predicate is re-evaluated each run).
4. **Backfill plan:** one-time backfill to generation 1 once real embeddings are enabled; the worker's stale predicate makes this just "run until zero stale."
5. **ivfflat tuning (TARGET, verify):** `lists=32` is fine for the current scale; add a documented threshold (e.g. >50k rows → retune `lists` / consider HNSW). No index change ships without an `EXPLAIN`/recall check on the eval set (§12).

### 5.4 Review extraction / normalization model policy (§3.10, feeds V1/D1)

Two-tier, replacing the current single-deployment path in `review_attribute_batch.py`:

1. **Extract + normalize (nano, `resolve("review_bulk")`):** produce `ReviewAttributeEnrichment` (sentiment band, attribute scores, evidence terms, summary line) — same output schema (`schema_version` bump to `review-attributes-v2`), different model tier.
2. **Low-confidence recheck (mini, `resolve("review_recheck")`):** when nano `confidence < threshold` (config), re-run extraction with mini; keep whichever result has higher self-reported confidence. Deterministic fallback `build_deterministic_enrichments` remains the floor.
3. **Ad classification:** keep the keyword-marker method (`AD_MARKERS`) as the cheap first pass; **add** a nano model pass that classifies ambiguous posts as `ad|organic|uncertain` with confidence; `uncertain` → mini recheck. Output stays `is_ad`/`retained`.
4. **Idempotency:** unchanged `UPDATE WHERE id` + `content_sha256` of the input post determines recompute; a re-run only touches changed/low-confidence rows.

**Legal/privacy (G7):** extraction works on already-collected `community.posts` (ingestion itself is rollout-gated, §4.3); the pipeline never fetches new third-party review text on the serving path.

---

## 6. Hybrid Retrieval, Filters, Reranking (§3.4, target)

The live docent path switches from "SQL-by-place_id only" to **hybrid retrieval → rerank**.

### 6.1 Retrieval

- **ANN leg:** `rag_index.query_knowledge_chunks` (cosine `1-(<=>)`) on the query embedding (query = place name + category + active language + optional user intent phrase).
- **Keyword leg:** Postgres `ILIKE`/trigram on `title_ko||body_ko||body_en` for exact place/region/category terms (covers the case where ANN recall is weak on proper nouns — the legacy keyword-RAG strength).
- **Metadata filters (G3):** `category`, `region_slug`, `is_indoor` (weather-aware indoor/outdoor swap from s8), `time_kind` (static优先 for stable facts; dynamic freshness for events/weather), and `language_avail ∋ active_language`.
- **Place scoping:** primary = `place_id` (current behavior); hybrid broadens to a small neighborhood (same region/category) only when `place_id` grounding is thin (count < 1) — never silently invents places (G7).

### 6.2 Reranker (mini, `resolve("docent_qa")`)

- Fuse ANN + keyword via **reciprocal rank fusion** (cheap, deterministic) to a candidate pool (~20).
- **LLM rerank (mini):** score each candidate's relevance to the (place, category, weather context, language) query; return the **top-3** grounding set. Mini (not nano) because rerank quality directly bounds docent grounding.
- **Fallback:** if mini rerank is unavailable/disabled, fall back to RRF-only top-3 (degraded but honest; flagged in `grounding_meta`).

### 6.3 Wiring (minimal blast radius)

Add `db_repository.fetch_docent_knowledge_context_hybrid(place_id, query, filters, top_k=3)`; `docent_service.generate_script` calls it when a `rag_retrieval_mode` flag (config, default `hybrid`) is on, else the existing `fetch_docent_knowledge_context` (safe rollback). The existing priority-ordering code path is preserved as the `mode=legacy` branch.

---

## 7. Cache Keys, TTL, Idempotency (§3.6, target)

### 7.1 Script cache

- **Keep** the rich `script_identity` key (place/category/language/mode + scores + grounding_hash + request/weather). **Add** `embedding_generation` to the cache key so a reindex invalidates stale cached scripts automatically (prevents serving a script grounded on pre-reindex chunks).
- **TTL → config:** move the hardcoded `604800` to `config.docent_script_ttl_sec` (default 7 days), surfaced as `ttl_sec` in the response.
- **Fallback never persisted/reused (legacy rule, TARGET guarantee + test):** `rule_based_curation` rows must never be written to `travel.docent_scripts`; the cache-read path must skip/delete any row whose `source_method` is a fallback (mirror legacy `cached_source=="fallback"` → delete + return None → force regeneration next request). Add a focused test asserting no fallback row survives a cache read.
- **Idempotency:** upsert on `UNIQUE(place_id,category,language,mode)`; a duplicate concurrent request converges.

### 7.2 Audio cache (NEW, §3.8)

- **New table `travel.docent_audio_cache`** (additive migration): `cache_key text PK, script_hash text, language text, voice text, format text, audio bytea, bytes int, generated_at timestamptz, expires_at timestamptz, source_method text`. `cache_key = sha(script_hash, language, voice, format)`.
- **TTL:** shorter than script (e.g. 30 days, config) since audio is deterministic from text+voice.
- **Honest miss:** cache miss → synthesize → store → serve. Synthesis failure → honest 503-with-retry (never a silent empty/stale audio, G7).

### 7.3 Idempotency summary

| Resource | Key | Idempotent op |
| --- | --- | --- |
| knowledge chunk | `(source_type, source_id)` | `ON CONFLICT DO UPDATE` |
| docent script | `(place_id,category,language,mode)+gen` | upsert + fallback-never-cached |
| docent audio | `sha(script_hash,lang,voice,fmt)` | insert-if-absent |
| review attributes | mention `id` | `UPDATE WHERE id` + content-hash recompute |
| worker run | `ops.job_runs(job_id)` | stale-predicate re-eval each run |

---

## 8. Hallucination, Unsafe-Data, Fallback (§3.7, target)

### 8.1 Inline guardrails (must run before serve, cheap/deterministic)

- **Language lock (G6, §3.9):** after generation, assert single-language (KO: no Hangul-inimical long ASCII runs; EN: no Hangul). Violate → one mini regeneration; second violate → rule-based fallback in the **same** language. (Promotes the current offline-only `_language_purity_failed` to inline.)
- **No robot emoji / generic filler (G4):** strip a small blocklist of emojis (🤖 etc.) and filler phrases ("As an AI…", "AI-powered", "Let's…") via a sanitizer; count removals as a QA signal.
- **Score/secret leak (existing offline checks → inline):** block numeric-score patterns, table/cache/internal names, and secret-like substrings before serve.
- **Length contract:** script within mode bounds (brief ≈3–4 sentences; detail ≈6–8, matching the existing persona copy). Over-length → truncate at sentence boundary; under-length → fallback.
- **Weather honesty (G3):** do not assert sun/rain/clear unless a weather condition was provided (already in the prompt; promote to a post-check on weather verbs).

### 8.2 Offline LLM-judge QA (mini, §3.10)

- `evaluate_docent_script` gains a **mini LLM-judge** pass (config-gated) that scores: grounding faithfulness (every claim traceable to a citation), local-economy/local-experience relevance (G5), filler/robot-emoji presence (G4), language purity (G6), and route-action presence. The regex checks remain as the cheap pre-filter; mini judges the survivors.
- Stays **offline batch** (`run_docent_quality_qa.py`) — judges run over the eval set (§12) and a periodic production sample, never on the hot path.
- Output unchanged shape (`blocker`, `issue_tags`, `auto_precheck_score`, `rubric_scores`) plus a `judge_model`/`judge_version` stamp.

### 8.3 Rule-based fallback (`_rule_based_script`, target behavior)

When generation fails or trips an inline guard twice, the rule-based script must still be **locally grounded and honest**: it is assembled from the retrieved grounding chunks (name/category/region/distance/weather band) + a route action, explicitly framed as a concise curated summary (not an LLM claim), and **never** discloses private numeric scores (G5). It carries `source=rule_based_curation` and is **not cached** (§7.1).

### 8.4 Unsafe-data filter (ingest + grounding, G7/legal)

- **At ingest (chunk build):** scrubber removes PII patterns (phone, RRN-like, emails), secret-like strings, and any residual ad markers from `body_ko/body_en` before embedding. The food-keyword/ad-marker **methods** are re-implemented (lists are content, §0.3).
- **At grounding:** never inject raw review text — only normalized summaries (§5.2). A deny-list blocks obvious promotional phrasing from reaching the prompt.
- **Privacy:** the pipeline stores no user-identifying content in chunks; grounding is place-scoped, not user-scoped (matches legacy session-UUID, no-user-id privacy posture).

---

## 9. Output Contracts: Script, Reason, Audio (§3.5, §3.8, G1/G2)

### 9.1 Script contract (extends `DocentScriptData`)

Add an **on-demand** `citations` field and a `retrieval` meta block (additive, nullable so the wire model stays backward-compatible):

```jsonc
{
  // ...existing DocentScriptData fields...
  "citations": [            // on-demand (client passes include_citations=true, or via /reason)
    { "source_type": "place_profile", "source_id": "place:..",
      "title": "수원박물관", "language_avail": ["ko","en"],
      "similarity_band": "high|medium|low", "ref": "official|community|event|weather" }
  ],
  "retrieval": { "mode": "hybrid", "reranker": "mini|rrf", "candidate_pool": 20, "selected": 3,
                 "embedding_generation": 1 }
}
```

`source` enum is extended cleanly: keep `{rule_based_curation, db_cache, azure_openai}` and add a future `model_generated` alias only if the model-role router changes provenance (avoid breaking the Flutter enum).

### 9.2 Reason contract (NEW endpoint, G2/G5 — on-demand only)

`POST /api/v1/docents/reason` → a short, user-requested rationale connecting the place to **local experience / local economy**, grounded in citations, never quoting private scores. Same auth + a tighter rate limit (reasoning is more expensive). Behavior:

- Input: `place_id, category, language, context{weather, distance, scores(internal-only)}`.
- Output: `reason` (2–4 sentences, single language), `citations[]`, `source`, `cache_key` (keyed like script + a `reason` mode tag), `ttl_sec`.
- **Always on-demand:** the visual contract forbids always-on score/reason in the rail/sheet; the Flutter `점수/근거` action is the only trigger. No robot emoji / filler (G4).

### 9.3 Audio contract (§3.8, target)

- **Char-limit guard:** reject/segment scripts > N chars (legacy 6000; pick a conservative value, config) before synthesis; long detail scripts are sentence-segmented and concatenated (or capped with an honest truncation notice).
- **Idempotent retry:** transient Azure 5xx → bounded retry (e.g. 2) with the same `cache_key`; final failure → honest 503 `SPEECH_NOT_CONFIGURED`/`SPEECH_SYNTHESIS_FAILED` (existing codes) with `retryable=true`.
- **SSML prosody:** add neutral prosody/rate tags for an earphone-paced, non-robotic delivery (G1); language-locked voice selection (`_DEFAULT_VOICES`).
- **Serving:** keep binary MP3 (`audio/mpeg`); add `X-LALA-Audio-Cache` hit/miss header for observability.

---

## 10. Legal, Privacy, Observability

### 10.1 Legal data-source + privacy constraints

- **Sources:** only already-collected public/official data (`travel.places`, `culture.events`, KMA/AirKorea weather, `community.posts` from rollout-gated ingestion). No live third-party review scraping on the serving path.
- **No copying legacy data/assets/prompts** (§0.3). Food/ad keyword **lists re-derived**, not ported.
- **PII/secret scrubbing** at ingest (§8.4). No user ids in chunks or logs (session-UUID posture).
- **Citations expose source *type/table*, not raw user content** — a citation points to `community.posts`/official source, never embeds a reviewer's text (G7 + privacy).
- **Vendor neutrality:** model ids are config (§4.2); no provider lock-in in contracts.

### 10.2 Observability (extends `observability_plan.py`, non-mutating)

Per docent request, emit structured metrics (no PII):

- `docent.request{source, category, language, mode, cache_hit, retrieval_mode, grounding_count, reranker, qa_inline_block, latency_ms, status}`
- `docent.retrieval{candidate_pool, selected, ann_recall_band, embedding_generation}`
- `docent.audio{cache_hit, bytes, latency_ms, status}`
- `docent.reason{source, latency_ms}`
- **Quality meters:** offline QA pass rate, robot-emoji/filler removal count, language-lock regenerate count, fallback rate.
- **Cost meters:** nano vs mini call counts, embedding tokens, TTS characters (§11). All counters go to the existing ops datamart contract (no new PowerBI port — the inventory defers O1).

---

## 11. Costs, Quotas, Rollout/Rollback

### 11.1 Costs/quotas (TARGET estimates to validate)

| Lever | Driver | Control |
| --- | --- | --- |
| nano calls | review extract/normalize/ad-classify volume | batch size, confidence threshold for mini recheck, content-hash recompute only |
| mini calls | docent gen + reason + rerank + QA judge | script cache (7d), audio cache (30d), reason cache; offline QA on sample not full corpus |
| embedding calls | chunk count × generations | reindex worker batches stale-only; `embedding_generation` bump is rare |
| TTS characters | audio requests | audio cache; char-limit; prefer cached script reuse |
| pgvector | ivfflat probes | tune `lists`/ef at scale thresholds (§5.3) |

Cache-hit targets (TARGET, to confirm in canary): script ≥ 70%, audio ≥ 80% on repeated place/language.

### 11.2 Rollout (phased, flag-gated)

All behind **existing** enable flags + new fine-grained flags; every phase ships dry-run/preview first (the `run_* --preview` pattern):

1. `LALA_ENABLE_LIVE_AI` already gates generation; add `rag_retrieval_mode={legacy,hybrid}`, `rag_embedding_method`, `rag_embedding_generation`, `model_role_*`, `docent_inline_guards`, `docent_qa_judge`, `docent_reason_enabled`, `docent_audio_cache`.
2. Canary by **region then category** (e.g. one `sigun` first; attraction before restaurant) with metric watch on latency, fallback rate, QA blocker rate, cost.
3. Each flag defaults to the **current** behavior, so a no-op deploy is safe.

### 11.3 Rollback

Every target is behind a flag → **rollback = flip flags**. Schema changes are **additive only** (§13), so a rollback never requires a destructive migration. Audio/script caches tolerate mixed generations (keyed by generation).

---

## 12. Evaluation Set (30–50 representative places) — §3.11

### 12.1 Set design (TARGET)

Curate **40 places** (within the 30–50 bound) stratified to stress every gate:

- **Category mix:** attraction / restaurant / event / culture_venue (proportional, incl. the deck's Hwaseong/수원 exemplars).
- **Region mix:** ≥3 `sigun` (수원/평택/용인 per legacy `tourist_spot_info` filter) + edge (rural single-place region).
- **Language:** each place evaluated in **both** ko and en (G6) → 80 script cases.
- **Context axes:** indoor vs outdoor (G3 weather swap), with/without community mentions, with/without official profile, high vs low score (to test score-leak guard), long-name/romanization edge.
- **Audio subset:** 12 places × 2 languages for TTS contract checks.

Stored as a **test/eval fixture** (not product data): `place_id`, expected category/region, a few **grounding anchors** (official facts that must appear or be citable), and per-case G-gate expectations. **No golden prompt text** (clean-room) — only behavioral expectations + factual anchors.

### 12.2 Metrics

- **Retrieval:** recall@3 vs anchors (does hybrid+rerank surface the right chunk), ANN-vs-keyword contribution, latency p50/p95.
- **Grounding faithfulness:** mini-judge "every claim traceable to a citation" score.
- **Output quality:** inline-guard pass rate, offline QA `auto_precheck_score`, robot-emoji/filler count = 0 (G4 hard zero), language-purity = 100% single-language (G6 hard).
- **Contracts:** char-limit/retry/cache behavior on the audio subset; citation correctness on the reason subset.
- **Regression gate:** the eval runs in CI on every pipeline change; a drop in recall@3 or faithfulness, or any robot-emoji/language-mix, blocks merge.

---

## 13. Schema/API Contracts & Migrations (additive only)

| Migration (additive) | Change | Backward-compatible |
| --- | --- | --- |
| `rag.knowledge_chunks` | + `embedding_generation int NOT NULL DEFAULT 0`; enrich `metadata` filter fields | yes (default keeps existing rows "stale→reindex") |
| `travel.docent_scripts` | no structural change; guarantee fallback-not-cached via app logic + test | yes |
| `travel.docent_audio_cache` (NEW) | audio cache table §7.2 | yes (new table) |
| eval fixtures (NEW) | test-only tables/files under `sql/dev_reset` + `apps/api/tests` | yes (test-only) |

**API contract deltas** (additive, nullable fields; Flutter codegen regenerated):
- `DocentScriptData`: + `citations[]?`, + `retrieval?`.
- NEW `POST /api/v1/docents/reason` (+ request/response models).
- `POST /api/v1/docents/audio`: + `X-LALA-Audio-Cache` header; same binary body.
- OpenAPI regenerated (`export_openapi.py`); compat checked (`check_openapi_compat.py`).

---

## 14. Phased Milestones

Each phase is independently shippable and flag-gated; **docs-first**, then additive schema, then behavior.

| Phase | Scope | Exit criteria (evidence) |
| --- | --- | --- |
| **P0 — Plan + eval harness** | This doc; eval set (§12); retrieval/faithfulness meters stubbed | Eval set committed; CI runs eval (baseline numbers recorded, even if weak) |
| **P1 — Knowledge quality** | Bilingual `body_en` (§5.2); `metadata` filter fields; unsafe-data scrubber (§8.4) | 100% of source_types have `body_en`; scrubber test green |
| **P2 — Real embeddings + reindex** | `embedding_generation` migration; reindex worker (§5.3); serving default = semantic | Backfill complete; stale count = 0; recall@3 ≥ baseline on eval set |
| **P3 — Hybrid retrieval + rerank** | `fetch_docent_knowledge_context_hybrid`; mini rerank (§6); wired behind `rag_retrieval_mode` | Canary region: latency p95 within budget; recall@3 up vs legacy mode |
| **P4 — Inline guardrails + language lock** | Inline language/emoji/filler/leak gates (§8.1); fallback-not-cached guarantee+test (§7.1) | Eval: robot-emoji=0, language-purity=100%; fallback-never-cached test green |
| **P5 — Citations + on-demand reason** | `citations[]` + `POST /api/v1/docents/reason` (§9) | Reason endpoint serves grounded rationale on demand; citations correct on eval set |
| **P6 — Audio contract** | Audio cache, char-limit, retry, prosody (§9.3) | Audio cache-hit ≥ target; honest 503 on failure; char-limit test green |
| **P7 — Model-role router + mini QA judge** | `resolve(role)`; nano/mini split (§4.2, §5.4); offline mini judge (§8.2) | nano/mini cost split measured; QA judge runs on eval set + production sample |
| **P8 — Rollout** | Region/category canary; cost/quality watch (§11) | All flags on for one region; metrics within budget; rollback drill passed |

---

## 15. Risks & Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Real-embedding backfill cost/quotas | high spend, throttling | stale-only batches, per-run cap, off-peak schedule, generation bumps rare |
| Hybrid retrieval latency on hot path | slow docent | RRF cheap fusion; mini rerank bounded to ~20 candidates; cache; p95 SLO gate |
| Retrieval recall regression vs keyword | worse grounding | keep keyword leg; eval recall@3 gate; `rag_retrieval_mode=legacy` rollback |
| Hallucination / score leak | trust/legal | inline guards + mini judge + score-leak regex; G4/G6 hard-zero gates |
| Language mixing (G6) | broken UX | inline language lock + regeneration; client `singleLanguageText` defense-in-depth |
| Unsafe-data (PII/secret/ad) in chunks | privacy/legal | ingest scrubber + grounding deny-list + citation-no-raw-content rule |
| Vendor/model deprecation | outage | portable `resolve(role)` router; model ids in config |
| Audio cost / empty responses | cost, broken UX | audio cache, char-limit, retry, honest 503 |
| Concurrent reindex vs serve | stale/missing chunks | `embedding_generation` keying; ON CONFLICT idempotency; stale predicate re-eval |
| Community-data ingestion legal exposure | legal | ingestion stays rollout-gated; only normalized signals embedded |

---

## 16. Presentation-Tie Acceptance Criteria (G1–G7, concrete)

These are the **screen/API/DB** acceptance criteria the pipeline must satisfy. Each requires **evidence**, and a clear **implemented-vs-target** distinction.

### 16.1 API/DB acceptance (server-side, automated)

| ID | Criterion | Evidence | Gate |
| --- | --- | --- | --- |
| AC-1 | `POST /api/v1/docents/script` returns a single-language script grounded in ≥1 citation; `source` ∈ allowed enum | eval set: 80/80 cases single-language; `grounding_count≥1` for non-edge cases | G1,G6 |
| AC-2 | `POST /api/v1/docents/reason` returns a ≤4-sentence local-economy/experience rationale with citations, on demand only | eval set reason subset; no score quoted | G2,G5 |
| AC-3 | Weather/air context (when provided) is reflected; no invented sky conditions | inline weather-verb check; eval indoor/outdoor cases | G3 |
| AC-4 | Zero robot emoji; filler phrases removed | inline guard count; eval hard-zero | G4 |
| AC-5 | Normal flows serve live DB/API data; mock scripts only in fixtures | `isPlaceholderDocentScript` never true in prod; no `migration skeleton` strings | G7 |
| AC-6 | Audio is cached, char-limited, retried, honest-on-failure | audio cache-hit metric; char-limit test; 503-on-failure test | G1,G7 |
| AC-7 | KO and EN mutually exclusive end-to-end | language-lock inline + client `singleLanguageText`; eval 100% | G6 |
| AC-8 | Android (Flutter native) and iOS/Web (Flutter web) preserve the workflow | same API contract consumed by both; platform smoke in `smoke_api_matrix.py` | cross-platform |

### 16.2 Device screenshots (required from a real device)

Per the visual contract's evidence rules, the following **real-device captures** are required (stored under ignored `output/`/`.playwright-mcp/`, never committed with keys):

1. **Selected-place docent** (real place, live data): bottom sheet shows concise grounded script + Listen affordance; KO capture and EN capture (G1,G6).
2. **On-demand reason**: tapping `점수/근거` reveals the rationale + citations; KO + EN (G2,G5).
3. **Weather scenario swap**: same region, two weather states → plan/docent reflects indoor vs outdoor (G3) — captured on a real device with live weather.
4. **Honest states**: docent loading, docent unavailable (no grounding), audio unavailable (speech disabled) — each a distinct honest state, no mock (G7).
5. **Bilingual exclusivity**: one screen in KO-only, one in EN-only, side by side (G6).

A screenshot passes only if the underlying API call returned live data (verifiable via the `source`/`grounding_*` fields and the `X-LALA-Audio-Cache`/request headers). **No demo/mock data may appear in a normal-flow screenshot.**

### 16.3 Implemented vs future-target (honest ledger)

- **Implemented now (CONFIRMED):** RAG store + ivfflat; chunk builders; docent orchestration + 7-day cache + rule-based fallback; Azure OpenAI generation with clean-room persona + prompt guards; regex offline QA; Azure Speech TTS; review attribute batch (single-tier); Flutter single-language display.
- **Target (this plan, not yet implemented):** real embeddings as serving default + reindex generation; hybrid retrieval + mini rerank in live path; per-chunk citations + reason endpoint; inline guardrails + mini QA judge; audio cache/char-limit/retry; bilingual EN for all source_types; nano/mini model-role router; 30–50-place eval set. All TARGET items are flag-gated and additive-only.

---

## 17. Verification

- **Docs hygiene:** `git diff --check` (no whitespace errors); all internal markdown links resolve (validated below).
- **Plan-only check:** `git status` after commit shows **only** `docs/planning/cleanroom-rag-docent-reimplementation-plan.md` added — no product/infra/SQL changes.
- **(Future, when implemented):** `apps/api` pytest (eval set + inline-guard + fallback-never-cached + char-limit tests); `run_docent_quality_qa.py --preview` on eval set; `run_rag_index.py --query` recall probe; Flutter `flutter analyze` + `flutter test` on docent helpers; real-device captures per §16.2.

---

## 18. Cross-References

- Legacy evidence: `legacy-3dt-first-technical-spec.md` §6 (vectors/RAG), §7 (docent/TTS), §5 (review filtering/normalization), §17 (clean-room boundaries). *(sibling worktree `geondongkim/lala-legacy-technical-spec`; not linked — not in this tree)*
- Slice matrix: `legacy-3dt-first-feature-inventory.md` rows **V1, D1, T1, R1**. *(same sibling worktree)*
- Mobile UI contract (acceptance discipline, KO/EN exclusivity, no-mock rule): [`lala-mobile-visual-contract/`](./lala-mobile-visual-contract/) → [`01-flow-and-runtime-contract.md`](./lala-mobile-visual-contract/01-flow-and-runtime-contract.md), [`03-visual-acceptance-matrix.md`](./lala-mobile-visual-contract/03-visual-acceptance-matrix.md).
