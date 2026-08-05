# Multi-Session Orchestration Documentation

**Date**: 2025-08-05
**Phase**: Documentation & Process
**Branch**: `codex/multi-session-orchestration-runbook`
**Base Commit**: `fa5717ed5ad0ae839932d666875b8299d5629b9e`

## Overview

Established comprehensive documentation for multi-session orchestration in LALA-next,
defining roles, state machines, verification gates, and handoff protocols to enable
coordinated multi-agent development workflows.

## Motivation

As LALA-next implementation progresses through P0-P7 phases, multiple specialized
agent sessions (Controller, Implementer, Verifier, Integrator) need to coordinate
effectively. This documentation provides:

1. **Role Boundaries**: Clear definition of each agent's responsibilities
2. **State Machine**: IMPLEMENTER → VERIFIER → CORRECTION_REQUIRED loop → INTEGRATOR
3. **Verification Gates**: PASS, CORRECTION_REQUIRED, BLOCKED_EXTERNAL verdicts
4. **Runtime Validation**: Specific checkpoints for iOS, browser, location, map, weather, search, plan, docent
5. **Secret Safety**: Guidelines for handling secrets safely
6. **Emergency Procedures**: Recovery steps when things go wrong

## Documentation Structure

### `docs/operations/multi-session-orchestration-runbook.md`
**Purpose**: Comprehensive orchestration runbook for all agents
**Key Sections**:
- Role definitions and boundaries
- State machine and transitions
- Worktree management procedures
- Verification gates and evidence requirements
- Runtime validation checkpoints
- Secret safety procedures
- Recovery and emergency procedures
- Cost and peak-time policy

### `docs/operations/agent-controller-handoff.md`
**Purpose**: Handoff contract between agents
**Key Sections**:
- Handoff format templates
- Session state machine
- Worktree handoff procedures
- Emergency handoff procedures
- Secret safety guidelines

### `docs/operations/verification.md` (Updated)
**Purpose**: Verification procedures executed by Verifier Steward
**New Sections**:
- Verifier Steward role definition
- Verdict categories (PASS, CORRECTION_REQUIRED, BLOCKED_EXTERNAL)
- Evidence requirements
- Runtime validation checkpoints
- Alignment with multi-session orchestration framework

## Runtime Validation Checkpoints

Four checkpoints established for progressive validation:

1. **Checkpoint 1**: Post Offline Review/Data Integration (P1-P3)
   - Database schema verification
   - Data ingest pipeline smoke test
   - Review processing worker contract
   - Local Signals aggregate generation

2. **Checkpoint 2**: Post RAG Integration (P4)
   - RAG index generation (test mode)
   - Embedding provider connectivity
   - Docent generation contract
   - Retrieval quality evaluation

3. **Checkpoint 3**: Pre-Integration Promotion (All phases)
   - iOS simulator non-destructive testing
   - Browser testing
   - Location services
   - Map rendering
   - Weather services
   - Search functionality
   - Plan generation
   - Docent display

4. **Checkpoint 4**: Production Readiness (Before deployment)
   - AWS Secrets Manager access (IAM role)
   - Database connectivity
   - RAG serving generation health
   - Live AI provider connectivity (if enabled)
   - Speech provider connectivity (if enabled)

## Verification Gates

Three verdict categories defined:

**PASS**: All verification gates satisfied
- All tests pass (unit, integration, runtime)
- CI green at exact head SHA
- Runtime checkpoints validated
- No secret values exposed
- No scope violations
- No mock/demo in normal path

**CORRECTION_REQUIRED**: Specific issues identified
- Test failures or coverage regression
- Scope creep or unrelated changes
- Secret values detected in diff/logs
- CI failures at exact SHA
- Mock/demo data in production path
- Runtime checkpoint failures

**BLOCKED_EXTERNAL**: External dependency unavailable
- External API/service down
- Missing credentials or access
- Third-party dependency issues
- Approval required for live operations

## Key Design Decisions

1. **Control-Plane-Only Controller**: Controller agent stays in control plane only,
   never touches production data or secrets directly

2. **Evidence-Based Verification**: All verdicts require exact head SHA, diff evidence,
   test results, CI status, and runtime evidence

3. **Worktree Isolation**: Each phase uses dedicated worktree to prevent state
   contamination between sessions

4. **Secret Safety**: Presence/metadata only, never print values in logs or diffs

5. **Runtime Validation**: Progressive checkpoints validate system behavior incrementally,
   reducing integration risk

6. **Emergency Recovery**: Clear procedures for recovering from common failure modes

## Integration with Existing Work

This documentation aligns with and extends:
- **AGENTS.md**: Maintains invariants (Kakao Map, Logto SDK, Geolocator, PostgreSQL path)
- **verification.md**: Extends existing verification procedures with orchestration framework
- **lala-final-completion-execution-playbook.md**: Implements state machine and role boundaries
  defined in authoritative playbook

## Next Steps

1. Test orchestration workflow with actual multi-session implementation
2. Refine handoff protocols based on practical usage
3. Adjust runtime validation checkpoints as system evolves
4. Update documentation as new patterns emerge

## References

- Authoritative playbook: `docs/planning/lala-final-completion-execution-playbook.md`
- Project conventions: `AGENTS.md`
- Base integration branch: `integration/lala-consolidation-20260805`

---

**Status**: 🟢 Documentation Complete
**Branch Ready**: Yes
**Integration Target**: `integration/lala-consolidation-20260805`
