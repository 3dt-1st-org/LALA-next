# V1 Cross-Tab Shared-State + Persistence Design Contract — selected-place & plan across the 4 tabs

> **Slice within V1 phase PR #133.** This is a foundation design contract on the canonical branch
> `geondongkim/lala-v1-rc2-rail-reason-freshness` (PR #133; head `4942d41`). It ships as a
> **doc-only foundation slice** — **no separate branch or PR is created for it.** Binding work is
> deferred to later per-phase implementation lanes (one branch + one Draft PR each, per the V1
> delivery policy). Retargeting PR #133's base is integrator-owned, not here.

**Canonical branch:** `geondongkim/lala-v1-rc2-rail-reason-freshness` (PR #133; head `4942d41`).
**Scope:** make **selected-place** and **plan** (a) shared reactively across all 4 tabs and (b)
persisted across relaunch — **without** breaking the already-shared/persisted region + language,
and **within the privacy constraint** (persist only selected-place id + plan; no location/PII beyond
the existing manual region id). **NO new external / AI / live / device call.** **Status:** foundation
doc — all design decisions approved by the controller (§7); no product code in this slice.

This contract is a **claim about the real code at `4942d41`**. Every file path / line number below
was verified against the working tree this session. The controller and the independent verifier will
cross-check it.

> **Authoritative requirement.** The AUTHORITATIVE rule is playbook **§13.4** (4탭):
> *"탭 간 선택 지역, 언어, 일정, 선택 장소가 반응형으로 공유되고 앱 재실행 후 persist되어야
> 한다."* — selected region, language, **plan**, and **selected place** must be shared reactively
> across tabs and persist across relaunch. Region + language already satisfy this (Wave-1; §0). This
> contract closes the remaining two: **selected-place** and **plan**.

> **Format precedent.** This mirrors the section layout and honesty discipline of
> `v1-bounds-query-design-contract.md` and `v1-three-signals-design-contract.md` (especially the §0
> file:line audit, §3 binding matrix, §7 approved/rejected decisions, and §10 disjoint lanes with
> exclusive files + data-integrity flags + common base).

> **One fact that shapes the whole contract.** The sharing + persistence mechanism this contract
> extends is **already in production for region + language**: a process-local singleton with a
> `static final ValueNotifier<T>` (the reactive SSOT) + an optional `OnboardingPreferences`
> persistence attachment + a `bootstrapAppState` cold-start hydration. Selected-place and plan are
> wired to the **same** mechanism — two new holders that mirror `RegionContextStore`, two new
> versioned persistence keys that mirror `manualRegionId`, and the same attach→load→apply hydration
> order in `bootstrapAppState`. **No new state-management dependency, no new persistence backend,
> no new architecture.** The blast radius is "two new holder modules + their listeners + their
> persistence keys," all additive.

---

## 0. Current-state audit (not guess) — what is already shared/persisted vs. what is per-tab today

The 4 tabs are a `StatefulShellRoute.indexedStack`; each branch keeps its own widget state.
Region + language cross tab today via two static-`ValueNotifier` singletons; selected-place and
plan do **not** — they are per-tab fields that are neither shared nor persisted.

| Claim | Verified at | Verdict |
|---|---|---|
| 4 tabs = `StatefulShellRoute.indexedStack` with 4 branches: search / map-route / plan / local-signals | `apps/flutter_app/lib/core/routing/lala_router.dart:86` (shell), `:96-104` (search → `SearchPage`), `:105-121` (map → `MapRoutePage`), `:122-130` (plan → `PlanPage`), `:131-146` (local-signals → `LocalSignalsPage`) | ✅ |
| Bottom nav has exactly 4 destinations (검색/지도/일정/로컬 신호); `lalaTabPaths` indexes them 0..3 | `apps/flutter_app/lib/shared/widgets/lala_bottom_nav_bar.dart:28-53` (destinations), `:59-64` (`lalaTabPaths`) | ✅ |
| **Region sharing SSOT** = `RegionContextStore`, a singleton with `static final ValueNotifier<RegionContext?> _notifier`; cross-tab listen via `listenable`; `set()` (best-effort persist) + `setAndFlush()` (awaited); cold-start `applyManualRegionId(id)` | `apps/flutter_app/lib/core/location/region_context.dart:113-208` (`_notifier` :116-117, `listenable` :124, `set` :145, `setAndFlush` :162, `applyManualRegionId` :174) | ✅ |
| **Region privacy** — only a manual selection is persisted; `current`/`default`/`null` all map to a null id so precise coordinates are never stored | `region_context.dart:201-207` (`_persistedIdFor`) | ✅ |
| **Language sharing SSOT** = `OnboardingState`, a singleton with `static final ValueNotifier<String> _language` + `languageListenable`; `selectLanguage()` write-through-persist; cold-start `applySnapshot` | `apps/flutter_app/lib/features/onboarding/onboarding_state.dart:21-166` (`_language` :25, `languageListenable` :44, `selectLanguage` :67, `applySnapshot` :105) | ✅ |
| **Reactive consumption pattern** (the mechanism this contract mirrors): a tab adds a listener in `initState`, no-op-skips self-publishes, reloads from the store, removes the listener in `dispose` | `apps/flutter_app/lib/features/plan/presentation/pages/plan_page.dart:79` (`_onRegionChanged`), `:97-108` (no-op skip + `_reloadFromStore`), `:108` (`addListener`), `:129-130` (`removeListener`); identical shape in `search_page.dart:114,135` and `local_signals_page.dart:47,55` | ✅ |
| The shell itself reactively rebuilds on language change via `ValueListenableBuilder<String>` on `OnboardingState.languageListenable` (this is how the bottom-nav labels update) | `apps/flutter_app/lib/app/lala_main_shell.dart:27-32` | ✅ |
| **Persistence layer** = `OnboardingPreferences` over a swappable `OnboardingPreferencesBackend` seam (SharedPreferences in prod, in-memory fake in tests); versioned key prefix `lala.onboarding.v1.`; `load()` is failure-safe (store error / invalid id → clean first-run snapshot, never throws); bad manual id is dropped + cleaned | `apps/flutter_app/lib/core/persistence/onboarding_preferences.dart:21` (`kOnboardingStoragePrefix`), `:23-26` (keys), `:34-55` (`OnboardingSnapshot`), `:59-69` (backend seam), `:114-146` (failure-safe `load` + invalid-id drop), `:187-197` (`manualOptionForId` validation) | ✅ |
| **Cold-start hydration order** = `bootstrapAppState` (runs before `runApp`): resolve prefs → if null, detach + reset + run non-durable → else attach to both holders → `load()` → `applySnapshot` + `applyManualRegionId` (restore **before** any tab mounts, so the first frame sees the truth) | `apps/flutter_app/lib/app/bootstrap.dart:34-56` (resolve :38; null-path :39-48; attach :50-51; load :53; apply :54-55) | ✅ |
| **Selected-place is per-tab and NOT shared/persisted.** `_selectedPlaceId` is a local `String?` field on `_LalaHomePageState` (map tab only); set/cleared at ~12 call sites; search & local-signals tabs have **no** selected-place field at all | `apps/flutter_app/lib/features/home/home_page.dart:137` (`String? _selectedPlaceId;`); set/clear at `:271,:752,:786,:840,:879,:920,:936,:968,:1345`; resolved at `:480,:746` (`placeById(...) ?? featuredPlace(...)`); passed to view at `:1455`. Grep for `_selectedPlace`/`selectedPlaceId` in `search_page.dart` and `local_signals_page.dart` → **no hits** | ✅ gap |
| **Plan is per-tab and NOT shared/persisted.** Map tab and plan tab each hold their own `_dailyPlan` and each issue an **independent** `createDailyPlan()` call that can diverge | Map tab: `home_page.dart:128` (`LalaEnvelope<LalaDailyPlan>? _dailyPlan`), fetched at `:530` (`_backend.createDailyPlan`), consumed at `:1444` (view). Plan tab: `plan_page.dart:66` (`LalaDailyPlan? _dailyPlan`), fetched at `:243` (`(await _backend.createDailyPlan()).data`). Two independent fetches | ✅ gap |
| **"Add-to-plan" today is a no-op on a shared plan.** `LocalSignalPlaceAction.addToPlan` only *selects* the place on the map tab; there is no shared user-plan structure it mutates | `apps/flutter_app/lib/core/navigation/local_signal_action.dart:5` (`enum … { viewPlace, addToPlan }`); handled at `home_page.dart:838,877` (sets `_selectedPlaceId`, no plan mutation) | ✅ gap |
| **No other SharedPreferences keys exist** in the app besides the onboarding/region family — there is no pre-existing plan/place persistence to displace | grep `SharedPreferences`/`setString`/`getString`/`kOnboardingStoragePrefix` over `apps/flutter_app/lib` → only `bootstrap.dart` + `onboarding_state.dart` references (both about the existing onboarding layer) | ✅ |
| **Serialization constraint (shapes D3).** The generated client can **deserialize** `LalaDailyPlan`/`LalaPlanSlot`/`LalaPlace` (`fromJson`/`fromJsonObject`) but has **no `toJson`** anywhere — persisting a plan cannot call an existing `plan.toJson()` | `clients/flutter/lib/lala_api_client.dart:1094` (`LalaPlace.fromJson`), `:1369` (`LalaDailyPlan.fromJson`), `:1426` (`LalaPlanSlot.fromJson`); `grep -c toJson clients/flutter/lib/lala_api_client.dart` → **0** | ✅ constraint |

**Net:** region + language are already reactively shared across all 4 tabs and persisted across
relaunch (Wave-1, byte-for-byte). **Selected-place** is a map-tab-only `String?` — invisible to the
other 3 tabs and lost on restart. **Plan** is two independent `createDailyPlan()` fetches (map +
plan tabs) that can diverge and are both lost on restart. §13.4's "선택 장소" and "일정" halves are
therefore **not yet satisfied**. The mechanism to satisfy them — static-`ValueNotifier` holder +
`OnboardingPreferences` persistence + `bootstrapAppState` hydration — already exists and is the
pattern this contract extends.

---

## 1. Data flow + single source of truth

There will be **two new process-local singletons**, each an exact structural mirror of
`RegionContextStore`: `SelectedPlaceStore` (holds the active selected-place id) and
`PlanContextStore` (holds the active daily plan). Each owns one `ValueNotifier`, an optional
persistence attachment, and a cold-start `apply…` restore. Tabs read reactively via the listenable
and write through `set`/`setAndFlush` — **identical** to how region is consumed today. No tab keeps
a private copy that can diverge.

```
                            ┌─────────────────────────────────────────────┐
  any tab (map/search/      │  SelectedPlaceStore  (NEW — mirror of       │
  plan/local-signals)       │  RegionContextStore)                        │
  user taps a place /       │   static ValueNotifier<String?> _id         │   SSOT for the selected place
  cluster → writes the id   │   listenable  (cross-tab)                   │   (the id is durable; the
        │                   │   set(id) / setAndFlush(id)                 │    resolved LalaPlace is derived
        └──────────────────►│   attachPersistence(prefs) / applyId(id)    │    per-tab from each tab's own
                            └──────────────┬──────────────────────────────┘    loaded candidate set)
                                   value=  │  (ValueNotifier notification)
                                            ▼
  every other tab's listener (mirror plan_page.dart:97-108):
     addListener in initState → no-op-skip if unchanged → resolve against THIS tab's places → rebuild
        │
        └──► persistence (best-effort, write-through): prefs.writeSelectedPlaceId(id)
                                                            │
                                                            ▼  (cold start, before any tab mounts)
  bootstrapAppState: attach → load → SelectedPlaceStore.applyId(snapshot.selectedPlaceId)


  plan tab generates/regenerates       ┌─────────────────────────────────────────────┐
  createDailyPlan() → publishes;       │  PlanContextStore  (NEW — mirror of          │
  map tab reads instead of fetching    │  RegionContextStore)                         │
  independently                        │   static ValueNotifier<LalaDailyPlan?> _plan │   SSOT for the active timeline
        │                              │   listenable  (cross-tab)                    │   (last well-formed publish wins;
        └─────────────────────────────►│   set(plan) / setAndFlush(plan)              │    eliminates the dual-fetch
                                       │   attachPersistence(prefs) / applyPlan(p)    │    divergence of home_page:530 vs
                                       └──────────────┬──────────────────────────────┘    plan_page:243)
                                              value=  │
                                                       ▼
  map tab (planner sheet / route panel) + plan tab (timeline) rebuild from the SAME plan
        │
        └──► persistence (best-effort, write-through): prefs.writePlan(planDto)
                                                            │
                                                            ▼  (cold start, before any tab mounts)
  bootstrapAppState: attach → load → PlanContextStore.applyPlan(snapshot.plan)
```

**Single source of truth for selected-place:** `SelectedPlaceStore._id`
(`apps/flutter_app/lib/core/state/selected_place_store.dart`, new) — the **only** holder of the
active selected-place id. The *resolved* `LalaPlace` is **not** stored centrally (it depends on
each tab's loaded candidate set); each tab resolves `placeById(itsItems, SelectedPlaceStore.current)`
exactly as the map tab does today (`home_page.dart:480,746`). The id is the durable truth; the
object is a per-tab derivation. This mirrors region: `regionId` is the durable truth; coordinates are
resolved from the option list.

**Single source of truth for plan:** `PlanContextStore._plan`
(`apps/flutter_app/lib/core/state/plan_context_store.dart`, new) — the **only** holder of the active
`LalaDailyPlan`. Whichever tab generates/regenerates a plan publishes it via `set`/`setAndFlush`;
all tabs read the same value. The dual independent fetches (`home_page.dart:530` and
`plan_page.dart:243`) are replaced by "publish into the store / read from the store."

**Region + language SSOTs are unchanged:** `RegionContextStore` (`region_context.dart:113`) and
`OnboardingState.languageListenable` (`onboarding_state.dart:44`) remain the SSOTs for region and
language. The two new holders are **siblings**, not a replacement.

---

## 2. ASCII / data-flow — tab-A writes → shared holder → tab-B rebuilds → persistence → cold-start hydration

```
 ┌─ Tab A (e.g. map) ───────────────────────┐
 │  user taps a place / regenerates plan    │
 │  SelectedPlaceStore.set(id)              │        OR   PlanContextStore.set(plan)
 │      └─ flush variant awaits the write   │              (completion points / nav exits)
 └──────────────┬───────────────────────────┘
                │ ValueNotifier.value = …  (one notification per change; no-op-skip if unchanged)
                ▼
 ┌─ Shared holder (NEW, singleton) ─────────┐
 │  SelectedPlaceStore._id  /  PlanContextStore._plan        ← SSOT (in-memory, this session)
 │   • attachPersistence(prefs) — wired in bootstrapAppState │
 │   • set → notifier.value = x; unawaited(persist)         │
 │   • setAndFlush → notifier.value = x; await persist      │
 └──────────────┬───────────────────────────┘
                │ ValueListenable notification
        ┌───────┴───────┬──────────────┬─────────────┐
        ▼               ▼              ▼             ▼
 ┌─ Tab B (plan) ─ ┌─ Tab C (search) ─ ┌─ Tab D (local-signals) ─ ┌─ shell ──┐
 │ _onSelectedPlace │ …addListener…    │ …addListener…            │ (nav/a11y)│
 │  Changed:        │ resolve id       │ resolve id               │           │
 │  no-op if same;  │ against this     │ against this tab's       │           │
 │  else rebuild    │ tab's items      │ items; rebuild           │           │
 └──────────────────┘──────────────────┘──────────────────────────┘───────────┘

                ┌─ persistence (write-through, best-effort) ──────────────────────┐
                │  prefs.writeSelectedPlaceId(id)   /   prefs.writePlan(planDto)  │
                │   • versioned key prefix (lala.crosstab.v1.*)                  │
                │   • null id / null plan → remove (clears the key)              │
                │   • write failure → in-memory stays authoritative (non-durable)│
                └──────────────┬─────────────────────────────────────────────────┘
                               ▼  (process restart)
 ┌─ bootstrapAppState (cold start, BEFORE any tab mounts) ──────────────────────┐
 │  attachPersistence(prefs) to BOTH new holders (mirror :50-51)                │
 │  snapshot = await prefs.load()              (failure-safe; never throws)     │
 │  SelectedPlaceStore.applyId(snapshot.selectedPlaceId)                        │
 │  PlanContextStore.applyPlan(snapshot.plan)    (null/corrupt → null, honest)  │
 │  …existing OnboardingState.applySnapshot + RegionContextStore.applyManual…   │
 └──────────────────────────────────────────────────────────────────────────────┘
        │ first frame sees the restored selection + plan (no transient blank, no re-fetch needed)
        ▼
   the 4 tabs mount reading the already-restored holders (exactly how region seeds tabs today)
```

> **Race / ordering notes (depicted, decisions D5):** (1) hydration runs **before** any tab mounts
> (`bootstrap.dart:34-56` already runs pre-`runApp`), so a restored id/plan is in the holder before a
> tab's `initState` reads it — the same property that lets a restored manual region seed the search
> and plan tabs with no device request (`cold_start_persistence_test.dart:436-518`). (2) an
> **order/epoch guard** prevents a stale persisted value loaded late from clobbering a fresh
> in-session selection: once hydration has applied (or the holder has accepted a runtime `set`), a
> later `apply…` is a no-op unless it carries a newer epoch — the bounds arc used the same shape for
> stale response suppression (`home_page.dart:164-167 _refreshEpoch`). (3) `setAndFlush` is used at
> completion/navigation points so a process kill right after the tap cannot lose the restart state
> (mirrors `RegionContextStore.setAndFlush`, `region_context.dart:162`).

---

## 3. Binding matrix — honest state → sharing/persistence behavior

Exactly one row describes the active state for each of selected-place / plan. The matrix is honest
about empty, corrupt, and non-durable states (playbook §4.1 / §13.5 — never fabricate).

| State | Trigger / inputs | Sharing behavior | Persistence behavior | Data-truth state |
|---|---|---|---|---|
| **S1 — fresh launch, no prior selection/plan** | empty store (first run, or nothing persisted) | holders start `null`; tabs show their honest empty/default (map → featured place fallback; plan → generates on first open) | nothing written; keys absent | **honest-empty** — no fabricated selection/plan; absence is truth |
| **S2 — warm cross-tab write (in-session)** | user selects a place on the map / regenerates the plan | `set` publishes to the holder; every other tab's listener rebuilds (no-op-skip if unchanged) | write-through best-effort (fire-and-forget); `setAndFlush` at completion points | **real-data-bound** — the place id is a real server id; the plan is a real `createDailyPlan` result |
| **S3 — relaunch with persisted state** | cold start; `load()` returns a valid id + plan DTO | `applyId`/`applyPlan` restore **before** tab mount; first frame already shows them | keys present and valid; echoed back through `apply…` | **real-data-bound** — restored from durable store; identical to what was persisted |
| **S4 — corrupt / version-mismatch persisted blob** | `load()` hits a malformed plan DTO (old schema, truncated, bad JSON) or an unknown place id | holders restore `null` (honest empty); app starts normally | bad value **dropped + cleaned** (mirror `onboarding_preferences.dart:131-139` invalid-id path) | **graceful-reset** — never crashes; degrades to S1 for that field |
| **S5 — persistence unavailable (non-durable)** | SharedPreferences init throws / backend fails | holders work in-memory for the session; sharing is fully functional | writes swallow errors (best-effort); nothing survives restart | **real-data-bound for the session** — choices hold in memory; non-durable (mirror `bootstrap.dart:39-48`) |

**Honest-state rules (never fabricate — playbook §4.1 / §13.5):**

- **Selected-place id is opaque, not PII.** A place id (e.g. `'seed-test-cafe'`) is a server
  identifier with no location/PII content; persisting it is within the §13.4 sanction ("선택 장소")
  and adds no location data beyond the existing manual region id. The **resolved** `LalaPlace`
  (with coordinates) is **never** persisted — only the id, exactly as region persists only the
  manual `regionId` and never coordinates (`region_context.dart:201-207`).
- **Plan persists what the user saw.** The persisted plan is the actual `LalaDailyPlan` timeline
  (slot titles + place ids + period), not a re-derivation. On relaunch the user sees the same
  timeline; the plan tab does **not** silently re-fetch and potentially change it (S3). Regeneration
  remains an explicit user action (`PlanPage` "일정 다시 만들기", `plan_page.dart:641`).
- **No fabrication in S1/S4.** A null/corrupt persisted state yields honest empty (the featured-place
  fallback on the map, the plan's own empty/loading state on the plan tab) — never a placeholder id,
  never a synthetic plan. This matches the existing per-state honesty in `plan_page.dart:50-56,395-426`.
- **Non-durable is honest (S5).** A failed store does not block the UI; the session works, choices
  hold in memory, and the only consequence is "won't survive restart" — the exact contract
  `bootstrap.dart:39-48` already upholds for region/language.
- **Region + language are untouched by these states.** S1–S5 describe only selected-place + plan;
  region/language follow their own (already-shipped) states and are byte-for-byte unchanged (D6).

---

## 4. Shared SSOT — the two new holders + persistence API (signatures only, no implementation)

All additions are **new files** (or new keys on the existing persistence module). No existing
holder's public API changes; no generated-client file is touched.

```dart
// apps/flutter_app/lib/core/state/selected_place_store.dart  — NEW, structural mirror of
// RegionContextStore (region_context.dart:113-208). Holds the active selected-place id.
class SelectedPlaceStore {
  SelectedPlaceStore._();

  static final ValueNotifier<String?> _notifier = ValueNotifier<String?>(null);

  // Optional cold-start persistence (attached in bootstrapAppState). null in tests.
  static OnboardingPreferences? _prefs;

  /// Listen for cross-tab selection changes (mirror RegionContextStore.listenable).
  static ValueListenable<String?> get listenable => _notifier;

  /// The active selected-place id, or null (no selection / honest empty).
  static String? get current => _notifier.value;

  static void attachPersistence(OnboardingPreferences prefs) => _prefs = prefs;
  static void detachPersistence() => _prefs = null;

  /// Publish a selection (or null to clear). Best-effort persist (fire-and-forget).
  /// Privacy: only the opaque place id is persisted; the resolved LalaPlace never is.
  static void set(String? id) { /* notifier.value = id; unawaited(_safeWrite(…)) */ }

  /// Awaited variant for completion/navigation points (mirror setAndFlush, region_context.dart:162).
  static Future<void> setAndFlush(String? id) async { /* notifier.value = id; await _safeWrite(…) */ }

  /// Cold start: restore the persisted id (null/unknown → null, honest empty).
  static void applyId(String? id) { /* notifier.value = id; (no write-back — already durable) */ }

  /// Reset to no selection (tests / re-onboarding). Forgets the persisted id.
  static void clear() { /* notifier.value = null; unawaited(_safeWrite(null)) */ }
}
```

```dart
// apps/flutter_app/lib/core/state/plan_context_store.dart  — NEW, structural mirror of
// RegionContextStore. Holds the active daily plan (the SSOT that replaces the dual-fetch).
class PlanContextStore {
  PlanContextStore._();

  static final ValueNotifier<LalaDailyPlan?> _notifier =
      ValueNotifier<LalaDailyPlan?>(null);

  static OnboardingPreferences? _prefs;

  static ValueListenable<LalaDailyPlan?> get listenable => _notifier;
  static LalaDailyPlan? get current => _notifier.value;

  static void attachPersistence(OnboardingPreferences prefs) => _prefs = prefs;
  static void detachPersistence() => _prefs = null;

  /// Publish the active plan (or null to clear). Best-effort persist via the plan DTO (D3).
  static void set(LalaDailyPlan? plan) { /* … */ }

  /// Awaited variant (regeneration completion / app-exit points).
  static Future<void> setAndFlush(LalaDailyPlan? plan) async { /* … */ }

  /// Cold start: restore the persisted plan. Corrupt/old DTO → null (graceful reset, S4).
  static void applyPlan(LalaDailyPlan? plan) { /* notifier.value = plan */ }

  static void clear() { /* notifier.value = null; unawaited(_safeWrite(null)) */ }
}
```

```dart
// apps/flutter_app/lib/core/persistence/cross_tab_preferences.dart  — NEW, structural mirror of
// onboarding_preferences.dart:101-183. Versioned keys + failure-safe load + graceful corrupt reset.
// Privacy: stores ONLY the selected-place id (opaque) + the plan DTO (slot titles/place ids/period).
// NEVER coordinates, raw transactions, or any PII beyond the existing manual region id.

const String kCrossTabStoragePrefix = 'lala.crosstab.v1.';   // versioned (mirror kOnboardingStoragePrefix)
// keys: '${kCrossTabStoragePrefix}selectedPlaceId'  (String?)
//       '${kCrossTabStoragePrefix}plan'             (JSON String? — the versioned DTO, D3)

@immutable
class CrossTabSnapshot {
  const CrossTabSnapshot({this.selectedPlaceId, this.plan});
  final String? selectedPlaceId;
  final LalaDailyPlan? plan;   // null when absent / corrupt / version-mismatch (graceful reset)
}

class CrossTabPreferences {
  CrossTabPreferences(OnboardingPreferencesBackend backend);   // REUSES the existing seam

  /// Loads the persisted snapshot. Never throws: a malformed plan DTO or unknown id
  /// degrades to null (S4) and the bad value is cleaned up (mirror load(), onboarding_preferences.dart:114-146).
  Future<CrossTabSnapshot> load() async { /* … */ }

  /// Persists (or clears) the selected-place id.
  Future<void> writeSelectedPlaceId(String? id) async { /* … */ }

  /// Persists (or clears) the plan as the versioned DTO (D3). Round-trips through
  /// LalaDailyPlan.fromJson (clients/flutter/lib/lala_api_client.dart:1369) on load.
  Future<void> writePlan(LalaDailyPlan? plan) async { /* … */ }

  /// Clears both keys (re-onboarding / reset).
  Future<void> clearAll() async { /* … */ }
}
```

```dart
// apps/flutter_app/lib/app/bootstrap.dart  — EXTENDED (additive). After the existing
// OnboardingState/RegionContextStore hydration (bootstrap.dart:50-55), attach + hydrate the two
// new holders from the SAME prefs instance. Failure path (:39-48) also detaches + clears them.
//   OnboardingState.attachPersistence(prefs);      // existing :50
//   RegionContextStore.attachPersistence(prefs);   // existing :51
//   SelectedPlaceStore.attachPersistence(prefs);   // [+contract]
//   PlanContextStore.attachPersistence(prefs);     // [+contract]
//   … final snapshot = await prefs.load();          // existing :53
//   OnboardingState.applySnapshot(snapshot);       // existing :54
//   RegionContextStore.applyManualRegionId(...);   // existing :55
//   final crossTab = await crossTabPrefs.load();   // [+contract]
//   SelectedPlaceStore.applyId(crossTab.selectedPlaceId);   // [+contract]
//   PlanContextStore.applyPlan(crossTab.plan);     // [+contract]  (epoch guard — D5)
```

**Persistence attachment model:** exactly `RegionContextStore`'s — the holder keeps an optional
`_prefs` ref; `set`/`setAndFlush` write through it when attached; `attach…`/`detach…` are wired in
`bootstrapAppState`; `apply…` is the cold-start restore. **No new backend, no new dependency.** The
`CrossTabPreferences` module reuses the existing `OnboardingPreferencesBackend` seam
(`onboarding_preferences.dart:59-69`) so it is unit-testable with the same `_MemoryBackend` /
`_FailingBackend` / `_DelayedBackend` fakes already in `cold_start_persistence_test.dart`.

---

## 5. Accessibility (a11y)

- **No new presentation node.** This contract changes *where selection/plan live* (per-tab field →
  shared holder), not *how they render*. The selected dock/detail, the plan timeline, and the bottom
  nav are rendered by existing widgets (`MapBottomDock`, `PlanSlotTile`, `LalaBottomNavBar`) whose
  a11y attributes are untouched.
- **Selection announcement is unchanged.** `placeCardSemanticsLabel(place, lang)`
  (`place_helpers.dart:212-223`) already derives the merged label from the resolved `LalaPlace`, not
  from the id. Moving the id into a shared holder changes *which* place is selected, not *how* it is
  labeled — so the screen-reader announcement stays correct on every tab with no extra wiring.
- **Plan a11y is unchanged.** `PlanPage`'s per-state `Semantics` labels (`plan_page.dart:494-501,586-577`)
  ride the plan object; sourcing the plan from the shared holder does not alter them.
- **No new touch target, no new KO/EN copy.** Sharing/persistence is invisible to the a11y tree.

---

## 6. Responsive / performance

- **One notification per change — no rebuild storm.** `ValueNotifier` fires once per distinct
  `value=`; the consumer pattern no-op-skips unchanged values (`plan_page.dart:102-105`), so only
  tabs whose visible state actually changes rebuild. Selecting a place pings 4 listeners; at most the
  tabs that resolve a different place rebuild — bounded, not per-frame.
- **No per-frame thrash.** Selection changes are discrete user actions (a tap); plan changes are
  discrete regenerations. There is no animation-frame / camera-idle cadence here (contrast the bounds
  arc's debounced camera query) — no debounce is needed.
- **Dual plan fetch is eliminated (net cheaper).** Today map (`home_page.dart:530`) and plan
  (`plan_page.dart:243`) each call `createDailyPlan()` independently. Centralizing to the shared
  holder means a publish by either tab is read by both — at most one fetch per regeneration, never
  two. No new network call is introduced; one is removed on average.
- **Persistence is off the critical path.** `set` is fire-and-forget (`unawaited`); `setAndFlush` is
  used only at completion points where the await is bounded by the existing `_DelayedBackend` shape.
  Cold-start `load()` is one SharedPreferences read (same cost as the existing onboarding `load()`).
- **Memory: two additional singletons holding one `String?` + one `LalaDailyPlan?`** — negligible;
  the plan object already exists per-tab today, so centralizing *reduces* peak (one shared vs two
  private copies).

---

## 7. Decisions D1–D8 — approved by the controller (locked)

All eight decisions are **approved**; the recommended option is locked in. Rejected alternatives are
retained for the record.

- **D1 — APPROVED: shared-state mechanism = extend the existing static-`ValueNotifier` singleton
  pattern (option a).** `SelectedPlaceStore` and `PlanContextStore` are exact structural mirrors of
  `RegionContextStore` (`region_context.dart:113-208`): one `static final ValueNotifier<T>`, a
  `listenable` getter, `set`/`setAndFlush`/`apply…`/`clear`, and an optional persistence attachment.
  Tabs consume them with the **same** `addListener`/`removeListener` pattern already used for region
  in `plan_page.dart:97-130`, `search_page.dart:114-135`, and `local_signals_page.dart:47-55`. This
  is the lowest-blast-radius option: zero new dependencies, one consistent mechanism across all four
  shared concerns (region, language, selected-place, plan), and the cold-start test fakes already
  exercise this shape. *(Rejected, option b — InheritedWidget/Provider: a second state-mgmt
  paradigm alongside the existing singletons, doubles the surface area, and forces a tree-position
  dependency the static holders don't have. Rejected, option c — Riverpod/Bloc: a new external
  dependency for a contract that the existing pattern already covers, violating the "no new dep"
  constraint and the V1 foundation policy.)*

- **D2 — APPROVED: scope of sharing = selected-place (id only) and plan (the `LalaDailyPlan`) shared
  across ALL 4 tabs, bidirectionally, with the holder as SSOT.** (a) **Selected-place:** the SSOT is
  `SelectedPlaceStore.current` (the id). Selecting on the map publishes; search/plan/local-signals
  resolve the id against their own items and reflect it (e.g. highlight, detail affordance). The
  resolved `LalaPlace` is **not** centralized — each tab resolves it from its own candidate set
  (exactly as `home_page.dart:480,746` does today: `placeById(items, id) ?? featuredPlace(items)`).
  (b) **Plan:** the SSOT is `PlanContextStore.current`. Whichever tab generates/regenerates a plan
  publishes via `set`; the map tab (planner sheet / route panel, `home_page.dart:1444`) and the plan
  tab (timeline) both read from the store instead of each fetching. This **eliminates the dual-fetch
  divergence** of `home_page.dart:530` vs `plan_page.dart:243`. "Add-to-plan"
  (`LocalSignalPlaceAction.addToPlan`) remains a selection action for now (no shared user-plan
  mutation is invented here — see §9). *(Rejected — centralize the resolved `LalaPlace` object too:
  forces a single canonical candidate set, which does not exist (each tab loads its own slice);
  the id is the only stable cross-tab currency, matching how region persists `regionId` not
  coordinates. Rejected — keep dual plan fetches and "sync" them: strictly more complex than one
  SSOT and re-introduces the divergence the contract removes.)*

- **D3 — APPROVED: persist selected-place id (plain String) + plan (versioned DTO) to
  SharedPreferences via a new `CrossTabPreferences` module that reuses the existing backend seam;
  hydrate on cold start in `bootstrapAppState`. Privacy: persist ONLY the opaque place id + the plan
  DTO (slot titles / place ids / period) — NO coordinates, NO raw transactions, NO PII beyond the
  existing manual region id.** The selected-place id is a trivial `String?` under a versioned key
  (`lala.crosstab.v1.selectedPlaceId`), mirroring `manualRegionId`
  (`onboarding_preferences.dart:26,160-166`). The plan is persisted as a **versioned app-owned DTO**
  serialized with `dart:convert` (`jsonEncode`/`jsonDecode` — a stdlib, **not** a new dependency),
  stored under `lala.crosstab.v1.plan`. The DTO is defined to round-trip through the existing
  `LalaDailyPlan.fromJson` (`clients/flutter/lib/lala_api_client.dart:1369`) on load. This is
  necessary because the generated client has **`fromJson` but no `toJson`** (`grep -c toJson` → 0,
  §0), so `plan.toJson()` does not exist; the DTO + round-trip is the approach that touches **no
  generated file** (the generated client is an API-lane artifact). Versioning (`v1.` prefix,
  mirroring `kOnboardingStoragePrefix`) makes future schema changes non-colliding; a corrupt or
  old-version blob degrades to null (S4) and is cleaned up, exactly as `load()` drops an invalid
  manual region id (`onboarding_preferences.dart:131-139`). *(Rejected — re-derive the plan on cold
  start by re-calling `createDailyPlan()` with persisted inputs: does NOT "persist the plan" — the
  timeline may change server-side, violating §13.4's "일정 … persist"; and it adds a cold-start
  network dependency the region layer deliberately avoids (`cold_start_persistence_test.dart` asserts
  zero device requests at cold start). Rejected — add `toJson` to the generated client: the client is
  an OpenAPI-generated artifact owned by the API lane; editing it couples this contract to codegen
  and risks regen overwrites. Rejected — persist the resolved `LalaPlace` with coordinates: location
  PII beyond the sanctioned id, violates the privacy constraint.)*

- **D4 — APPROVED: reactive propagation = the `ValueNotifier` listener mechanism already in use;
  consumers no-op-skip unchanged values.** A `set` on either holder fires one `ValueNotifier`
  notification; each tab's listener (mirror `plan_page.dart:97-108`) checks `if (!mounted) return;`,
  reads the new value, no-op-skips if it equals the tab's current derived state, and rebuilds
  otherwise. This is the **same** propagation that already shares region across the 4 tabs today —
  no new event bus, no streams, no `ChangeNotifier` diffing. Because the notification is one-per-
  distinct-value and consumers skip no-ops, there is no rebuild storm and no per-frame thrash (§6).
  *(Rejected — a broadcast `Stream<T>`: a second async mechanism alongside `ValueNotifier`; offers
  nothing the existing listenable doesn't, and adds subscription-lifecycle complexity to each tab.
  Rejected — `setState`-polling / `Timer`: anti-pattern; not reactive, misses cross-tab writes.)*

- **D5 — APPROVED: hydration order + an order/epoch guard prevent a stale persisted value from
  clobbering a fresh in-session selection.** (a) **Order:** `bootstrapAppState` hydrates the two new
  holders **after** attaching persistence and **before** any tab mounts (the existing
  `attach→load→apply` sequence at `bootstrap.dart:50-55`, extended additively). Because hydration
  completes pre-`runApp`, a tab's `initState` reads the restored value on the first frame — the same
  property that lets a restored manual region seed search/plan with zero device requests
  (`cold_start_persistence_test.dart:436-518`). (b) **Epoch guard:** once the holder has applied the
  persisted value (or accepted any runtime `set`), a *later* `apply…` call is a no-op unless it
  carries a newer epoch — so a slow, stale persisted read cannot overwrite a selection the user just
  made. This is the same shape the bounds arc used for stale response suppression
  (`home_page.dart:164-167 _refreshEpoch`) and that `plan_page.dart:156,176` uses for its
  `_loadGeneration`. *(Rejected — block the first frame on hydration with no guard: the existing
  hydration is already pre-`runApp` and fast; an additional blocking gate adds startup latency for
  no benefit. Rejected — no guard, last-write-wins including stale persisted: a late-loaded stale
  id/plan would silently overwrite a fresh user choice — the exact regression the bounds arc's epoch
  guard exists to prevent.)*

- **D6 — APPROVED: region + language sharing/persistence stay byte-for-byte unchanged (additive
  only; do not re-architect the existing holders).** `RegionContextStore` (`region_context.dart:113`)
  and `OnboardingState` (`onboarding_state.dart:21`) are **not** edited — their public API, their
  `ValueNotifier`s, their persistence keys, and their hydration calls (`bootstrap.dart:50-55`) are
  untouched. The two new holders are **siblings**; the two new persistence keys live under a **new**
  prefix (`lala.crosstab.v1.*`), disjoint from `lala.onboarding.v1.*`. The existing
  `cold_start_persistence_test.dart` assertions (region/language hydration, invalid-id drop,
  setAndFlush ordering, seed-no-device-request) must pass with **zero** assertion changes. *(Rejected
  — fold selected-place/plan into `OnboardingState` or `RegionContextStore`: conflates unrelated
  concerns, bloats the existing modules, and risks the region/language invariants this contract must
  protect. Rejected — reuse the `lala.onboarding.v1.*` keyspace: risks key collisions and couples
  the two persistence lifecycles (re-onboarding clearAll would wipe selection/plan unexpectedly).)*

- **D7 — APPROVED: honest empty/degraded states — no fabricated selection/plan; corrupt blob →
  graceful reset (no crash).** S1 (nothing persisted) → holders are `null`; tabs show their existing
  honest empty/default (map → featured-place fallback `home_page.dart:746`; plan tab → its own
  loading/empty states `plan_page.dart:395-426`). S4 (corrupt/version-mismatch persisted plan DTO, or
  an unknown place id) → `CrossTabPreferences.load()` returns null for that field and **cleans up**
  the bad value (mirror `onboarding_preferences.dart:131-139`); the app starts normally with honest
  empty. S5 (storage failure) → non-durable session, in-memory authoritative (mirror
  `bootstrap.dart:39-48`). Never a placeholder id, never a synthetic plan, never a "선택됨" label
  with nothing behind it. *(Rejected — fabricate a default selected place or a default plan to
  "avoid emptiness": violates §4.1/§13.5 honesty and the existing per-state discipline. Rejected —
  crash / show an error screen on a corrupt blob: a corrupt persisted value is recoverable and must
  not block app start, exactly as the onboarding layer already degrades gracefully.)*

- **D8 — APPROVED: a11y / screen-reader — no regression to existing tab semantics; shared selection
  still announces correctly.** The a11y label for a selected place is derived from the resolved
  `LalaPlace` via `placeCardSemanticsLabel(place, lang)` (`place_helpers.dart:212-223`) and the dock/
  detail widgets — none of which this contract touches. Moving the id into a shared holder changes
  *which* place resolves, not *how* it is announced, so every tab's screen-reader output stays
  correct. The plan's per-state `Semantics` labels (`plan_page.dart:494-501`) ride the plan object
  and are likewise unaffected by sourcing it from the shared holder. The bottom-nav labels
  (`lala_bottom_nav_bar.dart:33-51`) are driven by `OnboardingState.languageListenable`
  (`lala_main_shell.dart:27-32`) — unchanged. *(Rejected — add a redundant "선택됨" announcement per
  tab: the existing `Semantics` on the dock/detail already conveys selection; a second label is noise
  and risks double-announce. Rejected — couple the announcement to the holder rather than the
  resolved place: would announce an id, not a human-readable label; strictly worse for AT users.)*

---

## 8. Acceptance matrix (what must be true to PASS)

Reactive sharing across the 4 tabs (§13.4 "반응형으로 공유"):
- [ ] Selecting a place on the **map** tab updates `SelectedPlaceStore`; the **search**, **plan**,
      and **local-signals** tabs reflect the same selection on their next build (listener no-op-skip
      when unchanged — D4).
- [ ] Regenerating the plan on the **plan** tab updates `PlanContextStore`; the **map** tab's
      planner sheet / route panel reflects the same plan without an independent `createDailyPlan()`
      call (the dual-fetch divergence is eliminated — D2).
- [ ] A selection/plan made on **any** tab propagates to **all** others within one `ValueNotifier`
      notification (no polling, no manual refresh).

Persisted across relaunch (§13.4 "앱 재실행 후 persist"):
- [ ] After a process restart, a persisted selected-place id is restored into `SelectedPlaceStore`
      **before** any tab mounts (first frame already reflects it — D5 order).
- [ ] After a process restart, a persisted plan DTO round-trips through `LalaDailyPlan.fromJson` and
      is restored into `PlanContextStore`; the user sees the same timeline (not a silent re-fetch).
- [ ] `setAndFlush` at a completion/navigation point makes the choice durable **before** the gate
      flips / nav runs (mirror `RegionContextStore.setAndFlush` ordering,
      `cold_start_persistence_test.dart:218-303`).

Region + language unchanged (no regression — D6):
- [ ] `RegionContextStore` and `OnboardingState` source files are byte-for-byte unchanged (no edit).
- [ ] The `lala.onboarding.v1.*` keyspace is untouched; new keys live under `lala.crosstab.v1.*`.
- [ ] `bootstrap.dart`'s existing region/language hydration calls are unchanged; the new calls are
      purely **additive** (attached after, restored after).
- [ ] Existing `cold_start_persistence_test.dart` assertions pass with **zero** assertion changes
      (region/language hydration, invalid-id drop, failure-safe, setAndFlush ordering, routing,
      seed-no-device-request all still hold).

No PII (privacy — D3):
- [ ] Persisted state contains ONLY: the opaque selected-place id (String) and the plan DTO (slot
      titles / place ids / period). **No** device coordinates, **no** `RegionSource.current`
      retention, **no** raw transactions, **no** PII beyond the existing manual region id.
- [ ] The resolved `LalaPlace` (with lat/lng) is **never** persisted — only the id (mirror
      `region_context.dart:201-207`).

Honest empty / corrupt (D7):
- [ ] S1 (empty store) → holders null; map shows featured-place fallback, plan tab shows its
      existing loading/empty state. No fabricated selection/plan.
- [ ] S4 (corrupt plan JSON / unknown place id) → `load()` returns null for that field, cleans the
      bad key, app starts normally. No crash, no error screen.
- [ ] S5 (storage failure) → session is non-durable, in-memory authoritative; UI unaffected.

Contract surface (additive only):
- [ ] Two new files: `selected_place_store.dart`, `plan_context_store.dart` (mirrors of
      `RegionContextStore`). One new file: `cross_tab_preferences.dart` (mirror of
      `onboarding_preferences.dart`). `bootstrap.dart` extended additively.
- [ ] **No** generated-client file touched (no `toJson` added; `clients/flutter/**` unchanged).
- [ ] **No** new external dependency (`dart:convert` is stdlib; reuses `shared_preferences` +
      `OnboardingPreferencesBackend`). **No** new backend, **no** migration, **no** live/AI/device call.
- [ ] The 4 tab files gain listener wiring only (mirror the existing region listener shape); no tab's
      rendering/a11y/State-bar logic is rewritten.

Tests (future lane — only after approval):
- [ ] `cross_tab_preferences` unit tests: round-trip id + plan DTO; corrupt JSON → null + cleanup;
      unknown id → null; store failure → clean snapshot. Reuse `_MemoryBackend`/`_FailingBackend`/
      `_DelayedBackend`.
- [ ] Holder tests: `set`/`setAndFlush`/`apply…`/`clear`; no-op-skip on unchanged; epoch guard
      rejects a stale late `apply…` after a runtime `set`.
- [ ] Cross-tab propagation widget test: select on map → reflected in plan/search/local-signals;
      publish plan → map reads it without fetching.
- [ ] Cold-start: extend `cold_start_persistence_test.dart` with selected-place + plan restoration +
      no-device-request + corrupt-blob-degrades — **additive** new cases; existing assertions unchanged.
- [ ] No frozen wall-clock / no live call / no device needed (holders + persistence are pure).

---

## 9. Out of scope (frozen / explicit non-goals)

- A new **state-management dependency** (Riverpod / Bloc / Provider / InheritedWidget tree) — D1
  rejects; the existing static-`ValueNotifier` pattern covers it with zero new deps.
- Persisting **location / coordinates / PII** beyond the existing manual region id. Only the opaque
  selected-place id + the plan DTO (slot titles / place ids / period) are persisted (D3 privacy).
- Editing the **generated client** (`clients/flutter/lib/lala_api_client.dart`) — including adding
  `toJson`. The DTO + `dart:convert` round-trip avoids touching any generated artifact (D3).
- A shared **user-assembled plan** structure / "add-to-plan actually mutates a plan list" semantics.
  `LocalSignalPlaceAction.addToPlan` stays a selection action; inventing a mutable user-plan model is
  a separate product decision, not part of "share + persist what exists today" (D2).
- Changing the **plan-generation / regeneration** contract (`createDailyPlan` inputs, server
  determinism, the plan tab's regenerate flow). This contract shares + persists the plan; it does not
  change *how* a plan is produced.
- Re-deriving the plan on cold start via a live `createDailyPlan()` call (D3 rejected) — not
  "persist"; adds a cold-start network dependency.
- Touching `RegionContextStore`, `OnboardingState`, or the `lala.onboarding.v1.*` keyspace (D6 —
  region/language are byte-for-byte frozen).
- Any **live / AI / external / provider / device** call. Sharing is in-memory `ValueNotifier`;
  persistence is SharedPreferences; hydration reads durable keys only (no network at cold start).
- Changing tab rendering, a11y labels, touch targets, or KO/EN copy (D5/D8 — presentation frozen).
- Any DB migration, API route/OpenAPI change, backend change, deploy, crawl, DNS/auth mutation, paid
  AI/Speech, secret output, runtime/device verification.
- Mutation of `4942d41`, PR #133, `main`, `integration/lala-vision-v3`, or any closed branch.

---

## 10. Implementation plan (future per-phase lanes — NOT this foundation slice)

This foundation slice ships the contract **doc only** — one commit on the canonical branch
(`geondongkim/lala-v1-rc2-rail-reason-freshness`, PR #133), approved as contract-only. The binding
work happens in **later per-phase implementation lanes** (each its own branch + Draft PR per the V1
delivery policy), with **disjoint file ownership** and a common base of `4942d41`.

| Lane | Exclusive files | Changes | Data-integrity dependency? | Blocked-by? |
|---|---|---|---|---|
| **Lane 1 — shared-state holders + reactive wiring** | `apps/flutter_app/lib/core/state/selected_place_store.dart` (NEW), `apps/flutter_app/lib/core/state/plan_context_store.dart` (NEW), `apps/flutter_app/lib/features/home/home_page.dart`, `apps/flutter_app/lib/features/plan/presentation/pages/plan_page.dart`, `apps/flutter_app/lib/features/search/presentation/pages/search_page.dart`, `apps/flutter_app/lib/features/local_signals/presentation/pages/local_signals_page.dart` ONLY | (a) Create `SelectedPlaceStore` + `PlanContextStore` as exact mirrors of `RegionContextStore` (§4). (b) Map tab (`home_page.dart:137`): replace the private `_selectedPlaceId` with reads/writes through `SelectedPlaceStore`; replace the private `_dailyPlan` (`:128`) reads with `PlanContextStore.listenable`; publish generated plans (`:530`) via `PlanContextStore.set`. (c) Plan tab (`plan_page.dart:66,243`): read plan from `PlanContextStore` instead of a private fetch; publish on regenerate. (d) Search + local-signals tabs: add a `SelectedPlaceStore` listener (mirror their existing `RegionContextStore` listener) to reflect the shared selection. (e) No-op-skip + `mounted` guard + epoch field in each listener. | **NO persistence** in this lane — holders keep an optional `_prefs` ref but it is left `null` (Lane 2 attaches it). Sharing is fully functional in-session; nothing survives restart yet. | **None** — develops standalone against the holder signatures in §4. |
| **Lane 2 — persistence + cold-start hydration** | `apps/flutter_app/lib/core/persistence/cross_tab_preferences.dart` (NEW), `apps/flutter_app/lib/app/bootstrap.dart`, `apps/flutter_app/test/app/cold_start_persistence_test.dart` ONLY | (a) Create `CrossTabPreferences` mirroring `onboarding_preferences.dart` (versioned `lala.crosstab.v1.*` keys, failure-safe `load()`, corrupt-blob → null + cleanup, reuse `OnboardingPreferencesBackend`). (b) Define the plan DTO (`dart:convert` round-trip via `LalaDailyPlan.fromJson`, §4/D3). (c) `bootstrap.dart`: attach `SelectedPlaceStore`/`PlanContextStore` to prefs (mirror `:50-51`), `load()` + `applyId`/`applyPlan` after the existing hydration (mirror `:53-55`); extend the null/failure path (`:39-48`) to detach + clear the new holders. (d) Add the epoch guard (D5) so a late stale persisted value cannot clobber a fresh selection. (e) Extend `cold_start_persistence_test.dart` with additive cases (id+plan restoration, corrupt-blob-degrades, no-device-request) — existing assertions unchanged. | **YES** — reads/writes SharedPreferences (the same store region/language use). The plan DTO round-trip is the one data-integrity-critical path (corrupt/old blob must degrade, never crash). | **Blocked-by Lane 1** — persistence hooks into the holder's `attachPersistence`/`set`/`setAndFlush`/`apply…` surface, which Lane 1 defines. |

**Cross-lane dependency (the one critical hand-off):** Lane 2 is **blocked-by Lane 1** on the
**holder API contract** — the method names and signatures in §4 (`attachPersistence`, `set`,
`setAndFlush`, `applyId`/`applyPlan`, `listenable`, `current`, `clear`). Lane 2's persistence module
calls through those methods (exactly as `OnboardingPreferences` calls through `RegionContextStore`'s
`attachPersistence`/`setAndFlush` today). **They CAN be developed in parallel** against this pinned
contract (Lane 2 codes the DTO + keys + bootstrap wiring against the signatures fixed in §4); Lane 2
merges after Lane 1's holders land. **File ownership is disjoint:** Lane 1 owns the two new holder
files + the 4 tab files' listener wiring; Lane 2 owns the new persistence module + `bootstrap.dart` +
the cold-start test. The only shared symbol surface is the holder API (§4), which is pinned by this
contract — **no merge conflict is possible on files**, only a compile-time dependency on the holder
signatures that Lane 1 owns and Lane 2 consumes.

Each lane: incremental commits (one coherent sub-step each); push every 1–3 commits; **never push
red**; keep RC1/RC2/RC3 + three-signals + bounds + cold-start tests green with **zero** assertion
changes to existing cases. Each lane reports its own head SHA, commands run, focused + full test
results, CI run id, and what is NOT yet verified. **Report = CLAIM** — cross-checked against actual
diff/tests/CI. No self-declared runtime/device PASS; sharing + persistence are verified by unit +
widget tests with in-memory fakes, not by a runtime/device claim.
