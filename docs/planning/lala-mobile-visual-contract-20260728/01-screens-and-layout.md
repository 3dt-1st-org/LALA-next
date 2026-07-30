# 01. Screens and Layout (20260728)

Four app screens are in scope: **Map**, **Local Signals**, **Plan**, and
**Weather recovery** (a plan sub-state). For each screen this file gives the
layout hierarchy, a block diagram, key dimensions, and the KO/EN copy. Dimensions
without a code/token source are tagged
`target-derived (20260728); design-owner confirmation pending`.

All horizontal insets use `mapGutter` (12 dp) on the map screen and `pageGutter`
(24 dp) on Local Signals/Plan; all card/chip/radius values use `controlRadius`
(8 dp); draggable sheets use `sheetTopRadius` (20 dp); icon-only controls use
`iconTarget` ≥ 44 dp. Source: `lala_visual_tokens.dart`.

---

## Screen 01 — Map (`01_target_map.png`)

**Purpose (target README):** combine official places, weather, image, individual
markers, and the user's *next local action* into one map decision. Map-first
home.

### Hierarchy + block diagram
```
┌──────────────────────────── 393 dp ────────────────────────────┐
│ Top bar: LalaWordmark(left)        settings icon(≥44dp,right)   │  ← over map
│ Category chips row: 전체/관광지/음식점/문화·행사/문화시설 (h≈40dp)   │
│ Recommended place rail (horizontal, h≈120dp)                    │
│ ── Kakao map fills the remaining canvas ──                      │
│   planner pill + weather pill (map overlay, top-right stack)    │
│   floating map controls (circular FABs, ≥44dp, right edge)      │
│   individual category markers (pin-first)                       │
│ Selected place detail panel (draggable sheet, radius 20dp)      │
│ Bottom navigation: 검색 / 지도 / 일정  (h≈64dp)                   │
└────────────────────────────────────────────────────────────────┘
```
- `Source: hierarchy` — `design-qa.md` (restored legacy map stack: top nav,
  category chips, recommended rail, planner/weather pills, floating controls,
  selected-place panel) + `code: home/home_page.dart` (map owner) + `target:
  01_target_map.png`.
- `Source: bottom nav copy` — `code: shared/widgets/lala_bottom_nav_bar.dart`
  (`검색 / 지도 / 일정`, Korean only per token contract).

### Key dimensions
| Element | Value | Source |
| --- | --- | --- |
| Horizontal inset (chips/rail/sheet/nav) | 12 dp | token: `mapGutter` |
| Category chip height | ~40 dp | target-derived (20260728); design-owner pending |
| Recommended rail card height | ~120 dp | target-derived (20260728); design-owner pending |
| Floating control diameter | ≥ 44 dp | token: `iconTarget` |
| Detail sheet top radius | 20 dp | token: `sheetTopRadius` |
| Card/chip radius | 8 dp | token: `controlRadius` |
| Bottom nav height | ~64 dp | target-derived (20260728); design-owner pending |

### KO/EN copy (exclusive)
| Element | KO | EN | Source |
| --- | --- | --- | --- |
| Wordmark | `LALA` | `LALA` | code: `shared/widgets/lala_wordmark.dart` |
| Docent CTA | `정보 더 듣기` | (EN variant in docent widget) | code: `design-qa.md` CTA change |
| Culture feature chip | `문화행사 데이터` | `Culture events` | code: `home/home_view_helpers.dart` |
| Rec-connect error | `추천 연결이 잠시 지연되고 있어요. 자동으로 다시 불러오는 중입니다.` | (EN variant in file) | code: `home/home_view_helpers.dart` |
| Rec-load error | `추천 장소를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.` | (EN variant in file) | code: `home/home_view_helpers.dart` |

> Target-derived (20260728); design-owner pending: the target image's on-map
> microcopy (e.g. weather/planner pill labels, "왜 지금 추천해요?" rationale
> trigger label) is visible but not yet isolated as a string in code; record as
> proposed copy only until the design owner confirms.

---

## Screen 02 — Local Signals (`02_target_local_signals.png`)

**Purpose (target README):** show public, source/freshness-confirmed information
and aggregate-type local signals. First-party traveller UGC + aggregate only.

### Hierarchy + block diagram
```
┌──────────────────────────── 393 dp ────────────────────────────┐
│ Header:  로컬 신호  /  Local Signals   (screen title 28/34)       │
│ Subtitle: 장소와 지역에 연결된 짧고 날짜가 명확한 관찰을 모아요.    │
│ Region selector:  전국 / Nationwide   (chip, controlRadius 8dp)   │
│ ── scroll list of signal cards (pageGutter 24dp inset) ──        │
│   SignalCard: category chip · place link · title/body            │
│               source · freshness date · translation provenance   │
│   …                                                              │
│   Load more: 더 보기 / Load more                                  │
│ Bottom navigation: 검색 / 지도 / 일정                              │
└────────────────────────────────────────────────────────────────┘
```
- `Source: hierarchy` — `code:
  local_signals/presentation/pages/local_signals_page.dart` (status state
  machine `_LocalSignalsStatus {loading, loaded, empty, disabled, error}`;
  `_SignalCard`; "더 보기" loader).
- `Source: public projection` — `code:
  local_signals/domain/local_signal_public.dart` (no author/moderation/score/
  token/coordinates/review fields — matches §3 invariants).

### Key dimensions
| Element | Value | Source |
| --- | --- | --- |
| Horizontal inset | 24 dp | token: `pageGutter` |
| Card radius | 8 dp | token: `controlRadius` |
| Category chip height | ~32 dp | target-derived (20260728); design-owner pending |
| Touch target (place link / load-more) | ≥ 44 dp | token: `iconTarget` |

### KO/EN copy (exclusive) — all `code: local_signals_page.dart`
| Element | KO | EN |
| --- | --- | --- |
| Title | `로컬 신호` | `Local Signals` |
| Subtitle | `장소와 지역에 연결된 짧고 날짜가 명확한 관찰을 모아요.` | `Short, dated observations connected to places and areas.` |
| Region (nationwide) | `전국` | `Nationwide` |
| Load more | `더 보기` | `Load more` |

> Honest empty / disabled / unavailable copy is defined per-state in
> `03-states-and-interaction.md`. Target-derived on-card labels (source name,
> freshness, translation badge) follow the public-projection field set in
> `local_signal_public.dart`; exact wording visible in
> `02_target_local_signals.png` is `target-derived; design-owner pending`.

---

## Screen 03 — Plan (`03_target_plan.png`)

**Purpose (target README):** a 4-slot day plan (morning/lunch/afternoon/dinner)
with travel time, weather, open hours, meals, and small-merchant linkage.

### Hierarchy + block diagram
```
┌──────────────────────────── 393 dp ────────────────────────────┐
│ Header: 일정 / Plan  (screen title 28/34)                        │
│ PlannerOverviewCard: date · summary · weather/PM context         │
│ ── slot timeline (pageGutter 24dp) ──                            │
│   PlanSlotTile:  오전 / 점심 / 오후 / 저녁  (4 slots)             │
│     place · travel time · open-hours · meal context              │
│ InterventionToast: weather/PM or closed-day change → alternate   │
│ Bottom navigation: 검색 / 지도 / 일정                              │
└────────────────────────────────────────────────────────────────┘
```
- `Source: hierarchy` — `code: plan/presentation/pages/plan_page.dart`
  (`LalaDailyPlan`; `LalaPlanSlot`; `hasVisiblePlanSlot(slot, language)`; status
  `{loading, data, error}`; `PlannerOverviewCard` + `PlanSlotTile` +
  `InterventionToast` reuse).
- `Source: 4 slots` — `target README P4` + `target: 03_target_plan.png`.

### Key dimensions
| Element | Value | Source |
| --- | --- | --- |
| Horizontal inset | 24 dp | token: `pageGutter` |
| Overview/slot card radius | 8 dp | token: `controlRadius` |
| Slot row min height | ≥ 44 dp | token: `iconTarget` |
| Toast radius | 8 dp | token: `controlRadius` |

### KO/EN copy (exclusive)
| Element | KO | EN | Source |
| --- | --- | --- | --- |
| Screen title | `일정` | `Plan` | code: routing/bottom-nav (`일정`) |
| Slot names (4) | `오전 / 점심 / 오후 / 저녁` | morning/lunch/afternoon/dinner equivalent | target-derived (20260728); design-owner pending (code filters slots by language but exact 4 labels are target-confirmed) |

> Target-derived (20260728); design-owner pending: slot labels, travel-time
> formatting, and the small-merchant/franchise distinction copy visible in
> `03_target_plan.png`. The plan generator (`createDailyPlan`) and slot model
> exist in code; the visible labels are confirmed against the target, not yet
> isolated as constants.

---

## Screen 04 — Weather recovery (`04_target_weather_recovery.png`)

**Purpose (target README):** restore state after relaunch and transparently
swap the plan when weather changes — show the prior plan **and** the alternate
with the change reason.

### Hierarchy + block diagram
```
┌──────────────────────────── 393 dp ────────────────────────────┐
│ (Plan header + PlannerOverviewCard, same as Screen 03)           │
│ Recovery banner: restored plan + what changed (rain / PM / hours)│
│ ── slot timeline ──                                              │
│   prior slot (muted/strike) → alternate slot (highlighted)       │
│   change-reason line per swap                                    │
│ InterventionToast (persistent until dismissed)                   │
│ Bottom navigation: 검색 / 지도 / 일정                              │
└────────────────────────────────────────────────────────────────┘
```
- `Source: hierarchy` — reuses Screen 03 plan components + `InterventionToast`
  (`code: plan_page.dart`); recovery = plan sub-state. `target:
  04_target_weather_recovery.png`.
- `Source: behavior` — `target README P4` ("비, 대기질, 휴무 변화가 생기면 기존
  장소와 대체 장소, 변경 이유를 함께 보여 준다").

### Key dimensions
Same as Screen 03 (shared plan chrome). Additional:
| Element | Value | Source |
| --- | --- | --- |
| Recovery banner radius | 8 dp | token: `controlRadius` |
| Prior-slot mute treatment | `muted` `#64748B` | token: `LalaVisualColors.muted` |
| Alternate-slot accent | `primaryBlue` `#2B6CB0` | token: `LalaVisualColors.primaryBlue` |

### KO/EN copy (exclusive)
| Element | KO | EN | Source |
| --- | --- | --- | --- |
| Recovery banner | (visible in target) | — | target-derived (20260728); design-owner pending |
| Change reason | (visible in target) | — | target-derived (20260728); design-owner pending |

> No recovery/alternate copy is currently isolated as a code constant; all such
> strings are `target-derived (20260728); design-owner confirmation pending` and
> must not be asserted as final until the design owner writes them into the code
> copy layer (`shared/l10n/lala_copy.dart` or the plan widgets).

---

## Per-screen 9-item coverage map

| Item | Map | Local Signals | Plan | Weather recovery |
| --- | --- | --- | --- | --- |
| (1) hierarchy + block diagram | 01 §Map | 01 §LS | 01 §Plan | 01 §WR |
| (2) exact dimensions | 01 §Map | 01 §LS | 01 §Plan | 01 §WR |
| (3) typography | 02 §type | 02 §type | 02 §type | 02 §type |
| (4) category color | 02 §cat | 02 §cat | 02 §cat | 02 §cat |
| (5) KO/EN exclusive copy | 01 §Map | 01 §LS | 01 §Plan | 01 §WR |
| (6) states (honest empty) | 03 §Map | 03 §LS | 03 §Plan | 03 §WR |
| (7) interaction | 03 §Map | 03 §LS | 03 §Plan | 03 §WR |
| (8) responsive + a11y | 04 | 04 | 04 | 04 |
| (9) acceptance captures | 05 | 05 | 05 | 05 |
