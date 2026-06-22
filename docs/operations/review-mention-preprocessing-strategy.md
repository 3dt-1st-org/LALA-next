# Review and Mention Preprocessing Strategy

Last updated: 2026-06-22 KST

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
| No dedicated guarded batch for review/mention ingestion | `community.place_mentions_weekly` is defined, but no `run_review_mention_*` tool exists yet. | Review quality stays `pending_review_attribute_analysis`. |
| Ad filtering is not a reusable persisted pipeline | Legacy filtering logic has been reflected in docent guards, but not yet applied to stored review rows. | Promotional content can inflate mention counts and docent tone. |
| Place matching is not fully audited | Place IDs exist in `travel.places`, but mention matching needs confidence and failure buckets. | Same-name places or franchise branches can be assigned incorrectly. |
| Review source provenance is too thin | `ingest.source_files` handles file provenance; API/search/community provenance needs the same discipline. | We cannot prove a score came from approved sources. |
| No human review lane for ambiguous matches | Existing plan tools are guarded, but ambiguous review matches need a manual queue. | Bad matches become hidden RAG/docent evidence. |

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
| M1. Plan and preview tool | Add the tool and wrappers with no DB mutation by default. | `scripts/unix/plan_review_mention_ingest.sh` prints plan output and no secrets. |
| M2. Deterministic filters | HTML cleanup, dedup, ad phrases, category-specific food noise policy. | Unit tests for attraction food-only rejection and restaurant food-term retention. |
| M3. AI classifier | JSON-only ad/relevance classifier with prompt versioning. | Preview output includes classifier decisions and confidence. |
| M4. Place matching | Confidence-ranked matching against `travel.places`. | Ambiguous rows do not enter `community.place_mentions_weekly`. |
| M5. Apply path | Guarded upsert to weekly aggregate table. | Apply inserts rows and logs an `ops.job_runs` record. |
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
