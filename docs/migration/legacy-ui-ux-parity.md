# Legacy LALA UI/UX Parity

This document defines the LALA-next MVP screen standard after the user clarified
that old screenshots are not authoritative. The current baseline is the latest
legacy LALA code under `legacy-lala-reference` at commit `819ebb2`.

## Authoritative Legacy Sources

- Web map shell: `legacy-lala-reference/src/frontend/web/templates/map/index.html`
- Web map state machine: `legacy-lala-reference/src/frontend/web/static/js/map_logic.js`
- Web map styling: `legacy-lala-reference/src/frontend/web/static/css/layout.css`
- iOS map view: `legacy-lala-reference/src/frontend/ios/LALA/LALA/Views/MainMapView.swift`
- iOS map policies:
  - `legacy-lala-reference/src/frontend/ios/LALA/LALA/Core/MapParityPolicy.swift`
  - `legacy-lala-reference/src/frontend/ios/LALA/LALA/Core/MapMarkerClusteringPolicy.swift`
  - `legacy-lala-reference/src/frontend/ios/LALA/LALA/Core/MapGuidanceLogic.swift`

Screenshots in `capture-wireframe-materials-2026-06-15` are useful historical
evidence, but they are not the latest MVP acceptance source.

## MVP UX Contract

- Map remains the first screen and the primary interaction surface.
- Category filters are visible on the map: `전체`, `명소`, `맛집`, `행사`, `문화`.
- Recommended places appear as a horizontal card rail over the map.
- The selected/recommended place in the rail and the detail panel should stay
  aligned.
- Planner and weather controls are available as map-level pills.
- Voice/docent/current-location controls appear as floating map actions.
- Selecting a place leads into a detail/docent surface with a primary
  `정보 더 듣기` action.
- Bottom-sheet style surfaces carry detail, planner, weather, and docent content.
- The visual language should keep LALA's obang palette while becoming more
  polished for the LALA-next public MVP.

## Current LALA-next Status

- Implemented: Kakao Maps API background, map-first shell, LALA navigation,
  category filters, horizontal recommended place rail, planner/weather pills,
  auto-docent/current-location floating controls, selected place panel, local
  score meters, legacy-style docent subtitle panel, and public-data proof chips.
- Implemented: first recommended rail card is prioritized to match the selected
  place in the bottom panel.
- Implemented: primary docent CTA now uses the legacy-style `정보 더 듣기` copy.
- Implemented: category chips filter the map, recommendation rail, and selected
  detail context.
- Implemented: planner, weather, and detail use dedicated draggable Flutter
  sheets.
- Implemented: voice and auto-docent controls have persistent ON/OFF state and
  visible map feedback.
- Implemented: marker clustering and selected-marker treatment now follow the
  legacy web/iOS rule more closely: small circular category markers, selected
  marker name pill, and category-aware cluster counts.
- Implemented: place media can flow from official-source `image_url` values
  such as TourAPI `firstimage`, with local fallback only when a source has no
  usable image URL.
- Implemented: Kakao map drag events now flow back into Flutter as camera
  updates. The app updates the active center and refreshes places, weather,
  planner, and docent data from that map center, matching the legacy
  `dragend -> loadPlaces()` interaction more closely.

## Next Acceptance Items

- Verify deployed production rendering after each Vercel build, especially
  Kakao domain allowlisting, DB-backed source labels, and TourAPI image loading.
- Expand live data coverage beyond the current DB snapshot so more default
  Suwon/Gyeonggi recommendations carry official image URLs.
- Keep public-data scoring and proof chips available on demand as the LALA-next
  differentiator, without making score/reason text dominate the default map
  experience.
