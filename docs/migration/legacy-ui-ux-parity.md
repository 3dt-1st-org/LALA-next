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
- Implemented: recommendation rail cards now preserve the legacy card semantics:
  category badges are visible, event cards include ongoing/ended status, and
  tapping the already-selected card keeps the user in the map context instead
  of reopening detail.
- Implemented: selecting a place from the rail, marker, auto-docent, or tour
  context now explicitly focuses the map on that place, matching the legacy
  `selectPlace -> map.panTo(place)` behavior.
- Implemented: primary docent CTA now uses the legacy-style `정보 더 듣기` copy.
- Implemented: category chips filter the map, recommendation rail, and selected
  detail context.
- Implemented: category chips now also propagate the active category into the
  places request and trigger the shared refresh path, matching the legacy
  `click_category_filter -> loadPlaces()` interaction.
- Implemented: the food-tour map pill follows the legacy `tour-btn` visibility
  rule. It stays off the default/all map surface and appears after the user
  enters the restaurant category, keeping the first map screen focused.
- Implemented: planner, weather, and detail use dedicated draggable Flutter
  sheets.
- Implemented: voice and auto-docent controls have persistent ON/OFF state and
  visible map feedback.
- Implemented: auto-docent now follows the legacy
  `runAutoDocentIfNeeded -> selectPlace(openDetail: false)` behavior by
  selecting and panning to the nearest place while keeping the user in the map
  guidance context instead of forcing the detail sheet open.
- Implemented: turning voice OFF now clears prepared docent and tour audio
  state, matching the legacy voice toggle behavior that stops both current
  docent audio and tour-guide audio.
- Implemented: marker clustering and selected-marker treatment now follow the
  legacy web/iOS rule more closely: small circular category markers, selected
  marker name pill, and category-aware cluster counts.
- Implemented: cluster marker taps now preserve the legacy zoom-in/context
  behavior more closely by focusing the cluster center, selecting the first
  cluster member as the active map context, and moving cluster members to the
  front of the recommendation rail.
- Implemented: the non-web/Kakao-key-missing fallback map now renders the same
  marker shapes, selected marker pill, cluster counts, and marker tap callbacks
  used by the live map path, so simulator and widget-test UI parity can be
  verified without depending on the Kakao SDK.
- Implemented: place media can flow from official-source `image_url` values
  such as TourAPI `firstimage`, with local fallback only when a source has no
  usable image URL.
- Implemented: Kakao map drag events now flow back into Flutter as camera
  updates. The app updates the active center and refreshes places, weather,
  planner, and docent data from that map center, matching the legacy
  `dragend -> loadPlaces()` interaction more closely.
- Implemented: Kakao map zoom events now also flow back into Flutter camera
  state on both web and native WebView map bridges, preserving the legacy
  `zoom_changed -> syncMarkerState()` behavior for cluster and selected-marker
  presentation.
- Implemented: the current-location floating control now resets selected
  place, active sheet, evidence, audio state, and map focus before refreshing,
  preserving the legacy `loc-btn -> requestCurrentLocation(...reload...)`
  recovery behavior.
- Implemented: planner slot cards are now active route stops. Tapping a stop
  moves the user into the corresponding place detail/docent surface, preserving
  the legacy planner-card-to-map-context interaction.
- Implemented: map-level load errors now keep the legacy recovery affordance.
  The Flutter error toast exposes a localized retry action wired to the same
  refresh path as the legacy `retry-btn -> loadPlaces()` flow.
- Implemented: the location consent overlay now keeps the legacy recovery
  affordance. In addition to opening settings, it exposes a localized retry
  action that restores in-app location consent and refreshes the map context,
  matching the legacy `overlay-retry -> loc-btn` flow.
- Implemented: the weather pill now mirrors the legacy `click_weather` flow
  more closely by opening the weather sheet and triggering the shared refresh
  path, so weather, intervention, and planner context are refreshed when the
  user explicitly asks for weather.
- Implemented: score and evidence-like context now stay on demand in the detail
  flow. Card-spending, transaction, source, score, and data-basis signals are
  revealed through the score/evidence control instead of competing with the
  default docent and place context.

## Next Acceptance Items

- Verify deployed production rendering after each Vercel build, especially
  Kakao domain allowlisting, DB-backed source labels, and TourAPI image loading.
- Expand live data coverage beyond the current DB snapshot so more default
  Suwon/Gyeonggi recommendations carry official image URLs.
- Keep public-data scoring and proof chips available on demand as the LALA-next
  differentiator, without making score/reason text dominate the default map
  experience.
