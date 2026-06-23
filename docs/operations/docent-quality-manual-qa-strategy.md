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
| Representative QA tooling now exists, but script generation is still pending | `scripts/unix/plan_docent_quality_qa.sh` selects a balanced DB-backed sample and writes local-only QA seed files. The first shared-dev run produced 50 records: 13 attractions, 13 restaurants, 11 events, and 13 culture venues. All 50 were marked `needs_script_generation` because the representative set had no cached `travel.docent_scripts` rows. | QA can start from a fixed sample, but content quality cannot be scored until representative scripts are generated or warmed through the API. |
| Manual rubric threshold is encoded as plan metadata, not yet completed by reviewers | The QA tool exposes 100-point rubric weights and pass thresholds, and tests reject placeholder/raw scores/PM omissions. | Script can pass technical checks while still needing human tone and legacy-parity review. |
| Reviewer record template is executable | The local-only writer creates JSON and Markdown rows with reviewer, manual score, issue tags, fix owner, retest status, and `legacy_parity` fields. | Team feedback is structured, but completion depends on filling the rows after generation. |
| No re-test loop tied to RAG and scoring | RAG regeneration and score updates are separate. | QA fixes may not survive the next batch. |

## Legacy LALA Touchpoints

Manual QA should judge whether LALA-next has refactored the old product quality,
not merely whether the new API returns a non-empty script.

| Legacy File | Behavior to Carry Forward | LALA-next Refactor Note |
|---|---|---|
| `legacy-lala-reference/src/frontend/web/services/docent_service.py` | Attraction scripts with review evidence used an energetic LALA chief-docent persona. | Verify `apps/api/app/services/ai_service.py` keeps that voice when visitor/RAG evidence exists. |
| `legacy-lala-reference/src/frontend/web/services/docent_service.py` | Attraction scripts without review evidence used a calmer space-curator persona from official data. | QA should confirm official-only places still sound grounded, not empty or generic. |
| `legacy-lala-reference/src/frontend/web/services/docent_service.py` | Restaurant scripts used a food-guide persona and converted keywords/reviews into listenable guidance. | Restaurant QA must fail scripts that lose taste/menu/service detail. |
| `legacy-lala-reference/src/frontend/web/services/docent_service.py` | Event scripts focused on practical route context and local mobile-app usefulness. | Event QA must check date, place, weather, crowd, and route usefulness. |
| `legacy-lala-reference/src/frontend/web/services/docent_service.py` | Fallback cache rows were deleted/ignored so fallback was never reused as if it were real script quality. | LALA-next smoke and QA must continue rejecting fallback/demo/mock source as a blocker. |
| `legacy-lala-reference/src/frontend/web/services/docent_service.py` | Story keywords such as history, origin, legend, hidden story, rumor, and anecdote were prioritized. | QA should reward scripts that surface story-bearing facts when the grounding supports them. |

## LALA-next Refactor Mapping

| Legacy Quality Contract | Current Repository Landing Point |
|---|---|
| Category-specific persona prompts | `apps/api/app/services/ai_service.py::_docent_system_prompt`. |
| Grounding assembly and food-noise filtering | `apps/api/app/services/docent_service.py::_prepare_docent_grounding_context`. |
| RAG context lookup | `apps/api/app/services/db_repository.py::fetch_docent_knowledge_context`. |
| Verified place-profile fallback, not mock text | `apps/api/app/services/db_repository.py::fetch_docent_place_profile_context`. |
| Public smoke rejection of fallback/mock wording | `scripts/unix/smoke_flutter_web.sh` and `scripts/unix/smoke_api_matrix.sh`. |
| Unit coverage for review category rules | `apps/api/tests/test_v1_routes.py` and `apps/api/tests/test_ai_service.py`. |

The manual QA sheet should include a `legacy_parity` field with one of:
`stronger_than_legacy`, `legacy_equivalent`, `weaker_than_legacy`, or
`not_comparable`. Any `weaker_than_legacy` row must link to the layer that needs
work: source data, review preprocessing, attribute scoring, RAG chunking, AI
prompting, or UI presentation.

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

Executable tooling:

```bash
scripts/unix/plan_docent_quality_qa.sh --preview --limit 50
scripts/unix/plan_docent_quality_qa.sh --write --limit 50
```

Default plan mode does not read DB. Preview mode reads the canonical DB through
`travel.places`, `travel.docent_scripts`, `travel.weather_observations`,
`analytics.place_score_snapshots`, `community.place_mentions_weekly`, and
`rag.knowledge_chunks`. Write mode creates ignored local files under
`output/local/docent-qa/` and never writes DB rows.

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
