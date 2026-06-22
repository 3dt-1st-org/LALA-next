# Docent Quality Manual QA Strategy

Last updated: 2026-06-22 KST

This document defines how LALA manually evaluates 30 to 50 representative
places so docent quality reaches legacy LALA level or better.

## Target State

Automated smoke tests prove the happy path: current location, DB/PostGIS places,
AirKorea PM10/PM2.5, live place grounding, and no raw score leakage. Manual QA
must go further and judge whether the generated docent script is actually good:

- grounded in official/RAG/place-profile evidence;
- faithful to category-specific persona;
- useful while walking or planning a route;
- clear in the selected language only;
- free of demo/mock/fallback wording;
- better than a generic tourism summary.

## Current Gaps

| Gap | Current Evidence | Risk |
|---|---|---|
| Automated smoke covers representative flows, not broad content quality | Deployed web smoke verifies live-context docent quality on selected smoke places. | A few good paths can hide weak scripts for other categories/regions. |
| No fixed 30 to 50 place QA set | Places exist across Gyeonggi and Seoul, but sample selection is not frozen. | QA can cherry-pick easy places. |
| No manual rubric threshold | Tests reject placeholder/raw scores, but not prose quality. | Script can pass technically while feeling bland. |
| No reviewer record template | Docs do not yet define how to record human judgment. | Team feedback becomes scattered and hard to fix. |
| No re-test loop tied to RAG and scoring | RAG regeneration and score updates are separate. | QA fixes may not survive the next batch. |

## Sample Selection

Use 30 to 50 places, selected from DB-backed places only. Do not use static
snapshot fallback rows for this QA.

Minimum sample:

| Dimension | Required Coverage |
|---|---|
| Region | Seoul and Gyeonggi both represented. |
| Category | At least 8 attractions/culture venues, 8 restaurants, 6 events, and remaining mixed. |
| Indoor/outdoor | At least 10 indoor or weather-safe places and 10 outdoor places. |
| Official source | TourAPI, KCISA, KOPIS where available. |
| Review richness | At least 10 places with review/mention evidence once pipeline is complete. |
| Local value | High and medium `local_spending_score`, plus places with missing card data. |
| Small merchant | Independent/local restaurants and known franchise candidates. |
| Weather/PM | Scripts generated under good and caution PM10/PM2.5 contexts. |
| Image state | Places with official images and places without images. |
| RAG state | Place profile only, place profile plus event, and place profile plus mention chunks. |

Candidate SQL shape:

```sql
SELECT
  p.place_id,
  p.name_ko,
  p.category,
  p.region_name_ko,
  latest_scores.final_score,
  latest_scores.review_quality_score,
  latest_scores.small_merchant_fit_score,
  COUNT(k.id) AS rag_chunk_count
FROM travel.places p
LEFT JOIN LATERAL (
  SELECT *
  FROM analytics.place_score_snapshots s
  WHERE s.place_id = p.place_id
  ORDER BY s.scored_at DESC
  LIMIT 1
) latest_scores ON true
LEFT JOIN rag.knowledge_chunks k ON k.place_id = p.place_id
GROUP BY p.place_id, latest_scores.final_score, latest_scores.review_quality_score,
         latest_scores.small_merchant_fit_score
ORDER BY p.region_name_ko, p.category, latest_scores.final_score DESC NULLS LAST;
```

## Generation Protocol

For each selected place:

1. Fetch the place through the public API with a real test coordinate.
2. Fetch weather and PM10/PM2.5 for the same coordinate.
3. Generate Korean brief and detail scripts.
4. Generate English brief script when English place data exists.
5. Save request payload, response metadata, and reviewer score.
6. Do not store API keys, bearer tokens, Key Vault URLs, or DB DSNs.

Required API checks:

- `source` must not be a fallback/demo/mock source.
- `grounding_count` must be positive for DB-backed places.
- `grounding_sources` must be present.
- script must contain the live place name or a verified localized name.
- script must not expose raw scores or internal source labels.
- script must mention PM10 and PM2.5 when those values were provided.

## Rubric

Score each script out of 100.

| Area | Points | Pass Criteria |
|---|---:|---|
| Factual grounding | 20 | Uses verified place/RAG/profile facts and avoids hallucinated details. |
| Category persona | 15 | Attraction/culture sounds like docent/curator; restaurant keeps food/service evidence; event gives practical route context. |
| Local value | 15 | Connects local spending, small merchant, or demand-dispersion context without raw scores. |
| Weather and PM context | 10 | Uses weather, PM10, and PM2.5 accurately when supplied. |
| Route usefulness | 10 | Gives a practical before/after route action. |
| Review/mention quality | 10 | Uses organic review insights naturally; rejects irrelevant attraction food snippets. |
| Language purity | 8 | Korean mode is Korean; English mode is English; no bilingual clutter. |
| Tone and listenability | 7 | Sounds natural through audio/earphones, not like a database report. |
| Safety and presentation | 5 | No demo/mock/fallback wording, raw scores, source codes, or secret-like values. |

Blockers:

- hallucinated facts about hours, prices, history, events, or weather;
- use of mock/demo/placeholder wording;
- fallback source presented as live data;
- raw score values in script;
- attraction/culture script dominated by unrelated food review;
- restaurant script losing food/taste/service evidence;
- wrong language output.

## QA Record Template

Use one row per script:

| Field | Value |
|---|---|
| `qa_date` | 2026-06-22 |
| `reviewer` |  |
| `place_id` |  |
| `place_name` |  |
| `category` |  |
| `region` |  |
| `language` | ko/en |
| `mode` | brief/detail |
| `grounding_count` |  |
| `grounding_sources` |  |
| `weather_context` | temp, PM10, PM2.5 |
| `score_total` | 0-100 |
| `blocker` | yes/no |
| `issue_tags` | grounding, tone, weather, language, review_noise, route_action |
| `notes` |  |
| `fix_owner` |  |
| `retest_status` | pending/pass/fail |

Store QA records as a local spreadsheet or markdown table under an approved
local-only path while reviewing. Commit only sanitized summaries and aggregate
findings unless the team approves a public QA artifact.

## Pass Thresholds

The first 100% QA target:

- 30 to 50 scripts reviewed;
- no blocker issues open;
- average score at least 90;
- every category average at least 85;
- no language purity failures;
- no demo/mock/fallback wording;
- at least 90% of scripts include a route action;
- 100% of scripts with weather/PM inputs mention PM10 and PM2.5 accurately;
- 100% of DB-backed scripts have grounding metadata;
- all fixes are followed by RAG regeneration or targeted script regeneration
  where relevant.

## Fix Loop

For each blocker:

1. Identify whether the issue came from source data, review preprocessing,
   attribute scoring, RAG chunking, live AI prompt, rule-based curation, or UI.
2. Fix the earliest responsible layer.
3. Re-run the affected batch:
   - review/mention preprocessing;
   - review attribute scoring;
   - place score batch;
   - RAG regeneration.
4. Re-run targeted API script generation.
5. Re-run smoke:

```bash
scripts/unix/smoke_api_matrix.sh --base-url https://api.lala-next.cloud --timeout 25
```

6. Re-test the failing QA rows.

## 100% Completion Definition

This area reaches 100% when:

- the representative 30 to 50 place sample is frozen and covers the required
  dimensions;
- every selected place has a saved QA record;
- blocker issues are zero;
- category averages meet the pass thresholds;
- QA findings are traceable to source, RAG, score, prompt, or UI fixes;
- deployed API and web smoke are green after the last fix;
- the final sanitized QA summary can be used in contest/team documentation to
  prove LALA is operating on real current-location, DB/PostGIS, PM10/PM2.5, and
  grounded docent paths rather than mock/demo behavior.
