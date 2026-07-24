# 03. Visual Acceptance Matrix

## 1. Blocking Evidence Rules

An implementation is not ready for design-owner review unless every required
row has the named evidence. A failed or unavailable check is recorded as
`blocked` or `failed`; it must not be renamed `passed` because tests compile.

- Capture each target at `393 x 852 dp` in a fresh browser profile and on one
  real mobile runtime. Keep browser/device chrome out of the app-owned visual
  comparison where it differs from the target.
- Capture reference and candidate in the same state and assemble a side-by-side
  comparison image before writing conclusions.
- Codex visually reviews the side-by-side image. OCR may check a prescribed
  string only; it cannot approve geometry, hierarchy, spacing, iconography,
  image quality, map fidelity, or responsive behavior.
- Browser map acceptance requires a successful Kakao SDK request and visible
  Kakao map tiles. A fallback message, abstract substitute, or map-looking
  background fails M1/M2.
- Do not commit raw device screenshots, key-bearing URLs, browser profiles, or
  any unredacted runtime artifact. Store temporary captures under ignored
  `output/` or `.playwright-mcp/`.

## 2. Capture Matrix

| ID | State | Required live condition | Pass condition | Failure examples |
| --- | --- | --- | --- | --- |
| O1 | S1 initial | Fresh onboarding state | 1/3, no selected travel row, disabled `다음`, page fits 360 dp | Auto-navigation on row tap; 2/4; oversized cards |
| O2 | S1 selected | Select domestic or overseas | One row selected; `다음` enabled; no route change until button tap | Chevron-only state; selection invisible; travel type lost |
| O3 | S2 Korean selected | State carried from S1 | 2/3, KO badge/check, no flag emoji, Korean-only copy outside rows | Flag glyphs; simultaneous Korean/English UI |
| O4 | S3 before permission | Valid production Kakao map key/domain | 3/3, real map preview, all three exit actions visible | `현재 지도를 표시할 수 없습니다`; missing manual selection |
| O5 | S3 permission denied | Deny browser/native permission | Manual selection remains actionable; no broken layout | Dead CTA or onboarding dead end |
| M1 | S4 low-volume map | API returns fewer than 80 visible places, normal map level | Actual tiles + individual category pins; no cluster bubble | Centre-only cluster, static fallback, no pins |
| M2 | S4 cluster threshold | Fixture or controlled data reaches 80+ places at level >=10 | Cluster count represents real member group; selected place stays individual | Cluster below threshold; a synthetic generic cluster |
| M3 | S4 selected place | Tap a real map pin | Rail and bottom sheet show the selected real place/media/docent preview; score hidden by default | Middle opaque docent card; borrowed image; default score block |
| M4 | S4 location recovery | No location permission | Compact notice with retry/manual selection does not cover rail/dock | Notice overlaps controls and rail |
| S1 | S5 pending | Delayed search response or test harness pending state | Exactly three neutral skeleton rows | Blank spinner page or skeleton after data returns |
| S2 | S5 loaded | Real API search response | Official image or neutral empty media; title/region/distance visible | Skeleton and results together; mock photos |
| S3 | S5 empty/error | Real empty/error response | Distinct honest state with retry where applicable | Silent blank surface |
| P0 | S6 generating | Daily-plan request pending | One neutral generating card + skeleton timeline; no fake completed stages | Duplicate cards; timer-driven stage completion |
| P1 | S6 loaded | Real daily-plan response | Loader is gone; actual slots/weather/order shown | Loading card remains; stale placeholder times |
| R1 | Responsive | `360`, `393`, `430`, `860` dp widths | Text fits, touch targets retain size, map overlays do not collide | Cropped chip labels; controls overlap dock |
| A1 | Accessibility | Widget/semantics inspection plus manual check | Labels for icon actions; focusable controls; readable yellow restaurant labels | Icon with no name; colour-only selected state |

## 3. Comparison Checklist

For each relevant row, the reviewer checks these visibly before reading test
logs.

1. **Composition:** element order, safe areas, and whitespace match the visual
   ground truth; no element uses accidental free space as its layout strategy.
2. **Typography:** title line breaks are intentional; Korean text is not clipped
   or double-localized; font hierarchy is recognizably the prescribed one.
3. **Controls:** sizes, radii, selected/unselected distinction, disabled state,
   and icon alignment match the contract.
4. **Images/map:** source is real official media/Kakao tile content. It is not a
   gradient, generated substitute, unrelated thumbnail, or unavailable state.
5. **State truth:** pending, loaded, denied, error, and selected states each
   communicate what the app actually knows.
6. **Interaction evidence:** capture or test proves a user can complete the
   listed action, not only see its static chrome.

## 4. Required QA Report Shape

The future implementation branch must add an ignored local report first, then
commit a redacted Markdown QA report only when the design owner asks for it.
Its headings must be:

```md
# LALA Mobile Visual QA - YYYY-MM-DD

## Reference
- Selected asset: <path or attached image id>
- Candidate commit: <sha>
- Viewport/runtime: <exact values>

## Evidence
| ID | Capture path | Functional proof | Visual verdict | Notes |
| --- | --- | --- | --- | --- |

## Open Differences
- P0/P1: blocking
- P2: must fix before review
- P3: optional follow-up

## Final Result
blocked | failed | ready for design-owner review
```

`passed` is not an allowed final result from an implementation agent. Only the
design owner may accept the finished visual result.

## 5. Verification Commands

Run from `apps/flutter_app` after the applicable slice is implemented:

```bash
flutter analyze
flutter test
```

Run a public web smoke using the guarded production path only when the task
explicitly includes deployment:

```bash
set -a
source .env
set +a
scripts/unix/deploy_flutter_web_vercel.sh --dry-run
```

Do not execute a production deployment merely to create a UI screenshot.

## 6. Human Review Gate

After Codex attaches the side-by-side evidence and classifies every row, the
design owner chooses one of these outcomes:

- `approve implementation`: allow PR review/merge.
- `approve with listed P3 follow-ups`: merge only after all P0-P2 rows pass.
- `revise contract`: update this packet first; implementation pauses.
- `reject implementation`: close/supersede the branch; do not salvage it by
  adding unrelated polish.
