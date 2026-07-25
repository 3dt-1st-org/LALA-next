# Review-Evidence Pipeline — Clean-Room Implementation Spec

Branch: `geondongkim/review-evidence-pipeline` (Draft PR against `main`).
Scope: provenance-safe review-evidence ingestion + quality pipeline. This is a
**clean-room refactor slice**: it makes approved review exports / API adapters
safely ingestible later. It is **not** permission to scrape Naver/Daangn or to
call external review APIs. No live DB migration/apply, no production deploy, no
cloud changes, no secrets, no real external collection, no mock/demo runtime data.

This spec is factual: where an external source is unavailable it is flagged
rather than invented (see §12).

---

## 1. Background — two coexisting paths

The repo has two review-derived paths. This slice hardens the clean-room path
and closes leaks where the legacy-derived path still reaches user-facing outputs.

| Path | Module | Shape | Status |
|---|---|---|---|
| **Clean-room (governed)** | `apps/api/app/services/review_ingest_governance.py` | Aggregate-only, DB-authoritative source gate, receipt idempotency, raw-text-forbidden, typed quarantine, single-transaction | Foundation exists (migration `062_review_ingestion_governance.sql` applied). Gaps closed by this slice. |
| **Legacy-derived (mention/attribute)** | `review_mention_ingest.py`, `review_attribute_batch.py`, `rag_index.py` | Reads raw `community.posts`, weekly aggregates into `community.place_mentions_weekly`, single-model AI, raw community-post body embedded into RAG | Ad filtering + food rule exist at mention layer; **raw-text RAG leak + single-model + no recheck seam** are the gaps. |

The legacy **Azure Functions** reference (`/Users/geondongkim/3dt-1st-Project`,
read-only) is a third, separate system. Its behavioural responsibilities were
extracted for retain/reject decisions (§2) but its architecture is **not** ported.

---

## 2. Legacy behaviour — retained vs rejected

Source: `src/functions/review_pipeline_func/function_app.py`,
`src/collectors/load_review_pipeline.py`, `load_restaurant_review.py`,
`tests/llm_review_processor_test.py`, `process_attractions.py`,
`process_restaurants.py` (read-only).

### Retained (as intent, re-implemented on current contracts)
- **Place-level structured analysis → typed, upsertable payload.** The legacy
  `process_*` generators turn raw reviews into `{summary, atmosphere, tips}` and
  upsert by place name. Intent retained: review evidence becomes a **typed,
  aggregate, upsertable** payload (`ApprovedReviewAggregate`), never raw text.
- **Embed the synthesis/aggregate, not the raw review.** Legacy `process_*`
  embeds `summary+tips`, not the raw body. Retained as the RAG privacy pattern:
  the governed handoff embeds aggregate signals only (§9).
- **Rule-based ad/relevance filtering before scoring.** Legacy attraction
  pipeline drops food-keyword descriptions pre-LLM. Retained as intent; in the
  governed path this becomes an explicit `is_organic` contract field (§5),
  because the boundary accepts no raw text to substring-scan.
- **Per-place error isolation.** Legacy isolates per-place exceptions and logs
  an errors list. Retained: the governed orchestrator is one transaction; per-run
  failure accounting is absolute/retry-safe.
- **Apply-guard + secret boundary.** Retained verbatim (existing
  `ALLOW_*_APPLY=1` + `--confirm` convention; never print DSN/keys).

### Rejected (clean-room redesign)
- **First-write-wins idempotency** (legacy `has_existing_*_reviews` per place;
  no content hash; silent no-op on embedding failure). Replaced by receipt-based
  content-hash dedupe (`ingest.review_ingest_receipts`) + explicit accounting.
  The governed path already implements the fix; this slice extends it to RAG
  work-signal dedup (§9).
- **Raw-text persistence + raw-text-to-docent** (legacy `description`/`clean_text`
  columns read back by docent, truncated 120–150 chars). Rejected: the governed
  path stores identity+hash+aggregate only. This slice additionally closes the
  equivalent leak in the current `rag_index._community_post_chunk` (§9).
- **System-prompt-only ad filtering + fall-back-to-raw on LLM failure.** Legacy
  re-inserts the original review text when extraction returns empty
  (`load_review_pipeline.py:166-169`). Rejected: extraction failure never
  re-admits raw text; non-organic evidence is quarantined, not recovered.
- **Silent no-op on embedding failure** (legacy `zip(cleaned, [])` inserts
  nothing). Rejected: RAG handoff failure must be surfaced, not silent.
- **Azure Functions runtime, Key Vault, managed identity, Azure SQL driver,
  timer-trigger orchestration.** Not portable; the current FastAPI + canonical
  Postgres + guarded batch tools are the substrate. None of the Azure bindings
  are ported.
- **`restaurant_reviews`/`attraction_details`/`restaurant_details` legacy
  tables.** These have **no DDL in the legacy repo** (flagged unavailable). Not
  ported; the current canonical tables (`community.place_mentions_weekly`,
  `rag.knowledge_chunks`, `travel.place_enrichments`) are reused (§3).

### Unavailable / not invented
- Legacy has **no per-attribute sentiment, no mention aggregation, no confidence
  scores, no selective recheck, no second model** in the review pipeline (those
  live in a *separate* Daangn community-post Function). Therefore the two-tier
  model-role policy (§8) is designed fresh against the current ops docs — nothing
  is ported from legacy.
- Legacy captures **no external review id, no author/owner field, no language
  field**. The clean-room contract requires a stable `external_key` supplied by
  the approved adapter/export (§4); we do not invent legacy ids.

---

## 3. Canonical contracts reused (no migration churn)

All four improvements reuse existing tables/columns. **No SQL migration is added.**

- `ingest.review_sources` (PK `source_name`; `license_class` CHECK ∈
  `licensed/public_processed/approved_export/rejected`; `source_status` ∈
  `active/disabled`) — `062_review_ingestion_governance.sql:27-44`.
- `ingest.review_ingest_receipts` PK `(source_name, external_key, content_sha256)`
  — cross-run dedupe arbiter. `062:114-128`.
- `community.ingest_runs` (`run_key` partial UNIQUE, `review_source_name` FK,
  retry-safe absolute counters) — `030:11-18` + `062:58-102`.
- `community.ingest_quarantine` (`reason_category` CHECK ∈ `schema_invalid,
  terms_violation, source_api_failure, duplicate_suspect, low_confidence,
  ambiguous_match`; dedupe UNIQUE `(provider, external_key, reason_category)
  WHERE resolved_at IS NULL`; `resolution` ∈ `approved/rejected/retried`).
  `reason_code` is free-text → **new reason codes need no migration**.
  `062:137-180`.
- `rag.knowledge_chunks` UNIQUE `(source_type, source_id)`; `source_type` CHECK ∈
  `place_profile/culture_event/community_post/place_mention/weather_context`;
  `content_sha256` + `metadata jsonb`. `036_rag_knowledge_tables.sql:3-29`.
- `community.place_mentions_weekly` UNIQUE `(week_start, place_name_ko, provider,
  category)`; `organic_mention_count`; `attributes jsonb`. `030:44-57`.
- `travel.place_enrichments` (`enrichment_type`, `attributes jsonb`, `confidence
  numeric(5,4)`, `source_method`, `model_name`, `prompt_version`; append-only).
  `010:36-50`.
- `ops.job_runs` (`job_name, status, started_at, finished_at, duration_ms,
  error_message`). `040:3-11`.
- Settings expose the standard OpenAI conventions `openai_api_key`,
  `openai_base_url`, `enable_live_ai` (`apps/api/app/core/config.py`). This slice
  adds `openai_review_batch_model` (default `gpt-5.4-nano`) and
  `openai_review_recheck_model` (default `gpt-5.4-mini`). LALA AI uses standard
  OpenAI only — never Azure (see §8).

---

## 4. Input / provenance contract (clean-room path)

The governed boundary accepts **already-normalized, aggregate-only** records from
an approved adapter/export (licensed API discovery, approved export, or public
processed under a declared terms version). It performs **no acquisition** and
reads no secrets.

Per-record required fields (existing): `source_name, provider, external_key,
license_class, terms_version, content_sha256` (64-hex), `received_at`, optional
`category`, `match_confidence ∈ [0,1]`, and the strict `normalized_attributes`
(`metric_key → score ∈ [0,1]`, bounded vocabulary).

**This slice adds (Improvement A):** an explicit organic-status signal so
non-organic/advertising evidence is rejected at the boundary:
- `is_organic: bool = True` (default true; backwards compatible).
- `non_organic_reason: str | None` — bounded enumerable, not free text.

Provenance is **DB-authoritative**, not caller-supplied: `source_name/provider/
license_class/terms_version` must equal the loaded registration row; accepted
records are re-bound to the registration (`review_ingest_governance.py:779-796`).

---

## 5. Advertisement / non-organic handling

Non-negotiable: advertising/non-organic/rejected text must **never** become a
positive mention, public score input, or docent/RAG evidence.

**Improvement A — governed non-organic exclusion.**
- `ReviewSourceRecord` gains `is_organic` + `non_organic_reason`.
- New quarantine reason code `terms_violation_non_organic` (category
  `terms_violation`, which is already in the `ingest_quarantine` CHECK). A
  non-organic record (`is_organic=False`) is routed to quarantine and is **never**
  projected to `ApprovedReviewAggregate`.
- Because the boundary is aggregate-only, "ad text" cannot be substring-scanned
  here; the approved adapter/export is responsible for setting `is_organic=false`
  (deterministic filter first, classifier second, per
  `review-mention-preprocessing-strategy.md:142-148`). The boundary **enforces**
  the decision rather than re-deriving it from text we deliberately do not hold.
- The legacy-derived mention path (`review_mention_ingest.AD_MARKERS`) keeps its
  deterministic ad filter for the raw-text lane; this slice does not weaken it.

**Defence in depth (unchanged, preserved):** the docent runtime guard
`docent_service._is_noisy_attraction_review_context` drops food-noise review
context for attraction/culture categories at read time. This slice preserves it
and ensures governed aggregates carry `category` so it still applies (§7).

---

## 6. Idempotency identity

Non-negotiable: replay must not duplicate a review, mention aggregate, or RAG
work signal.

- **Review/aggregate dedupe (existing, retained):**
  `(source_name, external_key, content_sha256)` receipt PK. Exact replay →
  `duplicate_count`, no aggregate emitted. Content revision (same
  `external_key`, new `content_sha256`) → fresh aggregate. In-batch dup → one
  new + one replay. Run-level `run_key = source|window|schema` resumes.
- **Weekly aggregate upsert (existing):** `community.place_mentions_weekly`
  `ON CONFLICT (week_start, place_name_ko, provider, category) DO UPDATE`
  (`review_mention_ingest.py:461`).
- **RAG chunk idempotency (existing + this slice's guarantee):**
  `rag.knowledge_chunks` `ON CONFLICT (source_type, source_id) DO UPDATE`
  keyed on `content_sha256`. **Improvement C** makes the governed handoff emit a
  deterministic `content_sha256` from the aggregate, so an exact replay of the
  same aggregate yields the same chunk id and does **not** emit a duplicate
  rebuild signal; a content revision changes the sha and is the explicit
  invalidation/rebuild trigger (§9).

---

## 7. Restaurant vs non-restaurant evidence rules

Non-negotiable (preserved + enforced at one more layer): restaurant food evidence
is allowed; a food-only review must not ground a non-restaurant docent.

- **Mention layer (existing):** `review_mention_ingest._category_policy` —
  `restaurant` → `restaurant_food_terms_retained`; food-only on a non-restaurant
  → `attraction_food_only_review_rejected` (retained=false). Preserved unchanged.
- **Attribute layer (existing):** `review_attribute_batch.attribute_names_for_category`
  restricts the attribute vocabulary per category (e.g. `taste` only for
  restaurants); the AI prompt rule #4 forbids treating unrelated food/cafe text
  as place quality. Preserved.
- **Docent layer (existing, preserved):** `_is_noisy_attraction_review_context`.
- **Governed aggregate (this slice):** `ApprovedReviewAggregate.category` is
  carried through the RAG handoff into `place_mention` chunk metadata, so the
  docent-side category guard has the category signal it needs even for the
  governed path (Improvement C).

---

## 8. Model-role policy

Non-negotiable: bulk defaults to **OpenAI gpt-5.4-nano**; low-confidence
selective recheck uses **OpenAI gpt-5.4-mini**; docent creation/QA stays
**OpenAI gpt-5.4-mini**.

Provider policy (durable, applies to all LALA AI work): **standard OpenAI API
only — never Azure OpenAI.** Reuse the existing OpenAI config/env conventions
(`OPENAI_API_KEY`, `openai_base_url`, the `LALA_ENABLE_LIVE_AI` gate, the
`openai.OpenAI` client as in `rag_index.build_openai_embedding`). The key value
is never printed, inspected, committed, or exposed.

**Improvement B — two-tier attribute scoring, standard OpenAI, injectable client.**
- Migrate the review-attribute AI lane (bulk + recheck) off Azure onto standard
  OpenAI. Config gains `openai_review_batch_model` (default `gpt-5.4-nano`) and
  `openai_review_recheck_model` (default `gpt-5.4-mini`), resolved via the
  existing `_env_or_secret` convention. The prior `azure_openai_*` deployment
  fields are left in place for unrelated legacy paths but are no longer used by
  review-attribute processing.
- `selected_review_batch_model(settings)` → `openai_review_batch_model`
  (gpt-5.4-nano). `selected_review_recheck_model(settings)` →
  `openai_review_recheck_model` (gpt-5.4-mini).
- `_build_openai_client(settings)` builds `openai.OpenAI(api_key=…,
  base_url=…)`, gated on `openai_api_key` + `enable_live_ai` (the key is never
  logged); `_missing_openai_settings` reports the missing pieces. The CLI runner
  redacts both `azure_openai_key` and `openai_api_key` from any error output.
- Add `RECHECK_CONFIDENCE_THRESHOLD` + `route_low_confidence_enrichments(…)`
  (subset below threshold on `attribute_confidence_avg`/`sentiment_confidence`).
- Make the AI client **injectable** (`client=None`; builds the OpenAI client when
  absent) in both `generate_ai_enrichments` and the new
  `generate_ai_recheck(*, candidates/enrichments, client=None, …)`, which re-asks
  the **mini** model only on the routed subset and merges (rechecked rows tagged
  `source_method="openai_recheck"`). Recheck is best-effort/non-fatal.
- Docent creation/QA is out of scope for this slice (its model routing is gap
  #11, §14); the policy states it stays gpt-5.4-mini.
- **Tests never make live AI calls** — they inject a fake client and assert:
  bulk uses `gpt-5.4-nano`, recheck uses `gpt-5.4-mini`, only low-confidence rows
  are routed, high-confidence rows are not.

---

## 9. RAG invalidation / rebuild handoff + raw-text boundary

Non-negotiable: RAG receives only allowed, grounded evidence and an explicit
rebuild/invalidation signal; raw unlicensed review text must not reach
user-facing outputs.

**Improvement C — governed RAG handoff (new module
`apps/api/app/services/review_rag_handoff.py`).** A bridge from
`ApprovedReviewAggregate` → grounded `place_mention` `KnowledgeChunk`, kept
**outside** `review_ingest_governance` (which by contract
[`test_governance_module_does_not_couple_to_rag_write_path`] must not import
`rag_index`). It:
- Builds an **aggregate-only** chunk body (place name, category, mention counts,
  organic count, sentiment, attribute scores) — no body/title/url.
- Carries `metadata.schema_version`, `metadata.ad_filter_version`,
  `metadata.prompt_version`, `metadata.source_freshness`, and `category` (for the
  docent food-rule guard, §7).
- Computes a deterministic `content_sha256` from the aggregate → **replay-safe**
  (same aggregate ⇒ same chunk id ⇒ no duplicate rebuild signal; changed
  aggregate ⇒ new sha ⇒ explicit rebuild trigger).
- Exposes `rag_rebuild_signal(...)` describing the set of `(source_type,
  source_id, content_sha256, changed: bool)` tuples an apply step should upsert
  via the existing `rag_index.upsert_knowledge_chunks` (which owns the DB write
  behind the apply-guard). The handoff itself performs **no DB write**.
- Guards every emitted body/metadata through
  `review_ingest_governance.enforce_no_raw_review_text`.

**Improvement D — close the `community_post` raw-body RAG leak.**
`rag_index._community_post_chunk` currently embeds the raw `community.posts.body`
into `rag.knowledge_chunks.body_ko`, which `fetch_docent_knowledge_context`
returns as docent grounding (user-facing). This is the same defect the legacy
pipeline had. Fix: build the `community_post` chunk body from **categorical**
fields only (title-as-label/keyword/region/provider), never the raw body, and
guard with `enforce_no_raw_review_text`. This is a deliberate privacy tradeoff
(reduced embedding discriminativeness for community posts) documented in the
devlog; `place_mention` chunks are already aggregate-only and unchanged.

Invalidation policy (ops doc `rag-regeneration-strategy.md:26-31,174-186`):
upsert-first by `(source_type, source_id)` with `content_sha256` as the
change/rebuild signal; `idx_knowledge_chunks_source_type_updated_at` carries
freshness. The proposed `plan_rag_index_cleanup` tool remains out of scope
(documented as proposed-only); this slice does not add cleanup logic.

---

## 10. Structured review qualities + attribute/mention result contract

Preserved contracts (no shape change):
- `ApprovedReviewAggregate` (governed): `aggregate_key`, `category`,
  `match_confidence`, `mention_count`, `organic_mention_count`,
  `sentiment_score ∈ [-1,1]`, `attribute_scores` (bounded vocab, `[0,1]`),
  `schema_version`. `to_rag_metadata()` is the only RAG-bound projection.
- `ReviewMentionDecision` / `ReviewMentionWeeklyAggregate` (legacy-derived):
  retain `reason`, `match_confidence`, `match_method`, `category_policy`,
  `organic_mention_count`, `filtered_ad_count`, `review_attributes`,
  `review_quality`.
- `ReviewAttributeEnrichment`: `sentiment_confidence`,
  `attribute_confidence_avg` (both `[0,1]`) — these are the routing inputs for
  Improvement B.
- `review_quality_score` formula and caps preserved (`<3 organic → null`;
  `3..9 → confidence cap 0.65`; ad-ratio `>0.50 → score cap 0.60`).
- This slice **adds** the `is_organic`/`non_organic_reason` fields (A) and the
  recheck routing outputs (B); it does not alter existing score math.

---

## 11. Failure / retry / replay semantics

- **Governed ingest (existing, retained):** one transaction boundary; gate
  failure aborts before any write; late failure rolls back; per-run counters are
  absolute/retry-safe overwrites; quarantine dedupes on retry.
- **Attribute batch (this slice):** the recheck seam is **best-effort and
  non-fatal** — a recheck failure leaves the bulk result in place (the row is
  still scored, just not upgraded); it never silently drops evidence and never
  re-admits raw text. Retryable AI errors reuse the existing
  `_is_retryable_ai_error` predicate.
- **RAG handoff (this slice):** emits an explicit rebuild signal only for changed
  content; exact replay emits none. A handoff/apply failure is surfaced via
  `ops.job_runs` (redacted error), never a silent no-op (rejecting the legacy
  embedding-failure bug).
- **No live AI in tests** (§13). No live DB apply in CI (apply-guarded).

---

## 12. External sources — availability (factual)

- **No external review source is wired or called in this slice.** There is no
  Naver/Daangn collector, no review-API client, no live AI call in tests. The
  slice makes approved adapters/exports **safely ingestible**; it does not
  ingest real data or pretend data exists.
- The legacy Azure review pipeline is read-only reference only; several of its
  tables have no DDL in that repo (flagged, not invented).
- Default settings have empty deployment names → AI paths raise clear
  "missing config" errors rather than silently degrading.

---

## 13. Test matrix (focused; no live AI, no live DB)

New/extended tests close the gaps the current-side map exposed (esp. idempotency
replay, rejected-ad exclusion, confidence routing, no raw-text leakage into
RAG/docent, dry-run behaviour).

| Area | Test | Asserts |
|---|---|---|
| A · non-organic | `test_non_organic_record_is_quarantined_not_accepted` | `is_organic=false` → quarantine reason `terms_violation_non_organic`, not in `accepted`. |
| A · non-organic | `test_organic_record_passes_through` | `is_organic=true` (default) accepted as before (back-compat). |
| A · raw-text | `test_non_organic_quarantine_entry_carries_no_raw_text` | quarantine entry + metadata pass `enforce_no_raw_review_text`. |
| B · routing | `test_route_low_confidence_picks_only_uncertain` | only `attribute_confidence_avg < threshold` routed; high-confidence excluded. |
| B · model-role | `test_bulk_uses_nano_and_recheck_uses_mini_with_injected_client` (fake client) | bulk call model = `gpt-5.4-nano`; recheck call model = `gpt-5.4-mini`; no live AI. |
| B · recheck merge | `test_recheck_upgrades_low_confidence_and_keeps_ids` | rechecked rows keep mention_id; high-confidence rows untouched. |
| B · dry-run | `test_recheck_seam_is_no_op_without_client_config` | missing config → recheck is skipped (bulk result kept), no raise. |
| C · handoff | `test_aggregate_to_place_mention_chunk_has_no_raw_text` | chunk body+metadata pass `enforce_no_raw_review_text`. |
| C · idempotency | `test_replay_aggregate_yields_same_sha_and_no_duplicate_signal` | same aggregate ⇒ same `content_sha256`, `changed=False`; revised ⇒ `changed=True`. |
| C · category | `test_handoff_chunk_carries_category_for_docent_food_rule` | chunk metadata carries `category`. |
| D · leak | `test_community_post_chunk_never_embeds_raw_body` | `_community_post_chunk` body contains no raw post body; passes raw-text guard. |
| Existing | regression | governance/mention/attribute/rag/docent suites remain green. |

Verification commands: targeted `pytest`, then `uv run pytest apps/api/tests`,
`uv run ruff check . && uv run ruff format --check .`,
`uv run pre-commit run --files <only changed files>` (scoped — see devlog; the
main clone carries unrelated uncommitted Flutter work that must not be touched),
`git diff --check`.

---

## 14. Out of scope / residuals

- Real external review collection / scraping / live AI runs (explicitly excluded).
- `plan_rag_index_cleanup` (stale-chunk cleanup) — proposed-only in docs; future slice.
- The legacy-derived mention/attribute lane is hardened only at the RAG boundary
  (D); a full migration of that lane onto the governed contract is a future slice.
- Docent-lane model routing unit test (gap #11) and exhaustive `review_quality`
  cap tests (gap #10) are noted but not required by this slice's non-negotiables.
