# 00. Visual Ground Truth (20260728 canonical target set)

> Canonical visual source: the **20260728 target image set** at
> `output/imagegen/lala-presentation-target-20260728/` (`01_target_map.png`,
> `02_target_local_signals.png`, `03_target_plan.png`,
> `04_target_weather_recovery.png`, `lala_target_contact_sheet.png`, plus its
> `README.md`). These images visualize the implementation contract; they are
> **not** final pixels and must not be filled with mock/invented data when real
> operational data is unavailable.

This contract is **docs-only**. It does not change UI code. It is a measured
design contract synthesized from three input sources, with every value traced.

## 1. Reference precedence (conflict resolution)

1. The 20260728 canonical target image for the screen (`01..04_target_*.png`).
2. This contract's explicit measurements and copy, each with a source tag.
3. Current `main` Flutter code (`apps/flutter_app/lib/**`) and its token SSOT
   `apps/flutter_app/lib/app/lala_visual_tokens.dart`.
4. Existing LALA data/behavior contracts (Local Signals public projection,
   planner slots, Kakao map bridge, `ColorScheme.fromSeed`, `LalaWordmark`).
5. The prior `.codex` contract at `docs/planning/lala-mobile-visual-contract/`
   (input only — its canonical was legacy code/older screenshots, **not** the
   20260728 set; see README delta).

OCR output, agent prose, and stale device screenshots may **not** overrule the
selected target image or the token SSOT. Values inferred from a target image
that are absent from tokens/code are recorded as
`target-derived (20260728); design-owner confirmation pending` and are never
asserted as final.

## 2. Canvas and token contract

Source: `apps/flutter_app/lib/app/lala_visual_tokens.dart` (code SSOT). The
prior `.codex` contract's token table matches this SSOT and is reused here with
attribution; no token values were invented.

App-owned viewport: **393 × 852 dp** (token file header; the task's 393 dp base
is the width). Device status bars, browser chrome, and home indicators are
outside the visual target. For 360..430 dp widths, preserve the named spacing
and use text wrapping only where explicitly permitted; do **not** scale type
from viewport width.

### 2.1 Spacing and size tokens (source: `lala_visual_tokens.dart`)

| Token | Value | Use | Source |
| --- | --- | --- | --- |
| `pageGutter` | 24 dp | Onboarding and search horizontal inset | code: `LalaVisualTokens.pageGutter` |
| `mapGutter` | 12 dp | Map chips, card rail, bottom-sheet inset | code: `LalaVisualTokens.mapGutter` |
| `contentGap` | 12 dp | Adjacent controls in a group | code: `LalaVisualTokens.contentGap` |
| `sectionGap` | 24 dp | Between major blocks | code: `LalaVisualTokens.sectionGap` |
| `actionHeight` | 52 dp | Primary/secondary action height | code: `LalaVisualTokens.actionHeight` |
| `iconTarget` | 44 dp minimum | All icon-only controls (touch target floor) | code: `LalaVisualTokens.iconTarget` |
| `controlRadius` | 8 dp | Cards, list rows, chips, inputs, buttons | code: `LalaVisualTokens.controlRadius` |
| `sheetTopRadius` | 20 dp | Draggable place/detail sheets only | code: `LalaVisualTokens.sheetTopRadius` |
| `locationPreviewHeight` | 150 dp | Onboarding S3 map preview height | code: `LalaVisualTokens.locationPreviewHeight` |
| `onboardingRowGap` | 16 dp | Onboarding row gap | code: `LalaVisualTokens.onboardingRowGap` |

### 2.2 Color tokens (source: `lala_visual_tokens.dart` / `LalaVisualColors`)

| Token | Value | Use | Source |
| --- | --- | --- | --- |
| `primaryBlue` | `#2B6CB0` | Primary CTA, selected state, map action | code: `LalaVisualColors.primaryBlue` |
| `ink` | `#1A202C` | Primary text and dark icon | code: `LalaVisualColors.ink` |
| `muted` | `#64748B` | Secondary text | code: `LalaVisualColors.muted` |
| `line` | `#D9E2EC` | Dividers and unselected borders | code: `LalaVisualColors.line` |
| `surface` | `#F7FAFC` | Page background | code: `LalaVisualColors.surface` |
| `card` | `#FFFFFF` | Raised selectable/control surface | code: `LalaVisualColors.card` |

> Context (non-normative): `design-qa.md` describes a legacy "obang" narrative
> (north black / east blue / center yellow / south red). The **normative** token
> values above are the code SSOT; the obang narrative is referenced only as
> heritage context, not as a token source.

### 2.3 Category color binding (source: `lala_visual_tokens.dart` / `LalaVisualColors`)

The chip, card accent, and map marker for a category must use the **same** token
so chip ↔ card ↔ marker stay consistent across every screen.

| Category | Token | Value | Text on fill | Source |
| --- | --- | --- | --- | --- |
| Attraction (관광지) | `attraction` | `#C53030` | `#FFFFFF` | code: `LalaVisualColors.attraction` |
| Restaurant (음식점) | `restaurant` | `#F5C842` | `#1A202C` (`restaurantInk`) | code: `LalaVisualColors.restaurant`/`restaurantInk` |
| Event (문화/행사) | `event` | `#2B6CB0` | `#FFFFFF` | code: `LalaVisualColors.event` |
| Culture (문화시설) | `culture` | `#0F766E` | `#FFFFFF` | code: `LalaVisualColors.culture` |

> Target-derived (20260728); design-owner confirmation pending: the four target
> images show additional category hues (e.g. a shopping/cafe tone) that are
> **not** present in the current code token set. Until the design owner adds
> tokens, those categories must collapse to the nearest existing token above and
> must not be invented as new hex values in code or assets.

## 3. Invariants (non-negotiable)

- Map = **Kakao Map** (not MapLibre). Conditional-import pattern
  (`kakao_map_view_{web,native,stub}.dart`) is preserved.
- **No robot emoji / AI decoration**; no flag emoji; no oversized black circular
  controls; no decorative color strip; no gradients.
- **KO/EN exclusive**: exactly one language displayed; never both at once.
- **No score / raw review / PII / moderation state / capability token** in the
  user-facing surface or RAG context (matches
  063_local_signals_contract + local_signal_public.dart).
- Markers first for sparse close results; use bounded geographic clusters at
  far zoom **or ≥ 24 places** (the places API caps results at 60). Honest "no
  image" state; never substitute a random photo.
- Recommendations score / internal ranking formula are **hidden by default**;
  rationale ("왜 지금 추천해요?") is opt-in.

## 4. Traceability policy

Every measurement, color, type role, and copy string in this contract carries a
`Source:` tag with one of:

- `code: <file>` — measured/defined in current `main` Flutter code.
- `token: <LalaVisualTokens|LalaVisualColors>.<name>` — the SSOT constant.
- `target: 0X_target_*.png` — visible in the 20260728 canonical image.
- `legacy: <path>` — prior `.codex` contract or `design-qa.md`, reused.

A value with no code/token source is tagged
`target-derived (20260728); design-owner confirmation pending` and is treated as
a proposal, not a final spec.
