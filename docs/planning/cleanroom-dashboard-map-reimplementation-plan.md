# Clean-Room Dashboard & Map Reimplementation Plan (LALA-next)

> **Status: PLAN-ONLY.** This document specifies behavior, contracts, and acceptance
> criteria. It does **not** change product source or infrastructure, and it does not
> copy anything from the legacy repo. Every legacy claim cites a **path + symbol** so a
> reader can re-verify against the read-only legacy tree. See [§1.4 Clean-Room
> Boundary](#14-clean-room-boundary-do-not-carry) for the explicit do-not-carry list.
>
> **Domain owner:** Flutter map/dashboard experience + backend serving contracts.
> **Predecessors this extends (must stay consistent with):**
> - `legacy-3dt-first-technical-spec.md` and `legacy-3dt-first-feature-inventory.md` — the
>   audited clean-room reverse-engineering + slice matrix. These live in the **sibling
>   worktree `lala-legacy-technical-spec`** (under `docs/planning/`), not in this repo, so
>   they are cited by name rather than linked; their evidence is summarized in [§1.1](#11-confirmed-legacy-evidence-path--symbol--map--dashboard--onboarding-domain).
> - [`lala-mobile-visual-contract/`](./lala-mobile-visual-contract/README.md) — authoritative
>   screen-level visual ground truth, S1–S6 (in this repo).
>
> **Source of product intent:** `LALA-발표자료-v2.pptx.pdf` (19 slides); slides 5–8 carry
> the mandatory capability gates (see [§2](#2-product-promise--capability-gates)).

---

## Table of Contents

1. [Domain Technical Specification](#1-domain-technical-specification)
2. [Product Promise & Capability Gates](#2-product-promise--capability-gates)
3. [Architecture & Portable Worker Contract](#3-architecture--portable-worker-contract)
4. [Screen-by-Screen Plan (S1–S6)](#4-screen-by-screen-plan-s1s6)
5. [Backend Contracts (API / DB / Migrations)](#5-backend-contracts-api--db--migrations)
6. [Model Policy](#6-model-policy)
7. [Legal Data-Source & Privacy Constraints](#7-legal-data-source--privacy-constraints)
8. [Observability](#8-observability)
9. [Retry & Idempotency](#9-retry--idempotency)
10. [Test / Eval Fixtures](#10-test--eval-fixtures)
11. [Rollout / Rollback](#11-rollout--rollback)
12. [Costs & Quotas](#12-costs--quotas)
13. [Risks](#13-risks)
14. [Phased Milestones](#14-phased-milestones)
15. [Metrics: Discover → Detail → Plan](#15-metrics-discover--detail--plan)
16. [Acceptance Evidence (Implemented vs Future)](#16-acceptance-evidence-implemented-vs-future)
17. [Open Questions](#17-open-questions)

---

## 1. Domain Technical Specification

### 1.1 Confirmed legacy evidence (path · symbol) — map / dashboard / onboarding domain

Legacy tree (read-only): `/Users/geondongkim/3dt-1st-Project`. Paths below are
**legacy-relative**. Behavior/interface only — no source copied.

| Capability | Evidence (legacy path · symbol) | Finding | Tag |
| --- | --- | --- | --- |
| Marker clustering policy | `src/frontend/ios/LALA/LALA/Core/MapMarkerClusteringPolicy.swift` · `shouldUseCluster(pointCount, latitudeDelta, ...)`, `buildPresentations(...)` | Activates when `pointCount >= max(2, minimumPointCount=12)` **and** `latitudeDelta >= activationLatitudeDelta=0.01`; buckets by `categoryKey` + quantized lat/lng grid (`defaultGridDivisions=5.0`, `minimumGridCellDelta=0.0003`); **selected point is always isolated as an individual `.place`** regardless of viewport. | CONFIRMED |
| Force-cluster at low zoom | `Views/MainMapView.swift` · `MapAnnotationRenderingPolicy` | `forceClusterMinimumLatitudeDelta = 0.006`, `maximumIndividualPins = 45`, `forceClusterGridDivisions = 3.6`, `visiblePaddingMultiplier = 0.7`, `minimumVisibleDelta = 0.0008`. Above the delta **and** >45 visible places, clustering is forced. | CONFIRMED |
| Viewport-bounded render + debounce | `Views/MainMapView.swift` · `scheduleMapAnnotationRebuild()`, `onMapCameraChange(frequency: .onEnd)` | Viewport-bounded annotations; **90 ms debounce** + cache-key (`spanBucket` 0.001 + `viewportBucket`); `force=true` bypasses debounce/cache. | CONFIRMED |
| Reload policy (places) | `Core/MapParityPolicy.swift` · `PlacesReloadPolicy.shouldReload(...)` | Reload when `force`, empty, or Haversine(center) ≥ threshold. `placesReloadThresholdMeters=250`; `userDrivenPlacesReloadDistanceMeters=500` w/ `userDrivenPlacesReloadCooldownSeconds=12`; `manualMapContextHoldSeconds=18`; programmatic-move suppression 0.8 s. | CONFIRMED |
| Reload policy (weather) | `Core/MapParityPolicy.swift` · `WeatherReloadPolicy.shouldReload(...)` | `defaultDistanceThresholdMeters=10_000`, `defaultMaxAgeSeconds=600`; on failure keeps prior cache if new source is `fallback` or temp empty; retry cooldown 8 s. | CONFIRMED |
| Auto-docent | `ViewModels/MainMapViewModel.swift` · `runAutoDocentIfNeeded(...)` | `autoDocentTriggerRadiusMeters=100`, `autoDocentRequestCooldownSeconds=12`; finds nearest place ≤100 m, briefs once per place. | CONFIRMED |
| Selection guidance | `Core/MapGuidanceLogic.swift` · `reduceSelection(...)` | Tap-same → deselect + stop speaking; tap-other → select + (if voice) speak + center map. Voice flag gates TTS. | CONFIRMED |
| Bottom sheet + XAI reason | `Views/MainMapView.swift` · `PlaceDetailBottomSheet`; `ViewModels/MainMapViewModel.swift` · `recommendationReason(for:)`, `playMoreInfo(for:)` | Medium/large detents; hero image, category/district/distance/address, recommendation text, event info; "Hear More Info" one-time eligibility (mode `brief` → `detail`). Reason copy: *"현재 위치에서 약 {distance} 거리의 {category} 추천 장소예요. {address}"*. | CONFIRMED |
| Network contract (places) | `Services/MapRemoteService.swift` · `fetchPlaces`; web `routes/main_map.py`, `services/map_api_service.py` | `GET /api/places` with `scope ∈ {radius, city}`, `radius`, `category ∈ {all, attraction, restaurant, event}`, `limit`, `language`; envelope `{count, scope, city, places[]}`; place fields include `name(_en)`, `lat/lng`, `region(_en)`, `distance_m`, `image_url`, `event_*`, `is_ongoing`. | CONFIRMED |
| Network contract (weather/docent) | `Services/MapRemoteService.swift` · `fetchWeather`; `routes/main_map.py` | `GET /api/weather` (`force`); `POST /api/docent/{script,audio}`. Weather: `temp`, `icon`, `dust{pm10,pm25,grade}`, `forecast[]`, `outdoor_status`. Client weather cache TTL **180 s**. | CONFIRMED |
| Onboarding + location | `Views/OnboardingView.swift`, `ViewModels/{OnboardingViewModel,LocationPermissionManager}.swift` | Single-screen intro; `CLLocationManager`; `isAuthorized` (when-in-use/always); `requiresSettingsAction` on denied/disabled; `openAppSettings()` deep-link fallback. | CONFIRMED |
| Web clustering + UX | `templates/map/index.html`, `static/js/map_logic.js` | Kakao `MarkerClusterer` `minLevel: 7`; SVG markers colored by category (`attraction #C53030`, `restaurant #F5C842`, `event #2B6SB0`); label balloons for selected or zoom ≤ 2; category chips `전체/명소/맛집/행사`; weather summary pill + bezier forecast chart; auto-docent 100 m/12 s. | CONFIRMED |

> **Note on category set:** legacy iOS/web expose `{all, attraction, restaurant, event}`
> (no `culture`). LALA-next canonical schema already adds `culture_venue`
> (`sql/canonical/010_travel_core_tables.sql` CHECK constraint). The chip→category
> mapping is a contract decision, not a parity requirement — see [§5.4](#54-category-chip--color-contract).

### 1.2 Inferred items

- The web `MarkerClusterer minLevel: 7` and iOS `latitudeDelta` thresholds are
  **platform-specific approximations of the same intent** (avoid pin overload). The
  Flutter/Kakao policy already codifies this as `places >= 80 && mapLevel >= 10`
  ([`features/map/map_helpers.dart`](../../apps/flutter_app/lib/features/map/map_helpers.dart)
  · `clusterMapPlacesForMap`). **INFERRED** that 80/10 is the canonical Flutter threshold
  inherited by the visual contract; it is the current truth, not a legacy constant.
- "Attention Insight" (legacy README §4.2) is **design-time methodology**, no runtime
  code — not a contract. **INFERRED** (matches legacy spec §10.2).
- The legacy web "weather summary pill" (`icon + outdoor_status + temp`) is the
  precursor of the compact weather/air status required here; LALA-next already exposes
  `outdoor_status` (`good|bad|unknown`) + dust grade, so the compact pill is a
  presentation delta, not a data gap.

### 1.3 Current LALA-next state (per area)

Baseline: `origin/main` at `24f8060`. The visual contract Slice A–E is **already merged**
(commit `c8e5d63`). What exists today:

#### Flutter app ([`apps/flutter_app/lib/`](../../apps/flutter_app/lib/))

| Area | Ownership | State |
| --- | --- | --- |
| Shell / nav | `app/lala_main_shell.dart`, `app/dashboard.dart`, `shared/widgets/lala_bottom_nav_bar.dart` | Exists; labels `검색/지도/일정`. |
| Onboarding | `features/onboarding/onboarding_state.dart`; `presentation/pages/{splash,start,language,location_consent}_page.dart`; `presentation/widgets/location_map_preview.dart`, `onboarding_progress.dart`, `onboarding_scaffold.dart` | 3 content steps (1/3–3/3); live map preview wrapper over Kakao bridge; manual region via `manual_location_options.dart`. |
| Kakao bridge | `kakao_map_view.dart` (entry) → `{_web,_native,_stub}.dart`; `kakao_map_models.dart` (`KakaoMapPlace{id,name,category,lat,lng,clusterCount,clusterMemberIds,selected}`, `isCluster`); `kakao_map_fallback.dart` | Conditional-import bridge; web renders category-colored pins vs white-bubble clusters. Fallback = **blocked** state, never a passing visual. |
| Map composition | `features/map/map_helpers.dart` (`clusterMapPlacesForMap`); `features/map/widgets/{top_map_chrome,category_chip,floating_map_controls,map_fab,map_bottom_dock,map_place_carousel_overlay,map_utility_control_row,map_toast,empty_dock_content}.dart` | Pin-first policy in place; rail, controls, dock exist. |
| Place / rail / sheet | `features/place/widgets/{map_rail_place_card,place_rail,recommended_place_card,featured_place_panel,signal_grid,signal_meter,proof_chip,context_fact,event_info_card}.dart`; `features/home/widgets/map_draggable_sheet.dart` | Rail cards; score/evidence behind `점수/근거` action; docent preview in dock. |
| Planner / plan | `features/planner/widgets/{planner_loading_card,planner_overview_card,plan_slot_tile,planner_sheet_content}.dart`; `features/plan/presentation/pages/plan_page.dart` | One pending card + skeleton timeline; no fake progress. |
| Search | `features/search/presentation/pages/search_page.dart` | Skeleton-only-while-pending; honest empty/error. |
| Weather / air | `features/weather/widgets/{weather_hero_card,weather_map_pill,weather_forecast_chart_card,weather_forecast_chart_painter,forecast_chip,weather_unavailable_card,weather_fact}.dart` | Compact pill + forecast chart + unavailable state. |
| Docent / voice / auto | `features/docent/widgets/{auto_docent_fab,dock_docent_preview,docent_subtitle,tour_audio_bar,tour_script_card}.dart` | Voice/auto toggles; docent in bottom sheet. |
| Location | `features/location/widgets/{manual_location_sheet,manual_location_province_chip,location_consent_overlay,location_startup_overlay}.dart`; `core/location/lala_location.dart`, `browser_location*.dart` | Geolocator + browser hybrid; manual region sheet. |
| Intervention | `features/intervention/widgets/intervention_toast.dart` | Weather-intervention toast. |
| Backend client | `core/backend/lala_backend.dart`; `clients/flutter/lib/lala_api_client.dart` (checked ref client); `clients/flutter_generated/` (generated OpenAPI) | Typed `/api/v1/*` access. |
| i18n | `shared/l10n/lala_copy.dart`, `shared/l10n/multi_language_text.dart`, `shared/labels/{basis_label,dust_label,source_label}.dart` | Single KO/EN copy source; no flag emoji. |

Tests: `test/features/map/map_clustering_test.dart`, `search_page_test.dart`,
`plan_page_test.dart`, `weather_map_pill_test.dart`, `location_map_preview_test.dart`,
`generated_client_places_poc_test.dart`.

#### Backend ([`apps/api/app/`](../../apps/api/app/))

| Surface | Ownership | State |
| --- | --- | --- |
| Router | `routers/v1.py` (`/api/v1/*`, `require_client_auth`) | `GET /places`, `GET /weather`, `POST /docents/{script,audio}`, `POST /plans/daily`, `GET /plans/intervention`, `GET|DELETE /me`. |
| Places query | `services/places_service.py::list_places` → `services/db_repository.py::fetch_places` | **Center+radius circle query**: bbox prefilter (`lat/lng BETWEEN`) + `ST_DWithin` + rank by `FLOOR(distance_m/500)` bucket → `final_score` → distance; `analytics.place_score_snapshots` (latest per place); event enrichment from `travel.place_events`. **No 4-corner viewport-bounds query yet** (see [§5.1](#51-viewport-query-delta-circle--bounds)). |
| Weather/air | `services/weather_service.py::current_weather` | DB `travel.latest_weather` → KMA Ultra-Short Nowcast + AirKorea sido realtime; 20-min in-process cache; `outdoor_status` + `dust{pm10,pm25,grade}` + derived forecast. |
| Docent | `services/docent_service.py::generate_script`, `generate_audio` | RAG grounding (`rag.knowledge_chunks` → `place_profile` fallback); cache keyed `(place_id, category, language, mode)` TTL 7 d; source `azure_openai|rule_based_curation|db_cache`; attraction food-noise guard; auto-fallback on `skeleton/mock/준비중` text. |
| Scoring | `services/recommendation_scoring.py::build_place_score`, `baseline_place_score` | 7-component weighted (`local-value-v2`); priors per category; hidden by default (`include_scores=False`). |
| Region | `services/region_catalog.py` | Province/region KO↔EN; parses `manual_location_options.dart`; TourAPI/KOPIS area codes. |
| AI | `services/ai_service.py` (`live_ai_enabled`, `selected_docent_model`, `DOCENT_AI_TIMEOUT_SECONDS=5.0`, `max_retries=0`) | Azure OpenAI, opt-in via `LALA_ENABLE_LIVE_AI`. |
| Workers | `apps/workers/app/{cli,contracts,rollout_plan}.py` | **Dry-run contracts only**; live execution rollout-gated. |

#### DB ([`sql/canonical/`](../../sql/canonical/))

`travel.places` (category CHECK `attraction|restaurant|event|culture_venue`,
`idx_places_geog_expr` GIST), `travel.place_events`, `travel.weather_observations`,
`travel.docent_scripts` (UNIQUE `(place_id,category,language,mode)`),
`analytics.place_score_snapshots`, `rag.knowledge_chunks` (ivfflat cosine). Views:
`travel.public_places`, `travel.latest_weather`, `compat.legacy_places_api`,
`compat.legacy_docent_scripts_api`.

### 1.4 Clean-Room Boundary (do-not-carry)

This plan is **behavior/interface only**. Re-implement, do not port:

- **Code:** no legacy Swift/JS/Python/SQL source.
- **Prompts/persona:** no legacy docent prompt wording, persona text, or few-shots —
  LALA-next `docent_service.py` owns its copy; we only re-derive behavior.
- **Assets:** no `.pbix`/Power BI files, no `stations.json` beyond public KMA grid, no
  images/CSS, no slide images committed.
- **Secrets/identifiers:** no connection strings, API keys, vault/registry/resource-group
  names, subscription/tenant/client IDs, queue/event-hub names. Use role-based placeholders.
- **Data:** no review text, no Daangn crawl payloads, no Naver review content, no
  `user_action_log` rows.
- **Food-filter keyword list:** paraphrase the method; do not copy the Korean term list.
- **Thresholds as truth:** legacy iOS/web zoom constants are *evidence of intent*
  (avoid overload, keep selected pin individual); the Flutter/Kakao policy is re-derived
  (current truth: `places >= 80 && mapLevel >= 10`).

**What may be re-implemented:** `/api/v1/*` route families, `{ok,data,meta,error}`
envelopes, SQL table/column/contract shapes (canonicalized under
`travel/culture/economy/community/rag/ops/compat`), docent-cache key shape, ranking
*method* (not legacy weights-as-truth). **ONMU isolation:** the LALA-next Key Vault must
not point at the ONMU vault; `int-cors-origins` is the only intentionally mirrored value.

---

## 2. Product Promise & Capability Gates

Derived from `LALA-발표자료-v2.pptx.pdf` (19 slides). Slides 5–8 are the mandatory
product promise; the deck outline (slides 1–4, 9–19) supplies positioning and guardrails.

### 2.1 Positioning & problem (slides 1–4)

- **Slide 1:** "외국인 관광객과 함께 다음 로컬 방문 장소를 연결해주는" AI platform —
  repositioned as a *travel-decision platform that converts the visitor's next action
  into local consumption* (beyond "AI docent").
- **Slide 2–3:** ~19 M foreign tourists in 2025, but visits outside famous Seoul spots
  stay high-barrier — "외국인은 한국을 찾지만, 진짜 로컬에는 도달하지 못한다"
  (info disconnect, no selection rationale, Seoul concentration).
- **Slide 4 (persona day):** pre/during-trip local-info gap **+** unexpected weather
  change ⇒ itinerary churn + satisfaction drop. This is the seed of the
  weather-aware, map-first loop.

### 2.2 Mandatory MVP promise (slides 5–8)

- **Slide 5 — "아이디어가 아닙니다. 경기도 테스트베드에서 이미 구현했습니다."** Two hero
  screens: **Map** (pins + selection) and **Daily Plan**. Speaker note mandates
  *"실제 구현 화면 캡처 중심. 개발도구 화면보다 사용자가 보는 화면 위주"* →
  **user-facing screens only, no developer-tool chrome.**
- **Slide 6 — service flow:** Gyeonggi testbed; **card spending + Daangn community +
  weather/air** data combined → situation-appropriate local course.
- **Slide 7 — data/AI structure:** how card/community/weather data flows in and becomes a
  recommendation (simple diagram; tech names demoted).
- **Slide 8 — 상황 대응 추천 (situation-aware):** weather/air banner drives **indoor vs
  outdoor** switching. Scenario A (비/미세먼지): indoor museum + fusion restaurant.
  Scenario B (맑음/쾌청): fortress trail walk → terrace lunch → alley walk → sunset cafe.
  Copy **reflects location (위치), travel time (이동시간), preference (선호도)**; banner:
  *"단순 리스트가 아닌 맥락(Context)를 반영하여 … 추천합니다."*

### 2.3 Supporting intent (slides 9–19)

- **Slide 12 — 지역 상권에 만드는 변화:** recommendation → actual visit/spend/dwell
  **conversion structure**. Source of the *user-requested "why this helps local
  economy"* explanation (see [§4.4](#44-local-economy-explanation)).
- **Slide 19 — 데이터 확보의 합법성 및 프라이버시 가드레일:** legality of data
  acquisition + privacy guardrails. Source of [§7](#7-legal-data-source--privacy-constraints).

### 2.4 Capability Gates (mandatory, non-negotiable)

These are **product gates**, not inspiration. Any screen/PR that violates one is blocked.

| Gate | Rule |
| --- | --- |
| **G1 No demo data** | Normal flows use **live DB/API data only**. No mock locations, fake map tiles, borrowed images, or static place arrays in normal paths. (Deterministic dev fixtures live under `sql/dev_reset/`, never shipped as "live".) |
| **G2 Honest states** | Every async surface has explicit **loading / loaded / empty / error** states with retry. No timer-driven "completed" claims, no spinner-only pages, no skeleton after data arrives. |
| **G3 KO/EN exclusive** | Korean mode shows Korean **only**; English mode shows English **only**. The sole deliberate bilingual surface is the S2 language-choice control (KO/EN text badges, no flag emoji). |
| **G4 Platform parity** | Android, iOS, **and Web** preserve the same user workflow (locate → category-aware places → grounded recommendation → add to plan). The Kakao conditional-import bridge is the single map path across all three. |
| **G5 Real-device evidence** | Acceptance requires **screenshots from a real device** (or production-key browser build) — never a fallback map, never a mock. See [§16](#16-acceptance-evidence-implemented-vs-future). |
| **G6 Map loop legible on first use** | The map+dashboard must make the full loop legible immediately: **locate → see category-aware local places → read a grounded recommendation → add to a plan.** No dashboard developer chrome, no fake map tiles, no permanent score/reason panels (score/reason stays behind the user-requested `점수/근거` action). |

---

## 3. Architecture & Portable Worker Contract

Use the **current** LALA-next architecture — **do not port Azure Functions**.

```
┌─ Flutter (Android/iOS/Web) ─ Kakao conditional-import bridge ─┐
│   /api/v1/*  via clients/flutter_generated  + lala_backend.dart │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTPS, Bearer/X-API-Key
┌─ FastAPI edge (apps/api) ─────────────────────────────────────▼─┐
│  places · weather · docents · plans · intervention · identity    │
│  PostgreSQL/PostGIS (radius+viewport) · pgvector (rag)           │
└──────────────────────────┬───────────────────────────────────────┘
                           │ DB_DSN (psycopg2)
┌─ Container/scheduled workers (apps/workers) ───────────────────▼─┐
│  weather_air_refresh · place_score_batch · (review_ingest)       │
│  portable WorkerContract: trigger · idempotency · retry · dry-run│
└──────────────────────────────────────────────────────────────────┘
```

### 3.1 Portable worker contract

When a timer/queue is needed, implement against a **single portable contract** in
`apps/workers/app/contracts.py` (today: dry-run). Each worker declares:

| Field | Meaning |
| --- | --- |
| `name` | Stable id (metrics/dedup key). |
| `trigger` | `timer(cron)` or `queue`; **not** an Azure binding. Container cron (k8s `CronJob`/Vercel/Supabase scheduler) or an in-process APScheduler — chosen at deploy, not in code. |
| `idempotency_key` | Natural key for safe re-runs (e.g. weather = `(location, observed_at)`; score = `(place_id, formula_version)`). |
| `retry` | `max_attempts`, backoff, `Retry-able` predicate (mirrors `ServiceError(retryable=...)`). |
| `dry_run` | Default `true` until rollout-gated (matches current `rollout_plan.py`). |
| `metrics` | Emits run/latency/freshness events to `ops.*` (see [§8](#8-observability)). |

**Workers in scope for this domain:**

1. **`weather_air_refresh`** — timer (~every 3 h, mirroring legacy cadence); idempotent on
   `(location, observed_at)`; writes `travel.weather_observations`; reuses
   `weather_service` KMA+AirKorea fetch. **Legal basis:** public open APIs
   ([§7](#7-legal-data-source--privacy-constraints)).
2. **`place_score_batch`** — timer/batch; idempotent on `(place_id, formula_version=
   local-value-v2)`; writes `analytics.place_score_snapshots` via
   `recommendation_scoring.build_place_score`.
3. **`review_ingest` (cross-domain, deferred)** — timer/CLI batch per legacy spec §2.1
   (timer, **not** queue — the "Storage Queue trigger" note was a CONFLICT, resolved as
   timer). Owned by the ingest domain; referenced here only for score-signal freshness.

> Review-ingest queue vs timer: treat as **timer/CLI batch** (legacy spec §2.1/§15). The
> queue fan-out pattern belongs to the Daangn crawler domain, not review ingest.

---

## 4. Screen-by-Screen Plan (S1–S6)

Visual ground truth is the audited
[`lala-mobile-visual-contract/00-visual-ground-truth.md`](./lala-mobile-visual-contract/00-visual-ground-truth.md).
This section adds the **backend/data contract** and **acceptance criteria** behind each
screen. Copy/geometry are **not** re-specified here — defer to the visual contract.

### 4.1 Onboarding (S1 travel type · S2 language · S3 location consent)

| Step | Backend/data contract | Acceptance (functional) |
| --- | --- | --- |
| **S1 Travel type** | Writes `travel_type ∈ {domestic, overseas}` to `OnboardingState` (`features/onboarding/onboarding_state.dart`); selects default language. | Tap selects only (no auto-nav); `다음` enabled after selection; advances to S2. (Gate G3: KO default for domestic.) |
| **S2 Language** | Sets app locale source (`shared/l10n/lala_copy.dart`); KO/EN mutually exclusive thereafter. | KO/EN **text badges** (no flags); one-language UI after selection; `2/3`. |
| **S3 Location consent** | `core/location/lala_location.dart` + `browser_location_*.dart` hybrid; on grant → refresh places/weather/planner/docent via home state. Manual region → `manual_location_options.dart` (parsed by `region_catalog`). On deny → default/selected region, compact recovery notice with `재시도`/`지역 선택`. | Real Kakao preview (key check); all three exits visible; denial keeps map usable. A missing key = **blocked**, not passed (Gate G5). |

**Backend touch:** onboarding writes nothing PII to the server; region/travel-type is a
client preference until the first authenticated call. No new onboarding route.

### 4.2 Map (S4) — the map-first loop

This is the core of the domain. Layers (top→bottom), per visual contract §6:

1. **Category chips** (`전체/명소/맛집/행사/문화`) → `GET /places?category=…`.
2. **Settings** icon (opens `features/settings/widgets/`).
3. **Recommendation rail** (`map_rail_place_card`) — photo cards, **no score/reason text**
   in rail.
4. **Pin-first markers** — individual category-colored pins; clusters only under policy.
5. **Lower-right control stack** — voice, auto-docent, recenter.
6. **Selected-place bottom sheet** — merges docent context; `일정에 추가` primary,
   `점수/근거` secondary.

#### 4.2.1 Kakao conditional bridge

- Single entry `kakao_map_view.dart` → `{_web,_native,_stub}.dart`; models in
  `kakao_map_models.dart` (`KakaoMapPlace`, `KakaoMapCamera`).
- **Bridge contract** (what the bridge must expose to the Flutter layer):
  - `setCamera(lat, lng, level)` and `onCameraChange → {center, level, bounds}`.
  - `setMarkers(List<KakaoMapPlace>)` (pin vs cluster via `isCluster`).
  - `onMarkerTap(id)` and `onClusterTap(memberIds)`.
  - Preview mode (S3): gestures/callbacks disabled, **key check still enforced**.
- **Blocked state** (`kakao_map_fallback.dart`) is an explicit failure UI, never a passing
  screenshot (Gate G1/G5).

#### 4.2.2 Server viewport querying

See [§5.1](#51-viewport-query-delta-circle--bounds). Today: center+radius circle. Plan:
add an optional **viewport-bounds** query so camera pan re-queries the visible rectangle
(pin-first discovery before clusters), while keeping the circle query for the rail/recommendation.

#### 4.2.3 Pin-first marker/cluster policy

- Re-affirm current policy `clusterMapPlacesForMap` (`features/map/map_helpers.dart`):
  **clusters only when loaded places ≥ 80 and map level ≥ 10**; below that, individual pins.
- **Selected pin always renders individually** (legacy `buildPresentations` invariant).
- **Never** render a cluster badge for fewer than the threshold (Gate G6).
- Re-derive deliberately for Kakao; do **not** port iOS `latitudeDelta` or web `minLevel`
  constants as truth ([§1.4](#14-clean-room-boundary-do-not-carry)).

#### 4.2.4 Category colors

From visual contract §2: `attraction #C53030`, `restaurant #F5C842` (dark text),
`event #2B6CB0`, `culture #0F766E`. Web bridge already maps category→color
(`kakao_map_view_web.dart` `colorFor(category)`). See [§5.4](#54-category-chip--color-contract).

#### 4.2.5 Selected-place bottom sheet (docent merge, no occlusion)

- On pin/rail tap (`MapGuidanceLogic.reduceSelection` semantics): select place, update
  sheet to category/name/distance + **concise docent preview** (mode `brief`) +
  `일정에 추가`; `점수/근거` opens score components + reason on request (Gate G6: not
  always-on).
- Docent preview sourced from `POST /docents/script` (cache hit preferred — `db_cache`).
- **No occlusion:** sheet initial height 196 dp, top radius 20; rail and controls remain
  visible. Docent lives **in the sheet/dock**, not an opaque middle card.
- "Hear More Info" → mode `detail` (one-time eligibility, legacy invariant).

#### 4.2.6 Compact weather/air status

- A pill: `outdoor_status` (`good|bad|unknown`) + temp + dust grade, from
  `GET /weather`. Tap → `weather_sheet_content` (forecast chart). Unavailable → concise
  unavailable state with retry (Gate G2).

#### 4.2.7 Voice / auto-docent / recenter state

- **Voice** toggle gates TTS on selection (`/docents/audio`).
- **Auto-docent** toggle: 100 m + 12 s cooldown (legacy invariant), respects voice flag.
- **Recenter** button → `setCamera(userLocation)` + refresh places/weather.

#### 4.2.8 Responsive mobile/web

- Breakpoints (visual contract §3): `360–430 dp` mobile S4; `431–859 dp` constrained rail;
  `≥860 dp` centered. No overlay collisions; safe rectangles after insets.

#### 4.2.9 Empty / loading / error

- **Loading:** skeleton rail + non-blocking `loadingBadge`; no fake pins.
- **Empty:** honest zero-result state (`empty_dock_content`) with `지역 선택`/`재시도`.
- **Error:** `statusBanner` retry; DB-unavailable → `503 PLACES_DB_UNAVAILABLE`
  (`places_service`) with static-snapshot fallback **only if** `static_snapshot_fallback`
  is enabled and clearly labeled (Gate G1/G2).

### 4.3 Search (S5)

- Field + one filter icon; category chips mirror map.
- States: pending → **3 skeleton rows only**; loaded → real results (official image or
  neutral empty media); empty/error → distinct honest states (Gate G2).
- Result tap → selects real place → map/place flow.

### 4.4 Plan (S6) + local-economy explanation

- `POST /plans/daily` (single request); pending → **one** generating card + skeleton
  timeline; loaded → real slots + weather + order (Gate G2: no timer progress).
- **Situation-aware slots** (slide 8): weather/air drives indoor vs outdoor selection —
  reuses `outdoor_status` + `planner_service.intervention`.
- **Local-economy explanation** (slide 12): a short, **user-requested** note explaining
  why a recommendation helps local experience/economy (e.g. small-merchant fit,
  demand-dispersion beyond crowded spots). Sourced from score components
  (`small_merchant_fit_score`, `demand_dispersion_score`) — surfaced only when the user
  asks (consistent with Gate G6). Copy re-derived; never legacy persona text.

---

## 5. Backend Contracts (API / DB / Migrations)

### 5.1 Viewport query delta (circle → bounds)

**Current** (`db_repository.fetch_places`): circle around `(lat,lng)` radius — bbox
prefilter + `ST_DWithin` + `FLOOR(distance_m/500)` bucket rank → score → distance.

**Delta (new, additive):** an optional viewport-bounds mode for the map camera so panning
shows pins across the visible rectangle before any density cluster.

- `GET /places` gains optional `bounds=minLat,minLng,maxLat,maxLng` (and optional
  `cluster_bucket` for server-assisted grouping). When `bounds` present, filter
  `lat/lng` within the rectangle (the bbox half of the existing query already does this),
  rank by score within bucket, and cap by `limit`. When absent, fall back to today's
  circle+radius (rail/recommendation path unchanged).
- Keep `ST_DWithin` optional (for "within walking distance" semantics on the rail).
- **No schema change required** — `idx_places_geog_expr` (GIST) + `idx_places_lat_lng`
  already support rectangle + radius filters. This is a query-parameter + SQL-shape
  change, validated by a focused test (see [§10](#10-test--eval-fixtures)).
- **Pin-first guarantee:** the map renders whatever the viewport returns as individual
  pins until the cluster threshold is met — the API returns places, clustering is a client
  policy (current `clusterMapPlacesForMap`).

### 5.2 Pin-first cluster policy (contract pin)

- Server returns **places** (not clusters). Clustering is the Flutter policy
  `clusterMapPlacesForMap`: cluster iff `loaded ≥ 80 && mapLevel ≥ 10`; selected stays
  individual. This is the cross-cutting contract pin (feature-inventory M1).

### 5.3 Weather/air compact status (contract)

`GET /weather` already returns the compact payload: `temp`, `icon`, `outdoor_status ∈
{good,bad,unknown}`, `dust{pm10,pm25,grade}`, `forecast[]`, `record_time`, `source`,
`location_match`. The compact pill consumes `outdoor_status + temp + dust.grade`. **No
new route.** Client cache TTL: legacy used 180 s (web) / 10 km·10 min policy (iOS);
LALA-next server caches 20 min in-process — document the client-side staleness policy
explicitly (≤10 min age or ≥10 km move → refetch; keep last good on transient failure).

### 5.4 Category chip ↔ color contract

| Chip (KO) | Chip (EN) | API `category` | Pin/chip color |
| --- | --- | --- | --- |
| 전체 | All | `all` | — (mixed) |
| 명소 | Attraction | `attraction` | `#C53030` |
| 맛집 | Restaurant | `restaurant` | `#F5C842` (dark text) |
| 행사 | Event | `event` | `#2B6SB0` → canonical **`#2B6CB0`** |
| 문화 | Culture | `culture_venue` | `#0F766E` |

> Legacy iOS/web lacked `culture`; LALA-next canonical schema adds `culture_venue`. The
> chip→`culture_venue` mapping is an **intentional divergence**, documented here. (Note:
> visual-contract token table and one legacy citation show `#2B6SB0`, a typo for
> `#2B6CB0`; canonical primary blue is `#2B6CB0`.)

### 5.5 Docent bottom-sheet merge (contract)

- `POST /docents/script` request carries `place_id`, `category`, `language`, `mode ∈
  {brief, detail}` + score/request/weather context; response `{script, source, ttl_sec,
  grounding_meta}`. Cache key `(place_id, category, language, mode)` in
  `travel.docent_scripts` (TTL 7 d). Prefers `db_cache` → avoids regen on sheet reopen.
- Grounding order (`rag.knowledge_chunks`): `place_profile` → story hints → review →
  `culture_event` → `weather_context`; attraction reviews with food noise are filtered
  (food-contamination guard). Copy re-derived; **never** legacy prompt text.
- Auto-fallback to `rule_based_curation` if output contains `skeleton/placeholder/mock/
  demo/준비중` (Gate G1 guard).

### 5.6 Daily-plan contract

`POST /plans/daily` `{lat,lng,radius_m,language}` → `{language, center, radius_m,
weather, slots[], source, …identity}`. **Current planner is thin** (morning place +
afternoon-weather slot). The slide-8 *situation-aware multi-slot* plan (morning/lunch/
afternoon/sunset, indoor↔outdoor) is a **future target** ([§16](#16-acceptance-evidence-implemented-vs-future));
this plan specifies the contract envelope so the planner can deepen without breaking the
client. Slot schema: `{period, title, place?, weather_hint}` (extendable to time windows).

### 5.7 Migrations

- **No breaking migration required** for the map/dashboard delta. Viewport-bounds is a
  query change; `idx_places_geog_expr` + `idx_places_lat_lng` already cover it.
- **If** server-assisted clustering is later added (optional), a read-only
  `travel.v_place_map_pins` view (place_id, name_{ko,en}, category, lat, lng,
  region_{ko,en}, image_url, latest_score) would centralize the pin payload — additive,
  behind a feature flag, with a focused parity test.
- All migrations stay canonical under `sql/canonical/`; dev fixtures under
  `sql/dev_reset/` only.

---

## 6. Model Policy

Per product owner policy (do not re-derive model assignment):

| Tier | Model | Used for |
| --- | --- | --- |
| High-volume extraction/normalization/classification | **`gpt-5.4-nano`** | Review extraction & normalization; ad/document classification; keyword/attribute batch extraction in ingest workers (`review_attribute_batch`, `review_mention_ingest`, franchise/category classification). |
| Low-confidence recheck + all docent generation/QA | **`gpt-5.4-mini`** | `docent_service.generate_script` (all generation); low-confidence extraction recheck; `docent_quality_qa`. |

**Plumbing:** `ai_service.selected_docent_model` already selects a deployment per role
(`azure_openai_docent_deployment` → `azure_openai_deployment`). Map the two tiers to two
deployments; keep `live_ai_enabled` opt-in, `DOCENT_AI_TIMEOUT_SECONDS=5.0`,
`max_retries=0` (retry/idempotency handled at the service/cache layer, [§9](#9-retry--idempotency)).

---

## 7. Legal Data-Source & Privacy Constraints

(Deck slide 19: *데이터 확보의 합법성 및 프라이버시 가드레일*.)

| Source | Legal basis | Constraint |
| --- | --- | --- |
| **KMA** (Ultra-Short Nowcast) + **AirKorea** sido realtime | Korean public open-API (공공데이터) | Named in prose; service key is a secret (Key Vault/env, never committed). Cache server-side to respect rate limits. |
| **TourAPI / KCISA / KOPIS** | Public tourism/culture open-API | Public content; cite source in docent (`source_label`); redact literal endpoints in docs. |
| **Card spending** | **Public aggregate statistics only** (시군구/업종 단위) — **never** individual transactions | Used as a regional signal (`local_spending_score`); no PII, no card numbers, no person-level data. |
| **Daangn community** | Public community **mention aggregation only** | Aggregate `place_mentions_weekly`-style counts; **no** post text, author identity, or crawl payloads shipped to clients. |
| **Location** | User consent (onboarding S3) | Precise GPS used client-side for ranking; **analytics store region-level only** (legacy `user_action_log` used session-UUID + `sigun_nm`, no user ids). Coordinate-level data is not persisted without explicit consent. |
| **Identity** | OAuth/Logto (`identity.users`) | Account-bound features only; analytics are session-scoped, not identity-bound, unless opt-in. |

**Guardrails:** KO PIPA / (for foreign users) GDPR-aware data-minimization; secret-zero
deploy (OIDC); ONMU vault isolation; `int-cors-origins` is the only mirrored value.
Forbidden by `tests/unit/test_secret_config_contract.py`-style checks: PG-URL/password
literals, hardcoded keys.

---

## 8. Observability

Extend the existing non-mutating `observability_plan.py` (no Power BI port — feature
inventory O1 deferred). For the map/dashboard loop:

- **Per-route metrics** (FastAPI `app.state.metrics`): request count, latency p50/p95,
  `source` mix (`db` / `public_mvp_snapshot` / `unavailable`), cache-hit ratio
  (`db_cache` for docents), `outdoor_status` distribution.
- **Data freshness**: `check_data_freshness_status` already reports
  `places/weather/scores/rag` max timestamps → expose in `ops.dependency_latest` /
  `/healthz`-style readiness. Stale weather (> threshold) → `stale`.
- **Worker events**: each `WorkerContract` run emits `run/{ok,fail}`, latency, items
  written, idempotency-skips.
- **Map funnel** (privacy-safe): see [§15](#15-metrics-discover--detail--plan). Region-level only.
- **No** client PII in logs; request IDs via `ensure_request_id` / `X-Request-ID`.

---

## 9. Retry & Idempotency

- **Docent:** cache-keyed `(place_id, category, language, mode)` upsert
  (`ON CONFLICT … DO UPDATE`) — idempotent regen; `max_retries=0` at the AI client, but the
  service layer falls back to `rule_based_curation` on retryable failure and re-attempts
  LLM next request (cached fallbacks are **not** reused — legacy invariant).
- **Weather:** in-process 20-min cache keyed by grid/sido+hour; transient failures keep
  last good (`fallback_error`); client refetch on ≥10 km move or >10 min age.
- **Places:** DB failure → `503 PLACES_DB_UNAVAILABLE` (retryable); static-snapshot
  fallback only if enabled + labeled. Viewport re-query debounced client-side.
- **Workers:** `idempotency_key` natural keys (weather `(location,observed_at)`, score
  `(place_id,formula_version)`) make re-runs safe; `Retry-able` predicate governs backoff.

---

## 10. Test / Eval Fixtures

- **Map clustering:** `test/features/map/map_clustering_test.dart` — assert <80 places /
  level<10 ⇒ individual pins; ≥80 & level≥10 ⇒ cluster; selected stays individual.
- **Viewport bounds:** new repo-level test that `fetch_places(bounds=…)` returns only
  in-rectangle places (delta from [§5.1](#51-viewport-query-delta-circle--bounds));
  parity with circle query for the rail path.
- **States:** `search_page_test.dart` (pending/loaded/empty/error), `plan_page_test.dart`
  (one loader, no timer progress), `weather_map_pill_test.dart` (good/bad/unknown/unavailable).
- **Docent merge:** test that bottom sheet shows `db_cache` script without regen; attraction
  food-noise filtering; auto-fallback on `mock/skeleton` text.
- **Eval fixtures (golden/eval, not shipped):** a small, **redacted** fixture set under
  `sql/dev_reset/` (already present) + `apps/api/tests/` for place/weather/docent envelopes.
  **Never** copy legacy review text or crawl payloads into fixtures.
- **Contract:** `generated_client_places_poc_test.dart` keeps the Flutter generated client
  in sync with `/api/v1/places`.

---

## 11. Rollout / Rollback

- **Feature flags:** viewport-bounds query, server-assisted clustering (if added), and
  deeper planner slots all land **behind flags** (config-driven, default off).
- **Workers:** stay `dry_run=true` until rollout-gated (`rollout_plan.py`); promote one
  worker at a time (weather first — lowest risk, public data only).
- **Rollback:** additive query params + views ⇒ revert = drop the flag; no destructive
  migration. Docent/places fallbacks (`rule_based_curation`, static snapshot) keep the app
  functional if AI/DB degrade.
- **Deploy:** no production deploy by this plan; Flutter web smoke uses the **guarded**
  dry-run path only (`scripts/unix/deploy_flutter_web_vercel.sh --dry-run`), per visual
  contract §5.

---

## 12. Costs & Quotas

- **KMA/AirKorea:** public-API quotas — server-side 20-min cache + per-grid dedup keeps
  call volume bounded (one call per grid/sido per hour, not per user).
- **Models:** `gpt-5.4-nano` for high-volume ingest (cheap, batched);
  `gpt-5.4-mini` for docent generation with **7-day cache** (`docent_scripts`) +
  grounding-hash identity to avoid regen on identical context. Budget guard:
  per-minute rate limit already enforced (`enforce_public_contest_paid_route_limit` on
  `/docents/{script,audio}`).
- **Kakao Maps:** domain-allowlisted JS key (build-time injected); quota monitored.
- **DB:** GIST + ivfflat indexes already present; viewport query is index-covered.

---

## 13. Risks

| Risk | Mitigation |
| --- | --- |
| Kakao key/domain failure on Web/iOS/Android | Explicit **blocked** state; never a passing screenshot (Gate G5). |
| Score/reason leaking into always-on UI | Keep behind `점수/근거`; widget tests assert absence in rail/sheet default. |
| Demo data slipping into normal flows | G1 + tests; dev fixtures isolated under `sql/dev_reset/`. |
| KO/EN bleed | G3 + i18n tests; single copy source (`lala_copy.dart`). |
| Planner over-claim (fake progress) | G2; one loader, no timer stages; `plan_page_test.dart`. |
| Legacy-threshold cargo-cult | [§1.4](#14-clean-room-boundary-do-not-carry); re-derive Kakao policy. |
| Review/community data PII leak | [§7](#7-legal-data-source--privacy-constraints); aggregates only. |

---

## 14. Phased Milestones

Sequenced for independent review; each is a separable PR series (not combined).

1. **M1 — Viewport-bounds query (backend).** Add `bounds` to `/places`; index-covered;
   parity test. Unblocks pin-first discovery on pan.
2. **M2 — Pin-first + cluster-policy hardening (Flutter).** Re-affirm
   `clusterMapPlacesForMap`; selected-pin-individual invariant; `<80 ⇒ pins` test.
3. **M3 — Bottom-sheet docent merge.** `db_cache`-first script; no occlusion;
   `점수/근거` secondary; food-noise guard test.
4. **M4 — Compact weather/air + intervention.** Pill from `outdoor_status`; situation-aware
   toast (slide 8 indoor/outdoor).
5. **M5 — Voice/auto/recenter state.** TTS gating; auto-docent 100 m/12 s; recenter refresh.
6. **M6 — Responsive + states sweep.** Breakpoints; loading/empty/error parity across
   map/search/plan.
7. **M7 — Daily-plan depth (future).** Situation-aware multi-slot planner (slide 8);
   contract-compatible slot schema; behind flag.
8. **M8 — Metrics + rollout.** Discover→detail→plan funnel; worker rollout (weather first).

---

## 15. Metrics: Discover → Detail → Plan

Privacy-safe, **region-level** (no coords/PII), session-scoped (legacy `user_action_log`
used session-UUID + `sigun_nm`). Funnel events:

```
map_view → category_filter → place_select(pin|rail|search)
        → detail_view → docent_request(brief|detail) → audio_play
        → add_to_plan → plan_generate → plan_generated
```

- **Discover:** `map_view`, `category_filter`, `place_select`.
- **Detail:** `detail_view`, `docent_request`, `audio_play`.
- **Plan:** `add_to_plan`, `plan_generate`, `plan_generated`.
- **Conversion KPIs:** place_select→detail_view; detail_view→add_to_plan;
  add_to_plan→plan_generated. Plus source-mix (`db` vs fallback) and weather
  `outdoor_status` distribution as context.

Implementation: an opt-in, session-scoped action log (re-derive; do **not** port legacy
`user_action_log` rows). Emitted via `app.state.metrics`; aggregated region-level only.

---

## 16. Acceptance Evidence (Implemented vs Future)

Each row distinguishes **what exists now** from **what this plan targets**. Evidence is a
**real-device / production-key browser screenshot** (Gate G5); fallbacks are `blocked`.

| Area | Implemented (current main) | Target (this plan) |
| --- | --- | --- |
| Onboarding S1–S3 | 3 steps, live map preview, manual region | Parity verified on device (G3/G5) |
| Map pin-first | `clusterMapPlacesForMap` (≥80/≥10) | Hardened invariant + selected-individual test |
| Viewport query | center+radius circle | + bounds mode (M1) |
| Rail | photo cards, no score | Verify no score/reason (G6) |
| Bottom sheet | docent preview in dock | `db_cache`-first, no occlusion (M3) |
| Weather/air pill | `weather_map_pill` | + situation-aware intervention (M4) |
| Voice/auto/recenter | toggles exist | policy tests (M5) |
| Search/Plan states | skeleton/honest states | cross-screen parity (M6) |
| Daily plan | thin (2 slots) | situation-aware multi-slot (M7, future) |
| Metrics | request-level | discover→detail→plan funnel (M8) |

**Screenshot protocol (Gate G5):** capture each state at `393×852 dp` in a fresh browser
profile **and** on one real mobile runtime; keep device chrome out of the comparison; do
**not** commit raw screenshots, key-bearing URLs, or profiles (store under ignored
`output/` / `.playwright-mcp/`). A map fallback or mock is `blocked`, never `passed`.

---

## 17. Open Questions

1. Should server-assisted clustering (read-only `v_place_map_pins` view) be added, or keep
   clustering fully client-side (`clusterMapPlacesForMap`)? (Default: client-side.)
2. Confirm the deeper daily-planner (slide 8 multi-slot, indoor/outdoor) is in-scope for
   this domain vs the planner domain — contract is specified either way ([§5.6](#56-daily-plan-contract)).
3. Pin the client weather staleness policy (10 km/10 min vs server 20-min cache) and
   whether to expose `ttl_sec` to the client.
4. Whether `culture_venue` gets a dedicated map chip now or stays folded into `all` until
   data volume warrants it (mapping in [§5.4](#54-category-chip--color-contract) covers both).
5. Review-ingest freshness dependency: does the map domain treat reviews as already-ingested
   `rag.knowledge_chunks`, or block on the ingest worker rollout? (Default: treat as
   already-ingested; docent degrades to `place_profile` fallback otherwise.)
