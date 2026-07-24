# 02. Implementation Slices

## Entry Condition

Do not begin any slice until the design owner explicitly approves documents
`00` through `03`. The slices are intentionally narrow so a regression can be
identified without mixing onboarding, map behavior, and loading-state changes.

## Slice A: Shared Visual Foundation And Navigation

**Goal:** introduce only the tokens/components needed by later slices, without
changing map/data behavior.

| Change | Allowed files | Acceptance |
| --- | --- | --- |
| Centralize measured spacing/radius/type constants | new small token file under `lib/app/` or existing theme location | Existing `ColorScheme.fromSeed` and Pretendard remain; no broad theme rewrite |
| Use existing wordmark consistently | `shared/widgets/lala_wordmark.dart`, onboarding screens as required | No improvised text/image logo |
| Normalize main nav copy | `shared/widgets/lala_bottom_nav_bar.dart`, focused tests | Korean labels exactly `검색`, `지도`, `일정`; no behavior change |
| Preserve minimum target sizes/semantics | touched shared controls only | Widget tests can find labels and selected state |

**Out of scope:** map overlays, onboarding routing, search fetch state, plan
loader, API client, deployment.

## Slice B: Three-Content-Step Onboarding

**Goal:** match S1-S3 while preserving the current onboarding-state boundary.

| Change | Allowed files | Acceptance |
| --- | --- | --- |
| Remove splash from visible progress accounting | `splash_page.dart`, `onboarding_scaffold.dart`, `onboarding_progress.dart` | Content screens expose 1/3, 2/3, 3/3 only |
| Add explicit S1 selection then next | `start_page.dart`, `onboarding_state.dart`, focused tests | Tapping a row does not navigate; `다음` only enables after selection |
| Render KO/EN S2 rows | `language_page.dart`, focused tests | No flag emoji; selected language updates copy source |
| Add read-only live preview and always-visible manual selection | `location_consent_page.dart`, a narrowly scoped preview wrapper, conditional map files only if signature extension is unavoidable | Real map passes live SDK check; fallback state is documented but not accepted visual evidence |

**Out of scope:** changing permission provider, storing new location data, map
provider replacement, global navigation rewrite.

## Slice C: Map Composition And Marker Truth

**Goal:** rearrange only the presentation of existing live map data.

| Change | Allowed files | Acceptance |
| --- | --- | --- |
| Enforce top/rail/control/dock safe regions | `app/dashboard.dart`, map widget files listed below | At 393x852 no overlay collision; desktop retains centered layout |
| Compact lower-right controls | `floating_map_controls.dart`, `map_fab.dart`, `auto_docent_fab.dart` | 44 dp targets; no central dark `꿈` control; states readable |
| Simplify rail selection | `map_rail_place_card.dart`, associated place widgets | One category-coloured selection border; score/reason not visible by default |
| Preserve pin-first clustering | `map_helpers.dart`, `kakao_map_view_web.dart`, `kakao_map_view_native.dart`, focused map tests | Fewer than 80 places and normal level show individual pins; a real cluster appears only under policy |
| Keep docent in selected sheet | `map_bottom_dock.dart`, `dock_docent_preview.dart` | Concise script preview appears in the bottom sheet, not an opaque middle card |

**Out of scope:** marker data model, current-location API, point clustering policy
change, unknown map SDK replacement, score algorithm.

## Slice D: Search Truthful States

**Goal:** make pending, loaded, empty, and error states visibly distinct.

| Change | Allowed files | Acceptance |
| --- | --- | --- |
| Create a reusable neutral skeleton primitive | new `shared/widgets/` component and test | No fake venue text/image; reduced-motion-safe animation or static alternative |
| Use three result-shaped skeleton rows | `search_page.dart`, search widget tests | Only while request pending; replaced completely on data/error |
| Align chip/input visual rules | `search_page.dart`, existing filter widgets if required | Search field + one filter icon; category state matches map |

**Out of scope:** search API behavior, ranking, review/mention pipelines.

## Slice E: Plan Pending And Loaded States

**Goal:** remove duplicated loader and make plan generation honest.

| Change | Allowed files | Acceptance |
| --- | --- | --- |
| Render exactly one pending card | `plan_page.dart`, `planner_loading_card.dart`, tests | One loader in P0; no duplicate widgets |
| Use neutral method row + timeline skeleton | same files | No timer/percentage/server-stage claim |
| Normalize title/nav copy | plan page, shared navigation | `오늘 일정`, `일정` in Korean mode |

**Out of scope:** daily-plan API changes, progress streaming, planner algorithm.

## Required Test Additions

| Area | Test intent |
| --- | --- |
| Onboarding start | Selection does not route; next routes only after a choice |
| Language | KO/EN badges present; flag emoji absent; one-language app copy after selection |
| Location preview | Wrapper uses injected Kakao map boundary; no key produces explicit blocked/fallback state in unit test |
| Map clustering | 79 places at level 10 produce individual pins; 80+ at level 10 may cluster; selected marker remains individual |
| Map layout | Small-mobile layout retains non-overlapping rail, control stack, and dock bounds |
| Search | Pending shows three skeleton rows; loaded/empty/error removes them |
| Plan | Pending has one card only; no timer-generated completion text; loaded removes loader |
| Semantics | Icon controls have labels and selection state is discoverable |

## Commit And Review Discipline

1. One slice per branch or a clearly separable commit series. Do not combine
   map SDK changes with unrelated onboarding/search polish.
2. Before every push: `flutter analyze`, focused tests, and `flutter test` for
   the affected package.
3. Before PR: capture the required visual states locally. Captures stay ignored
   under `output/` or `.playwright-mcp/`; no device screenshot or key is added
   to source control unless the design owner explicitly requests a redacted
   documentation asset.
4. Codex, not Claude Code, reviews the before/reference/after comparison and
   records blocked items honestly.
5. The design owner reviews the PR after visual evidence is attached. No direct
   merge to `main`.
