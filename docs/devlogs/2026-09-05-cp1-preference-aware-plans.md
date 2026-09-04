# Devlog — CP1 preference-aware daily plans (2026-09-05)

Base: `953de4b650fc796106f003a518d6c983e353c778` (PR #187 exact head), Orca worktree
`preference-aware-plans-20260905`. Branch: `geondongkim/preference-aware-plans-20260905`.
No live provider calls, no deploy, no DB writes, no simulator/browser, no secret enumeration.

## Objective

Turn the saved travel-preference screens into a real, explainable plan input, changing
behavior only where the repository has data authority, and reporting unsupported
effects honestly.

## API half (commit 1 — `feat(api): apply grounded travel-preference context to daily plans`)

- `DailyPlanRequest.preference_context`: optional strict `PlanPreferenceContext`
  (7 non-sensitive soft fields; `extra="forbid"` rejects unknown AND sensitive keys —
  allergens/dietary/avoid-ingredients/mobility/PII — with 422). Value sets/bounds are
  shared Literals with `TravelPreferenceSoft` (one vocabulary, no second SSOT).
- Grounded effects only:
  - candidate query radius capped from `max_one_way_minutes` and/or `walking_band`
    through the documented walking estimate (`travel_time_service.walking_distance_m`,
    4 km/h ≈ 67 m/min); never above the requested radius; band→minutes mapping
    short=15/medium=30/long=60 (documented convention inside the max_one_way bounds);
    attribution: the stricter contributor, explicit field wins ties.
  - known `is_indoor` candidates stably partitioned per `indoor_outdoor`; bad weather +
    medium/high sensitivity prefers known indoor over an outdoor soft preference;
    unknown indoor status is never treated as indoor; input order preserved.
  - `selected_place_id` still pinned exactly once; a pin outside the effective
    candidate set keeps the honest `SELECTED_PLACE_UNAVAILABLE` 422.
- `preference_effects` (only when context supplied): bounded field names, `applied`,
  10 reason codes, ko/en explanations, bounded `details`
  (requested/effective radius, weather status, ordering provenance).
  `food_cuisines`/`budget_band`/`exclude_closing_soon` always report `applied:false`
  with facet-unavailable codes — no invented cuisine/price/closure authority.
- No-context path is byte-identical (request serialization, request_hash/cache_key
  payload, response shape without the key) — regression-pinned at service and route.
- OpenAPI: `PreferenceEffect` schema + additive optional `DailyPlanData.preference_effects`.
- Tests: planner_service +22, v1_routes +6, openapi_contract +1. API suite **1974 passed**.

## Flutter half (commit 2 — `feat(flutter): send effective preference context from every plan entry point`)

- `composePlanPreferenceContext`: `TravelPreferencesStore` device-first defaults +
  trip-date `TripPreferenceOverride` through the existing `applyTo` precedence; guest
  (no account) works; read-only (no global mutation); pages take an injectable provider.
- Entry points all send the same effective context: map `_refresh`, addToPlan pinned
  generation, plan-tab `_fetchPlan`. PR #187 protections (refresh epoch, adoption
  gates, `_loadGeneration`) untouched.
- `PlanPreferenceEffectsSummary` on the plan tab + map planner sheet: grounded count
  chip + expandable entries; unsupported fields never shown applied; 5-locale copy;
  no overflow at 200% text (tests).
- **Correction (zone bug)**: the first wiring hung widget-test files because a later
  Flutter test zone awaited a `_loadFuture` completed in an earlier (dead) zone.
  `TravelPreferencesStore.ensureLoaded`/`TripLibraryStore.ensureLoaded` now return a
  fresh completed `Future.value()` in the caller's zone once loaded (first-load dedup
  unchanged). Regression: `plan_preference_context_cross_zone_test.dart`.

## Generated client (commit 2)

D-1 had hand-authored the generated models (no Java on host). This checkpoint ran the
REAL pipeline: Java 17 (`/opt/homebrew/opt/openjdk@17`) +
`scripts/generate_dart_client.sh` (openapi-generator 7.12.0 + patch script +
build_runner). Consecutive full runs are byte-identical (proved twice:
`git status` hash `6feb8b821fca8d7c`/diff hash on runs #2/#3, and full-diff equality
on runs #7/#8).

`patch_dart_dio_serializers.py` fixes added (each a real generator defect):
- nullable cast `as Foo?` kept the `?`, so nested models (e.g. `PlanPreferenceContext?`)
  were never rewritten to `.toBuilder()` → strip the suffix;
- generator over-emits `.toBuilder()` on scalar `anyOf` fields (`String?`, `int?`) →
  reverted to plain assignment (the script's documented primitive rule);
- integer-enum defaults emitted `const E._(E.number30)` (enum const into a String
  parameter) → rewritten to the generated name string.

Raw full-spec output still cannot be committed wholesale: known dart-dio bugs in
never-curated models (missing `ModelNull`, `override` used as a member name in
`TripPreferenceOverride*.g.dart`, ambiguous shared enum names between
`travel_preference_soft.dart`/`plan_preference_context.dart`, inline anyOf schemas).
Committed surface = the compiling curated set + the CP1 contract files as pure
generator output (integer enum for `max_one_way_minutes`, shared
`TravelPreferenceSoftFoodCuisinesEnum` naming adopted). Unrelated churn
(`me_data` bool-enum, api clients, README/docs of untouched models) was investigated
and reverted, not committed.

## Verification (exact commands, this checkpoint)

- API: `uv run pytest apps/api/tests` → **1974 passed** (includes +29 CP1 tests).
- Generated client: `dart test` in `clients/flutter_generated` → **239 passed**;
  `dart analyze` → 0 errors in the curated tree (the package is NOT warning-free:
  pre-existing generator-style warnings remain — unused imports, unused optional
  `specifiedType` parameters, etc.).
- Reference client: `dart test` in `clients/flutter` → **45 passed**; analyze clean.
- Flutter: `flutter analyze` → No issues found; full `flutter test` → **1024 passed**
  (includes +15 CP1 tests: compose precedence, cross-zone regression, entry-point
  context equality, summary semantics/5 locales/200% text).
- Lint: `uv run ruff check .` + `uv run ruff format --check .` clean;
  `uv run pre-commit run --all-files` all Passed; `git diff --check` clean.
- Generator idempotency: consecutive `bash scripts/generate_dart_client.sh` runs
  produce identical trees (hashes above).

## Correction (2026-09-05, independent verification): two defects

### D1: patch-script regression tests (missing)

The extended `patch_dart_dio_serializers.py` shipped without unit coverage. Added
`apps/api/tests/test_patch_dart_dio_serializers.py` — direct module import (no Java,
npx, network, or generator), `tmp_path` fixture reproducing the real dart-dio 7.12
output shape. Covers: (1) nullable nested cast + raw assign → `toBuilder()`;
(2) scalar cast + over-emitted `toBuilder()` → plain assignment; (3) non-nullable
nested cast + raw assign → `toBuilder()`; (4) single-line integer-enum default
`const E._(E.number30)` → `const E._('number30')`; (5) assign with no preceding cast
unchanged; plus idempotence (second `patch_file` run returns False, content stable).
Full API suite **1975 passed**.

### D2: five-locale effect explanations (raw server copy leaked)

`PlanPreferenceEffectsSummary` previously rendered the server KO/EN explanation
verbatim, so JA/zh-Hans/zh-Hant users saw Korean/English sentences. The widget now
maps every known bounded reason code (all 10) to client-owned KO/EN/JA/zh-Hans/
zh-Hant copy (`localizedPreferenceEffectExplanation`), interpolating only the
bounded details for radius effects (requested/effective meters, effective minutes);
the raw server explanation survives only as the fallback for unknown codes or
missing interpolation details. Applied/not-applied labels and 200% soft-wrap
behavior are unchanged. Tests: every code × every locale renders its localized
fragment with the raw server sentence proven absent (distinctive marker), KO/EN
rows keep labels + radius interpolation, unknown-code and missing-details cases
fall back to the raw text honestly. (Loop tests key the widget per code — a shared
ExpansionTile state made the expansion tap nondeterministic across iterations.)
Full Flutter suite **1032 passed**; `flutter analyze` clean.

Verification for the correction: focused D1/D2 tests first, then
`uv run pytest apps/api/tests --tb=no -p no:warnings` (1975 passed),
`uv run ruff check .` / `ruff format --check .` clean, `uv run pre-commit run
--all-files` all Passed, `git diff --check` clean, `flutter analyze` (No issues)
and full `flutter test` (1032 passed). Reference/generated client tests not re-run
(no tracked client files changed; client not regenerated).

## Honest limitations

- Server effect explanations are ko/en only (planner API convention); the client-owned
  summary copy is 5-locale and shows server explanations verbatim in the detail list.
- Radius cap uses the Haversine 4 km/h documented estimate, not a routing authority;
  `radius_m` in the response remains the request echo (requested/effective distinction
  lives in `preference_effects.details`).
- The weather-safety indoor preference applies only when bad weather is observed AND
  sensitivity is medium/high; unknown weather never triggers it.
- The generated package remains a curated subset of the full spec (see above); the
  full-tree regeneration is still blocked by upstream dart-dio bugs (B1.3 follow-up).
- No simulator/device runtime validation (widget/API/client tests only) — same gate
  as D-1/PR #187.
