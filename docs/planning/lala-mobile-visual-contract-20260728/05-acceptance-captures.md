# 05. Acceptance Captures (specification only — 20260728)

Covers item (9): the **required acceptance capture list per state**, per screen.
This PR is docs-only — **no captures are produced here**, only the specification
of what must be captured (device × viewport × language × state) during the P6
implementation/verification slice.

Capture rules: every capture is real-device or real-browser at the listed
viewport; never a mock screenshot. Each captured state must show **honest**
data states (real empty/unavailable where data is absent). Captures are stored
under `output/verification/lala-p6a-20260728/<screen>/<state>-<viewport>-<lang>.png`.

## Screen 01 — Map
| State | Viewport | Language | Must show |
| --- | --- | --- | --- |
| Loaded (markers+rail) | 393 dp (iPhone 14) | KO | Kakao tiles, individual category markers, recommended rail, planner/weather pills |
| Loaded (cluster) | 393 dp | KO | Cluster at far zoom or ≥ 80 places |
| Selected place | 393 dp | EN | Marker↔card bidirectional selection; detail sheet (radius 20) |
| Empty (no nearby place) | 393 dp | KO | Honest empty — no invented POIs |
| Unavailable (map/geo fail) | 360 dp (SE) | KO | Map-unavailable surface, manual region fallback |
| Error (rec-connect degrade) | 393 dp | EN | Auto-retry banner |
| Large Android | 430 dp | KO | 5 chips + settings reachable; no dock overlap |
| Desktop web | 1280 dp | KO | Content column cap; full-width map |

## Screen 02 — Local Signals
| State | Viewport | Language | Must show |
| --- | --- | --- | --- |
| Loading | 393 dp | KO | Placeholder |
| Loaded | 393 dp | EN | `_SignalCard` list, source + freshness + translation provenance |
| Empty | 393 dp | KO | Honest empty (no signals) |
| Disabled | 393 dp | KO | Feature-off surface |
| Error | 360 dp | EN | Error + retry |
| Card with place link | 393 dp | KO | View-place/add-to-plan intent available |
| Card without place link | 393 dp | EN | No place action rendered |

## Screen 03 — Plan
| State | Viewport | Language | Must show |
| --- | --- | --- | --- |
| Loading | 393 dp | KO | Overview + slot placeholders |
| Data (4 slots) | 393 dp | KO | Morning/lunch/afternoon/dinner, travel time, open hours, meal context |
| Data (EN slots) | 393 dp | EN | Language-filtered slots |
| Intervention toast | 393 dp | KO | Weather/PM/closed-day alternate + reason |
| Empty (no plan) | 393 dp | EN | Honest empty "make a plan" CTA |
| Error | 360 dp | KO | Error + retry |

## Screen 04 — Weather recovery
| State | Viewport | Language | Must show |
| --- | --- | --- | --- |
| Restored | 393 dp | KO | Prior plan restored after relaunch + recovery banner |
| Swapped | 393 dp | EN | Prior (muted) → alternate (`primaryBlue`) + per-swap reason |
| Persisting toast | 393 dp | KO | `InterventionToast` until dismissed |
| Relaunch + weather change | 393 dp | KO | Original vs alternate shown together |

## Cross-screen accessibility captures
| Item | Viewport | Language | Must show |
| --- | --- | --- | --- |
| 44 dp touch targets | 360 dp | KO | All icon controls ≥ 44 dp |
| Screen-reader labels | 393 dp | EN | Semantics announce category + selected state + source/freshness |
| Color-not-only signal | 393 dp | KO | Category text label accompanies fill color |
