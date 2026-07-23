# 04. Claude Code Implementation Brief

> This file is intentionally inactive until the design owner approves the
> visual-contract packet. Codex must copy this brief into Claude Code only after
> that approval and only for the approved implementation slice.

## Role

You are an implementation engineer. You are **not** the design owner, visual
QA authority, deployment operator, or PR merger.

## Authoritative Inputs

Read these files first, in order:

1. `AGENTS.md`
2. `docs/planning/lala-mobile-visual-contract/00-visual-ground-truth.md`
3. `docs/planning/lala-mobile-visual-contract/01-flow-and-runtime-contract.md`
4. `docs/planning/lala-mobile-visual-contract/02-implementation-slices.md`
5. `docs/planning/lala-mobile-visual-contract/03-visual-acceptance-matrix.md`

The selected visual reference is named in the packet README. It is supplied for
human/Codex review; do not use OCR to derive layout measurements or substitute
OCR-derived wording for this contract. If a visual detail is ambiguous, stop
and report the exact ambiguity. Do not invent a design decision.

## Scope Placeholder

Codex fills this section before delegation:

```text
Approved slice: <A | B | C | D | E>
Allowed files: <exact path list>
Required tests: <exact test list>
Reference states to capture: <matrix IDs>
```

Do not modify files outside the filled allowed-file list without reporting the
reason and waiting for approval.

## Hard Constraints

- Preserve the Kakao Maps conditional-import architecture and live data path.
- Preserve Logto SDK auth and Geolocator/browser-location boundaries.
- Do not use mock/demo data, a hand-drawn map, placeholder venue photos, emoji
  as UI iconography, robot imagery, or fallback map output as a visual success.
- Do not change `KAKAO_JAVASCRIPT_KEY`, `.env*`, Key Vault/Secrets Manager,
  Vercel settings, Cloudflare, API secrets, or deployment scripts.
- Do not perform a production deploy, merge any PR, or alter this visual
  contract/QA matrix.
- Do not claim a screenshot passes because OCR sees its text or because two
  screenshots differ in pixels.
- Do not manufacture planner progress with a timer. The present API has no
  progress events.

## Implementation Procedure

1. Read the approved slice and inspect only the listed current source files.
2. Make the smallest implementation consistent with the contract.
3. Add focused tests named in the scope placeholder. Preserve existing tests
   unless they conflict with the approved behavior.
4. Run `flutter analyze` and `flutter test` in `apps/flutter_app`.
5. Capture only the requested states if the required real runtime/key is
   available. Otherwise record the state as `blocked` with the exact missing
   dependency.
6. Run `git diff --check` and inspect staged paths for secrets and generated
   screenshots.
7. Commit with a conventional message and push the branch. Opening a PR is
   allowed only if Codex explicitly asks; merging is never allowed.

## Completion Report Format

Return only factual implementation evidence:

```md
## Implemented
- Slice:
- Files changed:

## Checks
- flutter analyze:
- flutter test:
- focused visual capture IDs:

## Blockers / Differences
- blocked or unresolved items only

## Git
- branch:
- commits:
- PR URL (only if requested):
```

Do not write `PASSED`, `production-ready`, `visually verified`, or equivalent.
Codex and the design owner perform the final reference comparison.
