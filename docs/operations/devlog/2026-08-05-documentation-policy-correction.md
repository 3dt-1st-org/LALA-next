# Devlog - 2026-08-05 Documentation Policy Correction

This log records the documentation policy corrections required by the supervisor audit
for the multi-session orchestration system. The corrections align runbook and
handoff documents with the control-plane separation and state machine requirements.

## Corrections Applied

### 1. Controller Control-Plane Scope

**Issue**: Controller responsibilities included mutable git/worktree operations

**Fix**: Updated `docs/operations/multi-session-orchestration-runbook.md` and
`docs/operations/agent-controller-handoff.md` to define controller as:

**CONTROL PLANE ONLY**:
- Read-only git/PR/worktree/CI/runtime state inspection
- Queue ordering, worker dispatch, verdict comparison, and checkpoint decisions
- Session lifecycle management and handoff coordination

**NEVER DOES**:
- Code/doc edits, commit/push, rebase/cherry-pick/conflict resolution
- PR retarget/merge/close or mutable worktree management

**Implementation Operations**:
- Implementer performs all code/doc changes
- Integrator performs retarget/rebase/merge/close after verifier PASS
- Required tools and examples must not tell a controller to run mutable Git/worktree operations

### 2. Canonical Verifier Worktree

**Issue**: Verifier worktree path was generic placeholder

**Fix**: Updated `docs/operations/multi-session-orchestration-runbook.md` with:
- Exact long-lived worktree path: `/Users/geondongkim/orca/workspaces/LALA-next/lala-zai-verification`
- One visible terminal/session titled "ZCode VERIFICATION STEWARD GLM-4.7"
- Bootstrap once; subsequent requests resume the same persisted session using
  `/Users/geondongkim/.local/bin/zcode-visible-run <worktree> <prompt-file> --continue`
- One verifier worktree/session, no per-PR verifier proliferation

### 3. Ledger and State Documentation

**Issue**: Tracked ledger location was incorrect, mutable state placement guidance missing

**Fix**: Updated ledger documentation to specify:
- Mutable live ledger is local/untracked at `output/local/verification-steward-ledger-20260805.md`
- Do not claim a tracked `docs/operations/verification-ledger.md` exists or should be edited
- Do not place live session IDs, secret values, tokens, raw env values, or mutable
  runtime state in tracked docs or PR body
- Tracked docs may define stable secret-free ledger schema and fields as operational
  placeholders

### 4. State Machine Corrections

**Issue**: Missing `INTEGRATION_VERIFIED` state, automatic main promotion implication

**Fix**: Updated state definitions in both documents to:
- Define `INTEGRATION_VERIFIED` as a distinct state after verifier PASS and
  integration-branch verification
- Do not define `CURRENT` as an automatic integrator-to-main promotion state
- Main promotion is a separate Draft/review step requiring explicit user/ops
  authorization plus deploy, DB migration, runtime, secret/IAM, and live-provider gates
- No automatic main merge, deploy, or production readiness claim

### 5. Exact SHA/Base Claims

**Issue**: Mutable operational claims presented as current truth in templates

**Fix**: Updated documentation to:
- Use placeholders like `<EXACT_HEAD_SHA>` and `<EXACT_BASE_SHA>` in templates
- Require the controller/verifier to query live state at each checkpoint
- Historical examples remain only when clearly labeled as historical evidence
- Remove or qualify mutable operational claims such as "current exact SHA/base is..."
from standards/templates

### 6. Existing Rules Maintained

**No changes to existing strong requirements**:
- Secret-safety rules remain intact
- No mock/demo-normal-path rules maintained
- No live-crawl/provider/DB/deploy/device rules maintained
- No secret-shaped examples added

## Verification

**Offline checks performed**:
- `uv run pre-commit run --all-files`
- `uv run ruff check .`
- `uv run ruff format --check .`
- `git diff --check`

**All checks passed**: No lint violations, format violations, or unintended changes.

## Changed Files

1. `docs/operations/multi-session-orchestration-runbook.md`
   - Controller responsibilities clarified as control-plane only
   - Canonical verifier worktree path specified
   - Ledger and state documentation corrected
   - State machine updated with `INTEGRATION_VERIFIED` state
   - Exact SHA/base claims converted to placeholders

2. `docs/operations/agent-controller-handoff.md`
   - Controller scope updated to match runbook
   - State definitions aligned with runbook state machine
   - Implementation operations clarified

3. `docs/operations/devlog/2026-08-05-documentation-policy-correction.md` (this file)

## Next Actions

- Create Draft PR targeting `integration/lala-consolidation-20260805`
- PR body must state exact base/head queried at creation
- Document docs-only scope, no production authorization
- Document remaining runtime/ops gates without exposing secrets/cloud IDs
- Leave PR unmerged for review