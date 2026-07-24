# Clean-Room Reimplementation Plan — Day Planner, Weather/Air Response, and Location Resolution

> **Status: PLAN-ONLY.** This document adds no product source and changes no
> infrastructure. It records a domain technical specification and a phased
> reimplementation design for the **daily itinerary + weather/air response +
> location-resolution** domain of LALA-next, derived from audited clean-room
> evidence and a mandatory product presentation.
>
> This plan is **behavior/interface-only**. It never licenses copying legacy
> code, prompts, review text, assets, secrets, resource identifiers, or
> undocumented data. See §18 (domain clean-room boundary) and the upstream
> `legacy-3dt-first-technical-spec.md §17 Clean-Room Boundaries`.

## 0. Provenance, Method, and How to Read This Plan

### Read-only sources consulted

| Source | Location | Role |
| --- | --- | --- |
| Audited clean-room technical spec | `/Users/geondongkim/orca/workspaces/LALA-next/lala-legacy-technical-spec/docs/planning/legacy-3dt-first-technical-spec.md` (read-only, sibling worktree) | Authoritative behavior/interface evidence for the legacy `3dt-1st-Project` ("LALA") system. |
| Audited feature-inventory matrix | `…/lala-legacy-technical-spec/docs/planning/legacy-3dt-first-feature-inventory.md` (read-only) | Slices P1 (day-plan), W1 (weather engine), L1 (location), WA1 (weather collector) — the four slices this domain absorbs. |
| Legacy repo | `/Users/geondongkim/3dt-1st-Project` (read-only) | Re-verified path+symbol evidence for the day planner, weather engine, and location resolution. |
| Current LALA-next | This worktree (`apps/api`, `apps/workers`, `apps/flutter_app`, `clients/flutter`, `sql/canonical`) | The implementation baseline this plan targets with a delta. |
| Product presentation | `/Users/geondongkim/Downloads/LALA-발표자료-v2.pptx.pdf`, slides 5–8 (surrounding slides 1–4, 9–12 for context) | **Mandatory product promise.** Slide text extracted by OCR (`tesseract kor+eng`) to avoid vision-tool hallucination, per the project's ground-truth discipline. |
| Mobile visual contract | `docs/planning/lala-mobile-visual-contract/` (in-repo) | Pixel/copy ground truth for S3 location consent, S4 map, S6 plan, and the truthful-state / forbidden-shortcut rules. |

### Legend

| Tag | Meaning |
| --- | --- |
| **CONFIRMED** | Read directly in legacy code/SQL or in current LALA-next source. Path/symbol cited. |
| **INFERRED** | Deduced from structure or absence of evidence; plausible but not directly observed. |
| **DIVERGENCE** | Legacy and LALA-next intentionally or accidentally differ; the disagreement is recorded and resolved here. |
| **TARGET** | A future design decision this plan proposes. Distinct from evidence. |
| **GATE** | A presentation-derived capability gate that is mandatory and blocks "done." |

### Domain ownership vs. sibling plans

This domain **owns**: the daily-plan orchestrator (`planner_service`), weather/air
alert thresholds and the indoor/outdoor substitution engine, GPS→region
resolution and the manual-region contract, and plan/intervention persistence.
It **consumes** (and does not redefine) the contracts owned by sibling domains:

- **Review-ingestion / restaurant-economy** → place scoring inputs (card spend,
  community mentions) surfaced through `recommendation_scoring.build_place_score`.
- **RAG-docent** → docent generation and TTS; this plan calls `docent_service`
  for planner narration and owns only the *planner-side* narration contract.
- **Dashboard-map** → map-first discovery, markers, and clustering; this plan
  owns the **location-resolution contract** that the map and plan screens share.

Cross-domain contract pins this plan publishes (for siblings to consume):
`/api/v1/plans/daily` slot schema, the weather alert-flag envelope, and the
region-resolution contract (GPS or manual selection → canonical region key).

## 1. Presentation-Derived Capability Gates (mandatory)

The presentation is a **required product promise, not decoration**. The gates
below are derived from OCR-confirmed slide copy and are blocking. Normal flows
must use live DB/API data with honest loading/failure states; Korean and English
are mutually exclusive UI modes; Android and iOS/Web must preserve the same user
workflow (per the dispatch contract and the in-repo
[`01-flow-and-runtime-contract.md`](./lala-mobile-visual-contract/01-flow-and-runtime-contract.md)).

| Gate | Presentation evidence (slide, OCR-grounded) | What "done" requires in this domain |
| --- | --- | --- |
| **G1 — Weather-triggered indoor/outdoor transition** | Slide 8: *"비가 오면 실내 코스로, 날이 개면 골목 산책으로 바뀝니다."* Situation A (비/미세먼지) → 실내 박물관 & 아케이드 상가 중심; Situation B (맑음) → 야외 성곽길 & 골목 테라스 중심. | The same day's plan **visibly** transitions to an indoor route on rain/fine-dust and **visibly** favors outdoor/alley/terrace walking in good weather. The transition is data-driven from the alert flags, not a static copy switch. |
| **G2 — Reasoned substitution, not a bare list** | Slide 8: *"단순 리스트가 아닌 문맥(Context) & 이유(reason)로 … 방문해야 할 명확한 의미를 제시합니다."* Slide 10: *"기존 맵스는 '장소'는 보여주지만, '지금 가야 할 이유'는 모릅니다."* | Every recommended slot and every replacement carries a short, user-requestable reason: **why this place, why now** (weather/air fit, local-economy signal, opening status). |
| **G3 — Location + travel-time + preference surfaced** | Slide 8 production note: *"위치, 이동시간, 선호도 반영 문구 추가."* | Each slot surfaces **location, movement/travel-time, and the user preference** that shaped it, in the active language only. |
| **G4 — Regenerate and listen affordances** | Slide 8 shows `Listen` and `Regenerate` controls on the Daily Plan. | A **regenerate** action (deterministic re-roll with a seed) and a **listen** hand-off to docent/TTS exist on the plan screen; regenerate produces a *different but still valid* plan and records the diff. |
| **G5 — Situation-aware local course** | Slide 6: *"카드 소비 데이터 결합, 당근마켓 로컬 커뮤니티 데이터 활용, 날씨/대기질 데이터를 결합해 상황에 맞는 로컬 코스를 추천"*; weather chip *"Sunny 22°C — Best for outdoor activities."* | The plan fuses live weather/air + scored places + community/local-economy signals into a single situation-appropriate course, with the weather fact shown alongside the plan. |
| **G6 — Honest states only** | In-repo [`01-flow-and-runtime-contract.md`](./lala-mobile-visual-contract/01-flow-and-runtime-contract.md) §F4 and "Forbidden Shortcuts": no mock data, no timer-driven progress, no stale "completed" UI. | Plan pending = one neutral generating card + skeleton timeline (matrix **P0**); plan loaded = real slots/weather/order (matrix **P1**); weather unavailable = concise unavailable state with retry, never a fake value. |
| **G7 — Day-scenario empathy** | Slide 4 persona day: wants a special local experience, hit unexpected rain, could not view outdoors, chose the wrong local spot → 만족도 하락. | The plan must be resilient to **mid-day weather change** (intervention) and must not strand the user on an outdoor plan when conditions turn. |

### Real-device screenshot evidence required

Per the in-repo
[`03-visual-acceptance-matrix.md`](./lala-mobile-visual-contract/03-visual-acceptance-matrix.md),
acceptance is not proven by tests or OCR alone. For this domain, a real-device
(Android) **and** browser/iOS-Web capture is required for at least:

1. **P1 loaded** — a real `/plans/daily` response rendering actual slots,
   weather fact, and order (no skeleton, no placeholder times).
2. **Weather-substitution pair** — the *same* starting day rendered under two
   weather fixtures: (a) rain/fine-dust → indoor-leaning route; (b) clear →
   outdoor/alley/terrace-leaning route. Side-by-side, with the replacement
   reason visible in the active language.
3. **Intervention transition** — a mid-session weather change visibly updating
   the active plan (intervention notice + accepted diff).
4. **Regenerate** — before/after of a regenerate that changes ≥1 slot while
   keeping validity (open hours, no duplicate, within radius).
5. **Location recovery** — permission-denied path still producing a valid plan
   from the manually selected region.

Captures are stored under an ignored `output/` path; no raw device screenshot,
key, or unredacted runtime artifact is committed. "Passed" is not a permitted
implementation-agent verdict — only the design owner may accept.

## 2. Confirmed Legacy Evidence (behavior/interface only)

### 2.1 Day-plan scheduler — `daily_planner.DailyTravelPlanner`

| Capability | Evidence (legacy path · symbol) | Confirmed behavior | Tag |
| --- | --- | --- | --- |
| 4 fixed slots | `src/services/daily_planner.py::_get_time_slots()` | `09:00–11:00 오전 (attraction)`, `11:30–13:00 점심 (restaurant)`, `13:30–16:00 오후 (attraction)`, `17:30–19:00 저녁 (evening_combo)`. | CONFIRMED |
| Open-status filter | `daily_planner.py` (slot fill) | Hard filter `bsn_state_nm = '영업'` before placing a place. | CONFIRMED |
| Radius per slot | `daily_planner.py` | Morning pool `radius_m=8000`; lunch/dinner/afternoon `radius_m=5000`. | CONFIRMED |
| Greedy nearest-neighbor | `_rank_morning_pool_by_anchor()`, `_haversine_meters()` (Earth radius 6,371,000 m) | Rank candidates by distance from a moving anchor; anchor (`anchor_lat/lng`) updates after each pick. **No global objective function** (not optimal TSP). | CONFIRMED + INFERRED (greedy-vs-optimal) |
| Per-day dedup | `self.used_place_names` | Selected place names are excluded from later slots. | CONFIRMED |
| Meal categories | `_recommend_places_for_slot()` | Lunch = `점심음식점`; dinner = `저녁음식점` + `저녁카페`; plus a `food_attraction` role via `_query_food_attractions()` used only in meal slots. | CONFIRMED |
| Planner docent (behavior) | `_get_smart_weather_instruction()`, `_get_slot_style_hint()` | Concise (2–3 sentence) slot narration; weather-aware instruction; time/role style hint. **Prompt wording is content — not copied** (§18). | CONFIRMED (behavior) |

### 2.2 Weather-aware engine — `weather_planner.WeatherTravelPlanner`

| Capability | Evidence (legacy path · symbol) | Confirmed behavior | Tag |
| --- | --- | --- | --- |
| Alert thresholds | `_extract_alert_flags()` | `is_bad_dust`: PM10 > 80 **OR** PM2.5 > 35; `is_heatwave`: temp ≥ 33.0; `is_coldwave`: temp ≤ −12.0; `is_strong_wind`: wind ≥ 4.0 m/s; `is_rain_snow`: precipitation_type > 0. | CONFIRMED |
| Alert priority | `_get_detailed_alert_type()` | Priority tuple `('rain_alert', 'cold_alert', 'heat_alert', 'pm_alert')`; multi-cause reasons concatenated via `_get_active_alert_reasons()`. | CONFIRMED |
| Indoor/outdoor proposals | `_get_indoor_recommendations()`, `_get_outdoor_recommendations()` | Indoor = `is_indoor=TRUE` attractions + cafes (`bizcond_div_nm_info='까페'`), top 5 by distance. Outdoor = `is_indoor=FALSE`, top 5 by distance, fallback to all attractions if <3 found. | CONFIRMED |
| Intervention diff | `check_and_propose_intervention()`; cache file `.weather_state_cache.json` | ASA-flag string mode `"{rain}_{wind}_{heat}_{cold}_{dust}"`; bucket mode (no ASA flags) `temp//5`, `wind//2`, `pm10//20`, `pm25//10` → `"{precip}_{tb}_{wb}_{pm10b}_{pm25b}"`. Proposes intervention when the state string changes. | CONFIRMED |
| Region resolution | `get_user_sigun_nm()` | GPS → nearest `tourist_spot_info` via `ST_Distance` → `sigun_nm`. **PostGIS-only**, no external geocoder. | CONFIRMED |
| Weather read | `get_current_location_weather()` | `realtime_weather_conditions` by `location LIKE '%{sigun}%'`, `record_time DESC LIMIT 1` (trailing 시/군 stripped). | CONFIRMED |

### 2.3 Weather/air collector — `src/functions/weather_air_func/`

| Aspect | Evidence | Confirmed behavior | Tag |
| --- | --- | --- | --- |
| Trigger | `function_app.py::WeatherAirDataCollector`, `@app.timer_trigger` | Schedule `"0 0 */3 * * *"` (every 3 h). | CONFIRMED |
| Sources | KMA + AirKorea; `stations.json`; `_latlon_to_tm()` (pyproj) | ~35 Gyeonggi cities with `lat/lon` and KMA grid `nx/ny`. | CONFIRMED |
| Sink | Event Hub `[weather/air telemetry hub]` | Enriched rows emitted to an event hub. | CONFIRMED |

### 2.4 Schema and indoor flag

- `realtime_weather_conditions` (`sql/ddl/realtime_weather_conditions.sql`):
  `location`, `record_time`, `temperature`, `precipitation_type`, `pm10/pm25`,
  ASA flags `is_rain_snow/is_bad_dust/is_heatwave/is_coldwave/is_strong_wind`
  (BIGINT), `outdoor_status`; index `(location, record_time DESC)`. CONFIRMED.
- `is_indoor` is **not** in base place DDL; it is produced by
  `scripts/classify_tourist_indoor.py` (a batch LLM classifier, "GPT-4o-mini")
  and consumed by `sql/analytics/hybrid_place_matching.sql`, which keeps only
  `is_indoor=TRUE` places when a weather alert is active. CONFIRMED.
- Legacy **opening-status** model is the single `bsn_state_nm` column
  (`'영업'/'폐업'`), **not** granular opening hours. CONFIRMED.

### 2.5 Web weather policy and dust grades

- `src/frontend/web/routes/ios_api.py`: `_WEATHER_CACHE_TTL_SEC=180`,
  `_WEATHER_CACHE_STALE_SEC=900`, `_WEATHER_CACHE_COORD_PRECISION=3`;
  `ThreadPoolExecutor(max_workers=4)` for parallel Open-Meteo weather + air calls.
- `_weather_snapshot()`: in-memory cache → DB (`realtime_weather_conditions`) →
  parallel Open-Meteo → KMA legacy, with a `fallback_error` field and stale
  reuse on total failure. CONFIRMED.
- `_dust_grade_code(pm10, pm25)`: PM10 good ≤30 / normal ≤80 / bad ≤150 /
  very_bad >150; PM2.5 good ≤15 / normal ≤35 / bad ≤75 / very_bad >75.
  CONFIRMED.
- `_latlon_to_grid()` KMA conversion constants: RE=6371.00877, GRID=5.0,
  SLAT1=30.0, SLAT2=60.0, OLON=126.0, OLAT=38.0, XO=43, YO=136. CONFIRMED.

## 3. Inferred / Open-Resolution Items

| Item | Status | Resolution in this plan |
| --- | --- | --- |
| Per-day slot cap constant | NOT-FOUND in legacy (no explicit max-places-per-day). | TARGET: cap is config (`plan.max_slots_per_day`, default 4) and enforced in the orchestrator. |
| Opening hours source | Legacy used `bsn_state_nm` only; no hour ranges. The presentation requires slot-window fit. | TARGET: new `place_operating_hours` data + an "open during slot window" predicate (§6.4). |
| Travel-time provider | Legacy used Haversine distance only (`_haversine_meters`); presentation note adds 이동시간. | TARGET: travel-time cache + provider with Haversine fallback (§6.5). This **exceeds** legacy. |
| Greedy vs. optimal | Characterized greedy; no global objective. | TARGET: keep deterministic greedy + anchor (parity) and document it is not TSP-optimal; do not claim optimality. |
| Intervention history persistence | Legacy used a process-local `.weather_state_cache.json` file. | TARGET: DB table `travel.weather_state_cache` (per region/session) so history survives restarts (§6.11). |
| `is_indoor` provenance | Legacy: batch classifier script. | TARGET: re-derive via the model policy (nano classification + mini recheck) into `travel.place_enrichments` (§9). |
| ANN/vector retrieval | Out of this domain's scope (RAG-docent owns it). | Not used by the planner; planner uses PostGIS + scoring only. |

## 4. Current LALA-next State (implemented evidence)

### 4.1 Day planner — `apps/api/app/services/planner_service.py`

- `daily_plan(request)` (`planner_service.py:10`) fetches `current_weather` +
  `list_places(category="all")` and returns a **minimal 2-slot** plan. Slots
  come from `_daily_plan_slots()` (`:78`): a `morning` slot ("첫 장소 추천" /
  "Start near a landmark") taking `place_candidates[0]`, and an `afternoon`
  slot ("날씨에 맞춰 조정" / "Adjust by weather") carrying only
  `weather["outdoor_status"]`. **No time windows, anchor, dedup, open-hours
  filter, meal roles, or scoring-driven assignment.** CONFIRMED.
- `intervention(*, lat, lng, radius_m)` (`:35`) sets `should_intervene` from
  `weather["outdoor_status"] == "bad"` and returns a single nearest `candidate`
  plus templated `_intervention_reason` / `_recommended_action`. **No
  indoor/outdoor filtering, no multi-place proposal, no diff/history.** CONFIRMED.
- Routes (`apps/api/app/routers/v1.py`): `POST /api/v1/plans/daily`,
  `GET /api/v1/plans/intervention`, `GET /api/v1/weather`. Envelopes
  `LalaDailyPlan` (`slots`, `weather`, `source`, `request_hash`, `cache_key`),
  `LalaIntervention`, `LalaWeather`. CONFIRMED.

> **Gap (P1 slice):** LALA-next ships a 2-slot stub; the legacy (and the S6
> plan screen) expects a full timed day. This is the central delta of this plan.

### 4.2 Weather — `apps/api/app/services/weather_service.py`

- `current_weather(lat, lng)` (`:75`) sources **KMA ultra-short nowcast +
  AirKorea sido realtime**; **Open-Meteo is not present** (divergence from the
  legacy web fallback chain). Fallback: KMA+AirKorea → AirKorea-only →
  unavailable. In-memory cache, 20-min TTL.
- Thresholds (`_kma_outdoor_status` `:574`): `precipitation != "0"` → bad;
  `temp ≥ 33 or ≤ −12` → bad; **`wind ≥ 14 m/s` → bad**. Dust:
  `build_dust_payload` (PM10 > 80 bad, PM2.5 > 36 bad).
- `_merge_outdoor_status_with_dust()` (`:478`): bad if weather bad **or** dust
  grade in {bad, very_bad}. **The API collapses the five ASA flags into a
  single `outdoor_status` string.** CONFIRMED.
- Refresh worker: `apps/api/app/services/weather_observation_refresh.py`
  (`fetch_weather_targets`, `fetch_weather_observations`,
  `insert_weather_observations`) — refresh functions exist but have **no live
  schedule** (worker-contract only). CONFIRMED.

> **DIVERGENCE (W1 slice):** (1) Legacy emits explicit per-flag booleans
> (`is_strong_wind` at wind ≥ 4.0 m/s); LALA-next returns one `good/bad` and
> uses wind ≥ 14. (2) PM2.5 dust cutoff 35 (legacy) vs 36 (LALA-next). Both are
> resolved by making thresholds config and emitting explicit flags (§6.8).

### 4.3 Location / region resolution

- `_sido_name_for_coordinate(lat, lng)` (`weather_service.py:484`): bounds match
  against `_PROVINCE_BOUNDS` (17 provinces), fallback to nearest reference
  point by squared Euclidean distance → `province.short_ko` (e.g., "경기").
  **Province-level only; no 시/군 (sigun_nm) resolution.**
- `db_repository.fetch_nearest_region_labels()` (`:581`): PostGIS
  `ST_Distance(ST_MakePoint(lng,lat), …::geography)` → nearest places'
  `region_ko/region_en`. Used for AirKorea station matching.
- `region_catalog.py` (`PROVINCES`, `REGION_NAME_EN`, `PROVINCE_BY_KO`) parses
  `apps/flutter_app/lib/manual_location_options.dart` for province metadata.
- Flutter: `manual_location_options.dart` (17 provinces, ~220 options) +
  `ManualLocationSheet`; `location_consent_page.dart` exposes `현재 위치 사용` /
  `지역 직접 선택` / `나중에 하기` (matches S3). CONFIRMED.

> **Gap (L1 slice):** resolution stops at province. The plan/weather queries
> need 시/군-level region keys to mirror legacy `sigun_nm` precision. This plan
> defines a canonical region-resolution contract (§6.2) without importing the
> legacy `juso`/`kterm` clients.

### 4.4 SQL canonical schemas

- `travel.weather_observations` (`sql/canonical/020_travel_domain_tables.sql`):
  `location_name`, `temperature_c`, `precipitation_type`, `pm10/pm25`, ASA
  flags as **boolean**, `observed_at/collected_at`; index
  `(location_name, observed_at DESC)`. Cleaner than legacy (booleans vs
  BIGINT). **No `wind_speed` column; no `outdoor_status` column (computed).**
- `travel.places` (`sql/canonical/010_travel_core_tables.sql`): `place_id`
  UNIQUE, `name_ko/en`, `category` CHECK (attraction/restaurant/event/culture_venue),
  `region_name_ko/en`, `province_code/city_code`, `lat/lng`, **`is_indoor`
  boolean**, GIST `geog` index. **No `bsn_state`, no opening-hours columns.**
- `travel.place_enrichments`: `enrichment_type`, `attributes jsonb`,
  `confidence`, `source_method`, `model_name`, `prompt_version` — the natural
  home for hours + indoor classification provenance.
- `travel.docent_scripts`: cache key `(place_id, category, language, mode)` +
  `expires_at` — already present (docent cache parity).
- `travel.place_events`: `starts_at/ends_at`.
- `travel.latest_weather` view: `DISTINCT ON (location_name) … ORDER BY
  observed_at DESC`.
- **Missing for this domain:** operating hours, travel-time cache, plan
  snapshots, intervention/weather-state history, region catalog table,
  weather-threshold config.

### 4.5 Flutter client

- `apps/flutter_app/lib/features/plan/presentation/pages/plan_page.dart` loads
  `createDailyPlan()` + `getIntervention()` in parallel; renders
  `PlannerOverviewCard` + `PlanSlotTile` list. (No dedicated
  `planner_loading_card.dart` — uses inline skeleton; Slice E of the visual
  contract is the in-flight work to formalize P0/P1.)
- Weather widgets under `features/weather/widgets/` (`weather_hero_card`,
  `weather_fact`, `weather_forecast_chart_card`, `weather_unavailable_card`,
  `weather_sheet_content`, `weather_map_pill`).
- API client `clients/flutter/lib/lala_api_client.dart`: `createDailyPlan()`
  (plannerTimeout 16 s), `getIntervention()`, `getWeather()` via Dio.
  CONFIRMED.

### 4.6 Worker contract — `apps/workers/app/contracts.py`

A **portable, provider-agnostic** worker contract already exists:
`WorkerJobDefinition`, `RetryPolicy`, `IdempotencyPolicy`, `PoisonPolicy`. The
`weather-refresh` job (`contracts.py:89`) declares `trigger="schedule/manual"`,
`writes=("travel.weather_observations",)`, retry
`exponential: 30s, 2m, 5m`, idempotency key
`source_system + region + observed_at` (upsert latest, 24 h window), poison →
`ops.dependency_checks status=failed`, and an operator action that keeps the
API on offline/latest-cache fallback. Live execution is gated behind
`ALLOW_WORKER_MUTATION=1` and currently raises `not_implemented`
(`contracts.py:264`) — **Azure Functions / Event Hub producers are deliberately
not ported in Wave 1.** This is the contract this plan reuses (§8).

### 4.7 Scoring — `apps/api/app/services/recommendation_scoring.py`

`build_place_score()` computes a **7-component weighted score**
(`local_spending 0.22`, `small_merchant 0.18`, `demand_dispersion 0.20`,
`culture_relevance 0.15`, `weather_fit 0.10`, `review_quality 0.10`,
`accessibility 0.05`) with category priors and deterministic 0–1 normalization.
**It is not wired into `daily_plan` slot assignment today** (only surfaced via
`include_scores` on places). `db_repository.fetch_places` orders by
`FLOOR(distance_m/500.0)` bucket then score — no greedy route optimization.

> **DIVERGENCE (R2 slice, owned by restaurant-economy):** the 7-component score
> is an intentional redesign of the legacy `0.4·card + 0.6·daangn` weighting.
> This plan **consumes** `build_place_score` and adds the `weather_fit`
> coupling (§6.7); it does not redefine the weights.

### 4.8 Tests / eval

- `apps/api/tests/test_planner_service.py` (15 tests: `_combined_source`,
  `_intervention_reason/_recommended_action`, `_daily_plan_slots` shape,
  `daily_plan_identity` hash/cache_key, weather/place mocks).
- `test_recommendation_scoring.py`, `test_weather_observation_refresh.py`.
- **No dedicated `current_weather` threshold test; no region-resolution test.**
- Flutter: `plan/plan_page_test.dart`, `weather/weather_helpers_test.dart`,
  `weather/weather_map_pill_test.dart`.

## 5. Target Architecture (LALA-next-native, not a port)

```
Flutter (plan screen)
  └─ Dio → POST /api/v1/plans/daily  (DailyPlanRequest: lat,lng,radius_m,language, travel_type?, seed?)
        └─ planner_service.daily_plan
              ├─ resolve_region(lat,lng)  ──► canonical region key (sigun/city)   [§6.2]
              ├─ current_weather(lat,lng) ──► weather + explicit ASA flags        [§6.8]
              ├─ list_places(... )        ──► PostGIS ST_DWithin candidates       [§6.2]
              ├─ build_place_score + weather_fit coupling                         [§6.7]
              ├─ build_day(slots=4, anchor greedy, open-hours, meal roles, dedup) [§6.3–6.6]
              ├─ weather_aware_substitute(indoor↔outdoor)                         [§6.9]
              └─ planner narration (docent_service, mini)                         [§9]
  └─ GET /api/v1/plans/intervention  (region/session key) ──► diff vs last accepted [§6.11]
  └─ POST /api/v1/plans/regenerate   (seed bump)         ──► deterministic re-roll [§6.10]
```

- **Runtime:** FastAPI + PostgreSQL/PostGIS (+ pgvector available but unused by
  the planner). No Azure Functions are ported; the only timer/queue need
  (weather refresh) is expressed through the existing portable worker contract
  (§8).
- **Determinism:** every plan carries `request_hash`/`cache_key`
  (`generation_identity`); a regenerate bumps the seed and is reproducible.
- **Honest degradation:** weather fallback chain (DB latest → KMA+AirKorea →
  AirKorea-only → unavailable) and places fallback (`db`/`public_mvp_snapshot`/
  `mixed`/`unavailable`) are already composed in `planner_service`; this plan
  preserves and extends them with explicit flag-level reasons.

## 6. Domain Design — by Capability

### 6.1 Permission-first current location + nationwide manual selection

- **Contract:** current location is **opt-in**; manual nationwide selection is
  **always reachable** and never hidden behind a permission failure (matches S3
  in [`00-visual-ground-truth.md`](./lala-mobile-visual-contract/00-visual-ground-truth.md)
  §5 and matrix O4/O5). `나중에 하기` completes onboarding on the defined
  default region.
- **Privacy:** raw GPS is **not persisted**. The API receives `(lat,lng)` per
  request; only the resolved canonical region key and a non-identifying session
  id are logged (parity with legacy session-UUID DAU model; no user ids).
- **Acceptance:** denial → compact notice with `재시도` + `지역 선택` (matrix
  O5/M4); a valid plan still returns from the manually selected region.

### 6.2 PostGIS proximity & region resolution

- **GPS → region:** extend resolution past province to **시/군**. Reuse the
  existing PostGIS pattern (`ST_SetSRID(ST_MakePoint(lng,lat),4326)::geography`,
  `ST_DWithin`, `ORDER BY ST_Distance`). Canonical region key =
  `(province_code, city_code)` from `travel.places`/`region_catalog`, with
  manual selection mapping directly to the same key.
- **TARGET: `travel.region_catalog` table** (province/city codes, KO/EN labels,
  `tour_api_area_code`, AirKorea sido mapping) sourced from the in-code
  `region_catalog.py`/`manual_location_options.dart` so resolution is data, not
  regex parsing.
- **No external geocoder** is required (parity with legacy PostGIS-only
  resolution); address-translation (KO→EN) remains a sibling-domain concern and
  is explicitly **not** the geocoder.

### 6.3 Four-slot day structure

- **TARGET:** restore the four timed slots as the planner's spine:
  `09:00–11:00 오전(attraction)`, `11:30–13:00 점심(restaurant)`,
  `13:30–16:00 오후(attraction)`, `17:30–19:00 저녁(combo)` — windows/roles as
  config (`plan.slot_windows`) so they are tunable without code changes.
- Each slot carries: `period`, `window` (start/end), `role`, `place` (nullable),
  `weather_fit`, `distance_m`, `travel_time_min`, and a `reason` short string
  (active language only).
- **Cap:** `plan.max_slots_per_day` (default 4) enforced by the orchestrator.

### 6.4 Opening hours

- **TARGET: `travel.place_operating_hours`** (place_id, weekday, open_time,
  close_time, break windows, source, confidence) or structured JSONB in
  `travel.place_enrichments`. Predicate `open_during(slot.window)` filters
  candidates before placement (replaces legacy `bsn_state_nm='영업'`).
- **Source:** public operating data + LLM extraction (model policy §9). When
  hours are unknown, the place is **down-ranked, not silently dropped**, and the
  reason copy says hours are unconfirmed (honesty rule G6).
- **Meal-slot fit:** restaurants must be open across the meal window; attractions
  across the visit window.

### 6.5 Travel-time / anchor constraints

- **TARGET: `travel.travel_time_cache`** (from_place_id, to_place_id, mode,
  seconds, distance_m, fetched_at, source) keyed by an ordered pair + mode.
- Greedy anchor walk (parity with legacy `_rank_*_by_anchor`): after each pick
  the anchor moves to the chosen place; the next slot's candidates are ranked by
  travel time from the anchor, then by score.
- **Provider:** a pluggable travel-time source (e.g., Kakao Mobility / OSRM) with
  a **straight-line Haversine fallback** (legacy parity) when quota is exhausted
  or the provider is unavailable. Mode defaults to walking for tourism; the
  presentation's "이동시간" (G3) is surfaced per slot.
- **Legal:** provider ToS is recorded; quota budgeted (§17); fallback keeps the
  plan usable without the paid provider.

### 6.6 Meal slot integration

- Lunch slot restricted to meal categories (parity: `점심음식점` analogue via
  `category='restaurant'` + meal sub-tags); dinner allows restaurant + cafe
  (combo). A `food_attraction`-style role may occupy a meal slot when the user
  preference / travel type favors a food route (slide 6 "local food route").
- Meal places must satisfy `open_during(meal window)` and the per-slot radius
  (default 5,000 m, configurable; morning pool 8,000 m — legacy evidence of
  intent, reaffirmed as config).

### 6.7 Deterministic candidate scoring

- **Wire `build_place_score` into slot assignment.** Today scoring is parallel
  to the planner; the target ranks each slot's candidate pool by a deterministic
  blend of **score** (7-component, owned by restaurant-economy) and
  **weather_fit** (this domain) and **travel_time** from the anchor.
- **weather_fit coupling:** `build_place_score` already exposes a
  `weather_fit` component; the planner materializes it from the live ASA flags
  and `is_indoor` (outdoor places penalized when any outdoor-blocking flag is
  active; indoor places favored).
- Determinism: same `(request, seed)` → same plan; tie-breaking is a stable
  secondary sort (place_id) so regenerate is reproducible.

### 6.8 Weather/air alert thresholds as config (resolving the divergence)

- **TARGET: `travel.weather_threshold_config`** (or app config) holding every
  threshold: `pm10_bad`, `pm25_bad`, `heatwave_c`, `coldwave_c`,
  `strong_wind_ms`, plus dust grade bands. Defaults documented with their
  evidence:
  - PM10 > 80, PM2.5 > 35, heatwave ≥ 33, coldwave ≤ −12, precip > 0 — **legacy
    evidence, reaffirmed.**
  - **Wind:** legacy flagged at ≥ 4.0 m/s; LALA-next currently uses ≥ 14. This
    is a genuine disagreement. **Decision (TARGET):** introduce a **two-tier**
    wind config — a soft `discomfort_wind_ms` (default 7, "outdoor activity
    discomfort," leans toward legacy intent without over-flagging gentle
    breezes) and a hard `advisory_wind_ms` (default 14, KMA strong-wind advisory
    parity with current code). Both are config; the value is a deliberate,
    documented choice, not a copied threshold.
  - PM2.5 dust cutoff: align to **35** (legacy) and reconcile with
    `build_dust_payload`; record the chosen value in config.
- **TARGET: emit explicit per-flag booleans** (`is_rain_snow`, `is_bad_dust`,
  `is_heatwave`, `is_coldwave`, `is_strong_wind`) **plus** the summary
  `outdoor_status` in `/api/v1/weather` and inside the plan envelope, so the UI
  can render the specific reason (G2/G3) and the planner can stage substitutions
  by priority `rain > cold > heat > pm` (legacy priority, reaffirmed).

### 6.9 Indoor/outdoor replacement proposals (the G1 marquee)

- **TARGET: `weather_aware_substitute(active_flags, slot)`** that, when an
  outdoor-blocking flag is active, proposes indoor replacements (attractions
  with `is_indoor=TRUE` + cafes) ranked by score + travel time; in clear weather
  it favors outdoor/alley/terrace walking (outdoor attractions, terrace/cafe
  roles). This is the direct implementation of slide 8's two situations.
- Each replacement records **why** (which flag), **where** (location), **how
  far/long** (travel-time), and **which preference** drove it (travel type /
  food-route) — the four surfaced attributes from G3.
- **is_indoor provenance:** re-derive via nano classification + mini recheck
  into `travel.place_enrichments` (§9); never copy the legacy classifier script.

### 6.10 Regenerate vs. accept flow

- **TARGET: `POST /api/v1/plans/regenerate`** bumps the seed (deterministic
  re-roll) and returns a new plan that still satisfies all hard constraints
  (open hours, no duplicate, within radius, meal roles). The client diffs old vs
  new and highlights changed slots.
- **Accept** persists the chosen plan as a `travel.plan_snapshots` row (§7) and
  seeds the intervention baseline. **Regenerate does not mutate the accepted
  baseline until the user accepts.**
- Slide 8's `Listen` control hands the slot/plan narration to docent + TTS
  (RAG-docent domain; this plan owns only the planner→docent hand-off shape).

### 6.11 Intervention diff/history

- **TARGET: `travel.weather_state_cache`** (region_key, session_id, state_hash,
  bucket_vector, observed_at, proposed_at, accepted_at, diff jsonb) replacing
  the legacy `.weather_state_cache.json` file so history survives restarts and
  is auditable.
- `GET /api/v1/plans/intervention` returns the diff vs the last accepted state
  (ASA-flag string mode + bucket mode parity) with `should_intervene`, the
  multi-cause `reason`, `recommended_action`, and **indoor/outdoor replacement
  proposals** (upgrades the current single-nearest-place behavior).
- **History** is queryable per session/region for the transition screenshot
  (acceptance item 3) and for observability.

### 6.12 Accessibility & localized copy

- KO and EN are **mutually exclusive** outside the S2 choice control (in-repo
  [`00-visual-ground-truth.md`](./lala-mobile-visual-contract/00-visual-ground-truth.md)
  §2 and [`01-flow-and-runtime-contract.md`](./lala-mobile-visual-contract/01-flow-and-runtime-contract.md)
  §4). Plan/weather/reason copy is sourced from the active language only.
- Slot/reason strings carry semantic labels; weather alerts announce a concise
  status change; selected/active states are conveyed by text + border/fill, not
  color alone (accessibility contract §5). No truncation of selected labels at
  360 dp / 200 % text scale.
- Reason copy is **re-derived** by LALA-next (LALA-next `docent_service` owns
  copy); legacy planner-docent wording is **not copied** (§18).

## 7. Schema and Migration Contracts

All migrations are **additive and idempotent** (`CREATE TABLE IF NOT EXISTS` /
`ADD COLUMN IF NOT EXISTS`), consistent with the canonical SQL style.

| New/revised object | Purpose | Key fields |
| --- | --- | --- |
| `travel.region_catalog` | Data-driven region resolution | `province_code`, `city_code`, `name_ko/en`, `tour_api_area_code`, `airkorea_sido` |
| `travel.place_operating_hours` | Open-during-slot predicate | `place_id`, `weekday`, `open_time`, `close_time`, `source`, `confidence` |
| `travel.travel_time_cache` | Anchor travel-time memoization | `from_place_id`, `to_place_id`, `mode`, `seconds`, `distance_m`, `source`, `fetched_at` |
| `travel.plan_snapshots` | Accepted plan history | `id`, `session_id`, `region_key`, `seed`, `slots jsonb`, `weather_ref`, `accepted_at` |
| `travel.weather_state_cache` | Intervention diff baseline + history | `region_key`, `session_id`, `state_hash`, `bucket_vector`, `observed_at`, `proposed_at`, `accepted_at`, `diff jsonb` |
| `travel.weather_threshold_config` | Alert thresholds as config | `pm10_bad`, `pm25_bad`, `heatwave_c`, `coldwave_c`, `discomfort_wind_ms`, `advisory_wind_ms`, `precip_flag` |
| `travel.weather_observations` (revise) | Add `wind_speed` + explicit flag provenance | `wind_speed double precision` added; flags remain boolean |

### API contracts (envelope deltas — backward-compatible additions)

- `POST /api/v1/plans/daily` → `LalaDailyPlan` adds: `slots[]` with
  `window/role/place/weather_fit/distance_m/travel_time_min/reason`,
  `region_key`, `seed`, and `weather.alert_flags{is_rain_snow,…}`.
- `POST /api/v1/plans/regenerate` (new) → same envelope, new seed, changed-slot
  diff.
- `GET /api/v1/plans/intervention` → adds `proposals[]` (indoor/outdoor
  replacements with reason/location/travel-time/preference) and `diff` +
  `history_token`.
- `GET /api/v1/weather` → adds explicit `alert_flags` alongside `outdoor_status`.
- `DailyPlanRequest` adds optional `travel_type`, `seed`, `session_id`.

## 8. Portable Worker Contract (no Azure Function port)

The weather-refresh need is met by the **existing** `weather-refresh`
`WorkerJobDefinition` (`apps/workers/app/contracts.py:89`), not a ported Azure
Function. The plan refines it as follows (still behind `ALLOW_WORKER_MUTATION`):

- **Trigger:** `schedule/manual`. The portable contract deliberately leaves the
  scheduler pluggable — a container cron / hosted scheduler invokes the job on
  the legacy cadence (every 3 h) without binding to Azure Functions. No queue is
  needed for weather refresh.
- **Writes:** `travel.weather_observations` (one row per region/observed_at).
- **Retry/Idempotency/Poison:** unchanged from the existing contract
  (exponential 30s/2m/5m; key `source_system + region + observed_at`, upsert
  latest, 24 h window; poison → `ops.dependency_checks status=failed`, operator
  keeps API on latest-cache fallback).
- **Sources:** KMA + AirKorea (reaffirmed); Open-Meteo added **only as a
  fallback tier** to restore the legacy DB→Open-Meteo→KMA chain (the current
  LALA-next chain omits Open-Meteo). Each row records its `source_system`.
- **Legal:** KMA/AirKorea terms and attribution respected; the public grid
  conversion constants (§2.5) are interface facts, retained.

> A timer/queue is needed **only** for weather refresh in this domain; community
> ingest and ops rollup belong to sibling domains and are not added here.

## 9. Model Policy

Per the dispatch contract: **`gpt-5.4-nano`** for high-volume
extraction/normalization/classification; **`gpt-5.4-mini`** for low-confidence
recheck and all docent generation/QA. Mapping for this domain:

| Task | Model | Rationale |
| --- | --- | --- |
| Place **indoor/outdoor classification** (re-deriving `is_indoor`) | `gpt-5.4-nano` (batch), `gpt-5.4-mini` recheck on low confidence | High-volume classification (analogous to "ad classification"); mini recheck per policy. |
| **Opening-hours extraction/normalization** | `gpt-5.4-nano`, `gpt-5.4-mini` recheck | High-volume normalization of semi-structured data. |
| **Planner slot narration + replacement-reason copy** | `gpt-5.4-mini` | Docent generation/QA — "all docent generation." |
| Intervention reason templating | rule-based + `gpt-5.4-mini` for prose polish | Deterministic core; mini only for natural-language reason. |

All LLM outputs are stored with `source_method`, `model_name`, `prompt_version`,
and `confidence` (the `travel.place_enrichments` shape already supports this).
**Prompt/persona text is never copied from legacy** (§18); LALA-next derives its
own copy. Model identifiers are referenced by policy role; actual deployed IDs
are resolved at runtime from the secrets boundary.

## 10. Legal, Data-Source, and Privacy Constraints

- **Weather/air sources:** KMA and AirKorea are public services with terms and
  attribution requirements; Open-Meteo is used only as a fallback tier within
  its quota. No `stations.json` beyond public KMA grid data is carried (§18).
- **Location:** permission-first, raw GPS not persisted; only canonical region
  key + non-identifying session id logged. Manual selection never gated on
  permission. (Parity/enhancement over legacy session-UUID analytics.)
- **Travel-time provider:** ToS recorded; quota-budgeted; Haversine fallback
  keeps the plan functional without the provider.
- **Opening-hours data:** sourced from public data + LLM extraction; provenance
  and confidence stored so an unconfirmed hours claim is surfaced honestly.
- **Identity:** stays behind the Logto boundary; no direct token path is added.

## 11. Observability

- `GET /api/v1/plans/daily` and `/intervention` emit structured logs with
  `region_key`, `source` (db/public_mvp_snapshot/mixed/unavailable), weather
  `fallback_error`, and the alert-flag vector.
- Dependency checks flow to `ops.dependency_checks` (worker contract already
  routes weather failures there); plan/intervention acceptance and regenerate
  events are logged for the transition screenshot and for funnel analysis.
- Metrics: plan latency (p50/p95), weather fallback-tier hit rate, indoor/outdoor
  substitution rate, regenerate→accept conversion, travel-time fallback rate.

## 12. Retry / Idempotency / Failure Modes

- **Determinism:** `(request, seed)` is reproducible; `request_hash`/`cache_key`
  already exist. Regenerate is a seed bump, not a random reshuffle.
- **Weather fallback chain:** DB latest → KMA+AirKorea → AirKorea-only →
  unavailable, with stale reuse and explicit `fallback_error`. The plan never
  fabricates weather; on "unavailable" it degrades to a distance/score plan and
  says so (G6).
- **Places fallback:** `db`/`public_mvp_snapshot`/`mixed`/`unavailable` already
  composed; an `unavailable` plan returns an honest empty state, not mock slots.
- **Travel-time:** provider failure → Haversine fallback (logged); the plan still
  returns.
- **Worker:** weather-refresh idempotency (region+observed_at upsert) prevents
  duplicate rows on retry; poison path leaves the API on latest-cache fallback.

## 13. Test / Eval Fixtures

- **Unit:** slot builder (4 windows + roles), `open_during` predicate,
  `weather_aware_substitute` (rain→indoor, clear→outdoor), threshold config
  resolution (including wind two-tier), region resolution (GPS→city), greedy
  anchor + dedup, regenerate determinism, plan/intervention identity hashing.
- **Integration (PostGIS):** `ST_DWithin`/`ST_Distance` candidate selection and
  nearest-region resolution against a fixture DB.
- **Eval (correctness of the G1 tie):** a labeled fixture set of
  `(weather condition → expected indoor/outdoor lean)` to assert the transition
  is data-driven and matches slide 8's two situations; low-confidence LLM
  classifications rechecked by mini.
- **Flutter widget:** matrix **P0** (one generating card + skeleton, no timer
  progress) and **P1** (real slots/weather/order); weather available/unavailable
  states; regenerate before/after; intervention transition.
- **Route sim:** a GPX/fixture route (parity with legacy `suwon_*` fixtures) to
  exercise intervention across a simulated weather change.
- Legacy test fixtures are **not copied**; LALA-next fixtures are authored fresh.

## 14. Acceptance Criteria (screen / API / DB)

Implemented evidence vs. future target is split explicitly. "Impl" = exists
today on `main`; "Target" = this plan.

| Capability | Impl today | Target acceptance | Layer |
| --- | --- | --- | --- |
| 4 timed slots with roles | 2-slot stub | 4 slots, configurable windows/roles, all filled or honestly empty | API/DB/UI |
| Open-hours filter | none | `open_during(slot)` predicate; unknown hours down-ranked + flagged | DB/API |
| Anchor greedy + dedup | none | greedy anchor walk, `used_place_names` parity, stable tie-break | API |
| Meal roles | none | lunch/dinner/combo categories + food-route role | API |
| Scoring wired to planner | parallel only | `build_place_score` + `weather_fit` + travel_time rank slots | API |
| Explicit ASA flags | single good/bad | 5 flags + summary in `/weather` and plan envelope | API |
| Thresholds as config | hardcoded | `weather_threshold_config`, two-tier wind decision recorded | DB/config |
| Indoor/outdoor substitution | single nearest place | ranked proposals with reason/location/travel-time/preference | API/UI |
| Regenerate | none | `POST /plans/regenerate`, deterministic, diff highlighted | API/UI |
| Intervention history | none | `weather_state_cache` table, diff + history token | DB/API |
| Travel-time | Haversine only | travel-time cache + provider + fallback; surfaced per slot | DB/API |
| Region to 시/군 | province only | canonical region key; `region_catalog` table | DB/API |
| Honest P0/P1 states | inline skeleton | matrix P0/P1 (Slice E) on real device | UI |

**Real-device screenshots** (Android) **+** browser/iOS-Web are required for
acceptance items 1–5 in §1 (the weather-substitution pair is the marquee).

## 15. Phased Milestones

| Phase | Scope | Exit gate |
| --- | --- | --- |
| **0 — Config & data spine** | `weather_threshold_config`, `region_catalog`, `place_operating_hours`, `travel_time_cache` migrations; explicit ASA flags emitted; threshold tests. | Flags + thresholds config-driven; wind decision documented. |
| **1 — Full 4-slot planner** | Restore 4 slots/roles, anchor greedy + dedup, open-hours filter, meal roles, scoring wired in. | Planner unit/integration green; P1 screenshot from real device. |
| **2 — Weather-aware substitution + regenerate** | Indoor/outdoor engine, reason/location/travel-time/preference surfacing, `POST /plans/regenerate`. | Slide-8 substitution pair screenshot; G1/G2/G3 pass. |
| **3 — Intervention history + travel-time** | `weather_state_cache`, `/intervention` proposals + diff/history, travel-time provider + fallback. | Mid-session transition screenshot; G7 pass. |
| **4 — Hardening & rollout** | Observability, eval fixtures, quota tuning, accessibility/localization QA, feature-flagged rollout. | Design-owner review; rollback verified. |

Each phase is independently shippable behind a feature flag and rolls back to
the prior phase without schema destruction (all migrations additive).

## 16. Rollout / Rollback

- **Feature flags:** `PLAN_FULL_SLOTS`, `PLAN_WEATHER_SUBSTITUTE`,
  `PLAN_INTERVENTION_HISTORY`, `PLAN_TRAVEL_TIME` default off; enabled per
  environment. The 2-slot stub remains the fallback while flags are off.
- **Canary:** enable on internal/staging region first; monitor plan latency,
  weather fallback rate, and substitution correctness before full enable.
- **Rollback:** disable flags → reverts to stub planner (no migration reversal
  needed); weather stays on the existing chain; `plan_snapshots`/history tables
  are additive and inert when flags are off.
- **No deploy/merge by this plan:** opening a **DRAFT** PR only; merge is a
  separate human gate.

## 17. Costs / Quotas / Risks

- **LLM cost:** nano for bulk indoor/hours classification (one-time backfill +
  incremental on new places) + mini for narration/recheck. Budget the backfill;
  cache via `docent_scripts` and `place_enrichments` to amortize.
- **Weather quota:** KMA/AirKorea call volume bounded by the 3-h refresh ×
  region count; Open-Meteo fallback is the cheaper tier. Cache + stale reuse
  cap request growth.
- **Travel-time quota:** provider calls memoized in `travel_time_cache`; budget
  per-day unique pairs; Haversine fallback caps spend.
- **Risk register:** (1) wind-threshold divergence degrading outdoor plans if
  set too low — mitigated by two-tier config + eval; (2) hours-data sparsity
  silently dropping places — mitigated by down-rank + honest flag; (3)
  travel-time provider outage — Haversine fallback; (4) substitution feeling
  arbitrary — mitigated by surfaced reason/location/travel-time/preference
  (G2/G3); (5) LLM hallucinated hours/indoor labels — mini recheck + confidence
  gating.

## 18. Domain Clean-Room Boundary (do-not-carry)

This plan re-implements **behavior and interface only**. Do **not** carry from
legacy into LALA-next:

- **Code:** no `daily_planner.py` / `weather_planner.py` / `weather_air_func`
  source (re-implement behavior against FastAPI + the portable worker contract).
- **Prompts/persona:** no planner-docent system-prompt text, style-hint wording,
  or few-shot examples — LALA-next `docent_service` derives its own copy.
- **Cache file format:** do not copy `.weather_state_cache.json` verbatim;
  re-derive as the `travel.weather_state_cache` table.
- **Stations/resource data:** no `stations.json` beyond public KMA grid data; no
  `_STATION_COORD_MAP` resource identifiers.
- **Thresholds-as-truth:** legacy thresholds are **evidence of intent**, not a
  contract — reaffirm or revise deliberately in config (the wind 4-vs-14
  divergence is the canonical example).
- **Classifier script:** do not copy `classify_tourist_indoor.py`; re-derive
  indoor/outdoor labels under the §9 model policy.
- **Food-keyword list:** the exact meal/food-exclusion terms are content —
  paraphrase the method, do not copy the list (meal-role logic is re-derived
  from `category` + sub-tags).
- **Secrets/identifiers:** no legacy Event Hub names, queue names, Key Vault
  names, or connection strings (the `weather-refresh` job uses role-based
  `DB_DSN` / `KEY_VAULT_URL` dependencies only).

What **may** be re-implemented: route families (`/api/v1/plans/*`,
`/api/v1/weather`), JSON envelope shapes (additive), SQL table/column/contract
shapes under `travel.*`, the ranking *method* (greedy + anchor), the ASA-flag
set, and the dust-grade bands (public Korean guideline values).

## 19. Open Questions (for design owner, non-blocking)

1. **Wind threshold:** confirm the two-tier defaults (`discomfort_wind_ms=7`,
   `advisory_wind_ms=14`) or choose alternatives; this is the one threshold with
   a genuine legacy/current disagreement.
2. **Travel-time provider:** Kakao Mobility vs. OSRM (self-hosted) — ToS and
   cost differ; decision needed before Phase 3.
3. **Opening-hours source priority:** public open-data vs. LLM-extracted — which
   is authoritative when they conflict?
4. **Manual-region granularity:** expose 시/군 selection (richer) or keep
   province-level (simpler) for v1 region selection?
5. **Plan persistence scope:** per-session only, or per-user (requires identity
   coupling beyond this domain)?

## 20. References

- Audited clean-room spec (read-only, sibling worktree):
  `/Users/geondongkim/orca/workspaces/LALA-next/lala-legacy-technical-spec/docs/planning/legacy-3dt-first-technical-spec.md`
  (§8 day-plan/weather/location, §17 clean-room boundaries).
- Audited feature inventory (read-only):
  `…/lala-legacy-technical-spec/docs/planning/legacy-3dt-first-feature-inventory.md`
  (slices P1, W1, L1, WA1).
- Product presentation (read-only):
  `/Users/geondongkim/Downloads/LALA-발표자료-v2.pptx.pdf` — slides 5–8
  (slide 8 is the indoor/outdoor substitution contract; slide 6 the
  situation-aware local course; slide 4 the day-scenario).
- In-repo visual contract:
  [`00-visual-ground-truth.md`](./lala-mobile-visual-contract/00-visual-ground-truth.md),
  [`01-flow-and-runtime-contract.md`](./lala-mobile-visual-contract/01-flow-and-runtime-contract.md),
  [`03-visual-acceptance-matrix.md`](./lala-mobile-visual-contract/03-visual-acceptance-matrix.md).
- Current LALA-next anchors: `apps/api/app/services/planner_service.py`,
  `apps/api/app/services/weather_service.py`,
  `apps/api/app/services/recommendation_scoring.py`,
  `apps/api/app/services/region_catalog.py`,
  `apps/workers/app/contracts.py`, `sql/canonical/010_travel_core_tables.sql`,
  `sql/canonical/020_travel_domain_tables.sql`.
