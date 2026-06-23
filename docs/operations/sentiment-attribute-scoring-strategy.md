# Sentiment and Attribute Scoring Strategy

Last updated: 2026-06-22 KST

This document defines the path from preprocessed reviews and mentions to
category-aware sentiment, attribute scores, and `review_quality_score`.

## Target State

LALA should use reviews as structured local evidence:

- restaurants: taste, service, price, atmosphere, cleanliness, waiting/crowding;
- attractions and culture venues: atmosphere, cultural/story value, walking
  comfort, accessibility, crowding, photo/view value, practical tips;
- events: program quality, family/foreign-visitor friendliness, weather/indoor
  fit, crowding, access;
- all categories: organic sample size, ad-filter pass rate, sentiment confidence,
  and extraction confidence.

The result should feed:

- `travel.place_enrichments` with `enrichment_type='review_attributes'` or
  `sentiment`;
- `community.place_mentions_weekly.attributes`;
- `analytics.place_score_snapshots.review_quality_score`;
- `rag.knowledge_chunks.metadata` for grounded docent scripts.

## Current Gaps

| Gap | Current Evidence | Risk |
|---|---|---|
| `review_quality_score` coverage is narrow | `run_place_score_batch` now reads `community.place_mentions_weekly.attributes.review_quality.score`, but only places with enough organic evidence become non-null. | Review quality is real but still sparse until more approved review/mention sources are ingested. |
| Attribute extraction is not a full guarded AI batch | Rule-based review attributes and weekly mention aggregates exist; a separate AI extraction contract is still needed for broader coverage. | Reviews can affect some scores, but not enough places for final-quality coverage. |
| Category-specific attribute schemas need stronger test coverage | Existing JSON uses category policies and `review-attributes-v1`, but more category edge cases are needed. | Taste/service rules could still leak into attractions or be lost for restaurants if new sources are added carelessly. |
| Confidence and sample-size rules need operational monitoring | `review_quality_score` stays null below 3 organic reviews, and low evidence keeps `review_attribute_analysis` in missing signals. | A sparse source pool can make the review score look absent for many otherwise valid places. |
| Manual QA thresholds are not connected to scoring | Deployed smoke checks script quality, but not attribute scoring quality. | Good smoke can still hide weak review scoring. |

## Legacy LALA Touchpoints

Legacy LALA already had a useful review-analysis shape. The refactor should
preserve the category intent while making the output scoreable and auditable.

| Legacy File | Behavior to Carry Forward | LALA-next Refactor Note |
|---|---|---|
| `legacy-lala-reference/src/collectors/process_attractions.py` | `analyze_reviews_with_llm()` required at least 3 retained reviews, combined the top review sample, and returned JSON fields such as `summary_ko`, `summary_en`, `atmosphere`, `atmosphere_en`, `tips`, and `tips_en`. | Convert the same evidence into explicit attribute objects, not only prose summaries. |
| `legacy-lala-reference/src/collectors/load_review_pipeline.py` | `extract_keywords_with_llm()` produced compact adjective/noun signals from attraction review batches. | Store top terms under `community.place_mentions_weekly.attributes` and use them as evidence phrases for attribute scoring. |
| `legacy-lala-reference/src/collectors/process_restaurants.py` | Restaurant analysis used a food-guide persona and preserved menu/taste/service content. | Restaurant attribute schema must prioritize `taste`, `service`, `price`, `atmosphere`, `cleanliness`, and `wait_crowding`. |
| `legacy-lala-reference/src/collectors/process_restaurants.py` | `get_ranked_restaurants()` combined card spending and local community mention summaries after IQR capping and normalization. | Keep the principle that local consumption and organic mention quality affect recommendations, but route it through `local-value-v2` instead of copying old fixed weights. |
| `legacy-lala-reference/src/collectors/*` | Review summaries were embedded after analysis. | In LALA-next, scoreable attributes and prose summaries should both feed RAG metadata/chunks after the batch is committed. |

Legacy summaries were good for docent voice, but they were not enough for the
current product goal. The new output must explain which attribute was scored,
how much evidence supported it, and why the score is safe to use.

## LALA-next Refactor Mapping

| Legacy Output | Current Repository Landing Point |
|---|---|
| `summary_ko`, `summary_en` | `travel.place_enrichments.attributes.summary_ko` and `summary_en`, then selected `rag.knowledge_chunks` text. |
| `atmosphere`, `tips` | Category-specific attributes such as `atmosphere`, `practical_tip`, `walking_comfort`, or `program_quality`. |
| Extracted keywords | `community.place_mentions_weekly.attributes.top_terms` with source count and confidence. |
| Old restaurant ranking signal | `analytics.place_score_snapshots.review_quality_score` and existing local-value components, not a standalone ranking table. |
| LLM analysis temperature/prompt assumptions | Versioned prompt metadata in `travel.place_enrichments.prompt_version` and `attributes.schema_version`. |

The first implementation should update `apps/api/app/services/place_score_batch.py`
so `review_quality_score` is read from the new versioned review attributes
instead of remaining `pending_review_attribute_analysis`. The UI/API should
continue to hide score details unless the user explicitly opens the
score/reason view.

## Attribute Schema

All attributes should be stored on a 0 to 1 scale with count and confidence:

```json
{
  "schema_version": "review-attributes-v1",
  "sentiment_score": 0.42,
  "sentiment_confidence": 0.86,
  "organic_review_count": 38,
  "attributes": {
    "atmosphere": {"score": 0.82, "count": 21, "confidence": 0.88},
    "service": {"score": 0.74, "count": 12, "confidence": 0.81}
  }
}
```

### Restaurant Attributes

| Attribute | Weight Inside Review Quality | Notes |
|---|---:|---|
| `taste` | 0.30 | Menu, flavor, freshness, signature dish. |
| `service` | 0.20 | Staff, ordering, responsiveness. |
| `price` | 0.15 | Value for money, local affordability. |
| `atmosphere` | 0.15 | Comfort, local mood, seating. |
| `cleanliness` | 0.10 | Hygiene, table/kitchen mentions. |
| `wait_crowding` | 0.10 | Lower crowd stress raises score; high waiting lowers it. |

Food terms are retained for restaurants. This is intentional.

### Attraction and Culture Venue Attributes

| Attribute | Weight Inside Review Quality | Notes |
|---|---:|---|
| `cultural_story` | 0.25 | History, origin, exhibition/story value. |
| `atmosphere` | 0.20 | Mood, calmness, view, architecture. |
| `walking_comfort` | 0.15 | Route, shade, slope, stroller/wheelchair hints. |
| `photo_view` | 0.15 | Photo spot, view, seasonal appeal. |
| `practical_tip` | 0.15 | Parking, time, booking, weather/season tips. |
| `crowding` | 0.10 | Lower crowd stress raises score. |

Food-only snippets are rejected unless they are clearly route tips and not
descriptions of the attraction itself.

### Event Attributes

| Attribute | Weight Inside Review Quality | Notes |
|---|---:|---|
| `program_quality` | 0.30 | Show/exhibit/festival content quality. |
| `family_friendliness` | 0.15 | Children, seniors, group suitability. |
| `foreign_visitor_fit` | 0.15 | Language, signage, cultural accessibility. |
| `access` | 0.15 | Transit, walking, parking. |
| `weather_indoor_fit` | 0.15 | Indoor/covered areas and weather risk. |
| `crowding` | 0.10 | Queue, congestion, reservation stress. |

## Scoring Formula

For each place with sufficient organic evidence:

```text
organic_coverage = min(1.0, organic_review_count / category_target_count)
ad_quality = 1.0 - min(1.0, filtered_ad_count / max(1, raw_review_count))
sentiment_norm = (sentiment_score + 1.0) / 2.0
attribute_mean = weighted category attribute score
confidence = min(sentiment_confidence, attribute_confidence_avg)

review_quality_score =
  0.35 * attribute_mean +
  0.25 * sentiment_norm +
  0.20 * organic_coverage +
  0.10 * ad_quality +
  0.10 * confidence
```

Minimum evidence rule:

- fewer than 3 organic reviews: keep `review_quality_score=null`;
- 3 to 9 organic reviews: allow score but cap confidence at 0.65;
- 10 or more organic reviews: normal scoring;
- high ad ratio above 0.50: cap score at 0.60 unless manually approved.

## Batch Design

Proposed tool:

- `apps.api.app.tools.run_review_attribute_batch`
- `scripts/unix/plan_review_attribute_batch.sh`
- `scripts/windows/plan_review_attribute_batch.ps1`

Modes:

- `plan`: prints target tables and schema versions only;
- `--preview`: reads preprocessed mentions and returns candidate attributes;
- `--dry-run-ai`: calls Azure OpenAI for JSON extraction without DB mutation;
- `--apply --confirm APPLY_REVIEW_ATTRIBUTE_BATCH`: writes enrichments and
  weekly aggregate attributes;
- apply guard: `ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY=1`.

The batch should never run inside user-facing API requests.

## AI Extraction Contract

The model must return JSON only:

```json
{
  "schema_version": "review-attributes-v1",
  "category": "restaurant",
  "sentiment_score": 0.42,
  "sentiment_confidence": 0.86,
  "attributes": {
    "taste": {"score": 0.91, "evidence": ["숯불 향", "고기 맛"]},
    "service": {"score": 0.72, "evidence": ["친절"]}
  },
  "rejected_evidence": [
    {"reason": "advertisement", "text_hash": "redacted"}
  ]
}
```

Guardrails:

- Do not invent attributes not evidenced by retained organic text.
- Do not output raw review text longer than a short evidence phrase.
- Do not mix Korean and English in the same public attribute label.
- Do not score food attributes for attractions unless the place is a restaurant
  or food is explicitly a route-tip context.

## Integration With `local-value-v2`

After apply:

1. `travel.place_enrichments` stores attribute and sentiment detail.
2. `community.place_mentions_weekly` stores aggregate weekly attributes.
3. `run_place_score_batch` reads the new signal and writes
   `analytics.place_score_snapshots.review_quality_score`.
4. `run_rag_index --source dynamic` adds selected attribute summaries to
   `rag.knowledge_chunks`.
5. Flutter and API score/reason surfaces show review detail only when users
   explicitly open score/reason UI; docent scripts use it as private grounding.

## Verification Commands

Planned command shape:

```bash
scripts/unix/plan_review_attribute_batch.sh
scripts/unix/plan_review_attribute_batch.sh --preview --limit 50
scripts/unix/plan_review_attribute_batch.sh --dry-run-ai --limit 20
ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY=1 \
  scripts/unix/plan_review_attribute_batch.sh \
  --apply \
  --confirm APPLY_REVIEW_ATTRIBUTE_BATCH \
  --limit 5000
```

Existing follow-up commands:

```bash
ALLOW_PLACE_SCORE_BATCH_APPLY=1 \
  scripts/unix/plan_place_score_batch.sh \
  --apply \
  --confirm APPLY_PLACE_SCORE_BATCH \
  --category all \
  --limit 3000 \
  --python .venv/bin/python

scripts/unix/smoke_api_matrix.sh --base-url https://api.lala-next.cloud --timeout 25
```

## 100% Completion Definition

This area reaches 100% when:

- category-specific attribute schemas are implemented and tested;
- restaurants retain taste/menu/service evidence;
- attractions and culture venues reject food-only review noise;
- `travel.place_enrichments` and `community.place_mentions_weekly` contain
  versioned sentiment/attribute outputs;
- `analytics.place_score_snapshots.review_quality_score` is non-null for
  eligible places with enough organic review evidence;
- low-evidence places keep `review_quality_score=null` rather than receiving a
  fake or inferred score;
- score and docent tests verify no raw score values, internal labels, demo text,
  mock wording, or unsupported claims leak to users.
