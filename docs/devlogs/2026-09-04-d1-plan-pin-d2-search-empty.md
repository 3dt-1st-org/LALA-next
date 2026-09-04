# Devlog — D-1 place-detail plan pinning + D-2 search filtered-empty (2026-09-04)

Base: `9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6` (origin/main exact head), Orca worktree
`fix-runtime-plan-search-20260904`. Branch: `geondongkim/fix-runtime-plan-search-20260904`.
No live provider calls, no deploy, no DB writes, no simulator/browser ops, no secret enumeration.

## D-1 (moderate): "일정 추가" must include the tapped canonical place, no cross-view reshuffle

### Confirmed facts (code reading, base head)

- `PlaceDetailPage._handoffToMap(place, addToPlan)` only sets `SelectedPlaceStore`, dispatches
  `LocalSignalPlaceActionRequest(placeId, addToPlan)` and `context.go(mapRoute)` — no plan
  generation anywhere in the chain.
- Map (`home_page`) addToPlan branches (`_tryResolveLocalSignalAction` /
  `_resolveLocalSignalPlaceAcrossCategories`) only `_selectPlace` + open
  `ActiveMapSheet.planner`; the sheet shows `_dailyPlan` from `_refresh`'s **unpinned**
  `createDailyPlan()`.
- `PlanPage._load()` (post-frame in initState) **always refetches** its own
  `createDailyPlan()` and publishes — the plan tab's first open replaces the map's active
  plan (dual generation → slots 3/4 differed between consecutive views). Branch state is
  kept alive by `StatefulShellBranch`, so the harm is the first-open fetch + publish.
- `PlanContextStore` (process-local SSOT) + `CrossTabPersistence`
  (`lala.crosstab.v1.*` write-through + cold-start hydration) already exist — publishing to
  the store IS publishing to persistence.
- `createDailyPlan` chain: pydantic `DailyPlanRequest` → openapi (auto from pydantic) →
  generated dart-dio `clients/flutter_generated` → reference `clients/flutter` client →
  `LalaBackend` facade. No selected-place concept at any layer (base).

### API half — DONE (commit 8aa4207, pushed)

- `DailyPlanRequest.selected_place_id: str | None` (≤128 chars). `BeforeValidator` strips
  whitespace **before** min-length → blank is rejected `VALIDATION_ERROR` 422 (clear
  contract, tested), `" p2 "` → `"p2"`.
- `planner_service.daily_plan` resolves the id against real `list_places` candidates only;
  unresolvable → `ServiceError(422, SELECTED_PLACE_UNAVAILABLE, ko/en message,
  retryable=False)` → error envelope via the global handler. No fabricated inclusion.
- `_daily_plan_slots(selected_place=...)`: pinned exactly once into first sensible slot
  (restaurant → lunch, else morning); marked used → never duplicated, never in
  swappable_alternatives; remaining 3 slots keep the existing deterministic allocation,
  four-slot/meal-slot/dedupe/fallback/localization/weather/travel-time/opening-hours
  contracts untouched (flag-free additive; unpinned path byte-identical).
- `daily_plan_identity`: `selected_place_id` added to payload **only when non-null** →
  unpinned request_hash/cache_key byte-for-byte preserved (regression-pinned by
  `test_daily_plan_identity_preserves_legacy_unpinned_payload_bytes`); pinned ≠ unpinned
  and pinned-a ≠ pinned-b (tested).
- Tests: `test_planner_service.py` +8, `test_v1_routes.py` +3 (route 200 inclusion-once +
  identity-distinct; 422 SELECTED_PLACE_UNAVAILABLE envelope; whitespace-only 422).
  `144 passed` across planner/v1-routes/openapi-contract/openapi-compat; ruff clean.

### Remaining D-1 work — DONE (commits 8aa4207, 04cf059, pushed)

1. Dart: generated `DailyPlanRequest` model gained `selectedPlaceId` (hand-authored to the
   exact generator pattern — openapi-generator CLI unavailable, no Java on host), `.g.dart`
   regenerated deterministically via `dart run build_runner build`; reference client
   `createDailyPlan({String? selectedPlaceId})` (omits the wire key when null). Client test
   proves pinned sends `selected_place_id` and unpinned omits the key.
2. Flutter facade `LalaBackend.createDailyPlan({String? selectedPlaceId})` +
   `LalaApiBackend` + 27 mechanical fake overrides across 13 test files.
3. Map `home_page` `_generatePinnedPlanForPlace`: single generation site for addToPlan.
   Requests `selectedPlaceId: request.placeId`, verifies actual inclusion in the response,
   publishes the exact plan via `PlanContextStore.set` (= crosstab persistence
   write-through) and opens the planner sheet on it; on failure/non-inclusion shows the
   truthful 5-locale SnackBar and does NOT open the sheet. In-flight guard prevents double
   generation. Because generation runs inside the action handler (after any
   action-triggered refresh completed), `_refresh`'s unpinned publish can no longer
   clobber the pinned plan. All addToPlan dispatchers (place detail, local signals,
   saved places) share this path.
4. `PlanPage`: first open adopts a compatible shared plan (same radius + API language +
   center within plan.radiusM of the tab's request center) with zero network calls;
   explicit refresh (calendar/regenerate/retry) and region/language change still fetch
   (incompatible ⇒ fetch, tested for language and far-center).
5. Tests: `map_add_to_plan_pinned_generation_test.dart` (pinned generation once + publish
   + sheet; failure copy + no sheet + store preserved), `plan_tab_shared_plan_adoption_test.dart`
   (adopt-no-refetch, identical instance, incompatible fetch, explicit refresh regenerates).
   Plan-state tests now reset `PlanContextStore` in setUp/tearDown (same singleton
   isolation pattern as RegionContextStore).

## D-2 (minor): search filtered-empty state — DONE (third commit)

- `search_page.dart` loaded branch renders `_SearchEmptyView` (key
  `search-filtered-empty-view`, hasQuery=true → reset affordance `search-empty-reset-filters`)
  when `_visiblePlaces` is empty from query/category filtering. Transport
  empty/unavailable/error/loading distinctions, semantics, 44dp target and 5 locales are
  inherited from the existing empty view unchanged.
- `search_filtered_empty_state_test.dart`: query-no-match empty, incompatible-category
  empty, reset recovery, compatible-filter still renders tiles.

## Verification results

- API: full `uv run pytest apps/api/tests` → **1945 passed**.
- Client: `dart test` in `clients/flutter` → **44 passed**.
- Flutter: `flutter analyze` → **No issues found**; full `flutter test` → **1002 passed**.
- Lint: `uv run ruff check .` + `ruff format --check .` clean (454 files);
  `git diff --check` clean; pre-commit hooks ran on every commit
  (detect-secrets baseline line numbers updated by the hook itself — flagged line moved
  from 1138 → 1184 in `lala_api_client_test.dart`; no secret values touched or printed).

## Assumptions

- "Sensible slot" = first slot of the pinned place's kind (restaurant → lunch, else
  morning), deterministic.
- Plan-tab compatibility threshold = plan center within `plan.radiusM` of the tab's request
  center (region/base coords) — adopts camera-near plans from the map; region/language
  change or explicit refresh regenerates.
- Server error message localization is ko/en only (planner API contract); app-facing
  failure copy is 5-locale via `lalaCopyMulti`.

## Runtime gates NOT covered here (per dispatch constraints)

No simulator/browser run — widget/API/client tests only. Runtime re-validation on a device
build remains a follow-up gate.
