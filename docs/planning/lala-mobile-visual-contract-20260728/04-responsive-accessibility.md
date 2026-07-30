# 04. Responsive and Accessibility (20260728)

Covers item (8) for all four screens: breakpoints, no text overflow, 5 category
chips + settings reachable, and no overlap between map controls and the bottom
dock.

## 1. Breakpoints

App-owned base viewport: **393 × 852 dp** (`token: lala_visual_tokens.dart`
header). Width ranges (target-derived (20260728); design-owner confirmation
pending for exact pixel gates, but rules are normative):

| Range | Device class | Rules |
| --- | --- | --- |
| 360..390 dp | Small Android / iPhone SE | Preserve `pageGutter`/`mapGutter`; allow only permitted text wrap; 5 chips + settings must remain reachable |
| 391..409 dp | Standard phone (iPhone 14/15, Pixel) | Base canvas (393 dp) — the visual target |
| 410..430 dp | Large Android (Pro/Max) | Same tokens; no layout reflow required |
| ≥ 768 dp | iPad / desktop web | Cap content column; map stays full-width with anchored overlays |

Normative rules:
- **Do not scale type from viewport width.** Type roles are fixed in
  `02-typography-color-tokens.md`.
- **No text overflow**: titles wrap only where explicitly permitted
  (onboarding title, screen title); chip labels are never truncated in a
  selected state.
- **5 category chips + settings always reachable**: the chip row must not push
  settings off-screen on 360 dp; chips wrap or scroll horizontally rather than
  shrink below the chip height.
- **No map-control ↔ bottom-dock overlap**: floating map FABs sit above the
  bottom navigation with clearance; the selected-place sheet never underlaps the
  dock.

## 2. Accessibility

| Requirement | Rule | Source |
| --- | --- | --- |
| Touch target floor | ≥ 44 dp on every icon-only control and selectable row | token: `iconTarget` |
| Screen-reader labels | Every interactive control has a semantic label; category chips announce category + selected state; map markers announce place name + category; signal cards announce source + freshness | `target-derived (20260728); design-owner pending` (semantics exist in code via Flutter `Semantics`; exact labels to be audited in P6 implementation) |
| Color is not the only signal | Category identity carries a text label (chip/marker tooltip), not only the category fill color | `00` §3 invariants |
| Contrast | Restaurant chip uses `restaurantInk #1A202C` on `#F5C842` for contrast; other category on-fill text is `#FFFFFF` | token: `LalaVisualColors` |
| Language exclusivity | Exactly one of KO/EN rendered; screen reader follows the selected locale | `00` §3 invariants |
| Motion / animation | Marker selection and sheet drag are brief and non-distracting; no decorative motion | `target-derived; design-owner pending` |

> `target-derived (20260728); design-owner confirmation pending`: precise
> screen-reader label strings and the exact small/large breakpoint pixel gates
> are proposals until the P6 implementation slice writes them into the widget
> `Semantics` nodes and the token file.
