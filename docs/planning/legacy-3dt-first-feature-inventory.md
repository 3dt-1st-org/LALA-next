# Legacy Feature-Evidence Inventory & Planning Slices

> Companion to [`legacy-3dt-first-technical-spec.md`](./legacy-3dt-first-technical-spec.md).
> This matrix maps each legacy capability to (a) its evidence in the read-only
> legacy repo, (b) its current state in LALA-next, and (c) an **independent
> planning slice** so work can be sequenced without cross-slice coupling.
>
> All evidence is **behavior/interface**; nothing here licenses copying legacy
> code/prompts/assets/secrets/data (see the spec's §17 Clean-Room Boundaries).

## How to read this matrix

- **Slice** — an independently plannable unit. Slices are ordered roughly by
  data-flow dependency (ingest → enrich → score → serve), but each can be
  designed in isolation because its *contract* (inputs/outputs/persistence) is
  named below.
- **Evidence** — legacy path + symbol(s) proving the capability exists.
- **LALA-next state** — what already exists (so a slice targets only the delta).
- **Verdict** — `GAP` (legacy capability missing/thin), `DIVERGENCE`
  (intentionally different design), `OPPORTUNITY` (chance to exceed legacy),
  `PARITY` (already equivalent).
- **Clean-room boundary** — the one thing this slice must NOT carry over.

## Feature-Evidence Matrix

| Slice | Legacy capability | Evidence (path · symbol) | LALA-next state | Verdict | Independence / boundary |
| --- | --- | --- | --- | --- | --- |
| **R1 — Review ingestion** | Naver blog review → clean → food-filter → LLM analyze → embed → upsert | `src/collectors/load_review_pipeline.py::run_batch_for_area`; `load_restaurant_review.py::run_restaurant_pipeline`; `process_attractions.py::clean_and_filter_text`; Azure Function `src/functions/review_pipeline_func/function_app.py::review_pipeline_daily` (**timer**, §2.1 conflict) | `apps/api/app/tools/review_mention_ingest.py`, `review_attribute_batch.py`, `rag_index.py` exist; Naver pipeline + food guard thin | **GAP** | Trigger is timer/CLI batch — do **not** assume a review-ingest queue. Don't copy review text or the food-keyword list. |
| **R2 — Fair ranking normalization** | IQR outlier clip (card only) + Min-Max + 0.4·card + 0.6·daangn, top-10 | `src/collectors/process_restaurants.py::get_ranked_restaurants`; `src/services/restaurant_docent.py::rank_restaurants`; matviews `locallink.v_card_stats_summary`, `daangn.v_daangn_stats_summary` | `recommendation_scoring.py::build_place_score` (7-component weights) | **DIVERGENCE** | Re-derive weights deliberately; legacy 40/60 is *evidence of intent*, not a contract to copy. |
| **V1 — Vector/RAG retrieval** | Embeddings stored `VECTOR(1536)` but **not** queried by runtime (keyword/SQL RAG) | `attraction_reviews.embedding`; `restaurant_docent.fetch_top10_context`; `sql/analytics/hybrid_place_matching.sql`; **no** ivfflat/HNSW index | `rag.knowledge_chunks` (ivfflat cosine) declared | **OPPORTUNITY** | Wire real semantic retrieval; do not mirror legacy's stored-but-unused vectors as the target. |
| **D1 — Docent generation** | Multi-persona KO/EN attraction/restaurant/planner narration; cache + LLM→fallback | `src/services/attraction_docent.py::generate_docent_script`; `restaurant_docent.py`; `daily_planner` docent; `docent_script_cache` table | `apps/api/app/services/docent_service.py` + `ai_service.py` | **PARITY (verify)** | **Never copy prompt/persona text** — re-derive from behavior; verify cache key (place_id, category, language, mode) + TTL. |
| **T1 — TTS audio** | Azure Speech REST, SSML, MP3, per-language voices, ≤6000 chars | `src/services/speech_synthesizer.py`; `src/frontend/web/services/speech_service.py` | `apps/api/app/services/speech_service.py` | **PARITY** | Don't copy voice-selection internals; interface only (MP3, lang→voice contract). |
| **P1 — Day-plan scheduler** | 4 fixed slots, open-hours filter, greedy nearest-neighbor w/ anchor, dedup, meal categories | `src/services/daily_planner.py::DailyTravelPlanner`; `_rank_morning_pool_by_anchor`; `_haversine_meters`; `used_place_names` | `apps/api/app/services/planner_service.py::daily_plan` | **GAP (verify)** | Verify slot layout + greedy + anchor; don't import planner code. |
| **W1 — Weather-aware fallback** | Threshold triggers (PM10>80, PM2.5>35, heat≥33, cold≤−12, wind≥4, precip>0), staged indoor swap, intervention state-diff | `src/services/weather_planner.py::_extract_alert_flags`; `_get_active_alert_reasons`; `check_and_propose_intervention`; `.weather_state_cache.json` | `apps/api/app/services/weather_service.py`; `planner_service.intervention` | **GAP (verify)** | Thresholds are config — re-affirm or revise deliberately; don't copy cache file format verbatim. |
| **L1 — Location/region resolution** | GPS → nearest `tourist_spot_info` → `sigun_nm` (PostGIS only); juso = address EN-translation only | `src/services/weather_planner.py::get_user_sigun_nm`; `src/api/juso_client.py`; `ST_DWithin/ST_Distance/ST_MakePoint` | `db_repository` PostGIS reads; `region_catalog` | **PARITY (verify)** | Don't import juso/kterm clients wholesale; keep address-translation vs geocoding separation explicit. |
| **TR1 — Translation clients** | K-Term (place KO→EN) + Juso (address KO→EN) with romanize fallbacks | `src/api/kterm_client.py::translate`, `romanize_fallback`; `src/api/juso_client.py::translate_address` | partial (`normalization.py`) | **GAP** | Fallback mapping tables are content — re-derive minimal maps; don't copy 88-entry suffix tables. |
| **M1 — Map clustering & markers** | Viewport 5×5 grid clustering (point≥12, Δlat≥0.01), max-zoom disable (0.006), 90ms debounce, cache-buckets; reload 250m, auto-docent 100m+12s | `src/frontend/ios/LALA/LALA/Core/MapMarkerClusteringPolicy.swift`; `Views/MainMapView.swift`; `Core/MapGuidanceLogic.swift`; `ViewModels/MainMapViewModel.swift` | Flutter Kakao map + `map_helpers.dart` (threshold `places≥80 && mapLevel≥10`) | **DIVERGENCE** | Platform differs (MapKit→Kakao); re-derive policy for Flutter; don't port Swift thresholds. |
| **C1 — Community crawl pipeline** | Timer orchestrator → queue fan-out → workers → weekly mention aggregation | `src/functions/daangn_weekly_crawler/function_app.py` (4 fns; queues [community crawl task queue], [mention aggregation queue]); `daangn.*` schema | `apps/workers` dry-run contracts; `community.*` schema | **GAP (rollout-gated)** | Queue pattern is the reference fan-out; live execution is approval-gated in LALA-next. Don't copy crawl payloads. |
| **O1 — Ops/Power BI dashboard** | `monitoring.*` datamart + `vw_*` Power BI DirectQuery + ASA realtime | `sql/ddl/create_monitoring_powerbi_{ops_tables,views}.sql`; `Arem Arem Azure Ops Semantic Model.pbix`; `azure_ops_monitoring_func` (5 jobs) | `observability_plan.py` (non-mutating); no Power BI | **GAP (deferred)** | Don't port `.pbix`/`.tmdl`; the `monitoring.vw_*` *contract* is the reusable artifact. |
| **MON1 — Azure monitoring functions** | 5 timer/event-hub jobs → health/log-kpi/cost/inventory/stream | `src/functions/azure_ops_monitoring_func/` + `monitoring_jobs/*` | `apps/workers` `ops-rollup` contract (dry-run) | **GAP (rollout-gated)** | Don't copy resource identifiers; re-implement collection against LALA-next resources. |
| **WA1 — Weather/air collector** | KMA+AirKorea every 3h → Event Hub [weather/air telemetry hub]; 35 stations | `src/functions/weather_air_func/function_app.py::WeatherAirDataCollector`; `stations.json` | `weather_observation_refresh.py`; `weather_service` | **GAP (verify)** | Station list beyond public KMA grid is content — re-derive; don't copy `stations.json`. |
| **I1 — Identity/privacy/action-log** | iOS location consent; `user_action_log` (session-UUID DAU, no user ids); XAI reason | `src/frontend/ios/.../MainMapViewModel.swift`; `sql/ddl/user_action_log.sql`; README XAI | `identity.users`, OAuth/JWT, `community.user_posts` | **PARITY (enhanced)** | LALA-next identity is richer; don't port legacy session-UUID analytics as-is. |
| **SEC1 — Secrets (KeyVaultManager)** | Singleton, DefaultAzureCredential, KV→env fallback, non-failure | `config/vault_manager.py::KeyVaultManager` | `apps/api/app/core/key_vault.py` + reuse-plan | **PARITY** | Don't port vault URL/secret names; keep ONMU-vault isolation (`int-cors-origins` only). |
| **OPS1 — CI/deploy** | OIDC secret-zero deploy; container CMD fix; docker compose | `.github/workflows/oidc.yml`; `Dockerfile`; `infra/docker/`; handoff docs | LALA-next CI + deploy runbooks | **PARITY (verify)** | Don't port legacy resource names/subscription ids. |
| **TEST1 — Tests** | pytest unit + GPX route sim + dedup smoke + secret-contract | `tests/unit/*`; `tests/sql/daangn_dedup_smoke_test.sql`; `tests/ios/routes/*` | `apps/api/tests/*` (broad) | **PARITY (broader)** | Don't copy legacy test fixtures; LALA-next already exceeds coverage. |

## Slice Dependency Graph (loose)

```
R1 (review ingest) ──► V1 (vector/RAG) ──┐
R2 (ranking) ────────────────────────────┼──► D1 (docent) ──► T1 (TTS)
WA1 (weather) ──► W1 (weather engine) ───┤            ▲
L1 (location) ──┬──► P1 (day-plan) ──────┤            │
                │                         │   M1 (map) consumes D1/T1/W1
C1 (crawl) ──► R2 (ranking signal)        │
TR1 (translation) feeds D1/L1 place names │
MON1/O1 (ops) — independent of serving    │
I1/SEC1/OPS1/TEST1 — cross-cutting, independent
```

- **R1, C1, WA1** are ingest producers (can start in parallel).
- **R2, V1, W1, TR1** enrich/transform (depend on their producer's contract, not its implementation).
- **D1, P1** consume the enriched data (depend on R2/V1/W1/L1 contracts).
- **T1, M1** are presentation-layer (depend on D1/W1 outputs).
- **MON1/O1, I1/SEC1/OPS1/TEST1** are orthogonal and fully independent.

## Recommended First Wave (lowest coupling, highest unblock)

1. **R1** — unblocks V1/D1 by defining the review→embed→persist contract.
2. **W1** — unblocks P1/D1 weather-aware paths; verify thresholds.
3. **L1** — small, unblocks P1 region queries.
4. **V1** — the one **OPPORTUNITY** slice; decide ANN-vs-keyword explicitly.

## Cross-Slice Contract Pins (what each slice must publish)

- **R1** → `community.posts` / review tables + `extracted_keywords` shape + `VECTOR(1536)` column.
- **R2** → a deterministic `place_score_snapshots` write keyed by place + component breakdown.
- **V1** → `rag.knowledge_chunks` retrieval API (k, filter, min_score).
- **D1** → `/api/v1/docents/{script,audio}` envelope + cache key (place_id, category, language, mode) + TTL.
- **P1** → `/api/v1/plans/daily` slot schema (4 slots, role, place_id, window).
- **W1** → `/api/v1/weather` flags (`is_rain_snow`, …) + intervention diff contract.
- **M1** → Flutter map annotation contract (place vs cluster, viewport bucket).

Each pin already has a partial LALA-next home; slices fill the delta only.
