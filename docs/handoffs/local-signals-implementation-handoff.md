# Local Signals implementation handoff

This ledger is the continuation point for the staged Local Signals and LALA
completion work. It intentionally records contract state and decisions, not
secret values or runtime credentials.

Status vocabulary follows the final completion playbook: this P0 is
`DRAFT_PR` and `IMPLEMENTED_NOT_RUNTIME_VERIFIED`, not `CURRENT`.

## Confirmed

- LS-1 through LS-4 are represented on `origin/main` through PR #75's squash
  merge at `906543d`; Local Signals remains first-party traveller UGC only.
- PR #77 is a separate Draft Local Signals follow-up and is not a dependency
  to modify in this P0 branch. Its current review/merge state must be checked
  independently before any future Local Signals work.
- This P0 branch is based on `origin/main` at `906543d` and implements the
  AWS Secrets Manager runtime contract, profile boundary, safe status metadata,
  API/worker entrypoint profiles, and offline contract tests.
- P0 commits are `592d46c` (`feat(security): add fail-closed runtime secret
  contract`) and `2b7caf9` (`chore(ops): enforce AWS runtime profiles`) on
  branch `geondongkim/lala-secrets-runtime-p0`.
- The exact requested renamed strategy documents were not present on this
  clean base. The available cleanroom execution, review, RAG/docent, planner,
  dashboard/map, restaurant-economy, Local Signals adaptation, and AWS
  operations analog documents were used as the governing equivalents.

## Assumptions

- `local` is the compatibility default when a process does not set a profile,
  but dotenv loading still requires an explicit `LALA_RUNTIME_PROFILE=local`.
- API authentication may be satisfied by configured guest/public-contest mode;
  otherwise the operational contract requires static or OIDC identity inputs.
- The next independent branch is created from the merged latest `origin/main`
  only after this P0 Draft PR is reviewed/merged.

## External decisions / gates

- AWS IAM role policy, logical secret inventory, region/prefix, rotation and
  retention/deletion policy, and production enablement are still required.
- PR #76's documentation-only AWS team handoff and local sync/build helpers
  must be sequenced by the repository owner; this P0 runtime code does not
  invoke its local sync helper.
- P1 official nationwide catalog coverage and aggregate quality, P2 governed
  review/mention preprocessing, P3 aggregate-only RAG/docent, P4 real planner
  and weather composition, and P5 map/exploration/Local Signals quality remain
  planned. No external data collection or live AI is enabled here.

## Phase status and next command

- P0 AWS runtime injection: `DRAFT_PR` / `IMPLEMENTED_NOT_RUNTIME_VERIFIED` in
  this Draft PR; focused runtime contract tests and the full API suite pass
  locally. Validation also includes
  `bash -n scripts/unix/*.sh`, ruff/format, pre-commit with detect-secrets,
  and `git diff --check`. Pending review, CI, and external IAM/secret-inventory
  decisions.
- P1 official data width/quality: planned, blocked on P0 contract and source
  inventory approval.
- P2 review/mention preprocessing: planned, blocked on source governance,
  license/provenance, and explicit live-AI approval.
- P3 RAG/docent: planned, blocked on P2 accepted aggregate inputs and eval
  ownership.
- P4 day planner/weather: planned, blocked on canonical nationwide places,
  operating hours, weather/PM data, and planner ownership.
- P5 map/exploration/Local Signals UI plus LS-5/LS-6: planned, blocked on the
  preceding data contracts and runtime/device verification decisions.

After P0 is merged, the next session should run:

```text
git fetch origin && git worktree add -b geondongkim/lala-official-data-p1 /Users/geondongkim/orca/workspaces/LALA-next/lala-official-data-p1 origin/main
```

Do not reuse the old LS-1/LS-4 worktrees and do not merge PR #77 as part of
this phase.
