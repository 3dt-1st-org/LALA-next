# 01. Flow And Runtime Contract

## 1. Current Main Baseline

This contract applies to `origin/main` at `0a5e42a`. The current app differs
from the target in ways that must be addressed intentionally, not concealed in
a visual restyle.

| Current ownership | Current behavior | Contract decision |
| --- | --- | --- |
| `features/onboarding/presentation/pages/splash_page.dart` | Counts as step 1 of 4 | Keep only as a short non-interactive boot transition. It is not one of the visible 1/3..3/3 content steps. |
| `start_page.dart` | Tap immediately selects and navigates | Store a pending travel type, show selected state, and advance only on `다음`. |
| `language_page.dart` | Uses flag emoji and 3/4 | Use KO/EN text badges and 2/3. |
| `location_consent_page.dart` | Uses a decorative icon rather than live map preview | Add a safe, read-only wrapper over the existing Kakao conditional-import bridge. |
| `app/dashboard.dart` | Large stack with overlapping rail, location toast, utilities, controls, and dock | Preserve functional layers but enforce the S4 hierarchy and collision rules below. |
| `features/map/map_helpers.dart` | Clusters only at `places.length >= 80 && mapLevel >= 10` | Preserve this policy. Add/retain a focused test so a low-volume map renders pins. |
| `kakao_map_view_{web,native,stub}.dart` | Conditional-import Kakao map system | Preserve. Any preview must use this boundary, not a separate map implementation. |
| `search_page.dart` | May render a spinner/empty state | Render skeleton only for an in-flight search request, then replace it with real results, empty state, or error. |
| `plan_page.dart` / `planner_loading_card.dart` | Loading behavior previously duplicated and had no truthful stages | One pending card only; never simulate server progress from elapsed time. |
| `shared/widgets/lala_bottom_nav_bar.dart` | Main navigation | Korean labels become `검색`, `지도`, `일정`; English remains English-only. |

## 2. Flow Contract

### F1. First Launch

1. The splash performs boot/routing work only. It does not expose a visible
   fourth content step.
2. S1 starts with no travel type selected. Tapping either row updates visual and
   semantic selected state only.
3. `다음` becomes enabled only after selection. It writes the travel type and
   preferred default language to `OnboardingState`, then routes to S2.
4. S2 starts with the travel-type default selected. Choosing a language updates
   `OnboardingState` immediately; `다음` routes to S3.
5. S3 exposes `현재 위치 사용`, `지역 직접 선택`, and `나중에 하기` at first
   render. Manual selection is never hidden behind a permission failure.
6. Completing any S3 exit path marks onboarding complete and opens the map tab.

### F2. Location And Map

1. Permission success updates the current coordinate via the existing
   Geolocator/browser-location provider and refreshes places, weather, planner,
   and docent data through the existing home state.
2. Permission denial keeps the map usable at the selected/default region and
   shows a compact recovery notice with `재시도` and `지역 선택`.
3. Kakao map SDK loading occurs with the production build key. A test must
   confirm that the live SDK request succeeds in the public browser build.
4. The preview and full map share the same conditional-import architecture.
   Preview mode disables gestures and callbacks but does not bypass key checks
   or draw substitute tiles.
5. A marker tap selects that place and updates the bottom sheet. A cluster tap
   focuses/reorders its real members using the existing callback path.

### F3. Search

1. Opening search has an immediately usable field and category filters.
2. Submitting/changing a query sets only the results region to pending.
3. Pending shows three skeleton rows; loaded replaces all skeleton rows with
   API results; no-result shows the honest zero-result state; error shows retry.
4. A result tap selects that real place and routes/reveals it through the
   existing map/place flow.

### F4. Plan

1. A plan-generation request is a single backend request in the current API.
2. While pending, show exactly one loading card and a neutral skeleton timeline.
3. Do not advance text through fake percentage/time stages. If progress events
   are later added to the API, this contract must be revised before showing them.
4. A successful response replaces the loader with actual plan slots, weather
   facts, and routing data. Failure shows retry with no stale “completed” UI.

## 3. Map Collision And Responsive Rules

| Breakpoint | Layout rule |
| --- | --- |
| `360..430 dp` | Mobile S4: chips, rail, lower-right vertical controls, then bottom dock. No two overlay regions may overlap. |
| `431..859 dp` | Preserve mobile hierarchy; constrain rail to a readable maximum width and maintain 12 dp map gutter. |
| `>=860 dp` | Use the existing centered map content width. Do not scale mobile font sizes; rail/dock may widen but preserve the same hierarchy. |

The map layout must calculate these safe rectangles after safe-area insets:

- top chrome: `0..56 dp`
- recommendation rail: `66..190 dp`
- utility/recovery notice: below rail or above control stack, never through it
- controls: right edge, at least 12 dp from sheet and 8 dp between targets
- dock: bottom aligned; controls remain at least 16 dp above its drag handle

When a recovery notice is shown, it has priority over the utility row, not over
the rail or selected-place sheet. Hide/move the lower-priority utility row
rather than allowing visual overlap.

## 4. Data And Language Contract

- Place title, category, region, distance, docent snippet, weather, and plan
  slots must be sourced from the existing API/DB-backed models.
- Place imagery uses an official `image_url` only. A missing image may produce a
  neutral empty image area; it must never borrow another place's image.
- In Korean mode, selected-place/detail/map labels are Korean only. In English
  mode, use existing English fields/labels only. Do not render `Korean /
  English` double labels outside the S2 choice control.
- Scores and their reasons are not a rail-card or always-on sheet element.
  Keep them behind the existing `점수/근거` / evidence action requested by the
  user.
- Weather uses actual API data. `준비 중` is only a transient request state; an
  unavailable response becomes a concise unavailable state with retry.

## 5. Accessibility Contract

- Every icon-only action has a tooltip and a semantic label: settings, voice,
  auto docent, return to location, filter, calendar, and bookmark.
- All primary and icon-only targets are at least `44 x 44 dp`; full-row
  onboarding choices and CTAs are at least 52 dp high.
- Selected state is communicated through text/semantics plus border/fill, not
  colour alone.
- Restaurant yellow surfaces use dark text and meet readable contrast.
- Text must not clip at 360 dp, 200% text scale, or Korean/English switching.
- Loading, error, permission, and completion changes announce a concise semantic
  status. Screenshot review cannot prove screen-reader behavior, so focused
  widget tests and manual assistive-technology checks remain required.

## 6. Forbidden Shortcuts

- No mock locations, fake map drawings, or blank photo placeholders passed off
  as live map/photo content.
- No map fallback accepted as a successful visual screenshot.
- No OCR-driven geometry or copy decisions.
- No image-only or hardcoded screenshot recreation in Flutter.
- No timer-driven progress claims for plan generation.
- No changes to `KAKAO_JAVASCRIPT_KEY` values, build secrets, Logto credentials,
  backend secrets, or deployment configuration in the UI implementation PR.
- No merge, deployment, or design-QA pass declaration by Claude Code.
