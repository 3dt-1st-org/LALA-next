# LALA Mobile Visual Contract — 20260728 canonical target set (P6A)

> **Measured design contract — docs only.** This PR does **not** modify any UI
> code, Flutter widget, router, asset, or token file. It only adds this new
> `docs/planning/lala-mobile-visual-contract-20260728/` directory.

## Headline metadata
- **Base SHA**: `f28a3353b7236a1f4c5ecceecc35f9e166529209` (`origin/main`)
- **Head SHA**: _(recorded in the P6A rebase/handoff commit; see git log of this branch)_
- **Branch**: `geondongkim/lala-p6a-visual-contract-20260728`
- **Canonical visual source**: `output/imagegen/lala-presentation-target-20260728/`
  (`01_target_map.png`, `02_target_local_signals.png`, `03_target_plan.png`,
  `04_target_weather_recovery.png`, `lala_target_contact_sheet.png`, `README.md`).
- **Role**: P6A = measured design contract (this PR). UI code is unchanged.
- **Order**: independent review → merge → then the **P6 implementation slice**
  writes widgets/tokens to match this contract.

## What this contract is
A measured, traceable UI design contract synthesized from three inputs, with the
20260728 target image set as the visual canonical:

1. `00-visual-ground-truth.md` — reference precedence, canvas/token contract,
   category-color binding, invariants, traceability policy.
2. `01-screens-and-layout.md` — Map / Local Signals / Plan / Weather recovery:
   hierarchy, block diagrams, dimensions, KO/EN copy, 9-item coverage map.
3. `02-typography-color-tokens.md` — type roles + color/category tokens (all
   sourced from `lala_visual_tokens.dart`).
4. `03-states-and-interaction.md` — per-state design (honest empty) + interaction.
5. `04-responsive-accessibility.md` — breakpoints, 44 dp, screen-reader, no
   overflow / no map-dock overlap.
6. `05-acceptance-captures.md` — required acceptance capture spec (not produced
   here).

## Traceability (no invented values)
Every measurement / color / type role / copy string carries a `Source:` tag:
`code:` (current `main` Flutter code), `token:` (`lala_visual_tokens.dart` SSOT),
`target:` (20260728 canonical image), or `legacy:` (prior `.codex` contract /
`design-qa.md`, reused). Values inferred from a target image but absent from
tokens/code are tagged
`target-derived (20260728); design-owner confirmation pending` and are **never**
asserted as final.

## Delta vs the prior `.codex` contract
`docs/planning/lala-mobile-visual-contract/` remains an input reference (not
modified here). Differences at the source-of-truth level:

| Aspect | Prior `.codex` contract | This 20260728 contract |
| --- | --- | --- |
| Canonical visual | Legacy LALA code + older screenshots (`design-qa.md` named legacy web/iOS code) | The 20260728 target image set (`01..04_target_*.png`) |
| Screens covered | S1–S6 (onboarding-focused) + flow/runtime | 4 app screens: Map, Local Signals, Plan, Weather recovery |
| Token table | Same values as `lala_visual_tokens.dart` | Reused unchanged (attributed to the code SSOT) |
| Category color | attraction/restaurant/event/culture tokens | Same tokens + chip↔card↔marker consistency rule |
| Copy | Onboarding copy | Per-screen KO/EN copy; on-card labels marked target-derived where not yet in code |

Source-of-truth change reason: the 20260728 target set is the design owner's
current visual brief (target README), superseding the legacy-code canonical.

## Non-normative source files read (informational)
`AGENTS.example.md` (AGENTS.md is absent/gitignored), `design-qa.md`,
`docs/planning/cleanroom-dashboard-map-reimplementation-plan.md`, and the prior
`docs/planning/lala-mobile-visual-contract/00..04`. The referenced
`docs/STYLEGUIDE.md`, `src/renderer/src/assets/main.css`, and
`docs/planning/lala-final-completion-execution-playbook.md` are **not present**
in this repository; the code SSOT (`lala_visual_tokens.dart`) and the target set
are the authoritative substitutes.

## Safety
No live API/crawl/DB apply/deploy/AI-TTS/secret lookup was performed. No UI code
was written from OCR improvisation — this contract is a synthesis only. No
invented measurements, colors, or copy are asserted as final.
