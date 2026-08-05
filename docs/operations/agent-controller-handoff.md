# Agent Controller Handoff

> **Scope**: LALA-next multi-agent orchestration boundaries
>
> **Last updated**: 2026-08-05
>
> **Base runbook**: See `multi-session-orchestration-runbook.md`

This document defines the handoff contract between agents in the LALA-next orchestration system. It aligns the Controller, Implementer, Verifier, and Integrator boundaries with the multi-session orchestration runbook.

## Role Boundaries

### Controller (Control-Plane Orchestrator)

**Scope**: State management and session coordination only

**Responsibilities**:
- Read-only git/PR/worktree/CI/runtime state inspection
- Queue ordering, worker dispatch, verdict comparison, and checkpoint decisions
- Session lifecycle management and handoff coordination

**Never Does**:
- Direct code implementation
- Secret value access or display
- Runtime validation execution
- External API calls or migrations
- Code/doc edits, commit/push, rebase/cherry-pick/conflict resolution
- PR retarget/merge/close or mutable worktree management

**Handoff To**: Implementer (with phase scope)

**Important**: Implementer performs all code/doc changes; integrator performs retarget/rebase/merge/close after verifier PASS. Required tools and examples must not tell a controller to run mutable Git/worktree operations.

### Implementer (Implementation Agent)

**Scope**: Single-phase or single-slice implementation

**Responsibilities**:
- Implement assigned phase/scope
- Create comprehensive tests
- Run local verification
- Create Draft PR with evidence
- Report completion with exact SHA

**Never Does**:
- Self-declare PASSED without verifier
- Production database operations
- Deployment or DNS changes
- Secret value exposure

**Handoff To**: Verifier Steward (with Draft PR)

### Verifier Steward (Verification Agent)

**Scope**: Independent verification and evidence collection

**Responsibilities**:
- Review diff against implementation contract
- Execute runtime validation checkpoints
- Collect evidence (screenshots, logs, metrics)
- Issue verdict with specific reasons
- Document next checkpoint

**Never Does**:
- Implementation work during verification
- Secret value display in reports
- Approve mock/demo as production-ready

**Handoff To**: Integrator (on PASS) or Implementer (on CORRECTION_REQUIRED)

### Integrator (Integration Agent)

**Scope**: Final integration promotion

**Responsibilities**:
- Review verifier PASS verdict
- Verify integration branch state
- Prepare integration promotion
- Create Draft PR for integration→main promotion

**Never Does**:
- Direct modification to implementation work
- Secret value exposure
- Merge without verifier PASS

**Handoff To**: Controller (session complete)

---

## Session State Machine

```
Controller → Implementer → Verifier → (Integrator → Controller | Implementer loop)
```

### State Definitions

| State | Trigger | Next | Gatekeeper |
|-------|---------|------|-------------|
| `ASSIGNED` | Controller creates worktree | Implementer | Controller |
| `IMPLEMENTED` | Implementer creates Draft PR | Verifier | Implementer |
| `VERIFIED_PASS` | Verifier issues PASS | Integrator | Verifier |
| `VERIFIED_CORRECTION` | Verifier issues CORRECTION_REQUIRED | Implementer | Verifier |
| `INTEGRATION_VERIFIED` | Verifier PASS, integration-branch verification complete | Integrator review for main promotion | Verifier |
| `INTEGRATION_READY` | Integrator creates promotion PR | Controller | Integrator |
| `COMPLETE` | Controller updates ledger | End | Controller |
| `BLOCKED_EXTERNAL` | External dependency identified | Controller | Verifier |

**Important**:
- `INTEGRATION_VERIFIED` is a distinct state after verifier PASS and integration-branch verification
- Main promotion is a separate Draft/review step requiring explicit user/ops authorization
- No automatic main merge, deploy, or production readiness claim

---

## Handoff Format

### Controller → Implementer

```markdown
## Phase {P0-P7} Implementation Assignment

**Date**: YYYY-MM-DD HH:MM KST
**Session**: {SESSION_ID}
**Controller**: Controller Agent

### Scope
[Detailed implementation scope]
### In-Scope Files
[List of files to modify]
### Excluded Files
[List of protected files - never modify]
### Base Branch
{branch-name}
### Base SHA
{exact SHA}
### Worktree Path
{absolute path}
### Prohibited Operations
- No production DB operations
- No deployments
- No secret value exposure
- No live/paid providers without approval

### Required Deliverables
1. Implementation of assigned scope
2. Comprehensive tests
3. Local verification pass
4. Draft PR with description
5. Completion report

### Completion Report Template
- Implemented changes
- Draft PR URL and exact SHA
- Test results
- CI status at exact SHA
- No prohibited operations

### Handoff Back
Report completion with above template.
Await Verifier Steward assignment.
```

### Implementer → Verifier Steward

```markdown
## Phase {P0-P7} Implementation Complete

**Date**: YYYY-MM-DD HH:MM KST
**Session**: {SESSION_ID}
**Implementer**: Implementation Agent

### Completed
[List of implemented features]

### Draft PR
- **Branch**: {branch-name}
- **URL**: {PR URL}
- **Base SHA**: {exact base SHA}
- **Head SHA**: {exact head SHA}

### Changed Files
- `apps/api/...` [change summary]
- `apps/flutter_app/...` [change summary]

### Testing Evidence
- **Unit Tests**: {count}/{total} passed
- **Integration Tests**: {count}/{total} passed
- **Local Verification**: PASSED

### CI Status
- **CI Run**: [link to exact SHA CI run]
- **Status**: all checks green

### Safety Confirmation
- [ ] No secret values in code/logs
- [ ] No live/paid providers used
- [ ] No production DB operations
- [ ] No deployments executed
- [ ] No unsupported --model flags

### Scope Validation
- [ ] Only in-scope files modified
- [ ] Excluded files untouched
- [ ] Changes match phase scope

### Next
Await Verifier Steward review and runtime validation.
```

### Verifier Steward → Integrator (PASS)

```markdown
## Phase {P0-P7} Verification PASS

**Date**: YYYY-MM-DD HH:MM KST
**Session**: {SESSION_ID}
**Verifier**: Verifier Steward

### Verdict
**PASS** - Ready for integration

### Tested Head SHA
{exact SHA tested}

### Evidence Summary
- **Diff Review**: Changes match phase scope ✓
- **Tests**: {count}/{total} passed ✓
- **CI**: Green at exact SHA ✓
- **Runtime**: All checkpoints validated ✓
- **Secrets**: No values exposed ✓

### Runtime Checkpoints Validated
1. [ ] Post offline review checkpoint
2. [ ] Post RAG integration checkpoint
3. [ ] Pre-integration checkpoint
4. [ ] Production readiness checkpoint

### Artifacts
- Screenshots: [links]
- Test logs: [path]
- Metrics: [summary]

### Recommendation
**APPROVED FOR INTEGRATION**

### Next
Integrator: Review and prepare integration promotion.
```

### Verifier Steward → Implementer (CORRECTION_REQUIRED)

```markdown
## Phase {P0-P7} Verification CORRECTION_REQUIRED

**Date**: YYYY-MM-DD HH:MM KST
**Session**: {SESSION_ID}
**Verifier**: Verifier Steward

### Verdict
**CORRECTION_REQUIRED** - Issues identified

### Tested Head SHA
{exact SHA tested}

### Issues Found
1. **File**: {path}:{line} - {issue description}
2. **File**: {path}:{line} - {issue description}

### Evidence
- **Tests**: {count}/{total} passed
- **CI**: [status and failures]
- **Diff Review**: [specific issues]

### Required Corrections
- [ ] Issue 1: {correction needed}
- [ ] Issue 2: {correction needed}

### Next
Implementer: Address issues and create new Draft PR.
Return to Verifier Steward for re-verification.
```

### Verifier Steward → Controller (BLOCKED_EXTERNAL)

```markdown
## Phase {P0-P7} Verification BLOCKED_EXTERNAL

**Date**: YYYY-MM-DD HH:MM KST
**Session**: {SESSION_ID}
**Verifier**: Verifier Steward

### Verdict
**BLOCKED_EXTERNAL** - External dependency unavailable

### Tested Head SHA
{exact SHA tested}

### External Blockers
1. **Dependency**: {name} - {reason}
2. **Service**: {name} - {reason}

### Impact
Cannot complete verification without external resolution.

### Next
Controller: Document blocker and await external resolution.
No further implementation work possible until unblocked.
```

### Integrator → Controller

```markdown
## Phase {P0-P7} Integration Ready

**Date**: YYYY-MM-DD HH:MM KST
**Session**: {SESSION_ID}
**Integrator**: Integration Agent

### Integration Decision
**APPROVED FOR INTEGRATION**

### Verified
- Verifier PASS verdict confirmed
- Integration branch state validated
- No merge conflicts detected
- Integration promotion PR created

### Integration PR
- **Branch**: {branch-name}
- **URL**: {PR URL}
- **Target**: integration/lala-consolidation-20260805
- **Head SHA**: {exact SHA}

### Next
Controller: Update session ledger.
Mark phase as COMPLETE.
Begin next phase planning.
```

---

## Worktree Management

### Worktree Creation

**Controller Creates Worktree**:
```bash
git worktree add \
  /path/to/LALA-next/lala-p{phase}-{description}-{timestamp} \
  -b codex/p{phase}-{description} \
  origin/integration/lala-consolidation-20260805
```

**Worktree Assignment**:
- One worktree per active phase
- Exclusive assignment to single implementer
- Lock recorded in session ledger

**Worktree Cleanup**:
- Only after PR merged or rejected
- Only after integrator decision final
- Only after session ledger updated
- Never prune active worktrees

### Session Ledger

**Location**: `docs/operations/session-ledger.md`

**Entry Format**:
```markdown
## Session {SESSION_ID}

| Field | Value |
|-------|-------|
| Date | YYYY-MM-DD HH:MM KST |
| Phase | P0-P7 |
| Controller | Controller Agent |
| Implementer | Implementation Agent |
| Verifier | Verifier Steward |
| Integrator | Integration Agent |
| Worktree | /path/to/worktree |
| Branch | branch-name |
| Base SHA | exact SHA |
| Start State | ASSIGNED |
| End State | COMPLETE |
| Verdict | PASS |
| Duration | {time} |
| Artifacts | [links] |
```

---

## Controller Operations

### Session Start

```bash
# Record session start
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) - Controller - Session {SESSION_ID} - Phase {P0-P7} - START" >> \
  docs/operations/controller.log

# Create worktree
git worktree add {WORKTREE_PATH} -b {BRANCH_NAME} {BASE_BRANCH}

# Launch implementer session
orca-cli launch --session-id={SESSION_ID} --role=implementer
```

### Session Monitor

```bash
# Check active sessions
ps aux | grep orca-cli

# Check worktree status
git -C {WORKTREE_PATH} status --short

# Check for draft PRs
gh pr list --head {BRANCH_NAME} --state draft
```

### Session Complete

```bash
# Record session completion
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) - Controller - Session {SESSION_ID} - Phase {P0-P7} - COMPLETE - {VERDICT}" >> \
  docs/operations/controller.log

# Update session ledger
# Update handoff document
# Release worktree lock (if appropriate)
```

---

## Emergency Procedures

### Session Timeout

**Symptoms**: Orca session unresponsive

**Recovery**:
1. Note last checkpoint from ledger
2. Check worktree state
3. Resume from next checkpoint
4. Document timeout in ledger

### Verification Failure

**Symptoms**: Verifier issues CORRECTION_REQUIRED

**Recovery**:
1. Review specific issues from verifier
2. Implementer addresses issues
3. Create new Draft PR
4. Return to verifier for re-verification

### External Blocker

**Symptoms**: Verifier issues BLOCKED_EXTERNAL

**Recovery**:
1. Document external dependency
2. Controller records blocker
3. Await external resolution
4. No implementation work until unblocked

---

## Secret Safety

### Controller Secret Safety

**Allowed**:
- Check secret metadata exists
- Verify secret presence for readiness
- Document secret dependencies without values

**Prohibited**:
- Display secret values
- Log secret strings
- Copy secret values to clipboard
- Attach secrets to handoff documents

### Implementer Secret Safety

**Allowed**:
- Use environment variables for secrets
- Reference secret by logical name
- Test with non-secret fixtures

**Prohibited**:
- Print secret values in output
- Log secret configuration
- Commit secrets to git
- Display DSN strings

### Verifier Secret Safety

**Allowed**:
- Verify secret dependency health
- Check secret presence without values
- Document secret configuration status

**Prohibited**:
- Display secret values in reports
- Log secret access results
- Include secrets in evidence artifacts

---

## Cost and Resource Policy

### Controller Cost Awareness

**Track**:
- Session duration
- Worktree count
- Active session count
- Orca process resource usage

**Monitor**:
- Peak-time operations
- Concurrent session limits
- Worktree storage usage

### Implementer Cost Awareness

**Track**:
- Test execution time
- Build resource usage
- Local verification duration

**Avoid**:
- Unnecessary test re-runs
- Excessive build iterations
- Resource-intensive operations during peak hours

### Verifier Cost Awareness

**Track**:
- Runtime checkpoint duration
- Screenshot/image storage
- Test execution time

**Avoid**:
- Redundant verification steps
- Excessive screenshot collection
- Duplicate test executions

---

## Conclusion

This handoff document defines the boundaries and communication protocols between agents in the LALA-next orchestration system. All agents MUST operate within their defined roles and follow the handoff formats specified herein.

The Controller maintains the single source of truth for session state in the session ledger. All handoffs MUST reference exact commit SHAs, never PR numbers or branch names alone.

Secret safety is paramount: no agent may expose secret values in logs, handoff documents, or output. Runtime verification confirms secret dependency health without exposing values.

This document, combined with the multi-session orchestration runbook and the final completion playbook, forms the complete operational contract for LALA-next multi-agent orchestration.
