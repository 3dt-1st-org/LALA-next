# 02. Typography and Color Tokens (20260728)

Normative source: `apps/flutter_app/lib/app/lala_visual_tokens.dart` (code SSOT)
and the type/color contract in
`docs/planning/lala-mobile-visual-contract/00-visual-ground-truth.md` §2 (prior
`.codex` contract, reused where it matches the code SSOT). No values invented.

## 1. Typography roles

Typeface: **Pretendard** for all roles except the **LalaWordmark** which uses the
existing `shared/widgets/lala_wordmark.dart` (no text imitation or image
replacement). Source: `code: app/lala_app.dart` (theme) +
`token: LalaVisualTokens.*Size/*LineHeight`. Weights from the prior contract §2,
confirmed against the token names.

| Role | Size / line height | Weight | Rules | Source |
| --- | --- | --- | --- | --- |
| Wordmark | 18 / 22 | 800 | Use `LalaWordmark` widget as-is | token: `wordmarkSize/LineHeight` |
| Onboarding title | 30 / 36 | 800 | At most two deliberate lines; prescribed copy | token: `onboardingTitle*` |
| Screen title | 28 / 34 | 800 | Search / Plan / Local Signals headings | token: `screenSize/LineHeight` |
| Section title | 20 / 26 | 800 | Selected-place and plan sections | token: `sectionTitle*` |
| Body | 15 / 22 | 500 | `muted` only when secondary | token: `bodySize/LineHeight` |
| Control label | 16 / 20 | 700 | Buttons and selectable rows | token: `controlLabel*` |
| Chip / metadata | 13 / 16 | 700 | Never truncate a selected-state label | token: `chipSize/LineHeight` |
| Bottom navigation | 12 / 16 | 700 | `검색 / 지도 / 일정` (Korean only) | token: `bottomNav*` |

Rules (non-negotiable): do **not** scale type from viewport width; do **not**
introduce gradients, robot/AI emoji, flag emoji, oversized black circular
controls, repeated score prose, or a decorative color strip.

> Target-derived (20260728); design-owner confirmation pending: the target
> images suggest a slightly larger place-title weight on the map detail panel
> than the current Section-title role. Until confirmed, the map detail title
> uses the Section-title role (20/26/800); a heavier map-detail role is a
> proposal only.

## 2. Color tokens (binding)

See `00-visual-ground-truth.md` §2.2 for the full table (`primaryBlue #2B6CB0`,
`ink #1A202C`, `muted #64748B`, `line #D9E2EC`, `surface #F7FAFC`, `card
#FFFFFF`). Binding rules:

- Primary CTA, selected chip state, and the primary map action use
  `primaryBlue`.
- Primary text uses `ink`; secondary/helper text uses `muted`.
- Dividers and unselected borders use `line`; page background is `surface`;
  raised selectable surfaces are `card`.
- The selected-place detail panel and plan overview are `card` over `surface`.

## 3. Category color binding (item 4 — chip ↔ card ↔ marker consistency)

The **same** category token must drive the category chip fill, the card accent,
and the map marker so the three never disagree on a screen.

| Category | Token | Fill | On-fill text | Chip | Card accent | Marker | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 관광지 Attraction | `attraction` | `#C53030` | `#FFFFFF` | ✔ | ✔ | ✔ | token: `LalaVisualColors.attraction` |
| 음식점 Restaurant | `restaurant` | `#F5C842` | `#1A202C` (`restaurantInk`) | ✔ | ✔ | ✔ | token: `restaurant`/`restaurantInk` |
| 문화·행사 Event | `event` | `#2B6CB0` | `#FFFFFF` | ✔ | ✔ | ✔ | token: `LalaVisualColors.event` |
| 문화시설 Culture | `culture` | `#0F766E` | `#FFFFFF` | ✔ | ✔ | ✔ | token: `LalaVisualColors.culture` |

Consistency rule: if a category lacks a code token (e.g. shopping/cafe hues
visible in the targets), it must collapse to the nearest token above (no invented
hex). `target-derived (20260728); design-owner confirmation pending` for any
additional category token.

## 4. Token-vs-target delta (traceability)

- Every typography size/line-height and core/category color in this contract is
  backed by `lala_visual_tokens.dart` (`code`/`token` source). None were
  invented.
- The prior `.codex` contract's type/color tables are byte-consistent with the
  code SSOT and were reused (see README delta for what changed at the
  source-of-truth level).
- Values that appear in the 20260728 target images but are absent from the token
  set are listed in the per-screen files as `target-derived; design-owner
  pending` and are excluded from this token file by construction.
