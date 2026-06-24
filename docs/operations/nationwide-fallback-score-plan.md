# Nationwide Fallback Score Plan

Last updated: 2026-06-24 KST

This document defines how LALA can expand nationwide even when free
card-spending coverage remains partial.

The key rule is simple:

- nationwide service availability does not require nationwide
  `local_spending_score`;
- score quality should scale with real coverage;
- regions without an approved card source must remain null for
  `local_spending_score`.

## Goal

Enable nationwide recommendation and RAG coverage using already approved free
signals, while keeping the current score contract source-faithful.

This plan does not invent substitute card rows. It uses the existing
null-preserving score formula and expands nationwide through the components that
already have broader public-data coverage.

## Non-Negotiable Rules

1. Do not infer, copy, or synthesize non-Gyeonggi card-spending rows.
2. Keep `local_spending_score` null where no approved regional source exists.
3. Keep the current score-contract behavior where missing components are
   reweighted across the remaining non-null components.
4. Treat static snapshot fallback as an outage/local-check path only; it is not
   the same thing as nationwide score fallback.

See:

- [docs/data/data-dictionary.md](/Users/geondongkim/LALA-next/docs/data/data-dictionary.md:432)
- [apps/api/app/services/place_score_batch.py](/Users/geondongkim/LALA-next/apps/api/app/services/place_score_batch.py:121)
- [docs/operations/nationwide-expansion-plan.md](/Users/geondongkim/LALA-next/docs/operations/nationwide-expansion-plan.md:237)

## Free Nationwide Signals Available Now

The current score model already supports nationwide expansion without changing
the schema or pretending that missing card data exists.

| Score component | Current input relation | Free nationwide path | Coverage expectation | Rule |
|---|---|---|---|---|
| `local_spending_score` | `economy.card_spending_area_monthly` | approved regional card datasets only | partial | Keep null outside approved regions. |
| `small_merchant_fit_score` | `analytics.place_business_identity` | Fair Trade Commission franchise reference + place identity batch | broad where place names are matchable | Safe national fallback for local-business preference. |
| `demand_dispersion_score` | `travel.places` region density | TourAPI nationwide place coverage | broad | Works without card data because it compares place density by region. |
| `culture_relevance_score` | `culture.events`, `travel.place_events` | nationwide TourAPI + KCISA + KOPIS | broad after sweep | Strongest public-data replacement for local-value freshness outside Gyeonggi. |
| `weather_fit_score` | `travel.weather_observations` | KMA refresh + region catalog mapping | nationwide | Keep weather refresh cadence healthy before score apply. |
| `review_quality_score` | `community.place_mentions_weekly` | approved mention/review preprocessing | selective | Useful bonus signal, not a nationwide prerequisite. |
| `accessibility_fit_score` | place metadata and density context | nationwide place ingest and enrichment | broad | Safe supporting signal for sparse regions. |

## Coverage Tiers

The rollout should explicitly accept uneven signal coverage rather than trying
to hide it.

| Tier | Region state | Expected score behavior | Operational meaning |
|---|---|---|---|
| `A: full-local-value` | approved card source exists | all standard components may participate | Current Gyeonggi-style quality. |
| `B: public-signal` | no approved card source, but place/culture/weather/business signals exist | `local_spending_score` stays null and the rest are reweighted | Valid nationwide recommendation path. |
| `C: sparse-public-signal` | place coverage exists but culture/review/business inputs are still thin | only a subset of non-card components participate | Service can still operate, but score confidence is lower. |

The product decision should be to ship `B` nationally and improve regions from
`B` to `A` only when real card sources are onboarded.

## Practical Fallback Mapping

If we cannot use real regional card sales, the next-best free public-value
signals are:

| Need | Best free substitute | Why it is acceptable | What it cannot claim |
|---|---|---|---|
| local economic relevance | `small_merchant_fit_score` + `culture_relevance_score` | prefers local/smaller merchants and areas with active public culture supply | It is not a spend-volume proxy. |
| demand balancing | `demand_dispersion_score` | discourages already dense regions and helps spread traffic | It is not proof of real transactions. |
| real-time suitability | `weather_fit_score` | keeps recommendations context-aware nationwide | It does not replace economic impact. |
| quality confidence | `review_quality_score` when enough evidence exists | improves ranked ordering where organic evidence exists | It is sparse and must stay optional. |
| geographic usability | `accessibility_fit_score` | helps avoid poor-fit places in thin regions | It is a supporting, not primary, public-value signal. |

## What This Means For `final_score`

No formula rewrite is required for the first nationwide pass.

The current contract already states that missing components are not treated as
zero; the score is normalized over the available components. That means:

1. Gyeonggi can continue using real `local_spending_score`.
2. Seoul, Busan, Jeju, and other non-card regions can still produce valid
   ranked output from culture, weather, business-identity, density, and review
   signals.
3. We do not need a fake "national card index" to launch nationwide.

## Suggested Product Language

The API and docs should behave as if partial card coverage is expected, not as
if it were an error.

Recommended stance:

- recommendation is nationwide;
- `local_spending_score` is region-dependent;
- score evidence should expose null honestly rather than backfilling it;
- user-facing docent copy must continue avoiding raw score values.

## Rollout Order

1. Keep the nationwide place and culture sweeps moving first.
2. Keep franchise-reference, franchise-identity, and weather-refresh batches
   current because they are the best free nationwide support signals.
3. Rerun place-score preview after each major nationwide ingest wave.
4. Apply score snapshots only after preview quality looks stable.
5. Regenerate RAG after score apply so nationwide culture/weather grounding
   stays aligned.

## Free Indicator Matrix By Data Source

This is the practical "what can we use for free nationwide" matrix.

| Data source | Relation or batch | Nationwide value | Main score use | Readiness |
|---|---|---|---|---|
| TourAPI | `travel.places`, `travel.place_events` | nationwide place inventory and event adjacency | `demand_dispersion_score`, `accessibility_fit_score`, partial `culture_relevance_score` | ready and already being generalized |
| KCISA | `culture.events` | regional culture event supply | `culture_relevance_score` | ready and already generalized |
| KOPIS | `culture.events` | performance/event supply | `culture_relevance_score` | ready and already generalized |
| KMA weather | `travel.weather_observations` | live regional context | `weather_fit_score` | ready |
| FTC franchise refs | `economy.franchise_*`, `analytics.place_business_identity` | local-vs-chain business signal | `small_merchant_fit_score` | ready |
| Review mentions | `community.place_mentions_weekly` | organic quality evidence | `review_quality_score` | partial but useful |
| Regional card data | `economy.card_spending_*` | true spend signal | `local_spending_score` | partial only |

## Regions That Need No Special Exception

For the first nationwide release, these regions do not need custom score logic.
They only need honest signal availability:

- no card source yet: run the standard score batch and let
  `local_spending_score` stay null;
- card source later approved: ingest it and the next batch will naturally lift
  that region from Tier `B` to Tier `A`.

## Next Implementation Slice

The next natural implementation slice is:

1. preview nationwide place-score output after the broader TourAPI/KCISA/KOPIS
   sweeps;
2. inspect how many latest rows remain useful when `local_spending_score` is
   null;
3. if the preview quality is acceptable, apply score snapshots and regenerate
   RAG;
4. separately continue card-source onboarding for Seoul, Sejong, and
   Gyeongnam.
