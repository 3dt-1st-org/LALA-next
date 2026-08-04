# P3-M4: Bounded Review Replay Selection

**Date:** 2026-08-05
**Checkpoint:** P3-M4
**Status:** ✅ Complete
**PR:** #96 (Draft)

## Overview

Implemented deterministic replay window selection for the review mention preprocessing pipeline. This offline, aggregate-only feature extends the existing `review_mention_ingest.py` service and `run_review_mention_ingest.py` CLI tool to support bounded time and place scope filters.

## Implementation Details

### Service Layer Changes (`review_mention_ingest.py`)

Extended `fetch_review_mention_inputs()` with optional filter parameters:

```python
def fetch_review_mention_inputs(
    *,
    dsn: str,
    limit: int,
    provider: str,
    connect_timeout: int,
    since: str | None = None,          # NEW: inclusive lower bound
    until: str | None = None,          # NEW: exclusive upper bound  
    place_id: str | None = None,       # NEW: canonical place filter
) -> tuple[list[ReviewMentionPost], list[ReviewMentionPlace]]
```

**SQL Filter Construction:**
- Dynamic WHERE clause building with parameterized queries
- Time filters: `coalesce(created_at_source, collected_at) >= %(since)s`
- Upper bound: `coalesce(created_at_source, collected_at) < %(until)s` (exclusive)
- Place filter: `place_id = %(place_id)s` on places query
- Maintains backward compatibility (all filters optional)

### CLI Tool Changes (`run_review_mention_ingest.py`)

**New Arguments:**
- `--since YYYY-MM-DD` - Inclusive lower bound date
- `--until YYYY-MM-DD` - Exclusive upper bound date  
- `--place-id <id>` - Filter by canonical place_id

**Supported Date Formats:**
- `%Y-%m-%d` (e.g., `2026-06-15`)
- `%Y-%m-%dT%H:%M:%SZ` (e.g., `2026-06-15T14:30:00Z`)
- `%Y-%m-%dT%H:%M:%S` (e.g., `2026-06-15T14:30:00`)
- `%Y-%m-%d %H:%M:%S` (e.g., `2026-06-15 14:30:00`)

**Input Validation:**
- ✅ Rejects malformed date formats with clear error messages
- ✅ Rejects inverted ranges (`until <= since`)
- ✅ Rejects non-positive limits (`limit <= 0`)
- ✅ Rejects blank/empty place_id values
- ✅ Rejects unsafe place_id patterns (SQL injection prevention)
- ✅ Allows only alphanumeric, underscore, hyphen, colon, slash in place_id

**Output Metadata:**
- Filter values included in JSON/text output as bounded values
- Shows applied filters in text mode (provider, since, until, place_id)
- Supports both `--preview` and `--apply` modes

## Testing

**New Test Coverage (16 total tests):**

1. **CLI Validation Tests:**
   - Invalid date format rejection
   - Inverted range rejection  
   - Blank place_id rejection
   - Unsafe character rejection

2. **Integration Tests:**
   - Valid date filter acceptance and parameter passing
   - Valid place_id filter acceptance and parameter passing
   - Multiple date format parsing support

3. **Service Layer Tests:**
   - Date filter inclusion in SQL queries
   - Place_id filter in places query
   - Backward compatibility (no filters)

**Test Results:**
- ✅ All 16 tests pass
- ✅ Ruff linting passes
- ✅ Ruff formatting passes  
- ✅ Pre-commit hooks pass
- ✅ No security warnings

## Security Considerations

**SQL Injection Prevention:**
- Parameterized queries for all filter values
- Whitelist-based place_id validation (regex: `^[A-Za-z0-9_\-:/]+$`)
- Dangerous pattern detection: `['", '"', ';', '--', '/*', '*/', 'xp_', 'sp_']`
- No raw string concatenation in SQL construction

**Data Governance:**
- Offline-only processing (no live acquisition)
- Aggregate-only evidence (no raw review text storage)
- Replay/preview boundary only (no raw review table access)
- Respects existing `ingest.review_sources` (062 foundation)

## Usage Examples

**Date-bounded replay:**
```bash
python -m apps.api.app.tools.run_review_mention_ingest \
    --preview \
    --since 2026-06-01 \
    --until 2026-06-30 \
    --limit 1000
```

**Place-scoped replay:**
```bash
python -m apps.api.app.tools.run_review_mention_ingest \
    --preview \
    --place-id hoam-museum-123 \
    --limit 500
```

**Combined filters:**
```bash
python -m apps.api.app.tools.run_review_mention_ingest \
    --apply \
    --since 2026-06-01T00:00:00Z \
    --until 2026-06-30T23:59:59Z \
    --place-id hoam-museum-123 \
    --confirm APPLY_REVIEW_MENTION_INGEST
```

**JSON output:**
```bash
python -m apps.api.app.tools.run_review_mention_ingest \
    --preview \
    --since 2026-06-01 \
    --until 2026-06-30 \
    --json
```

## Backward Compatibility

✅ **Full backward compatibility maintained:**
- All new parameters are optional
- Existing calls without filters work identically
- No changes to database schema
- No changes to existing API contracts
- Existing tests continue to pass

## Files Modified

1. **Service Layer:** `apps/api/app/services/review_mention_ingest.py`
   - Extended function signature with optional filters
   - Dynamic SQL WHERE clause construction
   - Parameterized query execution

2. **CLI Tool:** `apps/api/app/tools/run_review_mention_ingest.py`
   - New CLI arguments with validation
   - Date parsing utilities
   - Filter output formatting
   - Input validation functions

3. **Tests:** `apps/api/tests/test_review_mention_ingest.py`
   - 9 new test functions for filtering functionality
   - Mock fixtures for SQL query verification
   - Validation logic testing

## Key Design Decisions

**Exclusive Upper Bound (`--until`):**
- Chose `<` (exclusive) for `--until` to enable proper time window partitioning
- Allows non-overlapping replay windows: `[since, until1)`, `[until1, until2)`
- Prevents double-counting in aggregate computations

**Flexible Date Formats:**
- Support multiple common datetime formats for user convenience
- Parse with multiple format patterns, fallback to None
- Ensure timezone-aware for ISO datetime formats

**Security-First Validation:**
- Validate place_id before database connection
- Multiple layers of safety (regex + dangerous patterns)
- Clear error messages for invalid input
- Fail-fast validation before expensive operations

## Compliance with Requirements

✅ **All P3-M4 requirements met:**
- [x] Extend `fetch_review_mention_inputs` with optional filters
- [x] Keep SQL parameterized and preserve existing behavior
- [x] Add CLI options with proper validation  
- [x] Reject malformed dates, inverted ranges, unsafe place IDs
- [x] Ensure selection is replay/preview boundary only
- [x] Include filter metadata in JSON/text output
- [x] Add focused offline tests for filtering functionality
- [x] Run verification sequence (pytest, ruff, pre-commit)
- [x] Create devlog with confirmed behavior
- [x] Commit with conventional commit message
- [x] Create Draft PR

## Next Steps

1. ✅ Implementation complete
2. ✅ Testing complete  
3. ✅ Verification complete
4. ✅ Documentation complete
5. 🔄 PR creation (Draft #96)
6. ⏳ Code review pending
7. ⏳ Merge to main pending approval