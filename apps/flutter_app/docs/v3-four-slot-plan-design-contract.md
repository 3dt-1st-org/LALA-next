# V3 Four-Slot Plan Design Contract — weather · air quality · closure · disruption response (ADOPTED)

> **Status: ADOPTED contract for the V3 controller.** Doc-only design contract; the author was
> read-only on all product code and committed nothing except this file. Every code claim below was
> independently re-verified against the V1+V2 code-complete state at
> `15bbf8fff9854bf0b51835fb482f9ad672e51ab6` (branch `geondongkim/lala-v3-four-slot-enrichment`)
> via `git show` / `git grep` (read-only by SHA). This doc supersedes the watchdog draft; all
> draft citation errors are corrected here.
>
> **Roadmap line (V3 scope):** *"V3: four-slot plan with weather, air quality, closure, and
> disruption response."*
>
> **Format precedent.** Mirrors the layout and honesty discipline of
> `apps/flutter_app/docs/v1-cross-tab-state-design-contract.md` and
> `v1-bounds-query-design-contract.md` (§0 file:line audit → decision register → wireframe →
> binding/state matrix → acceptance matrix → disjoint lanes → non-goals/BLOCKED_EXTERNAL).
>
> **Hard constraints (carry through every lane).** Additive-only on the generated-client SSOT and
> OpenAPI canonical schema. Generated client stays `fromJson`-only with **zero** `toJson`; OpenAPI
> slot/intervention schemas stay `additionalProperties: False`. App-owned encoders only (precedent:
> `cross_tab_preferences.dart::encodeLalaDailyPlan`). NO prod migration-apply (additive migration
> files OK only if strictly required and flagged). NO live alert/weather/AI provider calls —
> `BLOCKED_EXTERNAL = V7`. Real temporary/holiday closure + live alert feeds = `BLOCKED_EXTERNAL`;
> UI shows honest "(추정)/(est.)" for every estimated state. NO mock/demo on the normal path.
> KO/EN single-language (mutually exclusive). Preserve Kakao map / Logto / Geolocator +
> `browser_location` conditional imports / category colors / pin-first clustering. Standard OpenAI
> only (never Azure); never print keys.

---

## TL;DR — the one fact that reshapes the whole V3 scope

**The four-slot plan, plan-level weather, plan-level air quality (dust), the category-based
opening-hours estimate, and a weather-driven disruption intervention already exist and ship in the
V1+V2 code at `15bbf8f`.** V3 is therefore an **enrichment + surfacing** effort over
already-working structures — **not** a build-from-scratch of the four-slot plan, and **not** a
destructive reshape of `LalaDailyPlan` / `LalaPlanSlot`. The contract below is additive-only on the
generated client SSOT and the OpenAPI canonical schema.

The V3 real decisions are **(a) granularity** (per-slot weather/AQ projections vs. plan-level),
**(b) honest closure promotion** (turn the existing estimate into an explicit open/closed/unknown
slot field without inventing a real-hours authority), and **(c) disruption trigger expansion**
(closure-driven swaps, not just weather) without assuming any live alert feed.

---

## 0. Audit — verified at `15bbf8f` this session

All file:line below were re-pinned by `git show` / `git grep` against the frozen SHA. These are the
authoritative touch-points the V3 lanes edit.

### 0.1 Four-slot structure (D1 substrate)

| Fact | Verified at (`15bbf8f`) |
|---|---|
| `_PERIOD_ORDER = ("morning","lunch","afternoon","dinner")` — fixed-order 4-tuple | `apps/api/app/services/planner_service.py:162` |
| `_daily_plan_slots()` def + docstring *"정확히 4 period 슬롯(morning/lunch/afternoon/dinner)을 발생한다(순서 고정)"* | `planner_service.py:165` (def), `:166-172` (docstring) |
| 4-slot list comprehension consuming `_PERIOD_ORDER` | `planner_service.py:263-266` |
| Conventional start times table | `apps/api/app/services/travel_time_service.py:19` (`_PERIOD_START_TIMES`), surfaced via `period_start_time()` at `:52` |
| Deterministic allocation (restaurant→meals, other→morning/afternoon, dedup) | `planner_service.py:202-235` (`_take_deduping`, `_take_restaurant`/`_take_other`) |

> **Correction vs draft:** draft cited `_PERIOD_ORDER` at `planner_service.py:155` and the docstring
> at `:165`. **The symbol EXISTS** (the watchdog hint that it was absent was itself inaccurate);
> the real location is `:162`, docstring at `:166-172`. Corrected throughout this doc.

### 0.2 Plan-level weather + air quality (D2/D3 substrate — V3-A projects FROM these)

| Fact | Verified at |
|---|---|
| `current_weather(*, lat, lng)` — the single weather authority per plan | `apps/api/app/services/weather_service.py:75` |
| planner calls it once per `daily_plan()` | `planner_service.py:19` (call), `:26` (assigned to `weather` key) |
| `_merge_outdoor_status_with_dust(status, dust)` — AQ already flips `outdoor_status` to `bad` (bad weather **or** bad dust) | `weather_service.py:478` (def), `:479` (logic) |
| `_dust_outdoor_status(dust)` — dust→outdoor_status mapping | `weather_service.py:474` |
| Honest-empty forecast paths (`"forecast": []`) | `weather_service.py:125` (AirKorea-dust-only), `:142` (fully-unavailable), `:238` (KMA no-data) |
| Per-slot `weather_hint = weather.get("outdoor_status")` — the **same** plan status copied into every slot (no per-slot forecast) | `planner_service.py:180` (compute), passed into `_plan_slot` at `:264` |
| `build_dust_payload()` / `unknown_dust_payload()` — existing honest-empty dust authority | `apps/api/app/services/dust_quality.py:41` (build), `:21` (unknown) |
| Client `LalaWeather` / `LalaDust` / `LalaForecastItem` | `clients/flutter/lib/lala_api_client.dart:1187` / `:1240` / `:1275` |

> **Correction vs draft:** draft cited `LalaDust` at `:1203` and `dust` on `LalaWeather` at `:1200`.
> Real: `LalaWeather` at `:1187`, `LalaDust` at `:1240`. Corrected.

### 0.3 Closure estimate (D4 substrate — V3-A promotes this to `closure_state`)

| Fact | Verified at |
|---|---|
| `_CATEGORY_HOURS` / `_DEFAULT_HOURS` (restaurant 11-22, attraction 09-18, culture_venue 10-19, event 00-23:59, default 09-21) | `apps/api/app/services/opening_hours_service.py:12` / `:19` |
| `estimated_opening_hours(category)` — the category estimate | `opening_hours_service.py:22` |
| `is_within_hours(slot_time, open, close)` → bool\|None | `opening_hours_service.py:30` |
| planner computes per slot: `open_t,close_t` at `:305`, `oh_valid = is_within_hours(...)` at `:306` | `planner_service.py:305-306` |
| planner emits `opening_hours_valid` at `:317`, `estimated_opening_hours` at `:318` | `planner_service.py:317-318` |
| **PRE-EXISTING SCHEMA BUG (NEEDS_CODE for V3-A):** in `_daily_plan_slot_schema`, `estimated_opening_hours` is **nested inside** the `opening_hours_valid` property dict instead of being a sibling. Runtime emits them as siblings (`planner_service.py:317-318`) and the client parses `estimated_opening_hours` at top level (`lala_api_client.dart:1440`), but the OpenAPI schema is malformed. | `apps/api/app/core/openapi.py:916-923` (nested), `:946` (`additionalProperties: False`) |

> **V3-A obligation:** when editing the slot schema to add the new V3 fields, **hoist
> `estimated_opening_hours` to a sibling property** of `opening_hours_valid` (one-line structural
> fix). The current nesting is masked only because response validation is not strictly enforced; it
> must not be carried forward into the V3 schema edit. Flagged NEEDS_CODE.

> **Correction vs draft + task hint:** (a) draft cited `_CATEGORY_HOURS` at `opening_hours_service.py:21-31`
> and `is_within_hours` at `:46-69`; real lines are `:12`/`:19`/`:22`/`:30`. (b) The slot fields are
> **`travel_time_from_previous_minutes`** and **`opening_hours_valid`** / **`estimated_opening_hours`** —
> NOT `walking_minutes` / `within_estimated_hours` (the task hint's field names do not exist in the
> code). Corrected.

### 0.4 Disruption response (D5/D6 substrate — V3-A widens trigger + populates alternatives)

| Fact | Verified at |
|---|---|
| `intervention(*, lat, lng, radius_m, language)` | `planner_service.py:43` |
| `is_bad_weather = outdoor_status == "bad"` — the **only** trigger predicate today | `planner_service.py:57` |
| `"trigger_type": "bad_weather" if is_bad_weather else None` — **literal string**, NOT a module-level enum/set (additive widening is a one-line edit) | `planner_service.py:100` |
| `_intervention_trigger_factors(*, outdoor_status)` returns `[{"factor":"weather_outdoor_status","value":"bad"}]` | `planner_service.py:115-120` |
| `_find_indoor_alternative(...)` — the only response today (indoor swap via `is_indoor` provenance) | `planner_service.py:122` |
| OpenAPI `_intervention_data_schema`: `trigger_type` is `anyOf [string, null]` (additive-safe); `trigger_factors[].items` is `additionalProperties: False`; schema `additionalProperties: False` | `apps/api/app/core/openapi.py:983` (def), `:1005` (`original_slot`), `:1012` (`alternative_slot`), `:1019-1022` (`trigger_type`), `:1023-1035` (`trigger_factors`), `:1054` (schema closed) |
| Route `GET /api/v1/plans/intervention` | `INTERVENTION_PATH` at `openapi.py:20`; handler at `apps/api/app/routers/v1.py:188-195` |
| `swappable_alternatives` hard-coded `[]` on every slot (gap V3 fills) | `planner_service.py:322`; OpenAPI at `:936-940` (*"Empty until swap-authority is available."*) |
| Candidate pool source for V3-D6: `list_places(...)` (category=`"all"`) → `place_candidates`; split into `restaurants`/`others`, deduped via `_take_deduping` | `places_service.py:31` (`list_places`); `planner_service.py:19` (fetch), `:177-178` (split), `:202-220` (dedup) |
| Client `LalaIntervention`: `originalSlot`/`alternativeSlot`/`triggerType`/`triggerFactors` | `clients/flutter/lib/lala_api_client.dart:1457` (class), `:1487-1490` (fields), `:1517-1518` (parse) |

> **Correction vs draft:** draft cited `is_bad_weather` at `:70`, `trigger_type` at `:97`, client
> `LalaIntervention` at `:1468`, `triggerType` at `:1501`. Real: `:57`, `:100`, `:1457`, `:1489`/`:1517`.
> Corrected.

### 0.5 Cross-tab SSOT + persistence (D7 substrate — V3 must not regress)

| Fact | Verified at |
|---|---|
| `PlanContextStore` — static `ValueNotifier<LalaDailyPlan?>` singleton; `.set`/`.current`/`.listenable`/`.clear` | `apps/flutter_app/lib/core/state/plan_context_store.dart:22` (class), `:25-26` (`_notifier`), `:30` (`listenable`), `:33` (`current`), `:38` (`set`), `:41` (`clear`) |
| Lane 2 persistence intent (versioned DTO under `lala.crosstab.v1.*`) documented in-file | `plan_context_store.dart:6-8` |
| App-owned encoder (NO generated `toJson`): `encodeLalaDailyPlan` + per-field encoders | `apps/flutter_app/lib/core/persistence/cross_tab_preferences.dart:189` (no-toJson comment), `:197` (`encodeLalaDailyPlan`), `:248` (`_encodePlanSlot`) |
| `plan_page.dart` listens + writes through `PlanContextStore` | `:143` (`addListener`), `:313` (`PlanContextStore.set`) |

### 0.6 Generated-client SSOT invariants (the constraint V3 must preserve)

| Invariant | Verification at `15bbf8f` |
|---|---|
| `toJson` occurrences in the generated client | `grep -cE "toJson" clients/flutter/lib/lala_api_client.dart` → **0** ✅ |
| OpenAPI slot schema `additionalProperties: False` | `openapi.py:946` ✅ |
| OpenAPI plan-data schema `additionalProperties: False` | `openapi.py:979` ✅ |
| OpenAPI intervention schema `additionalProperties: False` | `openapi.py:1054` ✅ |
| App-owned (not generated) serialization precedent | `cross_tab_preferences.dart:197` ✅ |

> Note: the Dart client itself contains no `additionalProperties` token — that is an OpenAPI-side
> constraint that drives generation. The invariant is correctly stated as "OpenAPI schemas closed
> (`additionalProperties: False`) + generated client is `fromJson`-only with zero `toJson`."

### 0.7 Current-state audit register (corrected from the draft)

| Claim | Verified at | Verdict |
|---|---|---|
| `LalaDailyPlan = {language, center, radiusM, weather, slots, source, requestHash, cacheKey}` | `lala_api_client.dart:1344-1376` | ✅ |
| `slots` is a list; backend hard-emits exactly 4; client does not enforce a count | client `:1360,1375` (list); backend `_PERIOD_ORDER` 4-tuple + docstring "정확히 4" at `planner_service.py:162,166` | ✅ |
| `LalaPlanSlot` fields today: `period`, `title`, `place?`, `weatherHint?`, `startTime?`, `stayDurationMinutes?`, `travelTimeFromPreviousMinutes?`, `estimatedOpeningHours?`, `openingHoursValid?`, `indoorOutdoor?`, `recommendationReason?`, `localFranchiseConfidence?`, `swappableAlternatives`, `unavailableReason?` | `lala_api_client.dart:1383-1455` | ✅ |
| `weatherHint` per slot = plan `outdoor_status` copied verbatim (no per-slot forecast) | `planner_service.py:180,264`; merge at `weather_service.py:478-479` | ✅ |
| `stayDurationMinutes` always null; `travelTimeFromPreviousMinutes` = Haversine÷4km/h (first/no-place → null) | `planner_service.py:315` (null), `:256` (walking), `travel_time_service.py:37` | ✅ |
| `estimatedOpeningHours` category estimate, "NOT authoritative" | `opening_hours_service.py:12,19,22`; planner `:305,318`; UI marker obligation in client `:1414` | ✅ |
| `openingHoursValid` = slot conventional `start_time` within estimated hours (T/F); None when no place / unparseable | `opening_hours_service.py:30`; planner `:306,317` | ✅ |
| `swappableAlternatives` always `[]` | `planner_service.py:322`; openapi `:936-940` | ✅ gap V3 fills |
| `indoorOutdoor` from `place.is_indoor`; null when absent | `planner_service.py:300-301` | ✅ |
| AQ (dust) plan-level on `LalaWeather.dust`; no per-slot dust | `lala_api_client.dart:1187` (`LalaWeather`), `:1240` (`LalaDust`) | ✅ |
| Dust already flips `outdoor_status` → already feeds every slot `weather_hint` | `weather_service.py:478-479` | ✅ |
| `LalaIntervention` GET; weather-only trigger; indoor-alternative response; `userDecision`/`applyState` boundary | `openapi.py:983,1005,1012,1019,1040-1047`; `routers/v1.py:188-195`; `planner_service.py:43-110`; client `:1457-1530` | ✅ |
| Only trigger = `outdoor_status == "bad"` (`trigger_type="bad_weather"`) | `planner_service.py:57,100,115-120,122` | ✅ gap V3 expands |
| No event-cancellation / live-alert / holiday / temporary-closure concept | `git grep -niE "cancellation|reroute|live.alert|holiday|temporary.closure|폐업|휴무|갑작" apps/api apps/flutter_app` → no hits | ✅ gap (BLOCKED_EXTERNAL) |
| Plan surface renders plan-level weather banner (`PlannerOverviewCard`) + `PlanSlotTile` list | `plan_page.dart:749` (overview), `:762` (slot list); `plan_slot_tile.dart`; `planner_overview_card.dart` | ✅ |
| `estimatedOpeningHours`/`openingHoursValid`/`swappableAlternatives` NOT rendered in `PlanSlotTile` today | `plan_slot_tile.dart` grep → no render hits | ✅ gap V3 surfaces |
| `PlanContextStore` is sole cross-tab plan SSOT | `plan_context_store.dart:22-41`; `plan_page.dart:143,313` | ✅ |
| Generated client = SSOT; `fromJson`-only; zero `toJson`; OpenAPI canonical | `grep -c toJson clients/flutter/lib/lala_api_client.dart` → 0; schemas `openapi.py:895,950,983` | ✅ constraint |
| OpenAPI slot schema `additionalProperties: False` (additive fields require schema edit + regen) | `openapi.py:946,979,1054` | ✅ constraint |
| Feature flags `PLAN_FULL_SLOTS` / `PLAN_WEATHER_SUBSTITUTE` available for V3 gating | `apps/api/app/core/feature_flags.py:185,192` | ✅ |

---

## 1. Scope interpretation — delta over the V1+V2 baseline

| Roadmap noun | V1+V2 baseline (already ships) | V3 delta (this contract) |
|---|---|---|
| **four-slot plan** | 4 fixed periods, fixed conventional start times, deterministic deduped allocation | **No structural change.** Promote count + order + period semantics into a hard invariant (D1). Add per-slot `closure_state` + optional `forecast_window` + `air_quality_bad` (D2/D3/D4). |
| **weather** | Plan-level `LalaWeather`; per-slot `weather_hint` = plan status | Optional additive per-slot `forecast_window` drawn from **existing** plan-level `weather.forecast` by nearest-time match — **no new weather call** (D2). Plan-level stays SSOT. |
| **air quality** | Plan-level `LalaWeather.dust`; dust flips `outdoor_status` | AQ **stays plan-level** (one station per region; per-slot would be fabricated). V3 names the existing chain + adds outdoor-only `air_quality_bad` projection (D3). |
| **closure** | Category-based `estimated_opening_hours` + `opening_hours_valid` | Promote to per-slot `closure_state: open\|closed\|unknown` (projection); surface "(추정)/(est.)" marker (D4). Real temporary closure = honest `unknown`. |
| **disruption response** | `LalaIntervention`, weather-only trigger, indoor-alternative response | Expand trigger to `{bad_weather, closure_detected}` derived **offline** from slot `closure_state`; populate `swappable_alternatives` from existing pool (D5/D6). **No live alerts.** |

---

## 2. Decision register

Each decision is labeled, rationalized against the audit, and marked **additive** where it must not
break the generated-client SSOT or Lane 2 persistence.

### D1 — Four-slot is a HARD CAP + fixed period order (ratify reality, do not relax)

- **Decision:** The plan emits **exactly 4** slots in fixed order `morning → lunch → afternoon →
  dinner`, each with conventional start (09:00 / 12:00 / 14:00 / 18:00). "Four-slot" is a **hard
  cap**, not a default. A slot with no candidate keeps `place: null` + an honest
  `unavailable_reason` rather than being dropped — the count is always 4.
- **Rationale:** Already backend behavior (`_PERIOD_ORDER` at `planner_service.py:162`, docstring
  "정확히 4" at `:166`). Ratify as a contract invariant so downstream surfaces can rely on it.
- **Migration:** **None.** No change to `LalaDailyPlan` or `_PERIOD_ORDER`.

### D2 — Weather granularity: plan-level SSOT + OPTIONAL additive per-slot `forecast_window`

- **Decision:** `LalaDailyPlan.weather` (`LalaWeather`) **remains the only** weather/dust authority.
  V3 adds an **optional additive** per-slot `forecast_window: {time, temp, icon} | null` populated by
  **nearest-time matching** the slot's `start_time` against the **existing** plan-level
  `weather.forecast` list. **No new weather API call per slot.**
- **Rationale:** The plan already fetches one weather payload per region; re-querying per slot would
  violate the no-live-data-on-normal-path invariant. `LalaForecastItem{time,temp,icon}` already
  exists (`lala_api_client.dart:1275`), so `forecast_window` is a pure projection.
- **Honest-empty:** `forecast_window = null` whenever `weather.forecast` is empty (AirKorea-only /
  unavailable paths, `weather_service.py:125,142,238`).
- **Touch-point:** computed in `_plan_slot` (`planner_service.py:286`) using the `weather` arg.
- **Migration:** **Additive.** New nullable field on slot; OpenAPI slot schema gains
  `forecast_window` (nullable object, `additionalProperties` stays False); generated client gains a
  nullable parsed field.

### D3 — Air quality stays plan-level; make the existing chain explicit + outdoor-only `air_quality_bad`

- **Decision:** AQ (dust) **stays plan-level** via `LalaWeather.dust` (one station per region;
  per-slot AQ would be fabricated). V3: (a) documents the existing chain
  `dust.grade → _merge_outdoor_status_with_dust → outdoor_status → every slot.weather_hint`
  (`weather_service.py:478-479`) as the contract mechanism; (b) adds an optional additive per-slot
  boolean `air_quality_bad: bool | null` mirroring plan dust grade (`bad`/`very_bad` → true) **only
  for outdoor slots** (`indoor_outdoor == "outdoor"` or unknown) — a relevance flag, not a new
  source. Reuses `dust_quality.py` (`build_dust_payload` / `unknown_dust_payload`).
- **Honest-empty:** `air_quality_bad = null` when dust grade is `unknown` (never fabricate "bad").
- **Touch-point:** computed in `_plan_slot` (`planner_service.py:286`) from `weather_hint`/dust +
  `indoor_outdoor` (`:300-301`).
- **Migration:** **Additive** optional field.

### D4 — Closure: promote the existing estimate to per-slot `closure_state`

- **Decision:** Add additive per-slot `closure_state: "open" | "closed" | "unknown"`:
  - `"open"` ← `opening_hours_valid == true`
  - `"closed"` ← `opening_hours_valid == false`
  - `"unknown"` ← no place, OR `opening_hours_valid == null`, OR hours-unparseable
- Surface the **existing** `estimated_opening_hours` + mandatory "(추정)/(est.)" marker in
  `PlanSlotTile` (data present today, UI absent — gap §0.7).
- **Rationale:** The estimate + validity bool already exist (`opening_hours_service.py:22,30`;
  planner `:305-306,317-318`); `closure_state` is a pure projection giving the UI + disruption logic
  a single tri-state field.
- **Touch-point:** computed in `_plan_slot` (`planner_service.py:286`) from `oh_valid` (`:306`).
- **Hard honesty constraint — BLOCKED_EXTERNAL:** real temporary closure (holiday, sudden shutdown,
  observed closure) is **NOT knowable** from the category estimate. `closure_state` reflects the
  *estimate* only; UI must never present an estimated `open` as a guarantee. A real-hours authority
  (Kakao Places detail, public holiday hours) is a separate external lane = **BLOCKED_EXTERNAL**.
- **Migration:** **Additive.** Computed from existing fields at generation time.

### D5 — Disruption: expand triggers to `{bad_weather, closure_detected}`, offline-first, no live alerts

- **Decision:** Extend `LalaIntervention` so `trigger_type ∈ {null, "bad_weather",
  "closure_detected", "bad_weather_and_closure"}`:
  - `bad_weather` — existing (`outdoor_status == "bad"`, already includes bad dust).
  - `closure_detected` — **new**, derived **offline** from the plan's own slots: any slot whose
    `closure_state == "closed"`. No external feed.
  - `bad_weather_and_closure` — both.
- `trigger_factors` gains `{"factor": "slot_closure_state", "value": "closed", "period": "<period>"}`
  when a closed slot is detected — observable only, no invention.
- **Response UX** (reuses existing fields, no new contract surface):
  1. **Swap** — offer `swappable_alternatives[0]` (D6).
  2. **Regenerate** — re-call `POST /plans/daily` (`routers/v1.py:180`).
  3. **Notice** — existing `reason` / `recommended_action` copy + honest fallback.
- **Touch-point:** edit the literal at `planner_service.py:100` + `_intervention_trigger_factors`
  at `:115-120`; OpenAPI description at `openapi.py:1019-1022` (string+nullable, no schema break).
- **Hard honesty constraint — BLOCKED_EXTERNAL:** event cancellation, emergency closure, transit
  strike, weather *warning* feeds, push alerts = **all BLOCKED_EXTERNAL**. V3 disruption is
  self-contained (reacts only to facts in the plan). `user_decision`/`apply_state` boundary
  unchanged (API returns `pending`/`not_applied`; `openapi.py:1040-1047`).
- **Migration:** **Additive** enum widening on a string-typed nullable field.

### D6 — Populate `swappable_alternatives` from the existing candidate pool (empty → usable)

- **Decision:** Today `swappable_alternatives` is hard-coded `[]` (`planner_service.py:322`). V3
  populates it per slot from the **same** `_daily_plan_slots` candidate pool (places already fetched,
  deduped against the slot's assigned place + same-category preference), capped at 2–3. **No new
  fetch.**
- **Rationale:** Swap (D5) is useless without alternatives. The pool already exists
  (`list_places` at `places_service.py:31`; split/dedup at `planner_service.py:177-220`).
- **Honest-empty:** `[]` when the pool is exhausted. Never fabricate places.
- **Touch-point:** `_plan_slot` emit at `planner_service.py:322` + the assigned/dedup set at
  `:202-235`.
- **Migration:** **Content change**, not a schema change.
- **ASSUMPTION (§11-A1):** confirm real regions return ≥5–6 candidates so ≥1 alternative survives
  per slot after assignment.

### D7 — Composition with `PlanContextStore` + Lane 2 persistence (additive, no V1/V2 regression)

- **Decision:** All new slot fields ride on the **existing** `PlanContextStore` mechanism
  (`plan_context_store.dart:22-41`) unchanged — they live on `LalaDailyPlan`, which the store holds.
  Lane 2 persistence (versioned DTO under `lala.crosstab.v1.*`, `plan_context_store.dart:6-8`) must
  be regenerated-aware so additive fields serialize — but because the generated client is
  `fromJson`-only and the persistence DTO is a **separate app-owned structure**
  (`cross_tab_preferences.dart:197`), V3 is additive to both.
- **Migration:** Keep `lala.crosstab.v1.*` (additive nullable fields are forward-compatible; older
  snapshots read new fields as absent). Controller may bump to v2 if preferred — either is safe.

---

## 3. Data flow + single source of truth

```
                         POST /api/v1/plans/daily  (routers/v1.py:180 — existing)
                                    │
            ┌───────────────────────┼────────────────────────┐
            ▼                       ▼                        ▼
   current_weather(lat,lng)   list_places(...)         (no new calls)
   weather_service.py:75      places_service.py:31     V3 reuses these two
     → LalaWeather            → place_candidates        payloads ONLY
       {temp, icon,             [Place, …]
        dust: LalaDust,          (deduped, assigned
        forecast: […],           to 4 periods)
        outdoor_status}
            │                       │
            │  (D3: dust.grade already → outdoor_status via
            │   _merge_outdoor_status_with_dust — UNCHANGED)
            ▼
   _daily_plan_slots(place_candidates, weather, language)   planner_service.py:165
            │
            │  per period in _PERIOD_ORDER (morning,lunch,afternoon,dinner):  ← D1
            │   ├─ place            = assigned candidate (or null + unavailable_reason)
            │   ├─ weather_hint     = plan outdoor_status        (existing, :180)
            │   ├─ start_time       = 09/12/14/18                (existing, :314)
            │   ├─ estimated_opening_hours = category estimate   (existing, :318)
            │   ├─ opening_hours_valid = is_within_hours(...)    (existing, :317)
            │   ├─ closure_state    = open/closed/unknown ◀── D4 NEW (projection of :306)
            │   ├─ forecast_window  = nearest match in weather.forecast ◀── D2 NEW
            │   ├─ air_quality_bad  = outdoor && dust bad ◀── D3 NEW (projection)
            │   └─ swappable_alternatives = pool leftovers ◀── D6 NEW (content only, :322)
            │
            ▼
   LalaDailyPlan { weather, slots[4], … }
            │
            │  PlanContextStore.set(plan)   plan_context_store.dart:38  (existing)
            │   static ValueNotifier<LalaDailyPlan?>; cross-tab reactive; Lane 2 persists
            ▼
   plan_page.dart → PlannerOverviewCard (plan weather + AQ chips)   plan_page.dart:749
                  → ListView of PlanSlotTile × 4                     plan_page.dart:762
                       (period · title · region · weather hint · indoor/outdoor ·
                        travel time · NEW closure marker · NEW forecast window)

   ── Disruption (D5), offline, self-contained ──────────────────────
   GET /api/v1/plans/intervention   routers/v1.py:188
      trigger_type ∈ {null, bad_weather, closure_detected, both}   planner_service.py:100
        bad_weather      ← plan outdoor_status == "bad"     (existing, :57)
        closure_detected ← any slot.closure_state == "closed"  ◀── D5 NEW
      response → swap (slot.swappable_alternatives[0]) ◀── D6
               → regenerate (POST /plans/daily)
               → notice (reason / recommended_action)
      NO live alert feed. NO event authority. ◀── BLOCKED_EXTERNAL
```

**SSOT rules:**
- `LalaDailyPlan.weather` is the **only** weather/dust authority. Slots project from it.
- `closure_state` is a **projection** of `opening_hours_valid` (+ null rules); never written
  independently.
- `swappable_alternatives` borrows from the plan's own candidate pool; regenerated with the plan,
  never fetched separately.
- `PlanContextStore` remains the **sole** cross-tab plan SSOT. V3 adds fields, not stores.

---

## 4. ASCII wireframe — four-slot plan surface (V3 enrichment in `**bold**`)

Per the operating contract ("UI work starts from a Markdown wireframe"), the V3 surface is the
V1+V2 surface plus the bolded closures/weather/AQ markers. No new screen; the existing `plan_page`
layout is extended in place.

```
┌──────────────────────────────────────────────────────────────────┐
│  일정  /  Plan                                [region]  [lang]    │
├──────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ PlannerOverviewCard  (plan-level weather — UNCHANGED)      │  │
│  │  [outdoor_status pill]  [temp]  [PM10 chip]  [PM25 chip]  │  │
│  │  **AQ → outdoor_status influence documented (D3)**         │  │
│  │  visible slots: 4   [↻ regenerate]                         │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ ☀  09:00  오전 / Morning            **forecast_window** ◀─ D2│  │
│  │    <place name> · <region>                                  │  │
│  │    [ Badge: 실내/실외 ]  [ Badge: **open/closed/unknown** ◀ D4]│  │
│  │    도보 ~N분  ·  **11:00-22:00 (추정/est.)**  ·  추천 이유  │  │
│  │    [ swap ▾ ]  ◀── D6 swappable_alternatives (if any)       │  │
│  └────────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ 🍽  12:00  점심 / Lunch              **forecast_window**     │  │
│  │    <place name> · <region>                                  │  │
│  │    [ 실내/실외 ]  [ **open/closed/unknown** ]               │  │
│  │    도보 ~N분  ·  **HH:MM-HH:MM (추정)**  ·  **AQ bad?** ◀ D3│  │
│  │    [ swap ▾ ]                                               │  │
│  └────────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ 🌤  14:00  오후 / Afternoon          **forecast_window**     │  │
│  │    … (same shape) …                                         │  │
│  └────────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ 🌙  18:00  저녁 / Dinner             **forecast_window**     │  │
│  │    … (same shape) …                                         │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ── on disruption (D5), inline notice card (offline) ──────────  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ ⚠  <reason copy (KO/EN)>                                   │  │
│  │    trigger: bad_weather | closure_detected | both          │  │
│  │    [ recommended_action ]   [ swap ]  [ regenerate ]       │  │
│  │    honest fallback when no alternative available           │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
   KO and EN are mutually exclusive on every label (single-language modes).
   Every (추정/est.) closure/forecast marker is honest-estimated, never a guarantee.
```

---

## 5. Binding / state matrix (what touches what)

| Concern | OpenAPI schema (canonical) | Generated client (SSOT) | Backend service | Flutter widget | Persistence (Lane 2) |
|---|---|---|---|---|---|
| D1 four-slot invariant | `_daily_plan_data_schema` `openapi.py:950` | `LalaDailyPlan.slots` `:1360` | `_PERIOD_ORDER` `planner_service.py:162` | `plan_page.dart:762` slot list | DTO v1 (additive ok) |
| D2 `forecast_window` | **ADD** nullable object on slot `openapi.py:895-946` | **ADD** nullable parsed field on `LalaPlanSlot` `:1383` | project from `weather.forecast` in `_plan_slot` `:286` | render in `PlanSlotTile` | nullable forward-compat |
| D3 `air_quality_bad` | **ADD** nullable bool on slot | **ADD** nullable bool on `LalaPlanSlot` | project from `dust.grade` + `indoor_outdoor` | marker on outdoor slots | nullable forward-compat |
| D4 `closure_state` | **ADD** nullable string on slot (+ **hoist `estimated_opening_hours` to sibling**, §0.3 bug) | **ADD** nullable string on `LalaPlanSlot` | project from `opening_hours_valid` in `_plan_slot` | render open/closed/unknown + `(추정)` | nullable forward-compat |
| D5 disruption triggers | widen `trigger_type` desc `openapi.py:1019` (string+null) | `LalaIntervention.triggerType` `:1489` | extend literal `planner_service.py:100` + `:115-120` | inline notice card | n/a (on-demand) |
| D6 `swappable_alternatives` | field exists (`[]`) `openapi.py:936` | field exists `:1419` | **content**: populate from pool `:322` | swap affordance | rides on plan DTO |
| D7 cross-tab + Lane 2 | unchanged | unchanged models | unchanged | `PlanContextStore` (existing) | DTO v1 additive (`cross_tab_preferences.dart:197`) |

**Exclusive-file discipline (for the lane DAG, §7):** backend schema/service edits must serialize in
one lane; Flutter widget edits run in a dependent lane once the client regenerates. No two lanes
touch the same file.

---

## 6. Acceptance matrix

Each row is independently verifiable. "Honest-empty" rows must demonstrate the null/unknown state,
not just the happy path.

| Requirement | Verifiable criterion |
|---|---|
| **Four-slot structure (D1)** | `POST /api/v1/plans/daily` always returns exactly 4 slots in order morning→lunch→afternoon→dinner with start_times 09:00/12:00/14:00/18:00, even when candidates are exhausted (place=null + unavailable_reason). |
| **Weather per slot (D2)** | For a plan whose `weather.forecast` is non-empty, each slot's `forecast_window` equals the nearest-time `LalaForecastItem`; for empty forecast (AirKorea-only/unavailable), every slot's `forecast_window` is **null**. No new weather call per slot (assert via request count). |
| **Air quality (D3)** | Plan-level `dust` renders in `PlannerOverviewCard` (existing). For an outdoor slot when `dust.grade ∈ {bad, very_bad}`, `air_quality_bad == true`; when `dust.grade == "unknown"`, `air_quality_bad == null` (never fabricated true). |
| **Closure (D4)** | A slot whose conventional start is within its category estimate has `closure_state == "open"`; outside → `"closed"`; no place / unparseable → `"unknown"`. Tile shows the `(추정)/(est.)` marker beside any hours string. **No claim of real temporary-closure authority.** |
| **Schema bug fixed (D4)** | After V3-A, `estimated_opening_hours` is a sibling property of `opening_hours_valid` in `_daily_plan_slot_schema` (no longer nested); `additionalProperties: False` preserved. |
| **Disruption — weather trigger (D5)** | `GET /api/v1/plans/intervention` with `outdoor_status == "bad"` returns `trigger_type == "bad_weather"` (existing preserved). |
| **Disruption — closure trigger (D5)** | When any plan slot has `closure_state == "closed"`, intervention returns `trigger_type` containing `closure_detected` and a `trigger_factors` entry `{factor: "slot_closure_state", value: "closed", period: <period>}`. |
| **Disruption — swap works (D5/D6)** | A slot with non-empty `swappable_alternatives` offers a swap; the swap replaces the slot's place in the plan held by `PlanContextStore`. When alternatives is empty, the UI shows the honest fallback (notice only), never a fabricated place. |
| **Honest-empty across all new fields** | A fully-unavailable weather path yields `forecast_window=null` AND `air_quality_bad=null` on every slot; a no-place slot yields `closure_state="unknown"`. No null is masked as a value. |
| **KO / EN single-language** | Every new label (closure marker, AQ marker, disruption reason/action) renders in exactly one language per active mode; `singleLanguageText` / `lalaCopy` path. Eval 100% single-language. |
| **No live data on normal path** | A plan request triggers exactly **one** weather fetch + **one** places fetch (existing); V3 adds **zero** new external calls. Disruption is computed from the plan's own fields. |
| **No V1/V2 regression** | Existing `weather_hint`, `estimated_opening_hours`, `opening_hours_valid`, `outdoor_status` merge, and `PlanContextStore` cross-tab sharing behave identically post-V3 (golden tests pass unchanged). |
| **Generated-client SSOT integrity** | New fields parse via regenerated `fromJson`; `additionalProperties: False` preserved on slot/plan/intervention schemas; `toJson` count remains 0 in the client. |
| **App-owned encoders only** | Lane 2 serialization uses `encodeLalaDailyPlan` (app-owned); no `toJson` added to the generated client. |
| **On-demand evidence (no live AI)** | V3 logic is rule-based, not AI. If AI copy is added (optional), standard OpenAI only (never Azure); fake client in tests; no secret in output. |

---

## 7. Lane-DAG (disjoint exclusive files; one branch + one Draft PR each)

Dependencies are strict; a lane may not start until its dependency's contract surface (schema/client)
is merged. Files are **exclusive** — no two lanes touch the same file.

### V3-A — Backend slot enrichment + schema (critical path, no dependency)

- **Owns (exclusive):**
  - `apps/api/app/core/openapi.py` — `_daily_plan_slot_schema` (`:895-946`): hoist
    `estimated_opening_hours` to sibling (§0.3 bug) + add nullable `forecast_window`, `air_quality_bad`,
    `closure_state`; keep `additionalProperties: False` (`:946`).
  - `apps/api/app/services/planner_service.py` — `_plan_slot` (`:286`): compute + emit `forecast_window`
    (D2), `air_quality_bad` (D3), `closure_state` (D4); populate `swappable_alternatives` from the
    existing candidate pool (`:322`, D6). No change to `_PERIOD_ORDER` (`:162`).
  - `apps/api/app/services/db_repository.py` — **only if** a slot projection needs a DB field read
    not already used (audit shows it does not today; touch only if required, additive).
  - **Regenerate** `clients/flutter/lib/lala_api_client.dart` (hand-edit minimal if the Java generator
    cannot run — Java absent; keep `fromJson`-only, zero `toJson`, no `additionalProperties` token).
- **Adds:** D2/D3/D4 projections + D6 content. Flag-gated additive via `PLAN_FULL_SLOTS`
  (`feature_flags.py:185`).
- **Tests:** `apps/api/tests/` (new) — unit tests for each projection:
  - `closure_state`: open / closed / unknown (no-place, null `opening_hours_valid`).
  - `forecast_window`: nearest-match when forecast non-empty; null when empty (`weather_service.py:125,142`).
  - `air_quality_bad`: true only for outdoor + bad/very_bad dust; null when `unknown`.
  - `swappable_alternatives`: dedup vs assigned place; `[]` when pool exhausted; same-category pref.
  - Schema: assert `estimated_opening_hours` is a sibling property; `additionalProperties: False` intact.
- **Exit:** OpenAPI slot schema updated; `_daily_plan_slots` emits new fields; honest-null in the
  unavailable path; all projection unit tests green.

### V3-B — Generated client regeneration (depends on V3-A)

- **Owns (exclusive):** `clients/flutter/lib/lala_api_client.dart` — `LalaPlanSlot` (`:1383`) +
  `LalaDailyPlan` (`:1344`) + (if trigger copy changes) `LalaIntervention` (`:1457`).
- **Adds:** nullable parsers for `forecast_window` / `air_quality_bad` / `closure_state`; verify
  existing `fromJson` unchanged for absent fields (forward-compat); `toJson` count stays 0.
- **Tests:** `clients/flutter/test/` (or `apps/flutter_app/test/`) — parse a V3-A payload; parse a
  pre-V3 payload (new fields absent → null); assert zero `toJson`.

### V3-C — Flutter four-slot surface (depends on V3-B; parallel with V3-D)

- **Owns (exclusive):**
  - `apps/flutter_app/lib/features/planner/widgets/plan_slot_tile.dart` — D4 closure marker +
    `(추정)/(est.)` label, D2 forecast window, D3 AQ-bad marker, D6 swap affordance. Overflow-safe
    (slot tile already exists; extend in place).
  - `apps/flutter_app/lib/features/planner/widgets/planner_overview_card.dart` — D3 documentation
    only (AQ→outdoor_status influence); no new data.
- **Adds:** render the V3-A projections; honest-empty rendering for null/unknown states; KO+EN
  single-language labels.
- **Tests:** `apps/flutter_app/test/features/planner/` (new) — widget tests: open/closed/unknown,
  forecast window present/absent, AQ marker, swap affordance shown/hidden, KO+EN golden captures,
  honest-empty rendering.

### V3-D — Disruption trigger expansion + intervention UI (depends on V3-B; parallel with V3-C)

- **Owns (exclusive):**
  - `apps/api/app/services/planner_service.py` — `intervention()` (`:43`), `trigger_type` literal
    (`:100`), `_intervention_trigger_factors` (`:115-120`): add `closure_detected` +
    `bad_weather_and_closure`; offline derivation from slots.
  - `apps/api/app/core/openapi.py` — `_intervention_data_schema` (`:983`) description only for
    `trigger_type` (`:1019-1022`); schema shape unchanged (string+nullable).
  - `apps/flutter_app/lib/features/intervention/widgets/intervention_toast.dart` — closure-trigger
    notice card; honest fallback when no alternative.
  - `apps/flutter_app/lib/features/plan/presentation/pages/plan_page.dart` — wire the expanded
    trigger into the existing toast mount (`:389-411`).
- **Adds:** D5 closure trigger + trigger_factors; swap/regenerate/notice UX; offline only.
- **Tests:** `apps/api/tests/` + `apps/flutter_app/test/features/intervention/` — `trigger_type` for
  bad_weather / closure_detected / both / none; trigger_factors observable-only; UI notice for each
  trigger; honest fallback when `swappable_alternatives == []`.

> **Note on `planner_service.py` / `openapi.py` shared by V3-A and V3-D:** these two lanes edit
> DIFFERENT functions in the same file (V3-A: `_plan_slot`/`_daily_plan_slots`; V3-D:
> `intervention()`/`_intervention_trigger_factors`). They **must serialize** (V3-A lands first;
> V3-D rebases on V3-A). If strict file-exclusivity is required, fold V3-D's backend edits into V3-A
> and keep V3-D UI-only (intervention_toast + plan_page). Controller's call; the contract is
> neutral. `db_repository.py` is V3-A-only by audit (no plan-slot role in `intervention()`).

### V3-E (optional) — Lane 2 persistence DTO (depends on V3-B; parallel)

- **Owns (exclusive):** `apps/flutter_app/lib/core/persistence/cross_tab_preferences.dart` —
  `encodeLalaDailyPlan` (`:197`) / `_encodePlanSlot` (`:248`): forward-compatible serialization of
  new nullable fields (keep `lala.crosstab.v1.*`); bootstrap hydration path.
- **Adds:** D7 forward-compatible serialization.
- **Tests:** cold-start hydration restores a V3 plan; a V2 snapshot reads with nulls for new fields
  (no crash); cross-tab regression golden passes.

### V3-F — Verification + evidence (depends on V3-C, V3-D)

- **Owns:** tests + captures only.
- **Exit:** §6 acceptance matrix satisfied; real-device KO+EN captures of closure marker, forecast
  window, disruption notice; honest-empty capture under unavailable weather; no-live-data assertion
  (request count).

**Parallelism:** V3-A is the critical path. V3-B follows V3-A (mechanical). V3-C and V3-D run in
parallel once V3-B lands (different functions/widgets). V3-E parallel with V3-C/V3-D (persistence
files only). V3-F is the gate.

---

## 8. Privacy / invariants (carry forward from V1/V2)

- **No new PII.** New slot fields are projections of existing weather/place/hours data; no
  location/PII beyond what `LalaDailyPlan` already holds. `PlanContextStore` privacy invariant
  (region id only, never precise coordinates) unchanged.
- **No live data on the normal path.** A plan request still issues exactly one weather + one places
  fetch. V3 adds zero new external calls. Disruption is computed offline from the plan's own slots.
- **Honest unavailable states everywhere.** `forecast_window=null`, `air_quality_bad=null`,
  `closure_state="unknown"`, `swappable_alternatives=[]` are first-class states with distinct UI,
  never masked as a value.
- **KO / EN mutually exclusive.** Every new label is single-language per the active mode.
- **Category colors + pin-first clustering unchanged.** V3 touches the plan surface only; map tab
  clustering/pin behavior (G-MAPLOOP) is out of scope. Kakao map / Logto / Geolocator +
  `browser_location` conditional imports untouched.
- **Standard OpenAI only (no Azure).** V3's disruption logic is rule-based. If AI disruption copy is
  added (optional, not required), it MUST use standard OpenAI (bulk=gpt-5.4-nano /
  recheck=gpt-5.4-mini per AI policy), fake client in tests, never emit secrets.
- **On-demand evidence.** Disruption reasons are short, observable, grounded in the plan's own
  fields — no invented factors.

---

## 9. Explicit non-goals

- **NOT** changing slot count or period order (4 / morning→lunch→afternoon→dinner is fixed).
- **NOT** adding a per-slot weather or AQ API call (granularity is projection-only).
- **NOT** introducing a real operating-hours / temporary-closure / holiday authority — separate
  external-dependency effort.
- **NOT** building live alert / push / event-cancel infra.
- **NOT** touching the map tab, clustering, pin-first behavior, or category colors.
- **NOT** changing `LalaDailyPlan` top-level shape (weather stays plan-level).
- **NOT** breaking Lane 2 persistence or the `PlanContextStore` cross-tab contract.
- **NOT** destructive rewrite of `LalaPlanSlot` — all changes are additive nullable fields.
- **NOT** mock/demo data on the normal path.

---

## 10. BLOCKED_EXTERNAL (do NOT assume on the normal path)

| Item | Why blocked | What V3 does instead |
|---|---|---|
| Real operating-hours authority (Kakao Places detail, public holiday hours) | External data dependency; not in the V1+V2 substrate | Category estimate + `closure_state="unknown"` for non-conventional; UI always shows "(추정)/(est.)" |
| Live air-quality API beyond AirKorea sido | External feed | Reuse `dust_quality.py` + AirKorea path; plan-level only |
| Live weather warning / alert feed | External feed; offline-first invariant | `bad_weather` derives from existing `outdoor_status` only |
| Event cancellation / transit disruption authority | No event/transit source | Out of scope; `closure_detected` covers the offline-derivable subset only |
| Prod migration-apply / flag-enable / ingest | Operations gate, not this contract | Doc-only; controller + integrator own rollout |
| Real-device capture / browser / sim execution | Verification lane (V3-F), not design | This contract specifies the criteria; V3-F executes |

---

## 11. ASSUMPTIONS / NEEDS_CODE the controller must resolve

- **A1 — Candidate pool sufficiency (D6).** That real regions return ≥5–6 candidates so ≥1
  alternative survives per slot after assignment + dedup (`planner_service.py:177-235`). Verify
  against a real `/places` response before relying on D6.
- **A2 — Intervention enum widening safety (D5).** That no consumer treats `trigger_type` as a
  closed enum (it is `anyOf [string, null]` at `openapi.py:1019-1022` and `String?` in the client
  `:1489`). Confirmed safe; widening is additive.
- **A3 — Lane 2 DTO version choice (D7).** Keep `lala.crosstab.v1.*` (additive, forward-compatible)
  or bump to v2. Controller's call; contract-neutral.
- **A4 — Forecast-window nearest-match semantics (D2).** Tie-break when two forecast items are
  equidistant from `start_time` (recommend: earliest). Verify against actual `forecast` cadence
  emitted by `weather_service.py`.
- **NEEDS_CODE — Schema bug (D4 / §0.3).** `estimated_opening_hours` is nested inside
  `opening_hours_valid` at `openapi.py:919-923`. V3-A MUST hoist it to a sibling when editing the
  slot schema. Runtime + client already treat it as top-level, so this is a schema-only fix with no
  behavior change.
- **NEEDS_CODE — `db_repository.py` role.** Audit shows the slot projections (D2/D3/D4/D6) need no
  new DB read beyond what `list_places` already returns. If V3-A finds otherwise, the touch is
  additive and V3-A-exclusive.
- **A5 — No AI in V3 core logic.** This contract specifies rule-based disruption. AI disruption copy
  is an additive sub-decision owned downstream (still standard OpenAI, never Azure).
