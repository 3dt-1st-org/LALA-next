# Review and Mention Preprocessing Strategy

Last updated: 2026-06-23 KST

This document defines how LALA reaches the target state for review and mention
preprocessing without falling back to demo, mock, or crawler-only behavior.
The normal data path is PostgreSQL plus Key Vault plus reviewed ingest jobs.
Static snapshot fallback remains only a limited read-only recovery path.

## Target State

LALA should treat reviews and local mentions as verified signals, not raw text
to paste into a docent prompt. The completed pipeline must:

- collect approved review, blog-search, community, and local mention inputs;
- remove advertisements, duplicated posts, and source spam;
- match each signal to `travel.places` with confidence and audit metadata;
- aggregate weekly place-level signals in `community.place_mentions_weekly`;
- keep category-specific review rules: food review terms are noise for
  attractions and culture venues when they are unrelated to the place, but they
  are first-class evidence for restaurants;
- write enough metadata for scoring, RAG, and manual QA to explain why the
  signal was trusted.

## Current Gaps

| Gap | Current Evidence | Risk |
|---|---|---|
| AI attribute extraction is not complete | `run_review_mention_ingest` now provides deterministic cleanup, ad filtering, category policy, matching, and weekly aggregate upsert; the JSON-only AI attribute batch is still separate work. | Taste/service/local-experience scores remain thinner than the final target. |
| Source coverage is still narrow | The first guarded source reads approved rows from `community.posts`; Naver Search/API or contracted exports still need a reviewed ingestion lane. | Representative places may lack enough organic evidence for `review_quality_score`. |
| Place matching needs human audit for ambiguous cases | Exact-name matching now records `ambiguous_match` and keeps those rows out of organic counts, but no manual queue UI exists yet. | Same-name places or franchise branches can wait for review rather than silently entering scoring/RAG. |
| Review source provenance is too thin | `ingest.source_files` handles file provenance; API/search/community provenance needs the same discipline. | We cannot prove a score came from approved sources. |
| No human review lane for ambiguous matches | Existing plan tools are guarded, but ambiguous review matches need a manual queue. | Bad matches become hidden RAG/docent evidence. |

## Legacy LALA Touchpoints

This is a refactor, so the new pipeline should start from the existing LALA
review guardrails instead of inventing a separate behavior.

| Legacy File | Behavior to Carry Forward | LALA-next Refactor Note |
|---|---|---|
| `legacy-lala-reference/src/collectors/process_attractions.py` | `clean_and_filter_text()` stripped HTML/entities and rejected attraction reviews containing food-only terms such as `맛집`, `카페`, `식당`, `디저트`, `메뉴판`, and `존맛`. | Keep this deterministic category guard, but persist rejection metadata instead of silently dropping the signal. |
| `legacy-lala-reference/src/collectors/load_review_pipeline.py` | `is_valid_attraction_review()` and `extract_attraction_content_batch()` separated actual attraction impressions from ads, shopping, eating, or unrelated comparison text. | Reuse the two-stage idea: deterministic cleanup first, JSON AI extraction second, with confidence and prompt version stored. |
| `legacy-lala-reference/src/collectors/process_restaurants.py` | Restaurant review discovery searched `"{name} 맛집"` and retained food, taste, menu, service, and atmosphere evidence. | Do not apply attraction food-noise filters to restaurants. Food terms are the product evidence for this category. |
| `legacy-lala-reference/src/collectors/load_restaurant_review.py` | Restaurant keywords were extracted from multiple review snippets and embedded for later retrieval. | Move keyword extraction into the same guarded review/mention batch so restaurant docents and scoring share one source of truth. |
| `legacy-lala-reference/README.md` | The reliability note explicitly called out review filtering to keep food reviews from contaminating attraction docents. | Preserve that as a refactor acceptance criterion, not just a nice-to-have test. |
| `legacy-lala-reference/src/frontend/web/services/docent_service.py` | Docent context loaded visitor summaries, atmosphere, tips, keywords, and review excerpts from persisted tables. | The new preprocessing pipeline must write durable DB/RAG evidence before the API generates public scripts. |

One legacy behavior should not be copied as-is: when an LLM extraction failed,
some paths could fall back to original review text. LALA-next should instead
mark the row as low confidence, send it to manual review, or exclude it from
scoring/RAG until a guarded retry succeeds.

## LALA-next Refactor Mapping

| Legacy Concept | Current Repository Landing Point |
|---|---|
| `locallink.attraction_reviews` retained snippets | Approved snippets become `community.posts` only when storage rights allow it; weekly aggregates always land in `community.place_mentions_weekly`. |
| `locallink.attraction_details` and `locallink.restaurant_details` summaries | `travel.place_enrichments` with `enrichment_type='review_attributes'`, `sentiment`, or `place_profile`, plus `prompt_version` and confidence. |
| Attraction food-noise exclusion | Shared filter module used by the proposed `run_review_mention_ingest` tool and by `apps/api/app/services/docent_service.py` as a runtime safety net. |
| Restaurant keyword extraction | `community.place_mentions_weekly.attributes.top_terms` and later `travel.place_enrichments.attributes` for category-specific scoring. |
| Review embeddings | `rag.knowledge_chunks` with `source_type='place_mention'` after the aggregate has passed ad filtering, place matching, and confidence thresholds. |
| Legacy direct DB writes | Guarded plan/preview/apply command style used by `run_place_score_batch` and `run_rag_index`, with `ops.job_runs` provenance. |

The first implementation slice is now in place:

1. `apps/api/app/services/review_mention_ingest.py` owns shared text cleanup,
   duplicate detection, ad phrases, category policy, exact place matching,
   weekly aggregation, and `ops.job_runs` recording.
2. `apps.api.app.tools.run_review_mention_ingest` provides plan, preview, and
   guarded apply modes.
3. `scripts/unix/plan_review_mention_ingest.sh` and
   `scripts/windows/plan_review_mention_ingest.ps1` follow the same guarded
   wrapper style as place scoring and RAG.
4. Unit tests cover ad filtering, attraction/culture food-noise rejection,
   restaurant food-term retention, ambiguous matching, text normalization, and
   guarded apply behavior.
5. The 2026-06-23 shared-dev apply processed 155 `community.posts` rows,
   upserted 139 weekly aggregates, left 12 ambiguous matches out of organic
   counts, and refreshed score/RAG. The table now has 168
   `review-mention-preprocess-v1` rows, 132 rows with deterministic
   `review_attributes`, and 10 rows with `review_quality`.

The next slice is to add broader source ingestion and AI attribute extraction
before score/RAG regeneration.

## Source Policy

Preferred sources:

- Naver Search API results for blog/review discovery when keys are configured;
- official or contracted review exports if later available;
- approved local community/mention datasets;
- public-data community indicators that can be legally stored and summarized.

Rejected sources:

- unauthenticated scraping that violates site terms;
- screenshots or manually copied reviews without source metadata;
- content with no stable source URL, timestamp, or collection method;
- any raw secret, token, or private user identifier.

## Canonical Flow

1. **Collect raw candidates**
   - Create a guarded tool, proposed name:
     `apps.api.app.tools.run_review_mention_ingest`.
   - Provide Unix/Windows wrappers:
     `scripts/unix/plan_review_mention_ingest.sh` and
     `scripts/windows/plan_review_mention_ingest.ps1`.
   - Modes must match existing operational style:
     `plan`, `--preview`, `--apply --confirm APPLY_REVIEW_MENTION_INGEST`.
   - `--apply` must require `ALLOW_REVIEW_MENTION_INGEST_APPLY=1`.

2. **Normalize text**
   - Strip HTML tags and entities.
   - Normalize whitespace, hashtags, repeated punctuation, and source-specific
     boilerplate.
   - Preserve Korean place terms and menu/place nouns needed for category rules.
   - Store only summarized or approved retained fields; avoid unnecessary raw
     personal data.

3. **Deduplicate and classify source quality**
   - Deduplicate by normalized title, URL, source, and text hash.
   - Add `content_sha256`, `source_url`, `source_provider`,
     `collected_at`, and `created_at_source`.
   - Mark low-trust sources instead of deleting them during preview.

4. **Filter ads and irrelevant snippets**
   - Use a deterministic filter first:
     repeated promotional phrases, excessive price coupon language, sponsor
     markers, unnatural call-to-action density, and duplicated merchant copy.
   - Use an AI classifier only after deterministic filters, with JSON output:
     `is_ad`, `ad_confidence`, `reason`, `organic_excerpt`.
   - Attraction/culture venue rule:
     food-only snippets are rejected unless they also contain place-specific
     museum, culture, park, architecture, performance, history, exhibition, or
     walking-route evidence.
   - Restaurant rule:
     food, taste, menu, service, price, and atmosphere are retained and later
     scored.

5. **Match to `travel.places`**
   - Match in ordered passes:
     exact normalized name + region, alias/name variant, address/geocode,
     nearby coordinate, then manual review candidate.
   - Persist `match_confidence` and `match_method`.
   - Anything below the confidence threshold goes to manual review and must not
     enter scoring or RAG automatically.

6. **Aggregate**
   - Upsert weekly rows into `community.place_mentions_weekly`:
     `mention_count`, `organic_mention_count`, `sentiment_score`,
     `attributes`, `provider`, and `updated_at`.
   - Use provider-specific aggregation metadata:
     sample size, retained review count, filtered count, ad ratio, confidence
     distribution, and extraction prompt version.

7. **Record source provenance**
   - For file/API batches, record source identity in `ingest.source_files` or
     a matching source-run table.
   - Record batch status in `ops.job_runs`.
   - Never print `DB_DSN`, API keys, review source tokens, or Key Vault URLs.

## Proposed Data Shapes

`community.place_mentions_weekly.attributes` should include:

```json
{
  "prompt_version": "review-mention-preprocess-v1",
  "organic_review_count": 38,
  "filtered_ad_count": 12,
  "match_confidence_avg": 0.91,
  "top_terms": ["야간 산책", "전시 동선", "조용한 분위기"],
  "source_mix": {
    "naver_blog": 31,
    "community_export": 7
  }
}
```

For restaurants, keep food terms:

```json
{
  "top_terms": ["숯불 향", "고기 맛", "반찬", "친절"],
  "category_policy": "restaurant_food_terms_retained"
}
```

For attractions/culture venues, keep the rejection evidence:

```json
{
  "category_policy": "attraction_food_only_review_rejected",
  "rejected_terms": ["메뉴판", "디저트"],
  "retained_terms": ["전시 동선", "건축 분위기"]
}
```

## Implementation Milestones

| Milestone | Scope | Done Evidence |
|---|---|---|
| M1. Plan and preview tool | Add the tool and wrappers with no DB mutation by default. | Implemented. `scripts/unix/plan_review_mention_ingest.sh` is included in repo verification and prints no secrets. |
| M2. Deterministic filters | HTML cleanup, dedup, ad phrases, category-specific food noise policy. | Implemented. Unit tests cover ad filtering, attraction food-only rejection, and restaurant food-term retention. |
| M3. AI classifier | JSON-only ad/relevance classifier with prompt versioning. | Pending. Deterministic `review-mention-preprocess-v1` metadata is stored first. |
| M4. Place matching | Confidence-ranked matching against `travel.places`. | Partially implemented. Exact-name matches are scored; ambiguous rows keep `organic_mention_count=0`. |
| M5. Apply path | Guarded upsert to weekly aggregate table. | Implemented. Apply requires `ALLOW_REVIEW_MENTION_INGEST_APPLY=1` and logs `ops.job_runs`. |
| M6. Integration | Feed sentiment/attribute scoring and RAG regeneration. | Score/RAG preview shows new review-derived inputs. |

## Verification Commands

Planned command shape:

```bash
scripts/unix/plan_review_mention_ingest.sh
scripts/unix/plan_review_mention_ingest.sh --preview --limit 50
ALLOW_REVIEW_MENTION_INGEST_APPLY=1 \
  scripts/unix/plan_review_mention_ingest.sh \
  --apply \
  --confirm APPLY_REVIEW_MENTION_INGEST \
  --limit 5000
```

Existing follow-up commands after apply:

```bash
scripts/unix/plan_place_score_batch.sh --preview --limit 20 --python .venv/bin/python
scripts/unix/plan_rag_index.sh --preview --source dynamic --limit 20 --python .venv/bin/python
```

The tool is also covered by:

```bash
python -m pytest apps/api/tests/test_review_mention_ingest.py apps/api/tests/test_safety_contracts.py -q
scripts/unix/verify_repo.sh --skip-install --python .venv/bin/python
```

## 100% Completion Definition

This area reaches 100% when:

- at least one approved review/mention source can run plan, preview, and guarded
  apply;
- `community.place_mentions_weekly` contains organic mention counts and
  attributes for representative places across attraction, restaurant, event,
  and culture venue categories;
- ad filtering and category-specific review retention are covered by tests;
- ambiguous place matches are excluded from scoring/RAG until manually approved;
- score batch preview no longer reports `review_attribute_analysis` missing for
  places with sufficient organic review evidence;
- deployed API and web smoke still pass with DB/PostGIS places and no fallback
  or mock data.
