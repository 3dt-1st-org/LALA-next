# 00. Visual Ground Truth

## 1. Reference Precedence

Resolve conflicts in this order.

1. The selected six-screen contact sheet named in `README.md`.
2. This file's explicit measurements and copy.
3. Existing LALA behavior and data contracts in `main`.
4. Existing LALA tokens: Pretendard, `ColorScheme.fromSeed`, category colors,
   Kakao map bridge, and `LalaWordmark`.

Do not use OCR output, agent-authored prose, or stale device screenshots to
overrule the selected image. The contact sheet gives visual hierarchy;
this contract resolves the behavior that is not visible in a still image.

## 2. Canvas And Token Contract

All mobile measurements below use an app-owned `393 x 852 dp` viewport. Device
status bars, browser chrome, and home indicators are outside the visual target.
For `360..430 dp` widths, preserve the named spacing and use text wrapping only
where this document explicitly permits it. Do not scale type from viewport
width.

| Token | Value | Use |
| --- | --- | --- |
| `pageGutter` | 24 dp | Onboarding and search horizontal inset |
| `mapGutter` | 12 dp | Map chips, card rail, and bottom sheet inset |
| `contentGap` | 12 dp | Adjacent controls in a group |
| `sectionGap` | 24 dp | Between major blocks |
| `actionHeight` | 52 dp | Primary/secondary onboarding action |
| `iconTarget` | 44 dp minimum | All icon-only controls |
| `controlRadius` | 8 dp | Cards, list rows, chips, text inputs, and buttons |
| `sheetTopRadius` | 20 dp | Draggable place/detail sheets only |
| `primaryBlue` | `#2B6CB0` | Primary CTA, selected state, map action |
| `ink` | `#1A202C` | Primary text and dark icon |
| `muted` | `#64748B` | Secondary text |
| `line` | `#D9E2EC` | Dividers and unselected borders |
| `surface` | `#F7FAFC` | Page background |
| `card` | `#FFFFFF` | Raised selectable/control surface |
| `attraction` | `#C53030` | Attraction chip and pin |
| `restaurant` | `#F5C842` with dark text | Restaurant chip and pin |
| `event` | `#2B6CB0` | Event chip and pin |
| `culture` | `#0F766E` | Culture chip and pin |

| Type role | Size / line height | Weight | Rules |
| --- | --- | --- | --- |
| Wordmark | 18 / 22 | 800 | Use existing `LalaWordmark`; no text imitation or image replacement |
| Onboarding title | 30 / 36 | 800 | At most two lines; use the prescribed copy |
| Screen title | 28 / 34 | 800 | Search and plan headings |
| Section title | 20 / 26 | 800 | Selected-place and plan sections |
| Body | 15 / 22 | 500 | Muted only when secondary |
| Control label | 16 / 20 | 700 | Buttons and selectable rows |
| Chip / metadata | 13 / 16 | 700 | Never truncate a selected state label |
| Bottom navigation | 12 / 16 | 700 | `검색`, `지도`, `일정` only in Korean |

Do not introduce gradients, robot/AI emoji, flag emoji, oversized black
circular controls, repeated score prose, or a decorative colour strip.

## 3. Screen S1: Travel Type

**Purpose:** let the user make a travel-context choice before advancing. A tap
selects a row; it must not navigate automatically.

| Element | Placement and size | Exact Korean copy | State/behavior |
| --- | --- | --- | --- |
| Wordmark | `x=24, y=20`; intrinsic `LalaWordmark` | `LALA` | Static |
| Progress | `x=24, y=63`; `1 / 3` | `1 / 3` | Text, not a four-step segmented bar |
| Heading | `x=24, y=105`; max width 236 | `어떤 여행을\n계획 중인가요?` | Two deliberate lines at 30/36; not accidental wrapping |
| Body | 16 dp below heading; max width 258 | `여행 유형을 선택하면 더 알맞은\n추천을 받을 수 있어요.` | Two deliberate lines permitted |
| Domestic row | top 260, height 80, full gutter width | `국내 여행` | Icon, label, trailing chevron; selected state uses 1 px primary border and pale blue fill |
| Overseas row | 16 dp after domestic; height 80 | `해외 방문` | Same structure and selection behavior |
| Primary action | bottom inset 44; height 52 | `다음` | Disabled until one row is selected; advances to S2 |

Use an existing Material icon or supplied asset for the domestic/overseas row;
do not use emoji. Selection needs an accessible checked semantic state.

## 4. Screen S2: Language

**Purpose:** choose only the display language. The selected language must update
the app's copy source before S3 and must remain one-language-only afterward.

| Element | Placement and size | Korean mode copy | State/behavior |
| --- | --- | --- | --- |
| Wordmark / progress | Same as S1 | `LALA`, `2 / 3` | Static |
| Heading | top 112 | `언어 선택` | 30/36 |
| Body | 14 dp below heading | `앱에서 사용할 언어를 선택하세요.` | One line at 393 dp |
| Korean row | top 214; height 72 | `KO` badge, `한국어` | Selected by default for domestic travel; check icon at right |
| English row | 12 dp below; height 72 | `EN` badge, `English` | Unselected radio at right |
| Primary action | Same as S1 | `다음` | Advances to S3 |

`KO` and `EN` are text badges, not flags. The content is intentionally bilingual
only on this selection screen. All subsequent UI uses the selected language.

## 5. Screen S3: Location Consent

**Purpose:** obtain current location without blocking manual regional selection.

| Element | Placement and size | Korean mode copy | State/behavior |
| --- | --- | --- | --- |
| Wordmark / progress | Same as S1 | `LALA`, `3 / 3` | Static |
| Map preview | top 91; full width; height 150 | No overlaid fallback prose | Real Kakao map, fixed preview center before permission, no fake tile drawing |
| Map marker | Centered within preview | Current-location dot | Use a real marker only after a coordinate is available; otherwise no invented pin |
| Heading | top 282; max width 272 | `내 주변을\n추천해 드릴게요` | Two deliberate lines |
| Body | 14 dp below heading | `현재 위치를 사용하면 가까운 명소·맛집·행사 등\n맞춤 추천을 받을 수 있어요.\n\n위치 정보는 동의 없이 저장되지 않으며,\n언제든지 변경할 수 있어요.` | Keep clear line breaks; no small-print block |
| Primary action | top 470; height 52 | `현재 위치 사용` | Calls existing permission flow; disabled only during request |
| Secondary action | 12 dp below; height 48 | `지역 직접 선택` | Opens existing nationwide manual-region sheet on first render |
| Tertiary action | 12 dp below | `나중에 하기` | Completes onboarding with the defined default region |

The live-map requirement is strict. If the Kakao JS key, domain allowlist, or
SDK fails, the state is **blocked**, not visually accepted. The existing clear
fallback can remain for an actual outage, but it cannot replace S3 evidence.

## 6. Screen S4: Map

**Purpose:** provide a map-first recommendation view with actual pins before
clustering, a photo-forward rail, and a compact selected-place sheet.

### Hierarchy

1. Full-bleed real Kakao map.
2. Top category chips and one settings icon.
3. A compact recommendation rail; no score/reason text in rail cards.
4. Individual category-coloured pins. Clusters only when the existing policy
   is met: at least 80 loaded places and map level at least 10.
5. Compact lower-right map controls, then a selected-place bottom sheet.

| Element | Placement and size | Requirement |
| --- | --- | --- |
| Category row | top 12; left 12; 40 dp high | `전체`, `명소`, `맛집`, `행사`, `문화`; selected chip filled dark/primary, others white |
| Settings | top 12; right 12; 44 dp target | Icon only, tooltip and semantics label `설정` |
| Recommendation rail | top 66; left/right 12; card width 148, height 114 | Up to three visible photo cards; image is official place media, no repeated thumbnail/mocked photo |
| Individual pin | 40 dp, 48 dp selected | Category colour follows current `categoryColor`; selected marker may show a concise name pill |
| Cluster | 48 dp | Only counts a real cluster; never display a cluster badge for fewer than 80 loaded places |
| Control stack | right 12; above sheet; 44 dp targets, 8 dp gap | Voice, auto-docent, current location; ON/OFF must be visually distinct without a large centre control |
| Bottom sheet | bottom aligned; initial height 196; top radius 20 | Category, name, distance, concise docent preview, one `일정에 추가` action; `점수/근거` remains a secondary detail action |

Map cards use one 1 px category-coloured selection border. Do not draw a second
inner selection border or a multicolour strip. When a location is unavailable,
the user-facing fallback notice must not obscure both the rail and controls;
it includes `재시도` and `지역 선택` actions.

## 7. Screen S5: Search

**Purpose:** allow an immediate place/region search with an honest loading state
and recent-search recovery state.

| Element | Placement and size | Requirement |
| --- | --- | --- |
| Search field | top 18; left/right 24; height 48 | Leading search icon, placeholder `장소·지역 검색`, one trailing filter icon |
| Filter chips | 12 dp below; height 36 | Same categories as map; selected category has one clear filled state |
| Loading result | below chips | Three result-shaped skeleton rows while a request is outstanding only |
| Skeleton row | image 96 x 88 + text rails | Uses neutral blocks; no fake venue names/images; does not remain after data/error arrives |
| Recent searches | below results/empty state | `최근 검색`, removable chips, and a restrained `전체 보기` action |

Do not show the loading skeleton as evidence for a loaded search result, and do
not show a blank spinner-only page. Results use official place images when
available; absent official media leaves the image slot neutral rather than
reusing another place image.

## 8. Screen S6: Plan

**Purpose:** make itinerary generation legible without inventing server progress.

| Element | Placement and size | Requirement |
| --- | --- | --- |
| Wordmark and title | `x=24`; wordmark then `오늘 일정` | Current date below title, Korean-only in Korean mode |
| Calendar action | top-right 44 dp target | Opens the existing planner/calendar interaction |
| Generating card | below date; one card only | Heading `일정을 준비하고 있어요`; no timer-derived “completed” stage claims |
| Method row | inside generating card | `장소 선택`, `동선 정리`, `날씨 반영` may be shown as neutral inputs; none becomes complete until a truthful backend response exists |
| Timeline preview | below generating card | Skeleton timeline while request is pending; real time/order/content after a plan response |
| Bottom navigation | fixed bottom | `검색`, `지도`, `일정`; selected tab uses primary blue |

The old duplicate loading-card behavior is prohibited. The implementation must
capture both `P0: request pending` and `P1: plan loaded`; they are separate
acceptance states.
