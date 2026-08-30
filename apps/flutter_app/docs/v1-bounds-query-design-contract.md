# V1 Bounds-Query Design Contract — viewport-rectangle place query (additive to center+radius)

> Historical contract note (2026-08-31): this document records the Kakao-based
> implementation at the named commit. The current map implementation uses the
> provider-neutral `LalaMap*` models and `naver-map-embed.html`; see
> `docs/planning/naver-map-migration-plan.md`. Historical identifiers below are
> intentionally retained as evidence of the original baseline.

> **Slice within V1 phase PR #133.** This is a foundation design contract on the canonical branch
> `geondongkim/lala-v1-rc2-rail-reason-freshness` (PR #133; head `36fe924`). It ships as a
> **doc-only foundation slice** — **no separate branch or PR is created for it.** Binding work is
> deferred to later per-phase implementation lanes (one branch + one Draft PR each, per the V1
> delivery policy). Retargeting PR #133's base is integrator-owned, not here.

**Canonical branch:** `geondongkim/lala-v1-rc2-rail-reason-freshness` (PR #133; head `36fe924`).
**Scope:** replace/augment the current **center+radius circle** place query with a true **viewport
bounds (SW/NE rectangle)** query, end-to-end — backend SQL → `/places` API → generated Dart client →
Flutter camera wiring — **without breaking the existing center+radius fallback or any §13.1
invariant.** **NO migration. NO live/AI/external/provider call.** **Status:** foundation doc — all
design decisions approved by the controller (§7); no product code in this slice.

This contract is a **claim about the real code at `36fe924`**. Every file path / line number below
was verified against the working tree this session. The controller and the independent verifier will
cross-check it.

> **Authoritative requirement.** The map section of the V1 reconciliation matrix is controller-local;
> the AUTHORITATIVE rule is playbook **§13.1**: markers/cards show **ONLY actual viewport results**;
> after the map finishes moving, **DEBOUNCE a BOUNDS query (not center+radius)**; pin-first
> clustering; selected marker / rail / card / category-color consistency. This contract implements the
> "bounds query" half of §13.1 additively — the center+radius path is retained verbatim as the
> fallback when bounds are absent, so no caller, test, or invariant regresses.

> **Format precedent.** This mirrors the section layout and honesty discipline of
> `v1-rc3-design-contract.md`, `v1-rc2-design-contract.md`, and `v1-three-signals-design-contract.md`
> (especially the three-signals §3 binding matrix and §7 approved/rejected decisions).

> **One fact that shapes the whole contract.** A rollout feature flag **already exists** for exactly
> this: `PLACES_VIEWPORT_BOUNDS` (W5-a, default **off**) — `apps/api/app/core/feature_flags.py:198-204`,
> already covered by `apps/api/tests/test_feature_flags.py:34`. The bounds query is gated behind this
> existing flag. **No new flag, no flag-list change** is introduced by this contract.

---

## 0. Current-state audit (not guess) — the center+radius circle today

The place query is, end to end, a **circle**: a bbox prefilter (sourced from center+radius) **AND** a
`ST_DWithin` circle predicate. There is **no viewport-rectangle query anywhere** today (verified:
`grep -niE "bbox|sw_lat|sw_lng|ne_lat|ne_lng|makeEnvelope|st_within|viewport"` over `apps/api` +
`apps/flutter_app` app code hits **only** the pre-existing `PLACES_VIEWPORT_BOUNDS` flag and unrelated
test/DOM viewport rects — no bounds query, no bounds param, no bounds model field).

| Claim | Verified at | Verdict |
|---|---|---|
| `/places` route takes `lat`,`lng`,`radius_m`,`category`,`lang`/`language`,`include_scores`,`limit`; delegates to `places_service.list_places` | `apps/api/app/routers/v1.py:85-109` (`radius_m=Query(1000,gt=0,le=50000)`, `limit=Query(60,gt=0,le=100)`) | ✅ |
| Service `list_places(lat,lng,radius_m,category,language,include_scores,limit=60)` → `db_repository.fetch_places`; returns `{count,places,query,source,location_engine,data_as_of}` | `apps/api/app/services/places_service.py:31-177` (DB path `:52-113`, snapshot fallback `:115-159`, empty `:161-177`) | ✅ |
| Repository `fetch_places` computes a bbox from center+radius via `_coordinate_radius_bounds`, filters `lat BETWEEN … AND lng BETWEEN …` (rectangle prefilter) **AND** `ST_DWithin(…,radius_m)` (true circle) | `apps/api/app/services/db_repository.py:184-241`; bbox source `:203-207`; rectangle `:234-235`; circle `:236-240` | ✅ |
| `_coordinate_radius_bounds(lat,lng,radius_m)` = square bbox (lat_delta=radius/111320; lng scaled by cos(lat)) | `apps/api/app/services/db_repository.py:462-475` | ✅ |
| Result is capped: `ORDER BY FLOOR(distance_m/500), final_score DESC, distance_m ASC, updated_at DESC` then `LIMIT max(1,min(limit,100))`; post-fetch `if distance_m > radius_m: continue` drops bbox overshoot | `apps/api/app/services/db_repository.py:310` (ORDER BY), `:318` (LIMIT), `:335` (circle gate) | ✅ |
| PostGIS is **already** in use (no extension to add): `ST_SetSRID`, `ST_MakePoint`, `ST_Distance`, `ST_DWithin`, `::geography` | `apps/api/app/services/db_repository.py:211,228-240` | ✅ |
| OpenAPI `PlacesQuery` schema **requires** lat/lng/radius_m; `additionalProperties:False`; no bounds properties | `apps/api/app/core/openapi.py:716-741` | ✅ |
| The Dart client `getPlaces` is **OpenAPI-generated** from `openapi.py` via `openapi-generator` (snake→camel: `radius_m`→`radiusM`) | `clients/flutter/lib/lala_api_client.dart:152-162` (`getPlaces({lat,lng,radiusM=1000,limit=60,category='all',lang='ko',includeScores=false,…})`); generator note `apps/api/app/core/openapi.py:375`; path-package dep `apps/flutter_app/pubspec.yaml:13` (`lala_next_flutter_client_reference: path: ../../clients/flutter`) | ✅ |
| Flutter `LalaBackend.getPlaces()` is **parameterless**; `LalaApiBackend.getPlaces()` reads `config.lat/lng/radiusM/placeLimit/category/lang/includeScores:true` and forwards to the generated `_client.getPlaces` | `apps/flutter_app/lib/core/backend/lala_backend.dart:17` (abstract), `:69-79` (impl) | ✅ |
| Query point flows: `_queryLat/_queryLng` → `_currentConfig()` → `config.lat/lng` → `getPlaces()` | `apps/flutter_app/lib/features/home/home_page.dart:189-191` (`_currentConfig`), `:331` (`_refresh`), `:402` (calls `_backend.getPlaces`) | ✅ |
| Reload trigger = haversine center-distance **≥ 250 m** (`shouldReloadPlacesForMapMove`) | `apps/flutter_app/lib/core/geo/geo_helpers.dart:5-18` (default `thresholdMeters=250`) | ✅ |
| Reload is **debounced 450 ms** on camera-idle (`_mapCameraDebounce`); idle handler sets `_queryLat/_queryLng` + `_mapLevel` | `apps/flutter_app/lib/features/home/home_page.dart:882-919` (`_handleMapCameraIdle`; Timer `:914`) | ✅ |
| Camera model carries **only** lat/lng/level — **no bounds/SW/NE** | `apps/flutter_app/lib/kakao_map_models.dart:54-65` (`KakaoMapCamera{lat,lng,level}`) | ✅ |
| JS embed `postCameraIdle` posts **only** `{type,lat,lng,level}` — **no bounds**; Kakao JS API `map.getBounds()` is available but unused | `apps/flutter_app/web/kakao-map-embed.html:170-180` (`dragend`/`zoom_changed` → `postCameraIdle`) | ✅ |
| Native JS-bridge parses `cameraIdle` → `KakaoMapCamera(lat,lng,level)` (no bounds) | `apps/flutter_app/lib/kakao_map_view_native.dart:169-177` | ✅ |
| Web JS-bridge parses `lala-map-camera-idle` DOM event → `KakaoMapCamera(lat,lng,level)` (no bounds) | `apps/flutter_app/lib/kakao_map_view_web.dart:93-101,126-145` (`_cameraFromDetail`) | ✅ |
| Pin-first clustering is **query-shape-agnostic**: threshold 24, far-level 10, top-60, 4×4/3×3 geographic grid, centroid per cell — operates on whatever `List<LalaPlace>` the query returns | `apps/flutter_app/lib/features/map/map_helpers.dart:56-194` (threshold `:72`, far-level `:73`, top-60 `:106`, grid `:132`, centroid `:154-157`) | ✅ |
| Config value object `LalaAppConfig{baseUri,…,lat,lng,radiusM,placeLimit,category,lang,…}` with `copyWith` | `apps/flutter_app/lib/core/config/app_config.dart:5-95` (fields `:47-58`, `copyWith :64-94`) | ✅ |

**Net:** today the map queries a **circle** (bbox ∧ `ST_DWithin`), the reload fires on **center-distance
≥ 250 m** (so a pure zoom that keeps the center does **not** reload), the camera/bridge carry **no
bounds**, and §13.1's "debounce a bounds query" is therefore **not yet satisfied**. The rectangle
prefilter machinery (`lat/lng BETWEEN`) already exists in SQL — it is just sourced from center+radius
and then intersected with a circle, instead of sourced from the viewport rectangle directly.

---

## 1. Data flow + single source of truth

The **bounds SSOT is the Kakao map itself** (`map.getBounds()` on camera-idle). Bounds are computed
**once** in the JS embed, carried through the bridge into `KakaoMapCamera`, threaded through
`LalaAppConfig` into the generated client, and echoed back in the `/places` `query` object. **No
client recomputes bounds from center+radius** (that would re-introduce the circle approximation
§13.1 forbids). When bounds are absent at any hop, the path falls back to center+radius verbatim.

```
Kakao map (camera-idle) ── map.getBounds() ──┐   ← [+contract] SSOT: the map, not a computed circle
apps/flutter_app/web/kakao-map-embed.html:170  postCameraIdle posts {type,lat,lng,level, sw_lat,sw_lng,ne_lat,ne_lng}
        │  (window.LalaMap.postMessage / lala-map-camera-idle DOM event)
kakao_map_view_native.dart:169  /  kakao_map_view_web.dart:126   ← [+contract] parse 4 bounds fields
        │
KakaoMapCamera{lat,lng,level, bounds?}          ← [+contract] kakao_map_models.dart:54 (optional bounds)
        │
_handleMapCameraIdle (home_page.dart:882)       ← unchanged 250 m gate + 450 ms debounce (D5); stores latest bounds
        │  (_refresh → _currentConfig() carries bounds via LalaAppConfig.copyWith)
LalaAppConfig{…,lat,lng,radiusM, bounds?}       ← [+contract] app_config.dart:5 (optional bounds + copyWith)
        │
LalaApiBackend.getPlaces (lala_backend.dart:69) ← [+contract] forwards bounds when present; else center+radius
        │
clients/flutter getPlaces({…,swLat,swLng,neLat,neLng})  ← regenerated from OpenAPI (Lane A hand-off)
        │  (HTTPS GET /api/v1/places?lat&lng&radius_m&…&sw_lat&sw_lng&ne_lat&ne_lng)
apps/api/app/routers/v1.py:85  /places          ← [+contract] 4 optional Query params (D3); flag-gated
        │
places_service.list_places (places_service.py:31) ← [+contract] thread bounds to fetch_places; echo in `query`
        │
db_repository.fetch_places (db_repository.py:184) ← [+contract] bounds branch: rectangle from SW/NE, circle off (D2)
        │
List<LalaPlace>  ──►  clusterMapPlacesForMap (map_helpers.dart:56)  ← UNCHANGED (D6): query-shape-agnostic
```

**Single source of truth for bounds:** the **Kakao map's `getBounds()` on camera-idle**
(`kakao-map-embed.html`). `KakaoMapCamera.bounds` (`kakao_map_models.dart`) is the in-app carrier;
`LalaAppConfig.bounds` (`app_config.dart`) is the call-site carrier; the `/places` `query` object
(`places_service.py`) is the server-side echo. There is **no second computation** of bounds anywhere —
the client never derives a rectangle from center+level/zoom (that would be an approximation and would
re-break §13.1). The `level`/center still ride alongside (they remain the distance/sort origin and the
reload-trigger inputs), but the **query filter** in bounds mode is the viewport rectangle alone.

---

## 2. ASCII / data-flow — camera-idle → debounced bounds query → markers

```
 ┌─ Kakao map ─────────────────────────────┐        user pans / zooms → map fires idle
 │  map.getCenter()  → (lat,lng)           │
 │  map.getLevel()   → level               │
 │  map.getBounds()  → SW(lat,lng),NE(lat,lng)   ← [+contract] the viewport rectangle (SSOT)
 └──────────────┬──────────────────────────┘
                │ postCameraIdle { type:'cameraIdle', lat,lng,level, sw_lat,sw_lng,ne_lat,ne_lng }
                ▼
 ┌─ JS bridge (native + web) ──────────────┐
 │  KakaoMapCamera(lat,lng,level, bounds)  │        bounds omitted if map didn't supply them → null
 └──────────────┬──────────────────────────┘
                │ _handleMapCameraIdle
                ▼
 ┌─ reload gate (home_page.dart:882) ──────┐
 │  center moved ≥ 250 m ?  ──┐            │        D5: + level-changed OR-clause (zoom refresh gap)
 │  level changed ?          ├─► reload    │        keep 450 ms debounce (no thrash)
 │  else ?            ──► no ┘             │
 └──────────────┬──────────────────────────┘
                │ Timer(450ms) → _refresh()
                ▼
 ┌─ query (bounds present → rectangle) ────┐
 │  GET /places ?lat&lng&radius_m          │        lat/lng = viewport center (distance/sort origin)
 │            &sw_lat&sw_lng&ne_lat&ne_lng │        radius_m retained as the FALLBACK circle param
 │            &category&lang&include_scores│        (used only on the center+radius fallback path)
 └──────────────┬──────────────────────────┘
                ▼
 ┌─ backend (flag PLACES_VIEWPORT_BOUNDS) ─┐
 │  bounds present ∧ flag on :             │
 │     lat BETWEEN sw_lat AND ne_lat       │        rectangle = exact viewport; ST_DWithin OFF
 │     lng BETWEEN sw_lng AND ne_lng       │        post-fetch `distance_m > radius_m` gate SKIPPED
 │     ORDER BY … LIMIT ≤100               │
 │  else (bounds absent / flag off) :      │
 │     existing bbox(circle) query — UNCHANGED   ← fallback invariant preserved
 └──────────────┬──────────────────────────┘
                ▼
   List<LalaPlace> (ONLY viewport-rectangle places) ──► clusterMapPlacesForMap ──► markers
        markers/cards show ONLY actual viewport results (§13.1) — never off-screen fabrication
```

> **Race-condition + selection notes (depicted above, decisions D5/D7):** (1) the debounced `_refresh`
> carries a monotonic **request-epoch guard** so a stale earlier reply cannot overwrite a newer candidate
> set (D5 response-ordering); (2) `_selectedPlaceId` survives the candidate-swap — when the selected pin
> scrolls out of the viewport the resolved place falls back to `featuredPlace` (not blank), and panning
> back re-resolves it (D7).

---

## 3. Binding matrix — honest state → query shape → markers

The query shape is decided by **(bounds present?) × (flag on?)**. Exactly one row runs per request.

| State | Trigger / inputs | Query shape that runs | Markers shown | Data-truth state |
|---|---|---|---|---|
| **B1 — bounds present, flag ON** (the new §13.1 path) | camera-idle supplied SW/NE; `PLACES_VIEWPORT_BOUNDS=on` | **rectangle**: `lat BETWEEN sw_lat AND ne_lat AND lng BETWEEN sw_lng AND ne_lng`; **circle OFF**; `ST_DWithin` omitted; post-fetch circle gate skipped; `ORDER BY FLOOR(distance_m/500),final_score DESC,distance_m ASC,updated_at DESC`; `LIMIT ≤100` | **ONLY** places whose lat/lng fall inside the viewport rectangle | **real-data-bound** — DB-cached `travel.public_places` only; no live provider, no fabrication; empty viewport → empty list (honest) |
| **B2 — bounds absent, flag ON** (camera/bridge without bounds, e.g. pre-idle / webview cold start) | bounds null at any hop | **existing circle** (bbox ∧ `ST_DWithin`) — UNCHANGED | center+radius circle result (current behavior) | real-data-bound (current path, unchanged) |
| **B3 — any bounds, flag OFF** (default rollout state) | `PLACES_VIEWPORT_BOUNDS=off` (default) | **existing circle** — bounds params **ignored, not errored** (forward-compatible) | center+radius circle result (current behavior) | real-data-bound (current path, unchanged) |
| **B4 — empty viewport rectangle** (bounds present, no places inside) | legitimate sparse area | rectangle query returns `[]` | **no markers** (honest empty) | real-data-bound — absence is truth, **not** a bug; §13.1 "only viewport results" holds vacuously |

**Honest-state rules (never fabricate — playbook §13.1 / §4.1):**

- **Viewport-only.** In B1, the rectangle is the **exact** filter; a place just outside the viewport is
  **not** returned. There is no padding/overscan and no center+radius approximation. Markers therefore
  never show off-screen places. (The `radius_m` param is retained on the wire as the fallback circle
  radius but is **ignored** in B1.)
- **No synthetic markers.** B4 returns an empty list; clustering (`map_helpers.dart:124-126`) already
  collapses an empty candidate set to no clusters/pins. Never fabricate a placeholder pin.
- **Fallback is byte-for-byte current behavior.** B2/B3 must produce **identical** SQL and identical
  `/places` output to today's circle path (same `query` object minus the four optional bounds keys,
  same `ORDER BY`, same `LIMIT`, same `source`/`location_engine`/`data_as_of`). This is the "no
  regression" invariant (§8).
- **Flag-off is forward-compatible.** B3 **ignores** bounds rather than `400`-ing, so a client may begin
  sending bounds before the flag flips in production without breaking. The flag is the only rollout
  switch (no second env var, no per-route toggle).
- **Distance/sort origin stays the viewport center.** `lat`/`lng` remain **required** params even in
  B1 (they are the viewport center); `distance_m` (from `ST_Distance` to that center) still drives
  `ORDER BY` and the proximity reason segment (`places_service.py:284-286`). Bounds change the
  **filter**, not the sort origin.

---

## 4. Shared SSOT — where bounds live (signatures only, no implementation)

All additions are **optional and additive**. No existing field's type or required-ness changes.

```dart
// apps/flutter_app/lib/kakao_map_models.dart  — camera gains an OPTIONAL bounds carrier
@immutable
class KakaoMapBounds {
  const KakaoMapBounds({required this.swLat, required this.swLng,
                        required this.neLat, required this.neLng});
  final double swLat, swLng, neLat, neLng;
  // value equality (mirror KakaoMapPlace operator ==/hashCode above)
}
class KakaoMapCamera {
  const KakaoMapCamera({required this.lat, required this.lng, required this.level, this.bounds});
  final double lat, lng; final int level;
  final KakaoMapBounds? bounds;   // [+contract] null → center+radius fallback (state B2)
}

// apps/flutter_app/lib/core/config/app_config.dart  — OPTIONAL bounds on the call-site config
class LalaAppConfig {
  // …existing fields unchanged…
  final KakaoMapBounds? bounds;            // [+contract] optional; null preserves current getPlaces
  LalaAppConfig copyWith({ /* …existing… */ KakaoMapBounds? bounds }) { … }
}

// apps/flutter_app/lib/core/backend/lala_backend.dart  — forward bounds when present
@override
Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() {
  return _client.getPlaces(
    lat: config.lat, lng: config.lng, radiusM: config.radiusM,
    limit: config.placeLimit, category: config.category, lang: config.lang,
    includeScores: true,
    swLat: config.bounds?.swLat, swLng: config.bounds?.swLng,   // [+contract] optional; null → circle
    neLat: config.bounds?.neLat, neLng: config.bounds?.neLng,
  );
}
```

```python
# apps/api/app/routers/v1.py  — four OPTIONAL Query params (additive; existing 8 unchanged)
@router.get("/places")
def places(
    request: Request,
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    radius_m: int = Query(1000, gt=0, le=50000),
    sw_lat: float | None = Query(None, ge=-90, le=90),   # [+contract] optional bounds
    sw_lng: float | None = Query(None, ge=-180, le=180),
    ne_lat: float | None = Query(None, ge=-90, le=90),
    ne_lng: float | None = Query(None, ge=-180, le=180),
    category: str = Query("all"), lang: str = Query("ko"),
    language: str | None = Query(None), include_scores: bool = Query(False),
    limit: int = Query(60, gt=0, le=100),
) -> dict: …  # all-or-none + sw≤ne validated in the service; passed through to list_places
```

```python
# apps/api/app/services/db_repository.py  — bounds branch in fetch_places (rectangle from SW/NE; circle off)
# When sw/ne all present (service pre-validates sw_lat≤ne_lat, sw_lng≤ne_lng):
#   min_lat,max_lat,min_lng,max_lng = sw_lat,ne_lat,sw_lng,ne_lng   (skip _coordinate_radius_bounds)
#   keep `lat BETWEEN %s AND %s AND lng BETWEEN %s AND %s`  (rectangle = exact viewport)
#   DROP the `AND ST_DWithin(…,%s)` clause in this branch
#   DROP the post-fetch `if distance_m > radius_m: continue` gate in this branch
# else: existing circle path UNCHANGED
```

**Server-side SSOT for the rectangle:** `db_repository.fetch_places` is the **only** place the
viewport rectangle becomes a SQL filter. The rectangle corners come straight from the validated
`sw_*`/`ne_*` params — **no re-derivation, no padding**. The service (`places_service.list_places`)
is the only place the `/places` `query` echo includes the four optional keys (mirroring how it echoes
`lat`/`lng`/`radius_m` today at `:99-107`).

---

## 5. Accessibility (a11y)

- **N/A / unchanged — backend + query-shape change.** This contract adds no Flutter presentation node,
  no new widget, no new touch target. Markers are still rendered by the existing JS embed
  (`kakao-map-embed.html`) and clustered by the existing `clusterMapPlacesForMap`; their a11y
  attributes (`role="img"`, `aria-label`, marker `title`) are untouched.
- Incidental a11y benefit (not a claim of new behavior): in state B1 the map describes **only**
  in-viewport places, so the screen-reader map label and the card rail stay consistent with what is
  visibly pinned — but this follows from §13.1 viewport-only, not from any a11y wiring added here.
- No new KO/EN copy; the reason/freshness strings (`places_service.py`) are unchanged by this contract.

---

## 6. Responsive / performance

- **Query cost — equal or lower.** State B1 runs the **same** `lat/lng BETWEEN` rectangle prefilter
  already in production (`db_repository.py:234-235`) and **drops** the `ST_DWithin` circle predicate
  (`:236-240`) and the post-fetch circle gate (`:335`). Net work is ≤ today; never more. No new index,
  no `ST_MakeEnvelope`, no GiST dependency (rejected alternative, §7 D2).
- **Result cap preserved.** `LIMIT max(1,min(limit,100))` (`:318`) and the clustering `top-60`
  (`map_helpers.dart:106`) are unchanged → marker count stays bounded exactly as today regardless of
  how dense the viewport is.
- **Debounce preserved.** The 450 ms camera-idle debounce (`home_page.dart:914`) is retained (D5); a
  bounds query is fired **at most** once per settled viewport, never per animation frame. The 250 m
  center-distance gate stays as a cheap short-circuit before the debounce.
- **No new network shape.** B1 adds four query-string params to an existing `GET /places`; the response
  envelope (`{count,places,query,source,location_engine,data_as_of}`) gains only four **optional** keys
  inside the existing `query` object. No new endpoint, no payload-size growth beyond the echo.
- **Narrow-viewport / overflow: unaffected.** This is not a presentation change; the
  `narrow_viewport_no_overflow_test.dart` gate is irrelevant here and is **not** extended by this
  contract (contrast three-signals §6, which did extend it for a longer reason string).

---

## 7. Decisions D1–D8 — approved by the controller (locked)

All eight decisions are **approved**; the recommended option is locked in. Rejected alternatives are
retained for the record.

- **D1 — APPROVED: bounds is ADDITIVE and OPTIONAL (option a); center+radius stays the fallback.** The
  four `sw_*`/`ne_*` params are optional on `/places`; when **all four** are present **and** the flag
  is on, the viewport rectangle runs (state B1); otherwise the existing circle query runs unchanged
  (B2/B3). `lat`/`lng`/`radius_m` remain **required** (they are the viewport center + the fallback
  radius + the distance/sort origin). **No existing caller, test, or client call site changes.**
  *(Rejected, option b — replacement: make `radius_m` optional and require bounds. Breaks every current
  caller — `LalaApiBackend.getPlaces` (`lala_backend.dart:69`), `search_page.dart:230`, the snapshot
  fallback (`public_mvp_data.py:35`), and all `/places` tests — for zero §13.1 gain, since the
  center+radius path is already correct. Additive keeps blast radius to "new optional params only.")*

- **D2 — APPROVED: backend rectangle = the EXISTING `lat/lng BETWEEN` prefilter re-sourced from SW/NE,
  with the `ST_DWithin` circle dropped in bounds mode; keep the `LIMIT` cap; NO migration.** In
  `db_repository.fetch_places`, the bounds branch sets `min/max_lat/lng` directly from the validated
  `sw/ne` (skipping `_coordinate_radius_bounds`, `:462-475`), keeps the `BETWEEN` clauses, omits the
  `ST_DWithin` circle (`:236-240`) and the post-fetch `distance_m > radius_m` gate (`:335`), and keeps
  `ORDER BY … LIMIT ≤100` (`:310,:318`). This is a **query-shape change behind a flag**, not a schema
  change — **no migration, no apply, no index add**. Honesty: the rectangle is the **exact** viewport;
  a place outside it is never returned (no off-screen fabrication, §13.1). *(Rejected — introduce
  PostGIS `ST_MakeEnvelope` + `&&`/`ST_Within` with a GiST envelope: more idiomatic "real" PostGIS, but
  adds operator/index machinery that is unneeded at Korea scale (viewport never crosses the ±180
  dateline), gains nothing over the `BETWEEN` rectangle already running in production, and risks a plan
  change. The `BETWEEN` rectangle is already correct and already exercised.)*

- **D3 — APPROVED: four OPTIONAL `/places` Query params (`sw_lat`,`sw_lng`,`ne_lat`,`ne_lng`),
  each ge-range-validated, with all-or-none + `sw≤ne` enforced in the service; OpenAPI `PlacesQuery`
  gains them as optional properties; existing callers unaffected; `include_scores`/reason/freshness
  behavior unchanged.** The route (`v1.py:85`) adds the four `Query(None, ge=…, le=…)` params;
  `places_service.list_places` accepts them, validates "all-or-none" and `sw_lat≤ne_lat`,
  `sw_lng≤ne_lng` (else `ServiceError(400, INVALID_BOUNDS)`), threads them to `fetch_places`, and
  echoes them (when present) inside the existing `query` object. The OpenAPI `PlacesQuery` schema
  (`openapi.py:716`) adds the four as optional `number` properties (the schema stays
  `additionalProperties:False`; only the four named optionals grow it). **Reconciliation with cleanroom
  W5-a:** the program spec (`docs/planning/cleanroom-reimplementation-execution-program.md:426`, item W5-a)
  sketches the bounds as a single `bounds=minLat,minLng,maxLat,maxLng` param; this contract instead uses
  **four discrete params** — a strict superset of the same rectangle (individually range-validatable,
  OpenAPI-clean, snake→camel-generatable). The rectangle semantics are identical; the divergence from
  W5-a's literal one-param shape is intentional and documented here. **Flag-off ignores bounds
  (B3), never errors** — so the param is forward-compatible. *(Rejected — make `radius_m` nullable in
  OpenAPI to "express" that bounds replaces it: breaks the generated client's `radiusM` default and
  every caller, for a documentation nicety. Rejected — return `400` when bounds sent with flag off:
  couples client rollout to server flag flip and breaks forward-compatibility; ignore is safer.)*

- **D4 — APPROVED: bounds derived from the Kakao map's `getBounds()` on camera-idle; carried as an
  OPTIONAL `KakaoMapCamera.bounds`; threaded via `LalaAppConfig.bounds` into the regenerated client.**
  (a) JS embed `postCameraIdle` (`kakao-map-embed.html:170`) calls `map.getBounds()` and posts
  `sw_lat/sw_lng/ne_lat/ne_lng`. (b) Both bridges parse them — native `kakao_map_view_native.dart:169`
  and web `kakao_map_view_web.dart:126` (`_cameraFromDetail`) — into `KakaoMapCamera(...,bounds)`
  (`kakao_map_models.dart:54`, new `KakaoMapBounds` value type). (c) `_handleMapCameraIdle`
  (`home_page.dart:882`) stores the latest bounds; `_currentConfig()` (`:189`) threads them through
  `LalaAppConfig.copyWith` (`app_config.dart:64`); `LalaApiBackend.getPlaces` (`lala_backend.dart:69`)
  forwards them when non-null. (d) The generated `clients/flutter getPlaces` is **regenerated from
  OpenAPI** (Lane A) to accept the four optional params. **SSOT = the map** — the client never computes
  a rectangle from center+level (that would re-approximate the circle §13.1 forbids). *(Rejected —
  derive bounds client-side from center+level using Kakao's level→meters table: re-introduces exactly
  the center+radius approximation §13.1 rejects, diverges from the real viewport at high latitudes /
  near the equator, and duplicates the map's own bounds logic. The map already knows its bounds; read
  them.)*

- **D5 — APPROVED: KEEP the 250 m center-distance gate + 450 ms debounce; ADD a level-changed
  OR-clause to the gate; the QUERY becomes bounds-based.** §13.1 wants "debounce a bounds query" — the
  **query** becomes the viewport rectangle (D1–D4); the **trigger** stays cheap: reload when center
  moved ≥ 250 m **OR** map level changed (zoom), then debounce 450 ms. The level OR-clause closes the
  current gap where a **pure zoom** (center unchanged) does not reload (`shouldReloadPlacesForMapMove`
  at `geo_helpers.dart:5-18` checks center distance only). No per-pixel / per-drag firing — the
  debounce still gates it. *(Rejected — switch the trigger to pure bounds-change (any SW/NE delta):
  fires on every micro-pan/zoom before the debounce short-circuit can suppress it, and discards the
  useful 250 m cheap gate. The level OR-clause gets the §13.1 zoom-refresh behavior at lower cost.)*

- **D5 (response ordering) — APPROVED: Lane B adds a monotonic request-epoch guard at the `_refresh`
  result-apply site.** `_refresh` (`home_page.dart:331`) is fired `unawaited(...)` from the camera-idle
  debounce (`:214`) and from location acquisition (`:756`); today it has **no** sequence guard — two
  overlapping calls resolve last-`setState`-wins (only a `mounted` check exists), so a slow earlier query
  can overwrite a newer candidate set. Bounds mode fires more queries (zoom, per D5's level OR-clause),
  widening that out-of-order window. Decision: capture an incrementing epoch token when a query is
  dispatched; on reply, apply the result only if the token is still current (else discard as stale).
  **Additive** — also hardens the existing center+radius path. *(Rejected — cancel the in-flight HTTP
  request on each new dispatch: the OpenAPI-generated client does not expose reliable per-call
  cancellation, and `_backend.close()` (`:352`) already tears down the prior client; an epoch guard is
  provider-agnostic and sufficient.)*

- **D6 — APPROVED: pin-first clustering (`clusterMapPlacesForMap`) is UNCHANGED and remains correct
  under a bounds query.** Clustering is query-shape-agnostic: it consumes the returned `List<LalaPlace>`
  regardless of whether they came from a circle or a rectangle. Threshold 24 (`:72`), far-level 10
  (`:73`), top-60 (`:106`), and the 4×4/3×3 geographic grid (`:132`) all operate on the candidate set;
  under B1 the candidates span the viewport, so the grid's min/max lat/lng (`:128-131`) span the
  viewport rectangle and centroids land inside it. No clustering threshold or grid change. *(Rejected —
  raise the cluster threshold for bounds mode to "fill the viewport": an unrequested clustering-policy
  change, out of scope (§9), and would alter marker density behavior §13.1 pins.)*

- **D7 — APPROVED: selected-place preservation across a bounds candidate-swap — NO selection change;
  existing graceful behavior is unchanged and documented here.** The selection SSOT is `_selectedPlaceId`
  (`home_page.dart:98`); `_refresh` does **not** clear it on reload (only explicit reset/clear handlers do:
  `:219,:690,:858`). The *resolved* selected place is `placeById(effectiveItems, _selectedPlaceId)` with a
  `?? featuredPlace(effectiveItems)` fallback (`:425,:684`), so when the user pans/zooms and the selected
  pin scrolls out of the viewport candidate set, the dock/detail gracefully resolve to the featured place
  rather than blanking — and `_selectedPlaceId` is retained, so panning back re-resolves it. This is
  **today's behavior** (the center+radius path already does the same); bounds mode changes **no** selection
  code and adds **no** flicker / forced-deselection. Out of scope: "keep the selected pin detailed even
  when off-screen" — a separate selection enhancement, not part of the bounds query. *(Rejected —
  force-deselect (`_selectedPlaceId = null`) when the selected pin leaves the viewport: destroys a valid
  user selection on every pan; the retained-id + featured-fallback is strictly better.)*

- **D8 — APPROVED: category-color consistency is unchanged under bounds results.** The category-color SSOT
  is `categoryColor`/`categoryColorHex` (`apps/flutter_app/lib/features/place/helpers/place_helpers.dart`),
  consumed identically by Flutter cards/chips/badges and by the JS marker embed
  (`kakao-map-embed.html`, identical hex). The bounds query changes only the **candidate set**
  (`List<LalaPlace>`), never the per-place category→color map, so marker/rail/card/dock colors stay mutually
  consistent whether candidates came from a circle or a viewport rectangle. No color code is touched by
  either lane. *(Rejected — introduce a bounds-mode color variant: violates §13.5 "색만으로 category 전달
  금지" and the SSOT; zero benefit.)*

---

## 8. Acceptance matrix (what must be true to PASS)

Viewport honesty (§13.1):
- [ ] State **B1**: every returned place has `sw_lat ≤ lat ≤ ne_lat` **and** `sw_lng ≤ lng ≤ ne_lng`
      (rectangle = exact filter); a place just outside the viewport is **never** returned.
- [ ] State **B4** (empty viewport): `/places` returns `count:0, places:[]`; clustering renders **no**
      markers/pins. No placeholder/fabricated pin.
- [ ] No off-screen fabrication in any state: markers/cards show **ONLY** actual viewport (B1) or
      circle (B2/B3) results.

Fallback intact (no regression — B2/B3 byte-for-byte current):
- [ ] Bounds **absent** (B2) → SQL is the existing `bbox ∧ ST_DWithin` circle; `/places` `query` object
      is identical to today (no `sw_*`/`ne_*` keys); `ORDER BY`/`LIMIT`/`source`/`location_engine`/
      `data_as_of` unchanged.
- [ ] Flag **off** (B3, default) → bounds params **ignored** (no `400`); circle path runs; identical
      output to today.
- [ ] Existing `/places` callers/tests pass with **zero** assertion changes: `LalaApiBackend.getPlaces`
      (`lala_backend.dart:69`), `search_page.dart:230`, snapshot fallback (`public_mvp_data.py:35`).

§13.1 invariants preserved:
- [ ] Kakao map remains the only map provider (no map swap).
- [ ] Pin-first clustering (`map_helpers.dart:56`) unchanged: threshold 24, far-level 10, top-60,
      4×4/3×3 grid, real-member centroids.
- [ ] Selected marker / rail / card / category-color consistency unchanged (no selection/rail/card
      code touched by this contract).
- [ ] Debounced query retained (450 ms); reload gate = center ≥ 250 m **OR** level changed (D5).
- [ ] Stale-response suppression: a later bounds-query result never overwrites a newer one (request-epoch
      guard in `_refresh`, D5 response-ordering).
- [ ] Selected place preserved across a bounds candidate-swap (retained `_selectedPlaceId` + featured
      fallback; no forced deselection/flicker, D7).
- [ ] Category-color SSOT unchanged — markers/rail/card/dock mutually consistent under bounds results (D8).

Contract surface (additive only):
- [ ] `/places` gains **four optional** params; `lat`/`lng`/`radius_m` stay **required**.
- [ ] OpenAPI `PlacesQuery` gains the four as optional `number` properties; `additionalProperties:False`
      retained; no existing property removed/retyped.
- [ ] `include_scores`/`reason`/`freshness` behavior unchanged (this contract does not touch
      `places_service.py` reason/freshness composition — only threads bounds into `fetch_places` and the
      `query` echo).
- [ ] Generated `clients/flutter getPlaces` regenerated; the four params are **optional** (defaults
      null) so existing call sites compile unchanged.
- [ ] No DB **migration**, no apply, no index add, no new flag (uses existing `PLACES_VIEWPORT_BOUNDS`).
- [ ] No live/AI/external/provider call; bounds query reads DB-cached `travel.public_places` only
      (`places_service.py:61-63` provider-isolation comment respected).

Tests (future lane — only after approval):
- [ ] `db_repository` / `places_service`: B1 returns only in-rectangle places; B2/B3 identical to
      pre-change circle output (snapshot-diff the `query` object); B4 → empty; all-or-none + `sw≤ne`
      validation → `INVALID_BOUNDS`; flag-off ignores bounds.
- [ ] Flutter: `KakaoMapCamera` round-trips optional bounds through both bridges; null bounds →
      `getPlaces` omits the four params (circle fallback); `_handleMapCameraIdle` reload fires on
      zoom (level change) as well as pan (D5).
- [ ] Keep green with **zero** assertion changes to existing `/places`, clustering, and reload tests.
- [ ] No frozen wall-clock / no live call needed (bounds query is a static DB read over cached rows).

---

## 9. Out of scope (frozen / explicit non-goals)

- Any **DB migration**, schema change, index add, or `apply` (the bounds branch is a query-shape change
  behind the existing `PLACES_VIEWPORT_BOUNDS` flag).
- Any **live / AI / external / provider** call. The bounds query is DB-cached/PostGIS only
  (`places_service.py:61-63`); it never triggers the live KMA/AirKorea provider and never calls a
  scoring/AI service.
- Changing the **pin-first clustering** policy (threshold 24, far-level 10, 4×4/3×3 grid, top-60) —
  D6 leaves it query-shape-agnostic and unchanged.
- Touching the **selected marker / rail / card / category-color** consistency surfaces — out of scope;
  this contract changes only the **candidate query**.
- Replacing the center+radius path (D1 option b) or making `radius_m` nullable in OpenAPI (D3
  rejected) — rejected to preserve the fallback and every caller.
- Introducing `ST_MakeEnvelope`/`ST_Within`/`&&` + GiST envelope (D2 rejected alternative) — the
  existing `BETWEEN` rectangle already suffices at Korea scale.
- Dateline / antimeridian wrap handling — Korea viewports never cross ±180; `sw_lng ≤ ne_lng` is
  always satisfiable. (If a future worldwide viewport needs wrap, that is a separate contract.)
- Client-side bounds derivation from center+level (D4 rejected) — re-approximates the circle §13.1
  forbids.
- Switching the reload trigger to pure bounds-change (D5 rejected) — loses the 250 m cheap gate.
- Mutation of `36fe924`, PR #133, `main`, `integration/lala-vision-v3`, or any closed branch.
- main merge, deploy, production DB write/migration-apply, crawl, DNS/auth mutation, paid AI/Speech,
  live provider call, secret output, runtime/device verification.

---

## 10. Implementation plan (future per-phase lanes — NOT this foundation slice)

This foundation slice ships the contract **doc only** — one commit on the canonical branch
(`geondongkim/lala-v1-rc2-rail-reason-freshness`, PR #133), approved as contract-only. The binding
work happens in **later per-phase implementation lanes** (each its own branch + Draft PR per the V1
delivery policy), with **disjoint file ownership** and a common base of `36fe924`.

| Lane | Exclusive files | Changes | Data-integrity dependency? |
|---|---|---|---|
| **Lane A — backend + OpenAPI + client regen** | `apps/api/app/routers/v1.py`, `apps/api/app/services/places_service.py`, `apps/api/app/services/db_repository.py`, `apps/api/app/core/openapi.py` ONLY (+ regenerate `clients/flutter/lib/lala_api_client.dart` from the updated spec) | (a) Route (`v1.py:85`): add four optional `Query(None, ge=…, le=…)` params. (b) Service (`places_service.py:31`): accept bounds, validate all-or-none + `sw≤ne` (`ServiceError(400, INVALID_BOUNDS)` else), thread to `fetch_places`, echo in `query` when present. (c) Repository (`db_repository.py:184`): bounds branch — rectangle from SW/NE, `ST_DWithin` OFF, post-fetch circle gate skipped, keep `ORDER BY`/`LIMIT`; else existing circle unchanged. (d) OpenAPI (`openapi.py:716`): four optional `number` props on `PlacesQuery`. (e) Regenerate `clients/flutter` so `getPlaces` accepts the four optional params. Gate the rectangle on the **existing** `PLACES_VIEWPORT_BOUNDS` flag (no new flag). | **YES** — DB read of `travel.public_places`; additive SQL only, **no migration**. Reads existing tables (table checks at `db_repository.py:43-46`). Honesty invariants (§8) enforced in the service/repository. |
| **Lane B — Flutter client wiring** | `apps/flutter_app/lib/kakao_map_models.dart`, `apps/flutter_app/web/kakao-map-embed.html`, `apps/flutter_app/lib/kakao_map_view_native.dart`, `apps/flutter_app/lib/kakao_map_view_web.dart`, `apps/flutter_app/lib/core/config/app_config.dart`, `apps/flutter_app/lib/core/backend/lala_backend.dart`, `apps/flutter_app/lib/features/home/home_page.dart`, `apps/flutter_app/lib/core/geo/geo_helpers.dart` ONLY | (a) `kakao_map_models.dart:54`: add `KakaoMapBounds` + optional `KakaoMapCamera.bounds`. (b) `kakao-map-embed.html:170`: `postCameraIdle` posts `map.getBounds()` SW/NE. (c) Native (`:169`) + web (`:126`) bridges parse the four fields. (d) `app_config.dart:5`: optional `bounds` + `copyWith`. (e) `lala_backend.dart:69`: forward bounds when non-null. (f) `home_page.dart:882`/`:189`: thread `camera.bounds` → `_currentConfig` → `_refresh`; D5 level-changed OR-clause in `geo_helpers.dart:5`. | **NO** — pure client wiring; consumes Lane A's regenerated client + pinned param contract. |

**Cross-lane dependency (the one critical hand-off):** Lane B is **blocked-by Lane A** on the
**pinned API param contract** — the four param names `sw_lat`/`sw_lng`/`ne_lat`/`ne_lng` (wire) →
`swLat`/`swLng`/`neLat`/`neLng` (generated Dart, snake→camel) — and on the **regenerated**
`clients/flutter/lib/lala_api_client.dart`. Lane B cannot compile against the new client surface until
Lane A's regen lands. **They CAN be developed in parallel** against this pinned contract (Lane B codes
the wiring against the names fixed in §7/D3–D4); Lane B merges after Lane A's regen. No other shared
file exists between the lanes (Lane A owns `apps/api/**` + the generated client; Lane B owns
`apps/flutter_app/**` client files) — ownership is **disjoint**, so no merge conflict is possible
except on the regenerated `clients/flutter` artifact, which Lane A owns end-to-end.

Each lane: incremental commits (one coherent sub-step each); push every 1–3 commits; **never push
red**; keep RC1/RC2/RC3 + three-signals tests green with **zero** assertion changes. Each lane reports
its own head SHA, commands run, focused + full test results, CI run id, and what is NOT yet verified.
**Report = CLAIM** — cross-checked against actual diff/tests/CI. No self-declared runtime/device PASS;
the bounds query is a real-data-bound DB read, verified by code/tests, not by a runtime/device claim.
