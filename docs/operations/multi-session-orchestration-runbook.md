# Multi-Session Orchestration Runbook

> **Scope**: LALA-next final completion implementation and verification
> 
> **Status**: Operational standard
> 
> **Last updated**: 2026-08-05
> 
> **Base integration branch**: `integration/lala-consolidation-20260805` (fa5717ed5ad0ae839932d666875b8299d5629b9e)

This runbook defines the orchestration contract for multi-agent, multi-session LALA completion work. It implements the control-plane separation between Controller, Implementer, Verifier, and Integrator roles described in the final completion playbook.

## Table of Contents

1. [Role Boundaries](#role-boundaries)
2. [State Machine](#state-machine)
3. [Worktree and Session Management](#worktree-and-session-management)
4. [Verification Gates](#verification-gates)
5. [Runtime Validation Checkpoints](#runtime-validation-checkpoints)
6. [Secret Safety](#secret-safety)
7. [Prohibited Operations](#prohibited-operations)
8. [Recovery Procedures](#recovery-procedures)
9. [Phase Retrospective Format](#phase-retrospective-format)
10. [Controller Operations](#controller-operations)

---

## Role Boundaries

### Controller (Control-Plane Only)

**Responsibilities:**
- State restoration and session handoff
- Worktree and git state management
- Verification dispatch and result collection
- Integrator promotion decisions
- Session lifecycle management

**Never Does:**
- Direct code implementation in controller sessions
- Secret value access or display
- Runtime validation execution
- External API calls or migrations

**Required Tools:**
- `git` for worktree and branch management
- `gh` for PR inspection and creation
- Terminal process management for Orca sessions
- File system access to handoff docs and ledgers

### Implementer (Implementation Agent)

**Responsibilities:**
- Single-phase or single-slice implementation
- Test creation and local verification
- Draft PR creation with clear scope
- Completion report with evidence

**Never Does:**
- Self-declaration of PASSED without verifier confirmation
- Production database migrations
- Deployment operations
- Secret value exposure in logs or commits

**Required Evidence:**
- Exact diff (files changed)
- Test pass/fail counts
- CI status at exact head SHA
- No live/paid provider use unless approved
- No secret values in output

### Verifier (Verification Steward)

**Responsibilities:**
- Independent diff review against contract
- Runtime verification execution
- Evidence collection (screenshots, logs, metrics)
- Verdict issuance with exact reasons

**Verdict Categories:**
- `PASS` - All gates satisfied, ready for integrator
- `CORRECTION_REQUIRED` - Specific issues identified, implementer loop
- `BLOCKED_EXTERNAL` - External blocker, no implementation work possible

**Never Does:**
- Implementation work during verification
- Secret value display in reports
- Approval of mock/demo as production-ready

**Required Evidence:**
- Exact head SHA tested
- Runtime artifacts (screenshots, logs)
- Specific test failures or contract violations
- No unsupported `--model` flags or hidden processes

### Integrator (Integration Agent)

**Responsibilities:**
- Final review before integration promotion
- Merge decision preparation
- Integration branch state verification
- Draft PR creation for integration promotion

**Never Does:**
- Direct modification to implementation work
- Secret value exposure
- Merge without verifier PASS verdict

---

## State Machine

### Implementation Flow

```
IMPLEMENTER → VERIFIER STEWARD → CORRECTION_REQUIRED loop → INTEGRATOR → (PASS | BLOCKED_EXTERNAL)
```

### State Definitions

| State | Entry | Exit | Next States |
|-------|-------|------|-------------|
| `TARGET` | Controller creates phase plan | Implementer assigned | `IMPLEMENTED_NOT_RUNTIME_VERIFIED` |
| `IMPLEMENTED_NOT_RUNTIME_VERIFIED` | Implementer creates Draft PR | Verifier assigned | `CURRENT`, `CORRECTION_REQUIRED` |
| `CORRECTION_REQUIRED` | Verifier issues correction request | Implementer addresses issues | `IMPLEMENTED_NOT_RUNTIME_VERIFIED` |
| `CURRENT` | Integrator promotes to main | Runtime verified in production | Complete |
| `BLOCKED_EXTERNAL` | External blocker identified | External resolution | `TARGET` (when unblocked) |
| `REJECTED` | Contract/security violation | N/A | Complete (not merged) |

### Phase Progression

P0 → P1 → P2 → P3 → P4 → P5 → P6 → P7

Each phase must reach `CURRENT` state before next phase begins. Stacked PRs require explicit merge order documentation.

---

## Worktree and Session Management

### Canonical Verifier Worktree

**Location**: Designated long-lived worktree for verification sessions

**Purpose**: Persistent verification state across sessions

**Ledger Location**: `docs/operations/verification-ledger.md`

**Ledger Schema**:
```markdown
## Session {SESSION_ID}

| Field | Value |
|-------|-------|
| Date | YYYY-MM-DD HH:MM KST |
| Phase | P0-P7 |
| Verifier | Agent/session identifier |
| Worktree Path | /path/to/verifier/worktree |
| Target Branch | branch-name |
| Target Head SHA | exact SHA |
| Base SHA | exact SHA |
| Verdict | PASS | CORRECTION_REQUIRED | BLOCKED_EXTERNAL |
| Evidence | links to artifacts |
| Next Checkpoint | next session entry point |
```

### Controller Worktree Management

**Creation Rules:**
- One worktree per active implementation phase
- Worktree name: `lala-p{phase}-{description}-{timestamp}`
- Base branch: Current integration branch
- Never use user's dirty root for implementation

**Creation Command:**
```bash
git worktree add \
  /path/to/LALA-next/lala-p1-5-review-recheck-rag-handoff \
  -b codex/p1-5-review-recheck-rag-handoff \
  origin/integration/lala-consolidation-20260805
```

**Cleanup Rules:**
- Only after final PR state (merged or rejected)
- Only after reachability audit confirms no dependent work
- Tab/worktree cleanup only after completion
- Never prune active worktrees

### Session Handoff

**Controller Responsibilities:**
1. Persist exact worktree path and branch name
2. Record exact base and head SHAs
3. Document terminal process ID for Orca sessions
4. Create handoff document in `docs/operations/`

**Implementer Handoff Acceptance:**
1. Verify worktree exists and is clean
2. Verify branch name matches documentation
3. Verify base SHA matches integration branch
4. Confirm understanding of prohibited operations

---

## Verification Gates

### Verifier Evidence Requirements

All verifier verdicts MUST include:

1. **Exact Head SHA** - Tested commit, not PR number
2. **Diff Evidence** - Files changed with line counts
3. **Test Results** - Pass/fail counts with specific failures
4. **CI Status** - Current CI check results at exact SHA
5. **Runtime Evidence** - Screenshots, logs, metrics for runtime gates
6. **Safety Confirmation** - No secret values, no unsupported operations

### Verifier Decision Matrix

| Gate | PASS Criteria | CORRECTION_REQUIRED | BLOCKED_EXTERNAL |
|------|---------------|-------------------|------------------|
| **Diff** | Changes match phase scope only | Unrelated changes, scope creep | N/A |
| **Tests** | All relevant tests pass | Test failures, coverage regression | N/A |
| **Ruff** | No check failures | Lint violations | N/A |
| **Format** | No format violations | Format issues | N/A |
| **Pre-commit** | All hooks pass | Hook failures | N/A |
| **Diff-check** | No unintended changes | Breaking changes detected | N/A |
| **CI** | All checks green | CI failures | N/A |
| **Secret** | No secret values in diff | Secret values detected | N/A |
| **Unrelated** | No unrelated changes | Scope violations | N/A |
| **Runtime** | All runtime gates pass | Runtime failures | External dependency unavailable |
| **Production** | Production-ready (no mocks) | Mock/demo in normal path | External service approval required |

### Prohibited Verifier Behavior

- Accept CI URLs from previous commits as current evidence
- Approve mock/demo data as production-ready
- Accept "visually correct" without runtime verification
- Approve with secret values in logs or output
- Use unsupported `--model` flags or hidden processes

---

## Runtime Validation Checkpoints

### Checkpoint 1: Post Offline Review/Data Integration

**Scope**: After P1-P3 (contracts, official data, review processing)

**Validation Targets**:
- Database schema migration dry-run
- Data ingest pipeline smoke test
- Review processing worker contract
- Local Signals aggregate generation

**Commands**:
```bash
# Schema verification
scripts/unix/verify_db_schema.sh

# Worker contract smoke
cd apps/workers
uv run python -m app.workers.review_bulk --dry-run --limit 10

# Aggregate generation test
uv run python -m app.workers.aggregate_signals --dry-run --test-mode
```

**Required Evidence**:
- Schema reconciliation report
- Worker dry-run output with record counts
- No production database modifications
- No secret values in output

### Checkpoint 2: Post RAG Integration

**Scope**: After P4 (RAG/docent integration)

**Validation Targets**:
- RAG index generation (test mode)
- Embedding provider connectivity
- Docent generation contract
- Retrieval quality evaluation

**Commands**:
```bash
# RAG generation test
cd apps/workers
uv run python -m app.workers.rag_index --test-mode --verify

# Docent generation test
uv run python -m app.workers.docent_generation --dry-run --sample 5

# Retrieval eval
uv run python -m app.eval.retrieval_quality --test-set /path/to/golden.json
```

**Required Evidence**:
- Index generation stats (chunk count, embedding count)
- Docent samples for 5-10 representative places
- Retrieval evaluation metrics (precision@k, MRR)
- No actual embedding costs incurred (test mode)

### Checkpoint 3: Pre-Integration Promotion

**Scope**: Before any promotion to integration→main

**Validation Targets**:
- iOS simulator non-destructive testing
- Browser testing
- Location services
- Map rendering
- Weather services
- Search functionality
- Plan generation
- Docent display

**iOS Simulator Testing**:
```bash
# Build and run
cd apps/flutter_app
flutter build ios --simulator
flutter install --device-id=<simulator-udid>

# Core flow testing
# 1. Fresh install and location permission
# 2. Map marker rendering
# 3. Search functionality
# 4. Daily plan generation
# 5. Docent display
# 6. Local Signals integration
```

**Required Evidence**:
- Screenshots of core flows
- No crashes or force-quit scenarios
- Location privacy respected
- No secret values in app bundle

**Browser Testing** (if web support exists):
- Core flow verification in target browsers
- Responsive design validation
- Location permission handling

### Checkpoint 4: Production Readiness

**Scope**: Before production deployment

**Validation Targets**:
- AWS Secrets Manager access (IAM role)
- Database connectivity
- RAG serving generation health
- Live AI provider connectivity (if enabled)
- Speech provider connectivity (if enabled)

**Commands**:
```bash
# Readiness check
curl https://api.example.com/readyz

# Secret dependency check (no values displayed)
curl https://api.example.com/readyz | jq '.data.secret_dependencies'

# Database probe
curl https://api.example.com/healthz | jq '.data.database'
```

**Required Evidence**:
- All readiness checks healthy
- No secret values in output
- Fail-closed behavior for missing secrets
- Rollback plan documented

---

## Secret Safety

### Secret Presence and Metadata Only

**Allowed Operations**:
- Check secret exists: `aws secretsmanager describe-secret`
- Check secret metadata: version, tags, rotation status
- Inject into environment: `aws secretsmanager get-secret-value --query SecretBinary --output text`
- Use Dart defines: `--dart-define="VAR_NAME=value"` (non-secret values only)

**Prohibited Operations**:
- Printing secret values to stdout/stderr
- Copying secret values to clipboard
- Attaching secret values to bug reports
- Committing secret values to git
- Displaying full DSN strings
- Logging complete ARN paths

### Root .env/.env.local and AWS Secrets Manager/SSM

**Development Profile (local)**:
- Source: Explicitly sourced `.env` or `.env.local`
- Behavior: Fail immediately if required secret missing
- Command fails with clear error message

**CI Profile (ci)**:
- Source: Test fixtures or injected CI environment variables
- Behavior: AWS SDK calls prohibited, use fixtures only
- No external secret manager access

**AWS Profile (aws)**:
- Source: IAM role + AWS Secrets Manager
- Behavior: Fail closed if required secret lookup fails
- No silent fallback to other providers

### Injection Example (Secret-Safe)

```bash
# CORRECT: Check secret exists and metadata
aws secretsmanager describe-secret \
  --secret-id lala/production/api \
  --query 'Name,VersionIdsToStages' \
  --output text

# CORRECT: Inject to environment without printing
export MY_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id lala/production/api \
  --query SecretString \
  --output text)

# CORRECT: Dart define for non-secret build value
flutter build apk --dart-define="LALA_API_BASE_URL=https://api.example.com"

# WRONG: Printing secret value
aws secretsmanager get-secret-value --secret-id lala/production/api --output text

# WRONG: Logging complete DSN
echo "Database connected: postgresql://user:password@host:5432/db"
```

### OpenAI vs Azure Distinction

**Standard OpenAI**:
- Provider: `openai`
- Endpoint: `https://api.openai.com/v1`
- Use case: Normal production path
- Requirement: Explicit live provider approval

**Azure OpenAI**:
- Provider: `azure`
- Endpoint: Azure-managed resource
- Use case: Enterprise isolation
- Requirement: Explicit Azure configuration

**Mock/Demo Prohibition**:
- No normal-path production use of mock providers
- Test fixtures only in CI/local profiles
- Clear separation in code between real and test providers

---

## Prohibited Operations

### Explicitly Prohibited Without Separate Approval

**Live/Paid Provider Operations**:
- Live OpenAI API calls (unless `--live-ai` approved)
- Live Speech API calls (unless `--speech` approved)
- Live paid search APIs (unless approved)
- Live crawling/scraping operations

**Production Database Operations**:
- Database migration `apply` without operator approval
- Database write operations in normal path
- Schema changes without migration files
- Bulk data operations without dry-run verification

**Deployment Operations**:
- Deployments to production environments
- DNS changes
- Authentication system mutations
- Device configuration changes

**Data Operations**:
- Production data deletion or truncation
- Secret rotation operations
- User data exports
- Analytics data exports

### Separately Approved Operations

**Operations Requiring Explicit Approval**:
- Database migration apply (Operator role)
- Production deployment (Operator role)
- DNS changes (Operator role)
- Authentication system changes (Operator role)
- Secret rotation (Operator role)
- Live AI provider activation (explicit approval)
- Production data operations (explicit approval)

### Mock/Demo Normal Path Prohibition

**Normal Path Definition**:
- Code paths executed in production deployment
- Default configuration without test flags
- User-facing API endpoints

**Prohibited in Normal Path**:
- Mock data sources presenting as real
- Demo providers hiding as production
- Placeholder values in critical fields
- Test fixtures in production configuration

**Allowed**:
- Explicit test-mode with clear flags
- Local development with test configuration
- CI environment with fixtures
- Snapshot fallback for outage resilience (documented)

---

## Recovery Procedures

### Timeout Recovery

**Orca Session Timeout**:
1. Note last completed checkpoint from ledger
2. Restart session from next checkpoint
3. Verify worktree state matches checkpoint
4. Continue from last successful state

**Test Timeout**:
1. Identify which test phase timed out
2. Re-run with increased timeout if appropriate
3. Document timeout reason in evidence
4. Continue with remaining tests

**Build Timeout**:
1. Check for previous build artifacts blocking
2. Clean build artifacts in affected worktree only
3. Re-run build with clean state
4. Document build configuration issues

### TUI Failure Recovery

**Terminal TUI Corruption**:
1. Exit current TUI session cleanly
2. Start new terminal session
3. Verify worktree state is clean
4. Resume from last checkpoint

**Display Issues**:
1. Document terminal type and dimensions
2. Use alternative interface if available
3. Verify no data loss from display issues
4. Continue with alternative display method

### One-Worktree-One-Runner Lock

**Lock Purpose**: Prevent concurrent modification of same worktree

**Acquisition**:
- Controller assigns worktree to single implementer
- Implementer acknowledges exclusive access
- Lock recorded in session ledger

**Release**:
- Implementer completes work and creates Draft PR
- Verifier completes verification and issues verdict
- Integrator completes integration promotion
- Controller records completion and releases lock

**Violation Response**:
- Detect concurrent access attempts
- Halt second session immediately
- Resolve conflict through controller
- Document violation in ledger

---

## Phase Retrospective Format

### Required Retrospective Sections

After each phase completion, document:

```markdown
## Phase {P0-P7} Retrospective

### Confirmed
- [List of completed deliverables]
- [Verified runtime behaviors]
- [Test results summary]

### Assumptions
- [Assumptions made during implementation]
- [Dependencies taken as given]
- [Scope decisions and rationale]

### External Decisions
- [External approvals required]
- [Third-party dependencies confirmed]
- [Provider choices and limitations]

### Pull Request
- **Number**: PR#{number}
- **URL**: https://github.com/3dt-1st-org/LALA-next/pull/{number}
- **Base SHA**: {exact base commit SHA}
- **Head SHA**: {exact head commit SHA}
- **Merge Status**: merged | open | draft | closed

### Testing Evidence
- **Tests Passed**: {count}/{total}
- **Runtime Checks**: {list of checkpoints validated}
- **Screenshots**: {links to evidence}
- **Manual Testing**: {list of manual tests performed}

### Next Actions
- [ ] [Specific action item 1]
- [ ] [Specific action item 2]
- [ ] [External dependency resolution]

### Remaining Blockers
- [List of any remaining external blockers]
- [Estimated resolution timeline]
- [Impact on next phases]
```

### Retrospective Location

- File: `docs/devlogs/phase-{P0-P7}-{name}-{date}.md`
- Format: Markdown with frontmatter
- Access: Read-only after phase completion

---

## Controller Operations

### Session Initialization

**Pre-Session Checklist**:
- [ ] Verify integration branch is up to date
- [ ] Create or verify verifier worktree exists
- [ ] Verify no concurrent sessions on target worktree
- [ ] Prepare handoff document with clear scope
- [ ] Document exact base SHA for phase

**Session Launch**:
```bash
# Record session start
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) - Controller - Session Start - Phase {P0-P7}" >> \
  docs/operations/controller.log

# Launch Orca terminal session
orca-cli launch --session-id={SESSION_ID} --worktree={WORKTREE_PATH}
```

### Session Monitoring

**Active Session Monitoring**:
```bash
# Check terminal process
ps aux | grep -i orca

# Check worktree git status
git -C {WORKTREE_PATH} status --short

# Check for draft PR
gh pr list --head {BRANCH_NAME} --state draft
```

**Session Health Indicators**:
- Terminal process responsive
- Git commits progressing
- Test executions visible
- No secret values in output
- CI checks running

### Session Completion

**Implementer Session Complete When**:
- Draft PR created with clear scope description
- All tests pass locally
- CI status documented with exact SHA
- Completion report filed
- No secret values in any output

**Verifier Session Complete When**:
- Verdict issued with evidence
- Runtime artifacts collected
- Ledger updated with next checkpoint
- Handoff document created for next role

**Integrator Session Complete When**:
- Integration promotion decision made
- Integration branch updated
- Draft PR for promotion created
- Phase retrospective documented

### Session Handoff Format

**Controller to Implementer Handoff**:
```markdown
## Controller Handoff - Phase {P0-P7}

### Scope
[Detailed scope description]
### In-Scope Files
[List of files to modify]
### Excluded Files
[List of files to never modify]
### Base Branch
{branch-name}
### Base SHA
{exact SHA}
### Worktree Path
{absolute path}
### Prohibited Operations
[list of prohibited actions]
### Required Evidence
[list of required deliverables]
### Completion Report Format
[template for completion report]
```

**Implementer to Verifier Handoff**:
```markdown
## Implementer Completion Report - Phase {P0-P7}

### Implemented
[List of implemented changes]
### Draft PR
- **Branch**: {branch-name}
- **URL**: {PR URL}
- **Head SHA**: {exact SHA}
### Changed Files
[List with change summary]
### Tests Passed
{count}/{total}
### CI Status
[Link to CI run at exact SHA]
### Safety Confirmation
- [ ] No secret values exposed
- [ ] No live/paid providers used
- [ ] No production DB operations
- [ ] No deployments executed
### Remaining Blockers
[List any external blockers]
```

**Verifier to Integrator Handoff**:
```markdown
## Verifier Report - Phase {P0-P7}

### Verdict
PASS | CORRECTION_REQUIRED | BLOCKED_EXTERNAL

### Tested Head SHA
{exact SHA}

### Evidence
- **Diff Review**: [summary]
- **Tests**: {count}/{total} passed
- **CI**: [status at exact SHA]
- **Runtime**: [checkpoint results]
- **Screenshots**: [links]

### Issues Found (if CORRECTION_REQUIRED)
[List specific issues with file/line references]

### External Blockers (if BLOCKED_EXTERNAL)
[List external dependencies]

### Recommendation
[Integrate | Return to Implementer | Await External Resolution]
```

---

## Appendix: Current State Examples

### Generic State Example

```markdown
## Current Phase Status

**Phase**: P3 - Review/Local Signals
**Branch**: codex/p3-review-local-signals
**Base SHA**: fa5717ed5ad0ae839932d666875b8299d5629b9e
**Current SHA**: {actual-sha-when-current}
**State**: IMPLEMENTED_NOT_RUNTIME_VERIFIED
**Draft PR**: #{number}
**CI**: [link to CI run]

### Completed
- Review ingest worker contract
- Local Signals API endpoints
- Aggregate generation pipeline
- Unit tests and integration tests

### Verified
- All tests pass locally
- CI green at exact SHA
- No secret values in code
- No production DB operations

### Pending Verification
- Runtime checkpoint: post offline review
- iOS simulator testing
- Browser testing
- Production readiness validation

### External Dependencies
- None
```

### Secret-Safe Configuration Example

```yaml
# config/local.yaml (non-secret values only)
api:
  base_url: https://api.example.com
  timeout: 30
  retry_attempts: 3

features:
  live_ai: false
  speech: false
  local_signals: true

aws:
  region: us-east-1  # Non-secret metadata
  secret_prefix: lala/production  # Non-secret pointer

# Secret values loaded from AWS Secrets Manager at runtime
# Never stored in configuration files
```

### Prohibited Example (What Not To Do)

```bash
# WRONG: Secret value in command
export OPENAI_API_KEY=sk-abc123...  # Never do this

# WRONG: Secret in logs
logger.info(f"Connected to database: {DB_DSN}")  # Never log DSN

# WRONG: Secret in commit
git commit -m "Add OpenAI key sk-abc123..."  # Never commit secrets

# WRONG: Mock data in normal path
if not os.getenv("LALA_USE_REAL_DATA"):
    return mock_places  # Never hide mock path
```

---

## Cost and Peak-Time Policy

### Cost Awareness

**AI Provider Costs**:
- Track token usage per session
- Monitor embedding generation costs
- Alert on unexpected cost increases
- Use test mode to avoid production costs

**Peak-Time Considerations**:
- Schedule heavy operations off-peak
- Rate-limit API calls during peak hours
- Monitor quota usage
- Implement backoff for rate limits

### Recovery After Cost Events

**Unexpected Cost Increase**:
1. Identify offending operation
2. Halt operation immediately
3. Review code for unintended calls
4. Implement additional safeguards
5. Document incident in retrospective

**Quota Exceeded**:
1. Note quota limit and reset time
2. Implement exponential backoff
3. Document quota in phase retrospective
4. Plan alternative approach if needed

---

## Verification Commands Reference

### Local Verification

```bash
# Full repository verification
scripts/unix/verify_repo.sh

# Skip install for speed
scripts/unix/verify_repo.sh --skip-install

# Python only
scripts/unix/verify_repo.sh --python .venv/bin/python

# Flutter verification
cd apps/flutter_app
flutter analyze && flutter test
```

### Database Verification

```bash
# Schema verification (no DB connection required)
scripts/unix/verify_db_schema.sh

# Resource verification (no DB connection required)
scripts/unix/verify_db_resources.sh

# Local MVP bootstrap (explicit localhost only)
scripts/unix/bootstrap_local_mvp_db.sh --dry-run
```

### Handoff Report

```bash
# Full handoff report
scripts/unix/handoff_report.sh

# Skip tests for quick check
scripts/unix/handoff_report.sh --skip-tests

# Skip Azure verification
scripts/unix/handoff_report.sh --skip-azure

# Specify OpenAPI baseline
scripts/unix/handoff_report.sh --openapi-baseline /path/to/baseline.json
```

---

## Conclusion

This runbook implements the orchestration layer for LALA-next final completion. All agents MUST operate within their role boundaries and follow the state machine defined herein. Any deviation from these procedures requires explicit documentation and approval from the Controller.

The canonical verifier worktree, session ledger, and handoff documents form the single source of truth for session state. All verification evidence MUST reference exact commit SHAs, never PR numbers or branch names alone.

Secret safety is paramount: no secret values, DSN strings, or complete ARNs may appear in logs, commits, or handoff documents. Runtime verification confirms secret dependency health without exposing values.

This runbook, combined with the final completion playbook and AGENTS.md, forms the complete operational contract for LALA-next completion work.
