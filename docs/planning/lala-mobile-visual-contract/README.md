# LALA Mobile Visual Implementation Contract

## Purpose

This is the design-owner review packet for the next LALA mobile UI pass. It is
deliberately a **contract**, not a loose redesign idea or a Claude Code task
brief. No Flutter implementation, deployment, or PR that changes UI may start
until the design owner approves this packet.

The previous image-to-code attempt is not a baseline. Its PR must not be used
as a visual reference or merged as a prerequisite for this work.

## Review Gate

The approval sequence is mandatory.

1. Codex updates this packet from the selected visual source and the current
   `main` code.
2. The design owner reviews the wording, measurements, copy, and scope in this
   directory.
3. Only after explicit approval, Codex prepares a focused implementation branch
   and gives Claude Code **only** `04-claude-implementation-brief.md`.
4. Claude Code may implement the listed files and run code checks. It may not
   reinterpret the visual target, edit this contract, deploy, or declare visual
   success.
5. Codex independently captures the reference states and the implementation at
   the same viewport, places them side by side, visually inspects them, and
   records the result in a new QA report. The design owner then decides whether
   the implementation PR is merged.

`flutter analyze`, `flutter test`, OCR text detection, and an image-to-image
pixel difference are useful secondary checks. None of them prove visual
fidelity on their own.

## Documents

| File | Role | Approval required before implementation |
| --- | --- | --- |
| `00-visual-ground-truth.md` | Reference precedence, design tokens, and exact per-screen geometry/copy | Yes |
| `01-flow-and-runtime-contract.md` | User flows, live-data rules, current-code ownership, and forbidden regressions | Yes |
| `02-implementation-slices.md` | Small, reviewable implementation order and file-level boundaries | Yes |
| `03-visual-acceptance-matrix.md` | Functional and visual acceptance evidence for each state | Yes |
| `04-claude-implementation-brief.md` | The exact delegated implementation instruction; do not run before approval | Yes |

## Visual Source Index

The selected target is the six-screen contact sheet created for this redesign:

- Local source: `/Users/geondongkim/.codex/generated_images/019eb5c9-cc07-7281-b358-f4056990313c/exec-f201cd1d-4186-42bc-8aea-2207d5e0923c.png`
- It contains, in reading order: travel type, language, location, map, search,
  and plan.
- The current-production implementation is a separate baseline, not a source
  of visual truth. Current screenshots must be recaptured immediately before
  implementation because production data, map tiles, and viewport chrome can
  change.

If that local source is unavailable in a future worktree, stop and ask for the
same image to be attached. Do not replace it with OCR text, an older capture,
or an adjacent generated image.

## Non-negotiable Product Invariants

- Map provider remains Kakao Maps through the existing conditional-import
  structure. Do not introduce MapLibre or a hand-drawn substitute.
- Normal recommendations, weather, place media, and docent content remain
  API/DB backed. A mock or static map/data source cannot be used to make a
  screenshot pass.
- Authentication remains behind the Logto SDK boundary. This redesign does not
  add a direct token path.
- Location continues to use the existing Geolocator plus browser-location
  hybrid boundary.
- The Kakao Maps JavaScript key is injected at build time through the guarded
  deploy script. A missing-key map fallback is a blocked test state, never a
  passed visual state.
- Korean mode shows Korean only and English mode shows English only, except for
  deliberately bilingual language-choice labels.

## Explicit Non-goals

- No Figma file or Figma MCP workflow.
- No new backend route, score formula, RAG behavior, or authentication policy.
- No deployment by an implementation agent.
- No automatic merge of an implementation PR.
