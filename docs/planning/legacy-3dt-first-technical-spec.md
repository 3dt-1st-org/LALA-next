# Legacy `3dt-1st-Project` Technical Specification (Clean-Room, Evidence-Led)

> Status: **documentation-only reverse-engineering**. No source from the legacy
> repo is copied into LALA-next. This file records **behavior and interface**
> evidence (file paths, symbol names, schemas, route/contract shapes, config
> values) so that downstream LALA-next design can re-implement — not port —
> legacy capability. See §17 *Clean-Room Boundaries* for the explicit do-not-carry list.

## 0. Provenance & Method

- Legacy source (read-only): `/Users/geondongkim/3dt-1st-Project` (a.k.a.
  `3dt-project`, `LALA` / "Local Area, Local Answer"). Evidence below cites
  **legacy-relative paths** (e.g. `src/functions/review_pipeline_func/function_app.py`).
- This worktree (writable): the LALA-next clean-room rebuild on branch
  `geondongkim/lala-legacy-technical-spec`.
- Existing LALA-next traceability narrative this extends:
  `docs/migration/source-diagnosis-traceability.md`,
  `docs/migration/legacy-flask-retirement.md`,
  `docs/migration/sql-canonicalization.md`.
- Evidence was gathered by reading legacy code/SQL/docs directly. Every claim
  below carries a path + symbol so a reader can re-verify against the read-only
  legacy tree.

### Legend

| Tag | Meaning |
| --- | --- |
| **CONFIRMED** | Read directly in legacy code, SQL, or a shipped doc. Path/symbol cited. |
| **INFERRED** | Deduced from code structure or absence of evidence; plausible but not directly observed. |
| **CONFLICT** | Two legacy sources disagree (typically code vs. a handoff doc). Stronger source wins; the disagreement is recorded. |

### Redaction policy

This spec cites only **legacy code paths, symbol names** (functions/classes/
structs/tables/columns) **and non-sensitive contract shapes** (route paths, JSON
envelope fields, SQL DDL shapes, config *behavior* such as cron schedules and
numeric thresholds). Concrete legacy **deploy identifiers** — cloud resource
names, registry/vault/resource-group names, queue/event-hub/consumer-group
names, Key Vault secret names, connection-bearing setting names,
subscription/tenant/client identifiers, and literal service endpoints — are
replaced with **role-based placeholders** (e.g. `[legacy vault]`,
`[community crawl queue]`, `[database host secret]`) even though no secret
*values* are present. File paths under the read-only legacy tree and universal
platform conventions (Azure built-in role names, generic env-var names such as
`DB_DSN`/`KEY_VAULT_URL`, public model/package names) are retained as interface
evidence. Public third-party open-API services are named in prose with their
literal endpoints redacted.

## 1. Topology & Runtimes

| Concern | Evidence (legacy path) | Finding | Tag |
| --- | --- | --- | --- |
| Web runtime | `wsgi.py`, `src/frontend/web/app.py::create_app()` | Flask 3.0 app factory; `wsgi:application` is the Gunicorn entrypoint. | CONFIRMED |
| Container | `Dockerfile` | `python:3.11-slim`; system deps `libpq-dev`, `gcc` (for psycopg2). Gunicorn `gthread`, **1 worker / 4 threads**, bind `:8000`, timeout `120s`, `--worker-tmp-dir /tmp` (Azure App Service sandbox). `PYTHONPATH=/app`. | CONFIRMED |
| Dependencies | `requirements.txt` | `flask>=3.0`, `psycopg2-binary>=2.9`, `openai>=1.40`, `azure-identity>=1.16`, `azure-keyvault-secrets>=4.8`, `gunicorn>=21.2`, `requests`, `python-dotenv`. Function apps pin their own `requirements.txt`. | CONFIRMED |
| Packaging | `pyproject.toml` | Name `3dt-project`, namespace/src-layout packages. | CONFIRMED |
| DB | `infra/db/init_sql/01_gis_vectordb_script.sql` | PostgreSQL with **PostGIS + pgvector + pgcrypto**. Legacy schemas observed: `locallink` (place/review/weather/ranking), `daangn` (community crawl), `monitoring` (ops datamart). | CONFIRMED |
| Azure edge | `.github/workflows/oidc.yml`, `docs/lala-container-deployment-handoff-2026-03-06.md` | App Service `[legacy web app service]`; ACR `[legacy registry]`; Managed Identity with `AcrPull` + `Key Vault Secrets User` (built-in roles). Container handoff root-caused an `appCommandLine` override that broke the Dockerfile CMD → fixed by empty `appCommandLine` + `wsgi.py`. | CONFIRMED |
| Local emulation | `AzuriteConfig`, `infra/docker/docker-compose.yml`, `*/local.settings.sample.json` | Azurite for Azure Storage; docker-compose local stack; sample Function settings. | CONFIRMED |

> Clean-room note: concrete legacy deploy identifiers (registry, App Service,
> vault, resource group, subscription/tenant/client IDs, queues, event hubs,
> secret names) are cited here only as **role-based placeholders** — e.g.
> `[legacy registry]`, `[legacy vault]`, `[community crawl queue]`. They are
> **not** ported into LALA-next config; LALA-next owns its own Azure naming. See
> §0 *Redaction policy*.

## 2. Azure Functions (Python v2 model, 4 function apps)

All four apps live under `src/functions/*` and use the `@app.*` decorator model
with per-app `host.json`, `requirements.txt`, and `local.settings.sample.json`.

### 2.1 Review ingestion — `src/functions/review_pipeline_func/`

> This is the function the dispatch brief singled out ("review ingestion
> trigger/binding/queue"). The finding is precise: **the review-ingestion
> Function is timer-triggered, not queue-triggered.** The queue-based fan-out
> pattern belongs to the Daangn crawler (§2.3), not to review ingestion.

| Aspect | Evidence | Finding | Tag |
| --- | --- | --- | --- |
| Trigger | `function_app.py` `review_pipeline_daily(timer: func.TimerRequest)` decorated `@app.timer_trigger(arg_name="timer", schedule=...)` | **Timer trigger**, default schedule `"0 0 17 * * *"` (≈ 02:00 KST daily), overridable via `REVIEW_PIPELINE_SCHEDULE`. | CONFIRMED |
| Bindings | `host.json` | No input/output bindings beyond the timer; function timeout `02:00:00`; extension bundle `[4.*, 5.0.0)`. | CONFIRMED |
| Queue | — | **None.** Review ingestion does not read from an Azure Queue. | CONFIRMED |
| Work | calls `src.collectors.load_review_pipeline.run_batch_for_area(lat, lng, radius_m)` per configured area and `src.collectors.load_restaurant_review.run_restaurant_pipeline(...)` per configured restaurant; areas/restaurants from `REVIEW_PIPELINE_AREAS` / `REVIEW_PIPELINE_RESTAURANTS` (JSON env). | Nightly batch: collect Naver reviews → clean/filter → LLM analyze → embed → upsert. | CONFIRMED |
| Conflict | `docs/lala-business-logic-phase4-handoff-2026-03-06.md` describes Phase 3 as "`review_pipeline_func` Azure Function (Storage Queue trigger)" | **CONFLICT.** Shipped `function_app.py` is a timer trigger; the handoff doc's "Storage Queue trigger" is either an earlier design or describes a different stage. LALA-next design should treat review ingestion as **timer/CLI batch** and *not* assume a review-ingest queue contract. | CONFLICT |

### 2.2 Weather & air — `src/functions/weather_air_func/`

| Aspect | Finding | Tag |
| --- | --- | --- |
| Function | `WeatherAirDataCollector(myTimer)` — `@app.timer_trigger`, schedule `"0 0 */3 * * *"` (every 3h). | CONFIRMED |
| Sources | Korea Meteorological Administration (KMA) + AirKorea; `stations.json` lists ~35 Gyeonggi cities with `lat/lon` and KMA grid `nx/ny`; `pyproj` for grid conversion. | CONFIRMED |
| Output binding | Emits enriched rows to **Azure Event Hub [weather/air telemetry hub]** (`azure-eventhub` dep). | CONFIRMED |
| Timeout | `host.json` `00:05:00`. | CONFIRMED |

### 2.3 Daangn (당근마켓) community crawler — `src/functions/daangn_weekly_crawler/`

This is the **queue-driven distributed crawl** ("Crawl → Aggregator" per README).

| Function | Trigger | Role | Tag |
| --- | --- | --- | --- |
| `daangn_weekly_crawler` | `@app.timer_trigger`, `"0 0 3 * * 1"` (Mon 03:00 KST, `TIMER_CRON`) | Orchestrator: enqueues one task per `(dong, keyword)` into queue **[community crawl task queue]**. | CONFIRMED |
| `daangn_crawl_worker` | `@app.queue_trigger(queue_name=[community crawl task queue], connection=[storage connection setting])` | Worker: crawls posts/comments for one `(dong × keyword)`; place-name extraction via regex + optional LLM (`MENTION_USE_LLM`). | CONFIRMED |
| `daangn_place_mentions_aggregator` | `@app.timer_trigger`, `"0 30 3 * * 1"` (Mon 03:30, `MENTION_AGGREGATION_CRON`) | Aggregates weekly place mentions; enqueues into **[mention aggregation queue]**. | CONFIRMED |
| `daangn_place_mentions_worker` | `@app.queue_trigger(queue_name=[mention aggregation queue])` | Aggregates `daangn.place_mentions_weekly` per `(place, category, city, week)`. | CONFIRMED |

`host.json`: queue `batchSize=1`, `maxDequeueCount=8`, `visibilityTimeout=00:05:00`, timeout `00:10:00`. Deps: `azure-storage-queue`, `beautifulsoup4`, `psycopg[binary]`. Keywords default `"맛집,명소,행사"` (`DAANGN_KEYWORDS`).

### 2.4 Azure ops monitoring — `src/functions/azure_ops_monitoring_func/`

Five functions; jobs live in `monitoring_jobs/*` (`_common.py`, `collect_health_metrics.py`, `collect_log_kpi.py`, `collect_cost.py`, `snapshot_resources.py`, `ingest_stream_kpi.py`).

| Function | Trigger | Job → sink | Tag |
| --- | --- | --- | --- |
| `monitoring_inventory_timer` | timer, `"0 5 0 * * *"` (daily 00:05 UTC) | `snapshot_resources.run()` → `monitoring.resource_inventory_snapshot` | CONFIRMED |
| `monitoring_health_timer` | timer, `"0 */5 * * * *"` | `collect_health_metrics.run()` → `monitoring.health_metrics_5m` | CONFIRMED |
| `monitoring_log_kpi_timer` | timer, `"20 */5 * * * *"` | `collect_log_kpi.run()` (Log Analytics KQL) → `monitoring.telemetry_kpi_5m` | CONFIRMED |
| `monitoring_cost_timer` | timer, `"0 */30 * * * *"` | `collect_cost.run()` (Cost Mgmt) → `monitoring.cost_daily` | CONFIRMED |
| `monitoring_stream_kpi_eventhub` | `@app.event_hub_trigger`, hub **[ops kpi event hub]**, consumer group [ops realtime ingest consumer group] | `ingest_stream_kpi` → `monitoring.telemetry_kpi_stream_1m`; **opt-in** (`MONITORING_EVENTHUB_KPI_ENABLED="1"`). | CONFIRMED |

Monitored service targets (from `collect_health_metrics.py`): `[legacy web app]`, `[legacy crawler function app]`, `[legacy weather function app]` (App Services) and `[legacy database server]` (DBforPostgreSQL).

## 3. Collector & Persistence Contracts

### 3.1 Review/analysis collectors (`src/collectors/`)

| File | Entry symbol | Behavior | Tag |
| --- | --- | --- | --- |
| `load_review_pipeline.py` | `run_batch_for_area(lat, lng, radius_m)` | 7-step attraction pipeline: Naver search → HTML clean → food-review filter → per-review content batch extract → keyword extract → Azure-OpenAI embedding (1536-d) → pgvector insert into `locallink.attraction_reviews`. | CONFIRMED |
| `load_restaurant_review.py` | `run_restaurant_pipeline(target_restaurant, sigun_nm)` | Parallel restaurant pipeline; Naver query `"{sigun_nm} {name} 후기"`; clean → LLM keywords → batch embeddings → `locallink.restaurant_reviews`. | CONFIRMED |
| `process_restaurants.py` | `get_ranked_restaurants(candidate_list)`, `analyze_reviews_with_llm(...)`, `save_analysis_result(...)`, `run_ranking_and_analysis_pipeline(...)` | Ranks (see §7), then per top restaurant: Naver reviews → LLM JSON analysis (summary/atmosphere/tips, KO+EN) → upsert `locallink.restaurant_details` with embedding. | CONFIRMED |
| `process_attractions.py` | `clean_and_filter_text(raw_html)`, `run_attraction_analysis_pipeline(...)` | Same shape as restaurants **without ranking**; `clean_and_filter_text` is the food-contamination guardrail (see §7.1). | CONFIRMED |
| `restaurant_filter.py` | `filter_restaurants_by_location(radius_m=150, lat, lon)` | Haversine radius filter on `locallink.gg_restaurant_info`; returns status `SKIP_WEIGHTING` when <10 hits else `PROCEED_TO_WEIGHTING`. | CONFIRMED |
| `attraction_filter.py` | `filter_attractions_by_location(radius_m=100, lat, lon)` | Haversine on `locallink.tourist_spot_info`; status `ATTRACTION_DETECTED` / `NO_ATTRACTION_NEARBY`. | CONFIRMED |

### 3.2 External API clients (`src/api/`)

| File | Symbol | External service / behavior | Tag |
| --- | --- | --- | --- |
| `kterm_client.py` | `translate(text)`, `romanize_fallback(text)`, `romanize_restaurant_fallback(...)` | National Institute of Korean Language **K-Term** API (public KO→EN terminology service; literal endpoint redacted — see §0) for KO→EN place-name translation; romanize fallback maps geographic suffixes (e.g. 산→Mountain) and business types; daily-limit code `"022"` stops further calls. | CONFIRMED |
| `juso_client.py` | `translate_address(kor_addr)`, `_romanize_full_fallback(...)` | Juso **Address Support** (public KO road-address → EN service; literal endpoint redacted — see §0); `hangul_romanize` fallback. **Note:** juso is *address EN-translation*, not reverse-geocoding (see §10). | CONFIRMED |

### 3.3 Persistence & secrets

| File | Symbol | Behavior | Tag |
| --- | --- | --- | --- |
| `config/vault_manager.py` | `get_vault_manager()`, `KeyVaultManager` | **Singleton.** `DefaultAzureCredential` (az-login local, Managed Identity cloud) → `SecretClient`. `get_secret(name)` does Key-Vault-then-env fallback (e.g. `[openai-key secret]` → `[OPENAI_KEY env var]`, uppercased with hyphens→underscores); `get_db_dsn()` builds DSN from 5 secrets `[database host|port|name|user|password secret]` (cached); `get_db_connection()` → `psycopg2.connect(..., connect_timeout=5)`. Phase-4 refactor: KV failure is **non-fatal** (WARN + env fallback). | CONFIRMED |
| `src/frontend/web/services/db.py` | `get_db_dsn()`, `get_db_connection()` | `DB_DSN` env overrides vault; `DB_CONNECT_TIMEOUT_SECONDS` default 5. | CONFIRMED |
| Upsert pattern | `INSERT ... ON CONFLICT (<name_col>) DO UPDATE SET ... = EXCLUDED.<col>, embedding = EXCLUDED.embedding` | Idempotent upsert keyed on place name; used for `*_details` tables. *(Pattern described, not copied — see §17.)* | CONFIRMED |

## 4. SQL Schemas (`sql/`, `infra/db/init_sql/`)

Schemas observed: `locallink` (places/reviews/details/weather/ranking/logging),
`daangn` (community crawl), `monitoring` (ops datamart).

### 4.1 `locallink.*` (places, reviews, enrichment)

| Table | Purpose | Notable columns / index | Tag |
| --- | --- | --- | --- |
| `gg_restaurant_info` | Gyeonggi restaurant master | `bizplc_nm`, `refine_wgs84_lat/logt`, `bsn_state_nm` (영업/폐업), `bizcond_div_nm_info`, `sigun_nm`; idx on `sigun`, `status`. | CONFIRMED |
| `tourist_spot_info` | Tourist spot master | `tourist_nm`, `lat/lng`, `sigun_nm`; filtered to 수원/평택/용인. | CONFIRMED |
| `gyeonggi_attractions` | Attraction master | `attraction_name` UNIQUE, `additional_info` ("입장료 / 주차료"), lat/lng. | CONFIRMED |
| `attraction_reviews` | Blog reviews + embeddings | `embedding VECTOR(1536)`, FK→`gyeonggi_attractions` CASCADE, `clean_text`, `extracted_keywords`. | CONFIRMED |
| `attraction_details` | LLM analysis (KO/EN summary/atmosphere/tips) + `embedding VECTOR(1536)` | upsert on `attraction_name`. | INFERRED (schema inferred from INSERT) |
| `restaurant_reviews` / `restaurant_details` | Restaurant analogues of the above | `VECTOR(1536)`; upsert on name. | CONFIRMED / INFERRED |
| `attraction_descriptions` | Wikipedia-sourced overview/history + `use_time`, `closed_days`, `parking`, `pet_allowed` | — | CONFIRMED |
| `gyeonggi_events` | Gyeonggi Cultural Foundation events | `city`, `lat/lng`, `content_id` UNIQUE (added 260308, TourAPI id). | CONFIRMED |
| `realtime_weather_conditions` | 30-min weather window per location | `location`, `record_time`, `temperature`, `precipitation_type`, `pm10/pm25`, ASA flags `is_rain_snow/is_bad_dust/is_heatwave/is_coldwave/is_strong_wind`; idx `(location, record_time DESC)`. | CONFIRMED |
| `gyeonggi_card_spending_stats` | ~5억건 card transactions | `ta_ymd`, `city`, `card_tpbuz_nm_1/2`, `hour/sex/age/day` codes, `amt`, `cnt`. | CONFIRMED |
| `user_action_log` | Analytics | `session_id` (browser UUID for DAU), `action_type`, `lat/lng`, `sigun_nm`, `place_id/name`; idx on created_at/action/session/sigun. | CONFIRMED |
| `docent_script_cache` | Docent cache (added 260305) | `place_id`, `category` (attraction/restaurant/event), `language` (ko/en), `mode` (brief/detail), `script`, `source` (llm/fallback/cache), `expires_at`; UNIQUE (place_id, category, language, mode); idx `expires_at`. | CONFIRMED |

### 4.2 `daangn.*` (community crawl)

`target_dongs` (city+dong UNIQUE, `dong_slug`), `community_posts` (`post_key` UNIQUE, `source_url` UNIQUE), `community_comments` (FK→posts), `place_mentions_weekly` (UNIQUE place+category+city+week_start; category ∈ 맛집/명소/행사), `crawl_runs`, `crawl_tasks` (per dong×keyword task lifecycle). All CONFIRMED.

### 4.3 `monitoring.*` (ops datamart)

Tables `resource_inventory_snapshot`, `health_metrics_5m`, `telemetry_kpi_5m`, `telemetry_kpi_stream_1m`, `cost_daily`; Power BI consumer views `vw_overview_latest`, `vw_service_health_5m`, `vw_realtime_kpi_1m`, `vw_cost_burn_daily` (MTD running sum), `vw_incidents_5m`. All CONFIRMED.

### 4.4 Ranking materialized views & analytics

- `locallink.v_card_stats_summary` (matview): `SUM(amt) GROUP BY city, card_tpbuz_nm_2`.
- `daangn.v_daangn_stats_summary` (matview): `SUM(mention_count) GROUP BY place_name, city_name`.
- `sql/analytics/hybrid_place_matching.sql`: PostGIS `ST_DWithin` radius candidate → weather-aware indoor filter (uses `is_indoor`, blocks outdoor when any ASA bad-weather flag) → join latest review snippet → order by distance, top-k.

### 4.5 Migration scripts (`sql/migration/Script-*.sql`, dated `260xxx`)

Daangn community (260226) → crawl_tasks (260303) → drop raw_payload + dedup + place_mentions_weekly (260304) → iOS docent cache (260305) → events lat/lng+content_id (260308) → monitoring/Power BI (260309).

## 5. Review Filtering, Normalization, Sentiment, Attributes

### 5.1 Cleaning & food-contamination guard (§7.1 of README "hallucination guard")

- `process_attractions.clean_and_filter_text(raw_html)` / `load_review_pipeline.clean_html(...)`: regex HTML-tag strip + HTML-entity decode + UTF-8 `ignore` safety. CONFIRMED.
- Food-vs-attraction separation: substring exclusion of food-detection terms (a small Korean keyword set) so restaurant reviews do not contaminate attraction docent context. **Method confirmed; exact keyword list is content, not interface — paraphrase, do not copy** (§17). `load_review_pipeline.is_valid_attraction_review(...)` implements the predicate; planner queries additionally use `NOT LIKE` food-term exclusions and a separate `_query_food_attractions(...)` used only in meal slots.
- Daangn dedup: `Script-daangn-community-post-dedup-260304.sql` — `ROW_NUMBER()` `PARTITION BY source_url ORDER BY crawled_at DESC`, keep `rn=1`, remap comment FKs, then unique index `uq_community_posts_source_url`. CONFIRMED.

### 5.2 "Fair ranking" normalization

- **IQR outlier correction** (`process_restaurants.get_ranked_restaurants`, mirrored in `restaurant_docent.rank_restaurants`): `Q1,Q3 = quantile([0.25,0.75])`, upper = `Q3 + 1.5*IQR`, **clip `card_score_raw` only** (daangn score is *not* clipped). CONFIRMED.
- **Min-Max**: `(x-min)/(max-min)` (0 when range=0), with `pd.to_numeric(..., errors='coerce').fillna(0)` to neutralize PG `Decimal`; yields `norm_card`, `norm_daangn`. CONFIRMED.
- **Weighted score**: `0.4*norm_card + 0.6*norm_daangn` (card 40% / daangn 60%), dedup by `restaurant_name` keep-first, **top 10**. CONFIRMED.

### 5.3 Sentiment & attributes (LLM-based)

- Method: Azure OpenAI, `response_format={"type":"json_object"}`, low temperature (~0.2–0.3), up to ~20 reviews concatenated. **No explicit pos/neg sentiment score** is produced; sentiment is implicit in extracted fields. CONFIRMED.
- Output schema persisted to `*_details`: `summary_ko/en`, `atmosphere_ko/en` (3–5 adjectives), `tips_ko/en`. `load_review_pipeline.extract_attraction_content_batch(...)` strips ads/comparisons/food from each review in batches of 10 before analysis. CONFIRMED.

## 6. Vectors / RAG

| Aspect | Evidence | Finding | Tag |
| --- | --- | --- | --- |
| Embeddings | `attraction_reviews.embedding VECTOR(1536)`; `generate_embeddings(_batch)` in collectors | Azure OpenAI **`text-embedding-3-small`** (1536-d); stored via `%s::vector`; batch generation for cost. | CONFIRMED |
| Vector index | none found in legacy DDL | **No `ivfflat`/`HNSW` index** in legacy — vectors stored with default indexing. | CONFIRMED (absence) |
| Retrieval path | `restaurant_docent.fetch_top10_context(...)`, `hybrid_place_matching.sql` | **Legacy RAG is keyword/SQL-based**, not ANN vector similarity: docent context fetches `extracted_keywords` + review snippets by SQL; `hybrid_place_matching` uses PostGIS + a review-snippet subquery. Vectors were *stored* but not *queried* by the runtime docent path. | CONFIRMED |

> **Evolution note (not parity):** LALA-next `rag.knowledge_chunks` *does*
> declare an ivfflat cosine index. Re-implementing legacy parity would *not*
> use ANN; the opportunity is to **exceed** legacy by actually wiring semantic
> retrieval — a deliberate behavior uplift, documented as such.

## 7. Docent Persona / Prompt / TTS (behavior only)

> Clean-room: the persona/prompt **wording is not reproduced**. What follows is
> the observable behavior/interface so LALA-next can re-derive its own copy
> (LALA-next already owns `apps/api/app/services/docent_service.py`).

| Capability | Evidence (symbol) | Behavior | Tag |
| --- | --- | --- | --- |
| Attraction docent | `attraction_docent.generate_docent_script(...)` | Role "LALA" (multi-role local curator/storyteller); KO/EN via `language`; `mode` ∈ {basic, history}; context from `attraction_details` (keywords/atmosphere) + `attraction_reviews` (tips) + `attraction_descriptions` (history/overview). | CONFIRMED (behavior) |
| Restaurant docent | `restaurant_docent.generate_*`, `fetch_tour_context(...)` | Earphone-friendly audio tour, ~2 min / 300–400 words, KO/EN; context hierarchy `restaurant_details` → `gg_restaurant_info` → `restaurant_reviews`; reuses `rank_restaurants` (IQR/MinMax/40-60). | CONFIRMED (behavior) |
| Planner docent | `daily_planner` (하루 동선), `_get_smart_weather_instruction(...)`, `_get_slot_style_hint(...)` | Concise (2–3 sentence) slot narration; weather-aware instruction; time/role style hint (morning/카페/저녁). | CONFIRMED (behavior) |
| TTS engine | `speech_synthesizer.py` (`VOICE_BY_LANGUAGE`), `speech_service.py` | Azure Speech **REST** (no SDK), SSML; output `audio-16khz-128kbitrate-mono-mp3`; per-language neural voices (public Azure voice IDs); max script ~6000 chars; env→vault credential fallback. | CONFIRMED |
| Cache | `docent_script_cache` table, `docent_service` | TTL cache keyed (place_id, category, language, mode); `source` ∈ llm/fallback/cache. | CONFIRMED |
| Fallback | LLM max ~2 retries → rule-based/fallback script; **cached fallback scripts are not reused** (re-attempt LLM next request). | CONFIRMED |

## 8. Day-Plan Constraints / Weather / Location

### 8.1 Day-plan scheduler — `daily_planner.DailyTravelPlanner`

- **4 fixed slots**: 09:00–11:00 오전(attraction) · 11:30–13:00 점심(restaurant) · 13:30–16:00 오후(attraction) · 17:30–19:00 저녁(combo). CONFIRMED.
- Hard constraints: `bsn_state_nm='영업'` (open) filter; meal placement in dedicated lunch/dinner slots; per-day cap 4 slots; PostGIS `ST_DWithin` radius per slot (e.g. 5000m from anchor for meals). CONFIRMED.
- Optimization: **greedy nearest-neighbor**, `_rank_morning_pool_by_anchor(...)` + `_haversine_meters(...)`; anchor (`anchor_lat/lng`) updates after each pick; `used_place_names` dedup prevents repeats. **No global objective function** (not an optimal TSP). CONFIRMED + INFERRED (greedy).
- Meal categories: lunch `점심음식점`; dinner `저녁음식점` + `저녁카페`; plus `food_attraction` role. CONFIRMED.

### 8.2 Weather-aware engine — `weather_planner`

- Thresholds (`_extract_alert_flags`, config values): **PM10 > 80**, **PM2.5 > 35**, **heatwave ≥ 33.0°C**, **coldwave ≤ −12.0°C**, **strong wind ≥ 4.0 m/s**, **precipitation_type > 0**. CONFIRMED.
- Staged fallback: `_get_active_alert_reasons(...)` detects multiple causes; priority `_get_detailed_alert_type` order **rain > cold > heat > pm**; reads `outdoor_status` first, else ASA flags, else `clear_sky_alert`. `_get_indoor_recommendations` (indoor + cafe) vs `_get_outdoor_recommendations`. CONFIRMED.
- Intervention: `check_and_propose_intervention(...)` diffs current vs cached state in `.weather_state_cache.json` (ASA-flag string mode, or bucket mode: Δtemp 5° / Δwind 2 m/s / ΔPM10 20 / ΔPM2.5 10). CONFIRMED.
- Reads `realtime_weather_conditions` by `location LIKE %sigun_nm%`, `record_time DESC LIMIT 1`. CONFIRMED.

### 8.3 Location / region resolution

- GPS → `get_user_sigun_nm(...)`: nearest `tourist_spot_info` via `ST_Distance` → `sigun_nm` → weather + place queries (`WHERE sigun_nm = %s`). **PostGIS-only reverse region resolution** (no external geocoder). CONFIRMED.
- `juso_client` is address EN-translation, **not** the geocoder. CONFIRMED.
- Spatial pattern: `ST_SetSRID(ST_MakePoint(lng,lat),4326)::geography`, `ST_DWithin(...,meters)`, `ORDER BY ST_Distance(...) ASC LIMIT N`. CONFIRMED.

## 9. Food Recommendation

- Ranking: `process_restaurants.get_ranked_restaurants` (card 40% + daangn 60%, IQR on card only, MinMax, top-10) — §5.2. CONFIRMED.
- Filtering: `restaurant_filter.filter_restaurants_by_location` Haversine default 150m, `SKIP_WEIGHTING` if <10. CONFIRMED.
- Meal-slot selection: §8.1 categories + anchor-radius `ST_DWithin`. CONFIRMED.
- Sources: `locallink.v_card_stats_summary` (card) and `daangn.v_daangn_stats_summary` (mentions). CONFIRMED.

## 10. Dashboard / Map / Geolocation / Markers

### 10.1 Power BI hybrid dashboard

- Artifacts: `Arem Arem Azure Ops Semantic Model.{pbip,pbix}` + `.Report/` + `.SemanticModel/` (TMDL `model/relationships/database.tmdl`, table mappings); separate `dashboard/user-dashboard-v1.*` (tables 맛집 추천 / 관광지 추천). CONFIRMED.
- Contract: Power BI **DirectQuery** over `monitoring.vw_*` views (§4.3); hybrid realtime = Diagnostic Settings → Event Hub(raw) → **Stream Analytics** 1-min agg (`infra/stream_analytics/azure_ops_realtime_kpi.saql`) → Event Hub(kpi) → Function → `telemetry_kpi_stream_1m`. CONFIRMED.
- Runbooks: `docs/powerbi-azure-ops-dashboard-runbook-2026-03-09.md`, `docs/azure-ops-hybrid-realtime-runbook-2026-03-09.md`. CONFIRMED.

### 10.2 iOS map clustering & markers (`src/frontend/ios/LALA/LALA/`)

- Policy: `Core/MapMarkerClusteringPolicy.swift` — `shouldUseCluster(pointCount, latitudeDelta, activationLatitudeDelta=0.01, minimumPointCount=12)` activates when `pointCount>=12 AND latitudeDelta>=0.01`; `buildPresentations(...)` buckets into a 5×5 grid by `categoryKey` + quantized lat/lng index, averaging cluster centroids; the selected point is always shown individually. CONFIRMED.
- Max-zoom disable: `Views/MainMapView.swift` `forceClusterMinimumLatitudeDelta = 0.006` — below this span, clustering is off even with many points. CONFIRMED.
- Rendering perf: viewport-bounded `placesForMapAnnotations` (span × padding), **90ms debounce** + cache-key (`spanBucket` precision 0.001 + `viewportBucket`); `PlacePinView` / `ClusterPinView`. CONFIRMED.
- Behavior: `Core/MapGuidanceLogic.swift reduceSelection(...)` (tap-selected deselects + stops speech); `ViewModels/MainMapViewModel.swift` — `PlacesReloadPolicy.shouldReload(distance>=250m)`, auto-docent at 100m + 12s cooldown, weather retry by distance, 0.8s camera-reload suppression. CONFIRMED.

### 10.3 Web map (`src/frontend/web/`)

- Routes (`routes/main_map.py`, `services/map_api_service.py`): `GET /map`, `GET /api/weather` (`force`, `Cache-Control`), `GET /api/places` (scope radius|city, category, language), `POST /api/docent/{script,audio}`. Defaults `lat 37.2636 / lng 127.0286`, `radius 10000`, `limit 50 / max 100`; categories `{all,attraction,restaurant,event}`, scopes `{radius,city}`. CONFIRMED.
- iOS mobile API (`routes/ios_api.py`): `/api/ios/v1/{places,weather,docent/script,docent/audio,health}` + `_require_api_key` (X-API-Key) decorator; weather helpers `_weather_snapshot`, `_compute_outdoor_status`, `_fetch_open_meteo_weather/air_quality`, `_legacy_weather_snapshot`, `_latlon_to_grid` (KMA grid), dust `_dust_grade_code(pm10,pm25)`. CONFIRMED.

> "Attention Insight" (README §4.2) is a **design-time UX methodology reference**; no runtime integration code found. INFERRED.

## 11. Operations / CI / Deploy

- CI: `.github/workflows/oidc.yml` — `workflow_dispatch`, `id-token: write` (OIDC), `azure/login@v2` from `secrets.AZURE_{CLIENT,TENANT,SUBSCRIPTION}_ID`, then reads a Key Vault secret (vault name is a legacy identifier — not ported). `.github/workflows/auto-assign.yml` auto-assigns PR author. CONFIRMED.
- Infra-as-code: `infra/db/init_sql/{01_gis_vectordb,02_daangn_community_schema,03_daangn_target_dongs_seed}.sql`; `infra/docker/{docker-compose.yml,Dockerfile}`; `infra/stream_analytics/azure_ops_realtime_kpi.saql`. CONFIRMED.
- Scripts: `scripts/ingest/*` (daangn bootstrap/run-once, `classify_tourist_indoor`, `enrich_*_en`, `fetch_wiki/tour_descriptions`, `fetch_tourapi_events`, `merge_events`, `redate_events_2026`, `add_missing_spots`); `scripts/monitoring/*` (`deploy_azure_ops_function.sh`, `provision_*`, `powerbi_automation.py`, `powerbi_service_sync.py`, `run_monitoring_pipeline.py`, `snapshot_resources.py`, `collect_*`); `load_gyeonggi_card_spending.sh`, `load_restaurants_data.py`; `sync_ios_api_base_url_from_keyvault.py`; `validate_local.py`, `check_ios_db_schema.py`. CONFIRMED.
- Handoffs: `docs/lala-container-deployment-handoff-2026-03-06.md` (appCommandLine fix), `lala-web-ios-handoff-2026-03-06.md` (web weather 10km-or-10min policy; parallel external calls + TTL cache + stale fallback), `lala-business-logic-phase4-handoff-2026-03-06.md` (vault unification), `keyvault-playbook.md` (portal-only access). CONFIRMED.

## 12. Privacy / Secrets / Error / Fallback

- Secrets: `KeyVaultManager` singleton (§3.3); OIDC secret-zero (no hardcoded secrets; `tests/unit/test_secret_config_contract.py` forbids PG-URL/password-literal patterns). CONFIRMED.
- Privacy: iOS location consent (`MainMapViewModel.configureLocationUpdates`, overlay when denied, stops updates when disabled); `user_action_log` uses **session UUID for DAU (no user ids)** + coords for analytics; README XAI transparency ("why this place") reflected as `recommendationReason(for:)`. CONFIRMED.
- Fallbacks: public-API flakiness ("점검중") handled with `BIGINT` coercion + exceptions; weather fallback chain **DB(`realtime_weather_conditions`) → Open-Meteo → KMA legacy** with `fallback_error` field and stale-dust reuse; docent LLM→fallback (§7); iOS `MapStatus` ∈ {none, noResults, networkError, configurationError}; health `/api/ios/v1/health` returns `{status, db, speech, openai}` (degrades if any subsystem not ok). CONFIRMED.

## 13. Tests

- Framework: **pytest** (~46 unit tests per handoff). CONFIRMED.
- `tests/unit/`: `test_rank_restaurants`, `test_map_api_service` (category/scope/radius + weather cache), `test_vault_manager` (mocked KV/cache/fallback), `test_secret_config_contract`, `test_daangn_seed_sql`, `test_daangn_weekly_crawler`, `test_docent_api_service`, `test_i18n`, `test_web_routes_main_map`. CONFIRMED.
- `tests/`: `llm_review_processor_test`, `naver_api_test`, `weather_change_simulation_test`; `tests/sql/daangn_dedup_smoke_test.sql`; `tests/ios/routes/` (`suwon_10mps_loop.geojson` 567 pts, `suwon_docent_compatible.gpx`); `TEST/api-test.ipynb`; `validate_local.py` (Flask test_client pre-build). CONFIRMED.

## 14. Gap Map → Current LALA-next

LALA-next state per `apps/api`, `sql/canonical`, `apps/workers`, `clients/flutter`, `apps/flutter_app`, `docs/migration`. "Gap" = legacy capability not yet at parity; "Divergence" = intentional different design.

| Legacy capability | Legacy evidence | LALA-next state | Verdict |
| --- | --- | --- | --- |
| Naver review → clean → LLM → embed pipeline | `load_review_pipeline`, `process_*` | `review_mention_ingest`, `review_attribute_batch`, `rag_index` tools exist; the **Naver-blog review pipeline + `clean_and_filter_text` food guard + keyword LLM** appears thin | **Gap** |
| Fair-ranking IQR/MinMax 40-60 | `process_restaurants.get_ranked_restaurants` | `recommendation_scoring.build_place_score` uses a **7-component weighted score** (local-spending 0.22, small-merchant 0.18, …) | **Divergence** (intentional; document weights) |
| Vector ANN retrieval | vectors stored but **not queried** (§6) | `rag.knowledge_chunks` has **ivfflat cosine** | **Opportunity** (exceed legacy by wiring semantic retrieval) |
| Day-plan greedy 4-slot + weather swap | `daily_planner`, `weather_planner` | `planner_service.daily_plan/intervention` exists | Verify parity of slots/thresholds/anchor logic |
| Weather thresholds (PM10>80 etc.) | `weather_planner._extract_alert_flags` | `weather_service` (KMA+AirKorea) | Verify threshold parity |
| Power BI ops dashboard | `monitoring.*` + `.pbix` + ASA | `observability_plan` non-mutating; **no Power BI parity** | **Gap (deferred)** |
| Azure Functions (4 apps, live) | `src/functions/*` | `apps/workers` **dry-run contracts only**; live execution blocked | **Gap (rollout-gated)** |
| iOS clustering policy | `MapMarkerClusteringPolicy` (MapKit) | Flutter **Kakao map** + `map_helpers` (threshold `places>=80 && mapLevel>=10` per visual contract) | **Divergence** (platform; re-derive policy, don't port thresholds) |
| KeyVaultManager singleton | `config/vault_manager.py` | `apps/api/app/core/key_vault.py` + reuse-plan (ONMU isolation) | Parity (with ONMU boundary) |
| Legacy route surface | `/api/ios/v1/*`, `/api/places`… | `/api/v1/*` + `compat.*` views | Parity (retirement plan exists) |

## 15. Confirmed vs Inferred — Summary

- **High-confidence (CONFIRMED, code/SQL-read):** topology/runtime; all four Function triggers/bindings; collector entry symbols; SQL table/column/index shapes; IQR/MinMax/40-60 weights; weather thresholds; day-plan slots/greedy/PostGIS; clustering policy constants; dashboard view contract; tests.
- **INFERRED:** `attraction_details`/`restaurant_details`/`restaurant_reviews` DDL (inferred from INSERT statements); greedy-vs-optimal characterization of the planner; "Attention Insight" being design-only.
- **CONFLICT:** review-ingestion trigger — **timer (code) vs "Storage Queue" (phase-4 handoff doc)**. Treat as timer/CLI batch.

## 16. Open Questions (for LALA-next design, not blocking this doc)

1. Should LALA-next add a Naver-review ingestion worker, or treat reviews as already-ingested `community.posts` + `place_mentions_weekly`?
2. Will LALA-next actually use ANN vector retrieval (uplift), or mirror legacy keyword-only RAG?
3. Confirm whether the legacy phase-4 "Storage Queue trigger" note reflects a never-shipped review-queue design we should *avoid* importing.
4. Port the docent cache TTL semantics (place_id, category, language, mode) — already partly present in `travel.docent_scripts`.

## 17. Clean-Room Boundaries (explicit do-not-carry list)

This spec is **behavior/interface only**. The following must **not** be copied from legacy into LALA-next:

- **Code:** no legacy Python/Swift/SQL source (re-implement behavior; LALA-next already owns FastAPI/Flutter/SQL equivalents).
- **Prompts/persona:** no docent system-prompt text, persona wording, or few-shot examples (re-derive from §7 behavior; LALA-next `docent_service` owns its copy).
- **Assets:** no `.pbix`/`.pbip`/`.tmdl` Power BI files, no `stations.json` beyond public KMA grid data, no images/CSS.
- **Secrets/identifiers:** no connection strings, API keys, Key Vault values, or legacy resource names (vault, registry, resource group, subscription/tenant/client IDs) ported into config.
- **Data:** no review text, no Daangn crawl payloads, no Naver review content, no user-action-log rows.
- **Food-filter keyword list:** the exact Korean exclusion terms are content — paraphrase the method, do not copy the list.

What **may** be re-implemented (interface/schema/contract shapes, already largely present): route families (`/api/v1/*`), JSON envelopes, SQL table/column/contract shapes (canonicalized under `travel/culture/economy/community/rag/ops/compat`), compat views, docent-cache key shape, ranking *method* (not weights-as-legacy-truth).

**ONMU isolation carry-over** (from `docs/migration/source-diagnosis-traceability.md`): the LALA-next Key Vault must not point at the ONMU vault; `int-cors-origins` is the only intentionally mirrored value.
