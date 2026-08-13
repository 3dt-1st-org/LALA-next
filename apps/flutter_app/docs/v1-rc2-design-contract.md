# V1-RC2 Design Contract — reason + freshness across rail / carousel / selected sheet

**Branch:** `geondongkim/lala-v1-rc2-rail-reason-freshness` (stacked on RC1 `6ad8d1f`).
**Scope:** Flutter-side binding only. Deterministic. NO new external/AI/mock data. NO API change.
**Status:** DRAFT — awaiting controller approval before any code is written.

This contract is a **claim about the real code at `6ad8d1f`**. Every file path / line
number below was verified against the working tree. The controller and the independent
verifier will cross-check it.

---

## 0. The two fields already exist end-to-end (RC1 done the data layer)

`LalaPlace` (the **single** typed place model every surface uses) already carries reason +
freshness, parsed once from the API JSON:

- `clients/flutter/lib/lala_api_client.dart:1042-1043` (ctor), `:1067-1068` (fields
  `final String? reason; final String? freshness;`), `:1099-1100`
  (`reason: _asOptionalString(json['reason']), freshness: _asOptionalString(json['freshness'])`).
- The API populates both on **DB and snapshot** paths
  (`apps/api/app/services/places_service.py:78-79` and `:123-124`, RC1-verified).

**Consequence:** RC2 is a **render-site binding + consistency** task. No new model field,
no new API call, no new plumbing into the map tab (the fields already travel with each
`LalaPlace`). The text is produced server-side; Flutter renders it verbatim.

**Honesty invariants carried from RC1 (non-negotiable):** `reason`/`freshness` are
`String?`; render the line **only when non-null && non-empty**; otherwise omit honestly
(blank, never a placeholder like "이유 없음"). NO internal score is shown. KO-only text
(from the API). Reason is **text-only — NO icon/decoration** (the correction RC1 applied).
Reuse existing category colors via the existing SSOT (`categoryColor`, see §4).

---

## 1. Data flow + single source of truth

There is **no app-wide place SSOT**; Map and Search are independent loaders, each holding
its own `List<LalaPlace>`. That is fine for consistency because the API is deterministic for
a given place+payload, so the same `placeId` yields the same `reason`/`freshness` text on
both loaders. The consistency guarantee is therefore: **every surface reads
`place.reason` / `place.freshness` verbatim and applies identical visibility + styling rules**
(see §4 shared helper) — no per-widget rewording, no per-widget recomputation.

```
API (places_service: reason/freshness per place)
  └─ JSON
     └─ LalaPlace.fromJson  (lala_api_client.dart:1099-1100)   ← fields parsed ONCE
        │
        ├─ MAP TAB  (SSOT: _LalaHomePageState._places, home_page.dart:86)
        │     _places?.data?.places  →  Dashboard(places:, selectedPlaceId:)  (home_page.dart:1366)
        │       Dashboard.build:
        │         topPlaces = prioritizeClusterMembers(filterPlaces(...))     (dashboard.dart:201-205)
        │         topPlace  = placeById(topPlaces, selectedPlaceId)
        │                     ?? featuredPlace(topPlaces)                      (dashboard.dart:207-208)
        │         ├── MapPlaceCarouselOverlay(places: topPlaces, ...)          (dashboard.dart:313)
        │         │     └── MapRailPlaceCard(place: place)                     (carousel_overlay:162)
        │         ├── MapBottomDock(topPlace: topPlace, dataAsOf: ...)         (dashboard.dart:438)
        │         └── MapDraggableSheet(place: topPlace)                       (dashboard.dart:520)
        │               └── FeaturedPlacePanel → FeaturedPlaceHeader           (map_draggable_sheet:158)
        │
        └─ SEARCH TAB (SSOT: _SearchPageState._places, search_page.dart:67)
              _visiblePlaces → _SearchPlaceTile(place)                         (search_page.dart:291)
                └── ALREADY renders reason/freshness (RC1: search_page.dart:791,841,885)
```

**Map-tab key fact:** the *same* `LalaPlace` object already reaches the carousel card, the
dock, and the detail header (they all branch off `topPlaces`/`topPlace` in `Dashboard.build`).
So binding the map-tab surfaces is **purely a render-site change in each widget**.

### 1a. Surface inventory — LIVE vs DORMANT (verified)

| Surface | File | Rendered in app today? |
|---|---|---|
| Search tile | `search_page.dart:778` `_SearchPlaceTile` | ✅ LIVE (RC1 bound) |
| Map carousel card | `map_rail_place_card.dart:14` `MapRailPlaceCard` | ✅ LIVE (via `dashboard.dart:313`) |
| Selected — pinned dock | `map_bottom_dock.dart:13` `MapBottomDock` | ✅ LIVE (via `dashboard.dart:438`) |
| Selected — detail header | `featured_place_header.dart:13` `FeaturedPlaceHeader` | ✅ LIVE (via draggable sheet) |
| Wide rail card | `recommended_place_card.dart:11` `RecommendedPlaceCard` | ❌ DORMANT (only ctor of dead `PlaceRail`) |
| Wide rail host | `place_rail.dart:11` `PlaceRail` | ❌ DORMANT (not constructed anywhere in `lib/`) |
| Rail thumb | `rail_place_thumb.dart:7` `RailPlaceThumb` | ❌ DORMANT + image-only (no text slot) |

**Live recommendation rail = `MapPlaceCarouselOverlay` → `MapRailPlaceCard`** (not `PlaceRail`).
See §6 for how the dormant widgets are handled.

### 1b. ⚠️ Naming collision to disambiguate (decision D-2, §7)

`MapBottomDock` already shows a chip it calls "freshness"
(`map_bottom_dock.dart:164-166` → `_freshnessLabel(dataAsOf, …)` at `:197-203`), but that
value is the **response-level dataset timestamp** `dataAsOf = places.data.dataAsOf`
(`null` on the DB path; snapshot `generated_at` on the snapshot path) — **not**
`LalaPlace.freshness` (which is **per-place**). These are two different concepts sharing one
word. RC2 binds the **per-place** `LalaPlace.freshness`; the pre-existing dataset chip is
unchanged and explicitly out of scope (§7 D-2).

---

## 2. ASCII wireframes (where the reason + freshness line sits)

Legend: `[+]` = newly bound by RC2. `[R]` = reason line. `[F]` = freshness text.

### 2a. Search tile — `_SearchPlaceTile` (RC1; unchanged, shown as the reference)
```
┌────────────────────────────────────────────┐
│ [CategoryBadge]  320m  [F]5분 전            │  ← freshness in top meta row (Wrap)
│ 경복궁                                       │
│ 📍 경복궁역                                  │
│ [R] 영업중 · 근접                           │  ← reason: own line, 1-line ellipsis
│                          [ PlaceThumb ]     │
└────────────────────────────────────────────┘
```

### 2b. Map carousel card — `MapRailPlaceCard` (148×114, image-centric; LIVE)
Compact P6A §13.2 contract. Reason is added as a 3rd line in the existing bottom gradient
overlay; freshness is **not** crammed onto this card (see decision D-1).
```
 ┌──────────────────────────────┐
 │ ●(cat dot)        (image)    │
 │                              │
 │      ...(photo)...          │
 │ ▓▓▓▓▓▓ gradient ▓▓▓▓▓▓       │
 │ 경복궁                         │  ← name (1 line, ellipsis)
 │ 수원 · 도보 300m              │  ← region · distance (1 line, ellipsis)
 │ [R] 영업중 · 근접             │  ← [+RC2] reason (1 line, ellipsis, 10px/w600/white); omitted when null
 └──────────────────────────────┘
```

### 2c. Wide rail card — `RecommendedPlaceCard` (DORMANT; bind for forward-compat)
Same family as the search tile (text-left + optional thumb-right). Reason + freshness sit
exactly as on the search tile, reusing the shared widget (§4).
```
┌──────────────────────────────────────┐
│ [CategoryBadge]  300m  [F]5분 전      │  ← [F] in meta row
│ 경복궁                                 │
│ 경복궁역 (subtitle)                    │
│ [R] 영업중 · 근접                     │  ← [+RC2] reason line (ellipsis)
└──────────────────────────────────────┘
```

### 2d. Selected — pinned dock — `MapBottomDock` (LIVE)
Reason + per-place freshness added to the existing meta row, matching the search-tile style.
```
┌────────────────────────────────────────────┐
│ [CategoryBadge]                            │
│ 경복궁                                       │  ← name
│ 수원 · 300m · 출처 · [F]5분 전              │  ← [+RC2 F] appended to TinyMeta row
│ [R] 영업중 · 근접                           │  ← [+RC2] reason line (ellipsis)
└────────────────────────────────────────────┘
```

### 2e. Selected — detail header — `FeaturedPlaceHeader` (LIVE)
Reason + freshness added in the meta block under the name/address.
```
┌────────────────────────────────────────────┐
│            (hero image)                     │
│ [CategoryBadge]                            │
│ 경복궁                                       │  ← name
│ 📍 region                                   │
│ address                                     │
│ 300m · [F]5분 전                            │  ← [+RC2 F] freshness in meta
│ [R] 영업중 · 근접                           │  ← [+RC2] reason line (ellipsis)
└────────────────────────────────────────────┘
```

---

## 3. Consistency matrix

Rows = surface. "Source" = where the text comes from (must be the `LalaPlace` field, never
recomputed). "Null-handling" = behavior when the field is null/empty.

| Surface | reason source | freshness source | reason null → | freshness null → |
|---|---|---|---|---|
| Search tile (`_SearchPlaceTile`) | `place.reason` (RC1) | `place.freshness` (RC1) | omit line | omit text |
| Carousel card (`MapRailPlaceCard`) | `place.reason` **[+RC2]** | **n/a on this card** (D-1) | omit line (2-line layout) | n/a |
| Selected dock (`MapBottomDock`) | `place.reason` **[+RC2]** | `place.freshness` **[+RC2]** | omit line | omit meta chip |
| Selected detail (`FeaturedPlaceHeader`) | `place.reason` **[+RC2]** | `place.freshness` **[+RC2]** | omit line | omit meta text |
| Wide rail card (`RecommendedPlaceCard`, dormant) | `place.reason` **[+RC2]** | `place.freshness` **[+RC2]** | omit line | omit text |

**Single source of truth for the rendered text:** `LalaPlace.reason` / `LalaPlace.freshness`,
verbatim. **Single source of truth for rendering rules:** the shared widget + helper in §4
(adopted by the search tile too, as a pure refactor — no behavior change).

---

## 4. Shared rendering SSOT (single source of truth for styling + visibility)

To guarantee identical styling/visibility everywhere, extract RC1's inline rules into shared
code and adopt it on all surfaces:

- **New widget file** `apps/flutter_app/lib/features/place/widgets/place_reason_freshness.dart`:
  - `PlaceReasonLine({required LalaPlace place, TextStyle? base})` — renders `place.reason`
    as `Row>Expanded>Text(maxLines:1, overflow: ellipsis)`, style `bodySmall` + slate-500
    (`0xFF64748B`) + `w600` + height `1.2`. Returns `SizedBox.shrink()` when
    `reason == null || reason.isEmpty`. (Mirrors `search_page.dart:885-903` exactly.)
  - `PlaceFreshnessText({required LalaPlace place, TextStyle? base})` — renders
    `place.freshness` as `Text`, style `labelSmall` + slate-500 + `w600`. Returns
    `SizedBox.shrink()` when null/empty. (Mirrors `search_page.dart:841-849`.)
- **New helper in `place_helpers.dart`** (the existing place-display SSOT):
  - `String placeCardSemanticsLabel(LalaPlace place, String language)` →
    `[placeDisplayName, categoryFilterLabel, ?"${distanceM}m" (if >0), region (if non-empty),
    ?reason (if non-null/non-empty)].join(', ')`. (Extracts `search_page.dart:791-798`.)

**Adoption:** search tile is refactored to call `placeCardSemanticsLabel` + use the two
widgets (behavior identical — pure dedup). `MapRailPlaceCard`, `MapBottomDock`, and
`FeaturedPlaceHeader` import and use the same widget(s)/helper. **Result:** one rule, four
surfaces, impossible to diverge.

**Colors/styles:** reuse `categoryColor(place.category)` (P6A §2.3 SSOT,
`place_helpers.dart:60`) for any category-tinted border already present — no new colors.
Reason/freshness text uses the existing slate-500 token already used by RC1 (no new token).

---

## 5. Accessibility (a11y) — per surface

Match the RC1 search-tile pattern: a **combined Semantics label** that includes the reason
(but not freshness — matching RC1, `search_page.dart:792-798`). All surfaces build it via the
shared `placeCardSemanticsLabel` helper (§4) so wording is identical.

| Surface | Semantics approach |
|---|---|
| Search tile | `Semantics(container:true, label: placeCardSemanticsLabel(...))` (RC1; refactored to use helper) |
| Carousel card (`MapRailPlaceCard`) | Existing `Semantics(label: name, selected:, button:)` (`:48-51`) → label becomes `placeCardSemanticsLabel(...)` so reason is announced |
| Selected dock (`MapBottomDock`) | Wrap the card in `Semantics(container:true, label: placeCardSemanticsLabel(...))` |
| Detail header (`FeaturedPlaceHeader`) | `Semantics(container:true, label: placeCardSemanticsLabel(...))` on the header block |

**Minimum 44dp touch target** is already satisfied by the tappable card surfaces; the new
text-only lines are non-interactive and add no new targets, so no regression.

---

## 6. Responsive — no overflow at narrow viewport (follow #124)

**Pattern (PR #124, `ab9a11d`):** when a `Text` shares a `Row` with unbounded siblings, wrap
it in `Flexible(child: Text(overflow: TextOverflow.ellipsis, maxLines: 1))`
(`map_place_carousel_overlay.dart:97-111`). In a fixed-width card, bare
`Text(overflow: ellipsis, maxLines: 1)` is sufficient (already used in `MapRailPlaceCard`
name/meta and `RecommendedPlaceCard`).

**Applied to RC2:**
- `PlaceReasonLine` is `Row>Expanded>Text(maxLines:1, ellipsis)` by construction → never
  overflows; long reasons ("영업중 · 실내활동 적합 · 근접 · 공식 데이터") ellipsize cleanly
  (RC1 proved this at 320dp, `search_page_states_test.dart:305-316`).
- Dock/detail freshness appended to a meta row that already uses ellipsis → wrap in
  `Flexible` if the row has unbounded siblings.
- **Gate:** extend `apps/flutter_app/test/features/map/narrow_viewport_no_overflow_test.dart`
  (the #124 regression test) to pump `MapRailPlaceCard` / `MapBottomDock` /
  `FeaturedPlaceHeader` with a long reason + freshness at 320/360dp and assert
  `tester.takeException()` is null.

---

## 7. Decisions requiring controller sign-off

- **D-1 (placement on the compact carousel card).** `MapRailPlaceCard` (148×114) is an
  image-centric card whose visual contract (P6A §13.2) is deliberately minimal
  (name · region · distance · category dot). **Recommended:** render **reason** on it (3rd
  gradient-overlay line, honest-omitted → keeps the 2-line layout when null) and render
  **freshness only on the roomy surfaces** (tile, dock, detail header). Rationale: freshness
  on a 148px image card either overflows or needs a legibility chip (forbidden: text-only,
  no decoration); the same place's freshness is one tap away on the selected dock/detail.
  *Rejected alternatives:* (B) "reason · freshness" on one bottom line — freshness gets
  ellipsized away on long reasons, so it isn't actually visible; (C) freshness legibility pill
  — violates "no decoration." If the controller requires literal freshness on the carousel
  card, we take option B and accept the ellipsis.
- **D-2 (dataset `dataAsOf` chip on the dock).** `MapBottomDock`'s existing
  `_freshnessLabel(dataAsOf)` chip is the **dataset** snapshot time, a different concept from
  per-place `LalaPlace.freshness`. **Recommended:** leave it untouched (out of RC2 scope) and
  add per-place freshness as a separate meta item; do **not** reuse the `_freshnessLabel` name
  for the per-place binding (avoids the collision). If the controller wants them merged into
  one chip, that is a semantic change and we will STOP and ask.
- **D-3 (dormant widgets).** `PlaceRail`, `RecommendedPlaceCard`, `RailPlaceThumb` are not
  wired into `lib/` today. **Recommended:** bind `RecommendedPlaceCard` (cheap, listed in the
  mission, keeps the rail-card family consistent if re-wired); do **not** wire `PlaceRail`
  into the app (that is a feature-wiring change, out of scope); leave `RailPlaceThumb`
  image-only (no text slot — nothing to bind). The consistency *test* (§8) targets the LIVE
  surfaces where the guarantee is observable.
- **D-4 (stale comment).** `map_rail_place_card.dart:12-13` claims "freshness 는 LalaPlace 에
  필드가 없어 honest-empty 로 생략한다" — now false. Correct the comment as part of the bind.

---

## 8. Acceptance matrix (what must be true to PASS)

Per surface (reason):
- [ ] Search tile: reason line shown when present; omitted when null (RC1 — must not regress).
- [ ] `MapRailPlaceCard`: reason line shown when present (3rd overlay line); 2-line layout
      preserved when null. No overflow at 320/360dp with long reason.
- [ ] `MapBottomDock`: reason line shown when present; omitted when null.
- [ ] `FeaturedPlaceHeader`: reason line shown when present; omitted when null.
- [ ] `RecommendedPlaceCard` (dormant): reason line shown/omitted (unit test only).

Per surface (freshness), per D-1:
- [ ] Search tile: freshness shown when present; omitted when null (RC1 — no regress).
- [ ] `MapBottomDock` + `FeaturedPlaceHeader`: per-place freshness shown when present;
      omitted when null; dataset `dataAsOf` chip unchanged.
- [ ] `MapRailPlaceCard`: freshness not rendered (D-1) unless controller picks option B.

Consistency:
- [ ] **One `LalaPlace` → identical `reason` text** across search tile, carousel card, dock,
      detail header (consistency test: same `LalaPlace` pumped through all four; assert the
      reason string is found in each that renders it).
- [ ] Shared `placeCardSemanticsLabel` used by all four → identical a11y wording.
- [ ] No surface recomputes or rewords reason/freshness (grep: only `place.reason` /
      `place.freshness` reads; no string literals masquerading as reasons).

Honesty / scope:
- [ ] No internal `score` rendered on any of these surfaces.
- [ ] No mock/placeholder reason; null → blank.
- [ ] No AI/icon/decoration on the reason line; KO-only text.
- [ ] No API change; no live provider call; no new external dependency.
- [ ] `map_rail_place_card.dart:12-13` stale comment corrected (D-4).

Tests (Phase 2):
- [ ] Per-surface widget test: reason shown when present + honest-omission when null (extend
      `map_rail_place_card_test.dart`; add dock + header tests — these have **no** direct test
      today, a real coverage gap).
- [ ] Consistency test: one `LalaPlace` → same reason across tile + carousel card + dock +
      header.
- [ ] Overflow: extend `narrow_viewport_no_overflow_test.dart` with long reason + freshness
      at 320/360dp (no exception).
- [ ] a11y: semantics label includes reason when present, excludes when absent, on each
      surface (reuse `_hasSemanticsLabel` helper pattern from `search_page_states_test.dart`).
- [ ] Note: freshness is a **static string** in Flutter (computed server-side), so **no
      frozen-wall-clock** is needed in Flutter tests (unlike the RC1 API-side
      `_freeze_service_now`). Fixtures use literal strings (e.g. `'5분 전'`).

---

## 9. Out of scope (frozen / explicit non-goals)

- The Kakao JS webview marker info-window (`LegacyMapCanvas`) — rendered in JS, not Flutter.
- Wiring `PlaceRail` into the app; reviving `RailPlaceThumb`.
- Merging/altering the dataset-level `dataAsOf` chip on the dock.
- Any API, client-model, or state-management change.
- Mutation of `6ad8d1f`, PR #132/#131, `main`, `integration/lala-vision-v3`, or any closed branch.

---

## 10. Phase 2 plan (only after controller approval)

1. Add `place_reason_freshness.dart` (`PlaceReasonLine`, `PlaceFreshnessText`) +
   `placeCardSemanticsLabel` in `place_helpers.dart`.
2. Refactor `_SearchPlaceTile` to use them (pure dedup; behavior identical).
3. Bind `MapRailPlaceCard` (reason; D-1), `MapBottomDock` (reason + freshness; D-2),
   `FeaturedPlaceHeader` (reason + freshness), `RecommendedPlaceCard` (dormant; reason + freshness).
4. Fix stale comment (D-4).
5. Tests per §8; `dart format`; `flutter analyze`; `flutter test` (affected).
6. `git diff --check`; commit `feat(v1-rc2): ...`; push; open **Draft PR base =
   `geondongkim/lala-v1-rc1-reason-freshness`** (stacked); report exact head + full CI rollup.
