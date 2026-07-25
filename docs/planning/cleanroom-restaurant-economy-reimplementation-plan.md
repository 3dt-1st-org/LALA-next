# Clean-Room Reimplementation Plan — Restaurant Discovery & Local-Economy Measurement

> Status: **PLAN-ONLY**. This document changes no product source or infrastructure. It is a
> behavior/interface specification and a phased implementation plan for the **restaurant
> discovery / recommendation** and **local-economy measurement** domain of LALA-next.
>
> Scope owner: this plan. Companion specs:
> [`legacy-3dt-first-technical-spec.md`](./legacy-3dt-first-technical-spec.md) (legacy evidence),
> [`legacy-3dt-first-feature-inventory.md`](./legacy-3dt-first-feature-inventory.md) (slices).
>
> **Link note (forward reference):** those two companion files are authored in the sibling
> `lala-legacy-technical-spec` worktree and land at `docs/planning/` on `main`. The relative links
> above are correct for the merged state; until that companion PR merges they are intentional
> cross-PR references, not broken links. No other links in this doc are external.
>
> This plan is **clean-room**: see §16 *Clean-Room Boundary*. Nothing from the legacy tree —
> source, prompts, review text, the food keyword list, assets, secrets, or resource identifiers —
> is copied. Legacy is cited only as `path :: symbol :: behavior` interface evidence.

---

## 0. Provenance, Method, Legend

- Legacy source (read-only): `/Users/geondongkim/3dt-1st-Project` ("LALA" / *Local Area, Local Answer*).
- Current target (writable): this LALA-next worktree on branch
  `geondongkim/lala-plan-restaurant-economy`, remote `github.com/3dt-1st-org/LALA-next`.
- Presentation capability gates (mandatory, §3): `/Users/geondongkim/Downloads/LALA-발표자료-v2.pptx.pdf`,
  slides 5–8. These are a **required product promise**, not inspiration.
- Every claim below is tagged so a reader can re-verify against code or the read-only legacy tree.

| Tag | Meaning |
| --- | --- |
| **CONFIRMED** | Read directly in LALA-next code/SQL or legacy code/SQL. Path/symbol cited. |
| **LEGACY** | Confirmed in the read-only legacy tree (interface evidence only — not a contract to copy). |
| **GATE** | A product promise derived from presentation slides 5–8; mandatory to satisfy. |
| **GAP** | Capability required by a GATE or by domain parity that LALA-next does **not** yet have. |
| **DIVERGENCE** | LALA-next intentionally differs from legacy; documented, not a defect. |
| **TARGET** | Net-new design this plan proposes (no existing implementation). |

> **No demo/mock data in normal flows** (GATE, §3). Every "implemented" claim below is backed by a
> live-DB/API path or an explicit honest fallback. Targets are labeled and not asserted as existing.

---

## 1. Domain Technical Specification

### 1.1 Confirmed legacy evidence (interface only)

All citations are `legacy path :: symbol :: behavior`. They establish **intent and method**, never a
contract to port verbatim. Where LALA-next has already re-derived a better design, the divergence is
recorded in §1.3.

| Concern | Legacy evidence | Behavior (paraphrased) | Tag |
| --- | --- | --- | --- |
| Restaurant ranking | `src/collectors/process_restaurants.py::get_ranked_restaurants`; `src/services/restaurant_docent.py::rank_restaurants` | IQR outlier clip on **card score only** (Q1=0.25, Q3=0.75, upper = Q3 + 1.5·IQR) → MinMax → weighted `0.4·card + 0.6·daangn` → dedup by `restaurant_name` keep-first → **top 10**. | LEGACY |
| Restaurant radius filter | `src/collectors/restaurant_filter.py::filter_restaurants_by_location` | Haversine, default `radius_m=150`; returns `SKIP_WEIGHTING` when <10 hits else `PROCEED_TO_WEIGHTING`. | LEGACY |
| Card-spend fact table | `sql/ddl/gyeonggi_card_spending_status.sql::locallink.gyeonggi_card_spending_stats` | Columns `ta_ymd, city, card_tpbuz_nm_1, card_tpbuz_nm_2, hour, sex, age, day, amt, cnt`. Loaded by `scripts/load/load_gyeonggi_card_spending.sh` (CSV → staging → insert). | LEGACY |
| Card-spend summary | `sql/ddl/create_ranking_summary_views.sql::locallink.v_card_stats_summary` | Matview `SUM(amt) GROUP BY city, card_tpbuz_nm_2`. | LEGACY |
| Community mention signal | `sql/ddl/create_ranking_summary_views.sql::daangn.v_daangn_stats_summary`; `daangn.place_mentions_weekly` | `SUM(mention_count) GROUP BY place_name, city_name`; `category ∈ {맛집,명소,행사}`. This is the 0.6-weighted "daangn" signal. | LEGACY |
| Restaurant master source | `sql/ddl/restaurants-data-table.sql::locallink.gg_restaurant_info`; `scripts/load/load_restaurants_data.py` | Gyeonggi open-data **restaurant license** CSV (수원/용인/평택): `bizplc_nm, refine_wgs84_lat/logt, bsn_state_nm(영업/폐업), bizcond_div_nm_info, sigun_nm`. | LEGACY |
| **Franchise / small-merchant classification** | — | **NOT FOUND in legacy.** No franchise, 가맹, 프랜차이즈, 공정거래, or 소상공인 logic exists. This is a **LALA-next innovation** (§1.3). | CONFIRMED (absence) |
| Meal-slot categories | `src/services/daily_planner.py::_query_restaurants` | Lunch `점심음식점` (excludes 카페/전통찻집/주점/유흥); dinner `저녁음식점` (excludes 카페/전통찻집); `저녁카페` (카페/전통찻집 only). | LEGACY |
| Restaurant review pipeline | `src/collectors/load_restaurant_review.py::run_restaurant_pipeline`; `extract_keywords_with_llm` | Naver blog search `"{sigun_nm} {name} 후기"` → HTML clean → keyword LLM → Azure OpenAI embedding → `locallink.restaurant_reviews(clean_text, extracted_keywords, embedding VECTOR(1536))`. | LEGACY |
| Restaurant detail analysis | `src/collectors/process_restaurants.py::analyze_reviews_with_llm`, `save_analysis_result` | JSON `summary_ko/en, atmosphere_ko/en, tips_ko/en` + `VECTOR(1536)` upsert into `locallink.restaurant_details`. Embedding model `text-embedding-3-small`. | LEGACY |
| Hybrid matching | `sql/analytics/hybrid_place_matching.sql` | PostGIS `ST_DWithin` candidate → weather-aware indoor filter (`is_indoor` preferred in bad weather) → review-snippet join → `ORDER BY distance_meters ASC`. | LEGACY |
| Product framing | `README.md` | "내국인의 실제 일상 데이터(카드 소비, 지역 커뮤니티)"; "데이터 기반 로컬 랭킹 시스템"; "5억 건의 경기도 카드 소비 데이터 + 당근마켓 지역 커뮤니티 언급". | LEGACY |

### 1.2 Inferred / open items

- **INFERRED** the legacy 0.4/0.6 weighting and 150 m filter were tuned for a single Gyeonggi
  contest window and a small place corpus; they are **evidence of intent** (card spend + organic
  community mention should move ranking), not a portable contract. LALA-next must not treat them as
  ground truth (DIVERGENCE, §1.3).
- **INFERRED** legacy "5억 건" card data is the same Gyeonggi Data Analysis card-sales dataset family
  LALA-next already ingests (§1.3). The headline volume is a marketing framing of an **aggregate,
  non-personal** dataset.
- **OPEN** whether LALA-next should add a Naver-review ingestion worker or treat reviews as
  already-ingested `community.place_mentions_weekly` (clean-room spec §16 Q1). This plan picks the
  latter for the restaurant domain (§6.2) and forbids copying review text.

### 1.3 Current LALA-next state (implemented evidence)

LALA-next already re-implements — and in several places **exceeds** — the legacy restaurant/economy
behavior under its own architecture (FastAPI + PostgreSQL/PostGIS/pgvector + Flutter/Kakao).

| Capability | Evidence (path :: symbol) | State | Tag |
| --- | --- | --- | --- |
| Fair ranking formula | `apps/api/app/services/recommendation_scoring.py::build_place_score`, `weighted_score`, `COMPONENT_WEIGHTS`, `FORMULA_VERSION="local-value-v2"` | **7-component** weighted score: `local_spending_score 0.22`, `small_merchant_fit_score 0.18`, `demand_dispersion_score 0.20`, `culture_relevance_score 0.15`, `weather_fit_score 0.10`, `review_quality_score 0.10`, `accessibility_fit_score 0.05`; missing components are skipped with weight renormalization; category priors + distance-dispersion prior baseline. | CONFIRMED — **DIVERGENCE** from legacy 0.4/0.6 (deliberate; weights are owned, not copied) |
| Score snapshot build | `apps/api/app/services/place_score_batch.py::fetch_place_signals`, `compute_score_snapshots`, `insert_score_snapshots` | Joins `economy.card_spending_area_monthly` + `analytics.place_business_identity` + `travel.weather_observations` + `community.place_mentions_weekly` → writes `analytics.place_score_snapshots`; records `ops.job_runs`; `_relative_score`/`_inverse_relative_score` implement a 0.35–0.95 band instead of raw MinMax (re-derives legacy intent). | CONFIRMED |
| Franchise vs small-merchant | `apps/api/app/services/franchise_identity.py::classify_place_business`, `BUSINESS_IDENTITY_TYPES`; table `analytics.place_business_identity` (`sql/canonical/035_data_pipeline_tables.sql`) | Classifies each place into `independent_local \| local_small_chain \| franchise_store \| national_franchise \| corporate_chain \| unknown`; produces `is_franchise`, `franchise_match_confidence` (0–1), `chain_scale_score`, `small_merchant_fit_score`; confidence-gated name + coordinate match against `economy.franchise_brands`/`franchise_locations`. | CONFIRMED — **net-new vs legacy** |
| Fair-trade franchise reference | `apps/api/app/services/franchise_reference_ingest.py::fetch_franchise_brand_references`; tool `apps/api/app/tools/run_franchise_reference_ingest.py` | Public **공정거래위원회 가맹정보** API (`getBrandFrcsStats`) → `economy.franchise_brands`; `chain_scale_score = log10(store_count)/3` capped at 1.0; idempotent `ON CONFLICT (primary_source, source_record_id)` upsert. | CONFIRMED |
| Aggregate card-spend ingest | `apps/api/app/services/card_spending_ingest.py::parse_card_spending_file`, `insert_card_spending_result`; tool `run_card_spending_file_ingest.py` | Parses Gyeonggi Data Portal CSV/XLSX/ZIP → `economy.card_spending_area_monthly` + `card_spending_demographics`; **aggregate only** (region × industry × month × gender × age); sha256 dedup via `ingest.source_files`; **no personal consumer rows**. | CONFIRMED — privacy-by-design |
| Place discovery API | `apps/api/app/routers/v1.py::places`; `apps/api/app/services/places_service.py::list_places`; `apps/api/app/services/db_repository.py::fetch_places` | `GET /api/v1/places` with `lat,lng,radius_m,category,lang,include_scores,limit`; PostGIS `ST_DWithin`; joins latest `place_score_snapshots`; `ORDER BY floor(distance_m/500) ASC, COALESCE(final_score,0) DESC, distance_m ASC` — **distance-bucketed then score-ranked** (fair ranking); explicit `source ∈ {db, static_snapshot}` and `location_engine ∈ {postgis, static_snapshot, none}`. | CONFIRMED |
| Categories | `places_service.py::_ALLOWED_CATEGORIES` | `all \| attraction \| restaurant \| event \| culture_venue`. **No cuisine/meal/diet facet exists yet** → GAP (§4.3). | CONFIRMED + GAP |
| Review-derived attributes | `apps/api/app/services/review_attribute_batch.py::RESTAURANT_ATTRIBUTES`, `generate_ai_enrichments`, `build_deterministic_enrichments`; schema `review-attributes-v1` | Restaurants extract `taste, service, price, atmosphere, cleanliness, wait_crowding`; LLM (gpt-5.4-nano deployment) + deterministic fallback; persists to `community.place_mentions_weekly.attributes.review_attributes` + `review_quality`. | CONFIRMED |
| Docent + rationale | `apps/api/app/services/docent_service.py::generate_script`, `_ko_score_sentence`, `_en_score_sentence`; `apps/api/app/services/ai_service.py::selected_docent_model` | KO/EN narration grounded in RAG + place profile; **score-derived "why this place" rationale** (local spending / small-merchant / demand dispersion / weather / culture); rule-based fallback when AI unavailable; strips internal metric fragments before display. | CONFIRMED |
| Local Restaurant Tour (proto) | `apps/flutter_app/lib/features/tour/tour_helpers.dart::tourGuideScript`, `restaurantTourPlaces` (used in `home_page.dart::_fetchTourAudio`) | Composes a compact walking food-route script from ≤5 nearby restaurants, referencing `localSpendingScore` for the signal sentence. **Not yet a first-class screen with category chips** → GAP (§5). | CONFIRMED + GAP |
| Map-first discovery UI | `apps/flutter_app/lib/features/home/home_page.dart` (`_selectCategory`, `_requestLocationThenRefresh`, `_returnToCurrentLocation`, `_focusCluster`); `apps/flutter_app/lib/features/map/map_helpers.dart::clusterMapPlacesForMap`, `featuredPlace`, `railPlaces` | Category chips, current-location + manual-location, **individual markers first**; density clusters only when `places.length >= 80 && mapLevel >= 10`; reload on ≥250 m move; auto-docent at 100 m + 12 s cooldown. | CONFIRMED |
| Daily plan (thin) | `apps/api/app/services/planner_service.py::daily_plan`, `_daily_plan_slots`, `intervention` | Returns morning slot + weather slot; `intervention` flags bad weather with reason + recommended action. **No lunch/dinner meal slots, no reasoned substitution** → GAP (§7). | CONFIRMED + GAP |
| Model policy knobs | `.env.example`; `apps/api/app/core/config.py` (`azure_openai_docent_deployment`, `azure_openai_review_batch_deployment`); `ai_service.selected_docent_model`; `review_attribute_batch.selected_review_batch_model` | `AZURE_OPENAI_DOCENT_DEPLOYMENT` (recommended **gpt-5.4-mini**) and `AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT` (recommended **gpt-5.4-nano**) already exist and match the mandated policy. | CONFIRMED |

### 1.4 Clean-room boundary (what this plan does NOT carry from legacy)

Re-stated per the spec's §17 for the restaurant/economy domain:

- **No legacy source** — Python/SQL/Swift. Re-implement behavior under FastAPI/Flutter/SQL.
- **No prompts/persona** — the legacy restaurant "food-guide persona", `analyze_reviews_with_llm`
  prompt text, and few-shots are not copied. LALA-next owns `ai_service._docent_system_prompt` and
  `review_attribute_batch.SYSTEM_PROMPT`.
- **No food keyword list** — the legacy food-detection / `점심음식점` exclusion term sets are
  **content**, not interface. Re-derive a minimal, audited cuisine taxonomy (§4.3).
- **No review text / crawl payloads** — `community.posts`, Naver bodies, Daangn payloads are never
  copied or re-emitted; only structured, paraphrased attributes and short evidence phrases.
- **No resource identifiers / secrets** — franchise API keys, card-data credentials, endpoints beyond
  the public 공정위 service URL are role placeholders.
- **No legacy weights as truth** — 0.4/0.6 and 150 m are evidence of intent, re-derived under
  `local-value-v2`.

---

## 2. Domain Goals (from the dispatch brief)

This plan must deliver, for **restaurant discovery / recommendation** and **local-economy
measurement**:

1. **Official restaurant/place sources** — public open-data masters, license/영업 status, PostGIS.
2. **Franchise-vs-small-merchant classification** using 공정위 fair-trade franchise data.
3. **Confidence and unmatched handling** — every classification carries a confidence; unmatched →
   `unknown` with honest UI surfacing.
4. **Aggregate card-spend / local-signal ingestion** — region/industry aggregates only.
5. **No personal consumer tracking** — aggregate, non-identifying; privacy by design.
6. **Fair ranking and score components** — transparent, auditable, snapshotted.
7. **Cuisine / meal / diet / indoor filters** — beyond the 4 top-level categories.
8. **Bilingual naming/descriptions** — KO/EN mutually exclusive UI modes.
9. **Review-derived food/service/atmosphere attributes** — structured, not prose-only.
10. **Transparent optional rationale** — "why this place", on demand, grounded.
11. **Feedback / evaluation metrics for local visit/spend dispersion** — closed-loop measurement.
12. **Presentation tie** — a Local-Restaurant-Tour-style exploration surface with **real category
    chips** and **grounded local-food narration**.

---

## 3. Presentation-Derived Capability Gates (mandatory)

Visually inspected `LALA-발표자료-v2.pptx.pdf` slides 5–8 (19-page deck; mockups rendered from real
Gyeonggi testbed screens). These are **required product promises**, not decoration. Every gate below
maps to concrete acceptance criteria in §4–§9.

> **Honest-data rule (applies to all gates):** no demo/mock data in normal flows. All normal UI uses
> live DB/API data with explicit honest loading/failure states. KO and EN are **mutually exclusive**
> UI modes. Android and iOS/Web must preserve the same user workflow.

### GATE-A (slide 5) — "이미 경기도 테스트베드에서 구현"
MVP exists on real Gyeonggi data: a **map** screen and a **daily plan**. The promise is *parity on a
real device*, not a slide. → Acceptance: real-device screenshots of Map + Daily Plan backed by live
`/api/v1/places` and `/api/v1/plans/daily` (§10).

### GATE-B (slide 6) — Situation-aware location recommendation (keystone for this domain)
Four mockups; the restaurant/economy gates are mockups 2 and 4:
- **(2) Map discovery:** a `Map` tab with a search affordance ("All locations"), **filter chips
  `Restaurants` / `Cafes`**, green map with **individual pins** (수원민속박물관, 화성행궁/수원화성), and a
  bottom panel "이 장소는 추천됩니다…" with a description. → **map-first discovery with category
  filtering, current location, individual markers before density clusters**, plus a "why this place"
  panel. (§4, §5)
- **(4) Local Restaurant Tour:** a dedicated surface titled **"지역 식당 투어"** with **category chips
  `전통 음식 / 카페 / 디저트 / 파인 푸드`** and narration: *"LALA는 방문자를 현지 음식 장소와 명확한
  방문 이유로 연결합니다. 각 단계는 거리, 분위기, 실제 현지 맛을 위해 선택됩니다."* → a
  Local-Restaurant-Tour exploration surface with **real category chips** and **grounded local-food
  narration** ("clear reason to visit"; "distance, mood, real local taste"). (§5)
- Slide subtext: *"카드 소비데이터 활용, 루틴 모델 카테고리 탐색, 날씨/거리별 데이터로 상황에 맞는
  로케이션 추천"* → card-spend, category exploration, weather/distance situation-aware ranking. (§4, §7)

### GATE-C (slide 7) — Data/AI pipeline (input → processing → output)
**Input:** 내국인 선호 · **5억 건 카드 데이터** · 로컬 SNS 리뷰 크롤링 · 기상청 실시간 API.
**Processing (LALA AI 엔진):** LLM 요약 · RAG 매칭 분석 · 추천. **Output:** 생활 밀착형 AI 도슨트.
→ The restaurant/economy plan must wire these same inputs through the LALA-next pipeline to docent
output (§6, §8). The "5억 건" is the **aggregate** Gyeonggi card dataset — no personal rows.

### GATE-D (slide 8) — Context-aware, not a list
*"단순 리스트가 아닌 맥락(Context)를 반영."* Two scenarios on the Daily Plan:
- **A (비/미세먼지):** indoor museum + an indoor lunch (e.g. a chicken/bar stop with a "delightful
  dining" rationale).
- **B (맑음/쾌청):** outdoor 화성 성곽 산책 → 테라스 런치 → 골목 산책 (local shops/cafes) →
  선셋 카페.
→ **Daily plan with weather/air context and reasoned substitutions** (indoor swap, meal-slot
reasons). (§7)

---

## 4. Slice RE-1 — Map-First Local Discovery (category + cuisine filters)

**Verdict today:** Map-first discovery, current location, individual markers, category chips, and
distance-bucketed fair ranking are **CONFIRMED** (`home_page.dart`, `fetch_places`,
`clusterMapPlacesForMap`). The **gap** is the cuisine/meal/diet/indoor facet promised by GATE-B.

### 4.1 Implemented (evidence)
- `GET /api/v1/places` returns PostGIS-ranked places with `source`/`location_engine` honesty flags.
- Flutter renders **individual pins first**; density clusters activate only at `places≥80 &&
  mapLevel≥10` — i.e. individual markers precede clusters, satisfying GATE-B(2) ordering.
- Category chips + current-location/manual-location flow + reload-on-move exist.

### 4.2 Target (GAP) — cuisine / meal / diet / indoor facet
Add a **second-level facet** so the Map chips (GATE-B: Restaurants/Cafes) and the Tour chips
(GATE-B: 전통 음식/카페/디저트/파인 푸드) are driven by real data, not hardcoded UI.

- **Schema (migration, additive):** extend `travel.places` with nullable `cuisine_taxonomy jsonb`
  (e.g. `{"ko":"전통 음식","en":"traditional","meal":["lunch","dinner"],"diet":[],"indoor":true}`)
  and a normalized `cuisine_code text`. Populate from official restaurant-license
  `bizcond_div_nm_info` (legacy column evidence) **re-derived** into LALA-next's own taxonomy —
  **never copy the legacy `점심음식점` exclusion term list** (§1.4).
- **API contract:** extend `GET /api/v1/places` with optional `cuisine` (enum from a published
  taxonomy), `meal ∈ {breakfast,lunch,dinner,snack,cafe}`, `diet ∈ {vegetarian,halal,...}` (only
  values with an official/declared source), and `indoor ∈ {true,false}`. These compose with
  `category` and PostGIS radius. Unknown enum values → `400 INVALID_FACET` (no silent wildcarding).
- **DB:** add a GIST/partial index on `(category, cuisine_code)` and reuse the existing
  `idx_places_geog_expr`; filter inside the existing CTE so scoring still joins correctly.
- **Flutter:** the Map filter chips read the taxonomy from a `/api/v1/taxonomies` (or OpenAPI
  generated type) endpoint so chips are data-driven and bilingual.

### 4.3 Acceptance criteria
- **API:** `GET /api/v1/places?category=restaurant&cuisine=cafe&indoor=true` returns only matching
  live-DB rows; response `source="db"`. Empty result → honest `count:0`, not a fallback mock.
- **DB:** migration is additive (no `DROP`); `git diff --check` clean; idempotent
  (`CREATE ... IF NOT EXISTS`).
- **UI:** on a real device (Android + iOS/Web), selecting `Restaurants` then `Cafes` re-queries and
  shows individual café pins within radius; a region with zero cafés shows an honest empty state.
- **Screenshot (required):** real-device capture of Map with Restaurants+Cafes chips and ≥3 live pins,
  and the "why this place" bottom panel open on one pin.

---

## 5. Slice RE-2 — Local Restaurant Tour (exploration surface)

**Verdict today:** a proto exists (`tour_helpers.dart::tourGuideScript`, `restaurantTourPlaces`,
`home_page.dart::_fetchTourAudio`). It is **not** the GATE-B(4) first-class screen with category
chips and per-stop grounded narration.

### 5.1 Target (GAP + GATE)
A dedicated **"지역 식당 투어 / Local Restaurant Tour"** surface that:
1. Lets the user pick a **category chip** (`전통 음식 / 카페 / 디저트 / 파인 푸드`) wired to the §4.2
   cuisine facet (data-driven, bilingual).
2. Builds a compact walking route of ≤5 nearby restaurants from **live** `/api/v1/places` results
   (re-uses `restaurantTourPlaces`), ranked by the `local-value-v2` score + walkable distance.
3. Narrates each stop with **grounded local-food narration** and a **clear reason to visit**, derived
   from real signals: distance, `small_merchant_fit_score`, `local_spending_score`, and review
   attributes (`taste`/`atmosphere`). Narration text must be **paraphrased structured attributes +
   short evidence phrases** — never copied review content (§1.4, §16).

### 5.2 Rationale generation (transparent, optional)
Extend the existing docent rationale (`docent_service._ko_score_sentence`/`_en_score_sentence`) with
a **tour-mode** variant that, per stop, emits one sentence on *why it helps the local experience /
local economy*, e.g. referencing small-merchant fit and local-spending signal — only when the
underlying scores are present and above a confidence floor; otherwise it states "limited local
signal" honestly. Rationale is **opt-in** (a "왜 추천하나요? / Why this stop?" affordance), matching the
brief's *"short, user-requested explanation"*.

### 5.3 Acceptance criteria
- **Screen:** selecting a chip re-queries live data; route has ≥1 and ≤5 stops; each stop shows
  name (KO/EN per UI mode), distance, and one optional rationale line.
- **Narration honesty:** if no restaurant matches the chip in radius, the screen shows an honest
  empty state (no fabricated stops, no demo names like "Hwaseong Black Street" unless that row exists
  in the live DB).
- **Bilingual:** KO mode shows KO chips/names; EN mode shows EN — never mixed in one mode.
- **Screenshot (required):** real-device capture of the Tour screen with one chip selected, ≥3 live
  stops, and the rationale line visible on one stop.

---

## 6. Slices RE-3 / RE-4 — Economy Ingestion & Review Attributes

### 6.1 RE-3 Aggregate card-spend + local signal (CONFIRMED → harden)
- `card_spending_ingest` is aggregate-only and sha256-deduped (§1.3). **Privacy invariant:** no
  personal consumer rows; only region × industry × month × demographic aggregates. This invariant is
  enforced by schema (`economy.card_spending_area_monthly` has no cardholder/user columns) and must
  be asserted by a test (§11).
- **Portable worker contract (timer):** ingestion is a CLI tool
  (`apps/api/app/tools/run_card_spending_file_ingest.py`) wrapped by a **scheduler-agnostic runner**
  — cron, GitHub Actions schedule, AWS EventBridge, or a container worker. The contract is:
  `tool(dsn, source_uri, year) → idempotent upsert → ops.job_runs row`. **Do not port Azure
  Functions**; the timer is the only portable primitive. Re-runs are safe (sha256 dedup).
- **Local signal:** `community.place_mentions_weekly` (community crawl output) feeds
  `review_quality_score` and ranking via `place_score_batch` — already wired; do not copy crawl
  payloads (§1.4).

### 6.2 RE-4 Review-derived food/service/atmosphere attributes (CONFIRMED → coverage)
- `review_attribute_batch.RESTAURANT_ATTRIBUTES = (taste, service, price, atmosphere, cleanliness,
  wait_crowding)` already matches GATE-C's "LLM 요약" intent. Persisted as structured attributes +
  `review_quality` (§1.3).
- **Gap (coverage):** per `docs/operations/sentiment-attribute-scoring-strategy.md`, review quality
  is real but sparse until more approved mention sources are ingested. Plan: grow the approved
  mention pool (community ingestion slice, separate plan) and keep `review_quality_score` null below
  3 organic reviews — surfaced honestly as "limited review signal" in UI.
- **No review text leakage:** evidence phrases are short (≤28 chars) and paraphrased; the docent
  attraction-review noise guard (`docent_service._is_noisy_attraction_review_context`) prevents food
  text contaminating attraction context.

---

## 7. Slice RE-5 — Daily Plan with Weather/Air Context & Reasoned Substitution (GATE-D)

**Verdict today:** `planner_service.daily_plan` is **thin** (morning + weather slot only); legacy
had 4 slots with meal categories (§1.1). GATE-D requires full weather-aware meal substitution.

### 7.1 Target (GAP)
- Restore a **slot schema** (morning / lunch / afternoon-snack / dinner) where lunch/dinner are
  **restaurant** slots filtered by the §4.2 meal facet (re-derived, not the legacy term list).
- **Reasoned substitution:** when `weather_service` reports bad outdoor status (rain/dust/heat/cold/
  wind per the ASA flags), the planner swaps outdoor → indoor (`is_indoor=true`) and emits a per-slot
  **reason** (re-uses `_intervention_reason` shape). This is GATE-D scenario A↔B.
- Substitution must use **live** candidate places; if no indoor candidate exists, return an honest
  "no indoor alternative found" note rather than fabricating one.

### 7.2 Acceptance criteria
- **API:** `POST /api/v1/plans/daily` returns ≥2 slots including a meal slot whose `place` is a real
  restaurant; a `reason` field explains any weather-driven swap.
- **Determinism:** identical `(lat,lng,radius_m,language,weather)` yields identical slots (no
  `Math.random`/`Date.now` in the path — consistent with repo-wide constraint).
- **Screenshot (required):** real-device Daily Plan under a simulated bad-weather scenario showing an
  indoor swap with a reason line, and a clear-weather plan with an outdoor + terrace-lunch slot.

---

## 8. Slice RE-6 — Fair Ranking, Confidence & Unmatched Handling

### 8.1 Fair ranking (CONFIRMED, document the divergence)
- `local-value-v2` (7 components) is the owned formula. The legacy 0.4/0.6 + 150 m are **not** the
  target. Document weights in `docs/data/data-dictionary.md` (already partly present,
  §1.3) and in the `place_score_snapshots.features` JSON so every score is auditable.
- **Fair-ranking guarantees to assert:** (a) no single source can dominate (weights sum to 1.0 with
  renormalization over present components); (b) franchise classification can only **reduce**
  `small_merchant_fit_score` (a national franchise never outranks an independent local on that
  component); (c) scores are snapshotted with `formula_version` for reproducibility.

### 8.2 Confidence & unmatched handling (CONFIRMED → surface in UI)
- `analytics.place_business_identity` already carries `franchise_match_confidence` and `unknown`.
- **Target:** expose a **data-basis/confidence summary** in `/api/v1/places` responses (e.g.
  `features.missing_signals`, already computed in `place_score_batch._features`) so the UI can show
  *"recommendation based on partial signals"* honestly. Unmatched places show `unknown` and a neutral
  baseline (`baseline_place_score`), never a fabricated high score.

### 8.3 Feedback / evaluation metrics for local visit & spend dispersion (TARGET)
The `demand_dispersion_score` is **forward-looking** (it rewards places that disperse demand beyond
crowded hubs). There is **no closed loop** measuring whether recommendations actually dispersed local
visits/spend. Add:
- **Anonymous feedback signal:** an opt-in, **session-level only** "visited / saved / not-for-me"
  action (consistent with legacy `user_action_log` session-UUID, no user ids — §1.1, and LALA-next's
  richer `identity` model must **not** be used to profile individuals). Aggregate to
  `analytics.recommendation_feedback` (new, additive): `(place_id, category, day, action_counts)`.
- **Dispersion metric (eval):** a periodic eval (offline, fixture-based) computing the Gini /
  Herfindahl of recommended-place visit/save concentration per region vs. a card-spend-only baseline.
  This measures the product goal ("helps local economy by dispersing demand to small merchants")
  **without** tracking any individual. Results land in `ops.job_runs` + an eval report artifact.
- **Privacy:** feedback is aggregate and session-anonymous; no join to user identity for scoring.

---

## 9. Cross-Cutting Contracts

### 9.1 Schema/API contracts (pins this plan must publish)
- **Migration (additive):** `cuisine_taxonomy`/`cuisine_code` on `travel.places`; `analytics.
  recommendation_feedback` table; optional `tour_route_cache` mirroring the docent-cache key shape
  (`place_id, category, language, mode` → re-derive, do not copy legacy TTL verbatim).
- **API:** `/api/v1/places` facet params (§4.2); `/api/v1/plans/daily` slot+reason (§7);
  `/api/v1/taxonomies` for data-driven chips; tour route via existing docent/tour helpers.
- **Envelope:** unchanged `success_envelope` with `meta.source` honesty.

### 9.2 Model policy (CONFIRMED knobs → formalize)
Map the mandated policy to existing config (no new infra):

| Workload | Deployment knob (`.env.example`) | Selector symbol |
| --- | --- | --- |
| High-volume review extraction / normalization / **ad classification** | `AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT` = **gpt-5.4-nano** | `review_attribute_batch.selected_review_batch_model` |
| Low-confidence recheck + **all docent generation / QA** | `AZURE_OPENAI_DOCENT_DEPLOYMENT` = **gpt-5.4-mini** | `ai_service.selected_docent_model` |
| Embeddings | `AZURE_OPENAI_EMBEDDING_DEPLOYMENT` = `text-embedding-3-small` | (collectors) |

- **TARGET:** add a **low-confidence recheck** stage to `review_attribute_batch`: any mention whose
  nano extraction has `attribute_confidence_avg < 0.6` or `organic_mention_count < threshold` is
  re-scored once by the **mini** deployment before apply. This realizes the "mini for low-confidence
  recheck" rule.
- **TARGET:** route **ad classification** (organic vs. promotional) through the **nano** deployment
  (deterministic pre-filter already exists via `filtered_ad_count`; nano classifies ambiguous rows).

### 9.3 Portable worker contract (timer/queue)
For any timer/queue need (card ingest, franchise reference refresh, score batch, feedback rollup,
dispersion eval): a CLI tool under `apps/api/app/tools/run_*.py` invoked by a **scheduler-agnostic**
runner with: idempotent upsert (sha256 or `ON CONFLICT`), `ops.job_runs` recording, bounded retries
with exponential backoff (re-use `review_attribute_batch._is_retryable_ai_error` predicate shape),
and a dry-run mode. **Do not port Azure Functions.** The container/scheduled-worker model
(`apps/workers`) is the execution substrate.

### 9.4 Retry / idempotency / observability
- **Idempotency:** card-spend sha256 dedup; franchise `ON CONFLICT (primary_source, source_record_id)`;
  score snapshots append-only with `formula_version`; feedback rollup keyed by `(place_id, day)`.
- **Retries:** transient AI errors (408/409/429/5xx) retried with backoff; non-retryable errors raise
  `ServiceError(retryable=False)`.
- **Observability:** every batch writes `ops.job_runs`; the non-mutating `observability_plan` covers
  health; AI calls carry `DOCENT_AI_TIMEOUT_SECONDS=5.0` and degrade to rule-based.

### 9.5 Legal data-source & privacy constraints
- **Sources are public open-data:** 공정위 가맹정보 (fair-trade franchise), Gyeonggi card-sales
  **aggregates**, Gyeonggi restaurant-license master, KMA/AirKorea weather/air. Each row records
  `primary_source`. No scraping of gated/ToS-forbidden data; community crawl is a **separate,
  approval-gated** slice (not in this plan's scope).
- **No personal consumer tracking:** card data is aggregate; feedback is session-anonymous and never
  joined to identity for scoring; location consent is explicit (`home_page.dart` consent flow).
- **Copyright:** review/mention content is **never** re-emitted; only paraphrased structured
  attributes + short evidence phrases.

### 9.6 Costs / quotas / risks
- **Costs:** nano for bulk review/ad work (cheap, high-volume); mini reserved for docent + recheck
  (lower volume, higher quality). Embeddings batch-generated for cost. Rate-limit
  `enforce_public_contest_paid_route_limit` already guards docent endpoints.
- **Quotas:** AI dry-runs may be throttled by provider quota (per sentiment-attribute doc); retry
  before judging windows.
- **Risks:** (1) sparse review/mention pool makes `review_quality_score` null for many places →
  honest "limited signal" UI, never a fake score; (2) cuisine taxonomy drift → publish via
  `/api/v1/taxonomies` + version it; (3) feedback dispersion metric could leak if joined to identity
  → enforce aggregate-only invariant by test; (4) franchise false positives → confidence gating +
  `unknown` fallback + UI surfacing.

---

## 10. Acceptance Evidence Matrix (implemented vs target)

| Gate | Capability | Implemented evidence | Target (gap) | Required screenshot (real device) |
| --- | --- | --- | --- | --- |
| GATE-A | Map + Daily Plan on Gyeonggi | `/api/v1/places`, `/api/v1/plans/daily`, `home_page.dart` | — (parity check) | Map + Daily Plan, live data |
| GATE-B(2) | Map-first discovery + category/cuisine/indoor chips + individual markers + "why" panel | category chips, individual pins, fair ranking | cuisine/meal/diet/indoor facet (§4.2) | Map: Restaurants+Cafes, ≥3 pins, panel open |
| GATE-B(4) | Local Restaurant Tour with real chips + grounded narration | `tour_helpers.dart` proto | first-class screen + data-driven chips + per-stop rationale (§5) | Tour screen, chip selected, ≥3 stops, rationale |
| GATE-C | card + reviews + weather → LLM/RAG → docent | ingest + attributes + docent | low-confidence recheck; ad-classification via nano (§9.2) | Docent script with score rationale, KO + EN |
| GATE-D | Weather-aware meal substitution with reason | `intervention` bad-weather flag | full slot schema + reasoned swap (§7) | Daily Plan: bad-weather indoor swap + clear plan |
| §8.3 | Feedback / dispersion eval | `demand_dispersion_score` (forward) | anonymous feedback + dispersion eval (§8.3) | eval report artifact (offline, not a UI screenshot) |

> **Screenshot policy:** all screenshots must be captured **from a real device** (Android + iOS/Web)
> against live `/api/v1/*` data, immediately before acceptance (production data/map tiles change).
> OCR/pixel-diff are secondary checks only and do not prove capability on their own. No screenshot in
> this doc is asserted to exist yet — they are **required artifacts**, not current evidence.

---

## 11. Test / Eval Fixtures

- **Unit (extend existing `apps/api/tests/`):**
  - `test_recommendation_scoring` — weight renormalization over missing components; franchise can
    only reduce `small_merchant_fit_score`.
  - `test_franchise_identity` — confidence gating; `unknown` fallback; coordinate-vs-name match.
  - `test_card_spending_ingest` — **assert no personal columns exist** (privacy invariant); sha256
    dedup; aggregate-only.
  - `test_places_service` + new `test_places_facets` — cuisine/meal/indoor filtering; invalid facet
    → 400; empty → honest `count:0`.
  - `test_planner_service` — bad-weather indoor swap emits a `reason`; determinism.
- **Eval fixtures (new, offline):** a small, **synthetic/curated** fixture of restaurant + aggregate
  card + mention rows (no real personal data) to compute the dispersion metric and exercise the
  nano→mini recheck path. Fixtures are authored, never scraped.
- **No legacy fixtures copied.**

---

## 12. Phased Milestones

Each phase is independently shippable and ends with the acceptance screenshot(s) for its gates.

- **Phase 0 (this PR):** plan-only document. No source/infra changes. DRAFT PR to `main`.
- **Phase 1 — Facets (GATE-B(2)):** additive migration + `/api/v1/places` facet params +
  `/api/v1/taxonomies` + Flutter data-driven chips. AC: §4.3.
- **Phase 2 — Local Restaurant Tour (GATE-B(4)):** Tour screen, data-driven chips, per-stop grounded
  rationale + tour-mode docent variant. AC: §5.3.
- **Phase 3 — Weather-aware plan (GATE-D):** slot schema + meal facet + reasoned substitution. AC: §7.2.
- **Phase 4 — Model policy + coverage (GATE-C):** nano→mini low-confidence recheck; ad-classification
  via nano; grow approved mention pool (cross-slice). AC: §9.2.
- **Phase 5 — Confidence surfacing + feedback/eval (§8):** data-basis/confidence in places response;
  anonymous feedback ingest; dispersion eval. AC: §8.3.

---

## 13. Validation Performed for This Plan

- **`git diff --check`** will be run before commit (whitespace/conflict markers).
- **Link validation:** all links in this doc are repo-relative (`./legacy-3dt-first-*.md`) or public
  open-data service references already present in the codebase (`getBrandFrcsStats`). No invented URLs.
- **Clean-room check:** no legacy source, prompt text, food keyword list, review text, secret, or
  resource identifier is reproduced — only `path :: symbol :: behavior` citations.

---

## 14. Open Questions (non-blocking, for downstream slices)

1. Cuisine taxonomy authority: derive purely from restaurant-license `bizcond_div_nm_info`, or also
   from review-derived `taste` attributes? (Default: license-derived, review-enriched.)
2. Tour route length: fixed 5 vs. walk-time-bounded? (Default: ≤5, compact walk.)
3. Should the dispersion eval gate ranking weights, or remain a reporting metric? (Default: reporting
   only for v1.)

---

## 15. Out of Scope (explicit)

- Community crawl live execution (approval-gated, separate plan; this plan only consumes its
  aggregated `place_mentions_weekly` output).
- Power BI / ops dashboard parity (deferred, per spec §14).
- iOS MapKit migration (Flutter/Kakao is the target; legacy clustering thresholds are not ported).
- Any change to product source or infrastructure — **this PR is documentation only.**

---

## 16. Clean-Room Boundary (restaurant/economy do-not-carry list)

Reaffirmed for this domain:

- **No legacy code** (`process_restaurants.py`, `restaurant_docent.py`, `daily_planner.py`,
  `restaurant_filter.py`, `load_restaurant_review.py`, `hybrid_place_matching.sql`).
- **No legacy prompts/persona** (restaurant food-guide persona, `analyze_reviews_with_llm` prompt).
- **No food keyword lists** (`점심음식점`/`저녁음식점`/`저녁카페` exclusion term sets; the legacy
  food-detection Korean terms). Re-derive a minimal, versioned cuisine taxonomy.
- **No review/mention text or crawl payloads.**
- **No legacy weights as truth** (0.4/0.6, 150 m, top-10). `local-value-v2` owns the formula.
- **No secrets/resource identifiers** (franchise API keys, card-data credentials, endpoints beyond
  the public 공정위 service URL).
- **No legacy assets** (`.pbix`, `stations.json` beyond public KMA grid, images/CSS).

What **may** be re-implemented (interface/contract shapes, largely already present in LALA-next):
the `/api/v1/places` envelope, the 7-component score contract, the franchise-classification output
shape, aggregate card-spend tables, review-attribute schema `review-attributes-v1`, and the
docent-cache key shape.
