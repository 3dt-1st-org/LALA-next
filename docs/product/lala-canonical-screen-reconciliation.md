# LALA Canonical Screen Reconciliation

This is the tracked reconciliation for the 36 logical screens in the functional
brief. A logical screen may be a route, a focused sheet, or a dedicated nested
page when that representation preserves the intended task and state.

The updated Stitch-to-runtime, flow-by-flow comparison is documented in
`docs/product/lala-stitch-vs-runtime-screen-comparison-v2-20260903.md`.

## Current completion snapshot

The canonical completion branch contains a reachable implementation for all 36
logical screens. This statement covers code and route/state bindings; it does
not claim that every runtime state has been exercised on a device.

| Scope | Implementation | Automated verification | Runtime verification |
| --- | --- | --- | --- |
| S-01--S-20 | Implemented on the integration line | Covered by the full Flutter/API/client suites | Prior evidence exists; final exact-head replay pending |
| S-21--S-25 | Implemented and merged through phase PRs | Covered by focused tests and the full suites | Prior phase evidence exists; final exact-head replay pending |
| S-30--S-32 | Implemented and reachable from detail, plan, and Local Signals | Covered by focused tests and the full suites | Prior phase evidence exists; final exact-head replay pending |
| S-40--S-44 | Implemented with public reads and Logto-gated writes/chat; private chat state is discarded on sign-out and late responses cannot reopen it | Focused auth-flow tests and the full suite pass | S-40 public read and the signed-out write gate verified on iPhone 17 Pro; authenticated operations remain gated |
| S-50--S-59 | Implemented, including persisted privacy and explicit sync resolution | Focused settings tests and the full suite pass | S-50 and S-58 verified on iPhone 17 Pro, including preference persistence across relaunch |

At the final application tree, Flutter analysis, all 832 Flutter tests, API
tests, Dart client tests, Ruff, formatting, pre-commit (including secret
detection), and diff checks passed. The same tree was installed on an iPhone 17
Pro simulator after removing the previous bundle. Visual and OCR inspection
confirmed onboarding, the configured map with real API places, location-denial
recovery, My Info, S-58, the public community empty state, and the Logto write
gate without fixture, mock, or demo data standing in for runtime truth. Other
authenticated, paid-provider, or production-mutating states retain their
separate gates.

| ID | Representation | Primary implementation | Entry | Runtime truth |
| --- | --- | --- | --- | --- |
| S-01 | route | `OnboardingSplashPage` | cold start | persisted restore, honest retry |
| S-02 | route | `OnboardingStartPage` | onboarding | persisted travel context |
| S-03 | route | `OnboardingLanguagePage` | onboarding | five supported UI languages |
| S-04 | route | `OnboardingLocationConsentPage` | onboarding | device location or recovery |
| S-05 | focused sheet | manual region selector | S-04 and map | nationwide manual region context |
| S-06 | route | `OnboardingAccountLinkPage` | onboarding | real Logto or guest continuation |
| S-10 | shell route | `MapRoutePage` / `LalaHomePage` | Map tab | configured map plus API places |
| S-11 | shell route | `SearchPage` | Search tab | API search and selected region |
| S-12 | route | `PlaceDetailPage` | map/search/signal | canonical place API and context |
| S-13 | focused sheet | restaurant communication | restaurant detail | stored dietary preferences |
| S-14 | focused sheet | `WeatherSheetContent` | map/detail | weather and air-quality API |
| S-15 | focused sheet | `TourSheetContent` | map/detail | selected real places and route |
| S-20 | shell route | `PlanPage` | Plan tab | four-slot server-compatible plan |
| S-21 | route | `InterventionComparisonPage` | plan intervention | actual before/after proposal |
| S-22 | route | `TripSettingsPage` | plan/profile | date-scoped server override |
| S-23 | route | `SavedPlacesPage` | My Info | device-first, account-synced IDs |
| S-24 | route | `PastTripsPage` | My Info | account plan history |
| S-25 | route | `VisitConfirmationPage` | plan slot | bounded visit feedback |
| S-30 | route | `DocentPlayerPage` | detail/plan player | RAG text; voice only when enabled |
| S-31 | shell route | `LocalSignalsPage` | Local Signals tab | governed public aggregates |
| S-32 | route | `LocalSignalDetailPage` | S-31 | source-safe detail and moderated action |
| S-40 | route | `CommunityFeedPage` | My Info | user posts, explicitly not verified signals |
| S-41 | route | `CommunityPostDetailPage` | S-40 | public read, authenticated reactions |
| S-42 | route | `CommunityCreatePostPage` | S-40 | authenticated explicit publish |
| S-43 | route | `ChatRoomListPage` | My Info/S-40 | authenticated room membership |
| S-44 | route | `ChatRoomPage` | S-43 | authenticated REST/WebSocket chat |
| S-50 | shell route | `ProfilePage` | My Info tab | account, sync, settings hub |
| S-51 | route | `AccountPage` | S-50 | Logto plus `/api/v1/me` state |
| S-52 | route | `TravelPreferencesPage` | S-50 | device-first/account-synced defaults |
| S-53 | nested page | `StylePreferencesPage` | S-52 | interests, pace, travel style |
| S-54 | nested page | `FoodPreferencesPage` | S-52 | dining preferences and hard constraints |
| S-55 | nested page | `MobilityPreferencesPage` | S-52 | mobility and accessibility constraints |
| S-56 | nested page | `BudgetPreferencesPage` | S-52 | budget, crowd, wait, operating rules |
| S-57 | nested page | `DocentPreferencesPage` | S-52 | language, depth, playback preferences |
| S-58 | route | `PrivacyLocationPage` | S-50 | persisted app choice plus OS controls |
| S-59 | route | `PreferenceSyncConflictPage` | sync indicator | explicit device/account resolution |

## Completion Rules

- `Implemented` means the entry path, intended states, and real binding exist.
- `Integration verified` additionally requires exact-head tests and CI.
- `Runtime verified` requires real iPhone 17 Pro or web evidence where the state
  can occur without fixtures, paid calls, or production mutation.
- Empty production community data is an honest empty state, not permission to
  insert demo content.
- Migrations, paid AI or speech, production writes, and deployment remain
  separately gated even when their screens are implemented.
