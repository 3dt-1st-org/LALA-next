# P1-2 Place Enrichment Uniqueness Implementation

**Date:** 2026-08-05
**Checkpoint:** P1-2
**Status:** ✅ Complete
**Migration:** 064_place_enrichment_replay_uniqueness.sql

## Summary

Implemented PostgreSQL 16-compatible uniqueness constraint on `travel.place_enrichments` for three-column null-safe uniqueness `(place_id, enrichment_type, prompt_version)` using `UNIQUE NULLS NOT DISTINCT`. Place-enrichment writers updated with appropriate ON CONFLICT handling: review attributes and AI profiling use DO NOTHING for idempotent replay safety, while local enrichment supports both DO NOTHING (append-only) and DO UPDATE (replace mode).

## Problem Statement

Multiple enrichment systems (local romanization, AI place profiling, review attributes) write to `travel.place_enrichments` without duplicate prevention. Prompt version bumps could cause duplicate enrichments, and `WHERE NOT EXISTS` patterns in some writers were not atomic.

## Implementation Details

### 1. Migration 064: Uniqueness Constraint with Preflight

Created additive, re-runnable migration using PostgreSQL 16 `UNIQUE NULLS NOT DISTINCT`:

**Duplicate preflight (fail-closed):**
```sql
-- Check for any duplicate replay keys before adding constraint
DO $$
DECLARE
    duplicate_count int;
BEGIN
    SELECT count(*) INTO duplicate_count
    FROM (
        SELECT place_id, enrichment_type, prompt_version
        FROM travel.place_enrichments
        GROUP BY place_id, enrichment_type, prompt_version
        HAVING count(*) > 1
    ) duplicates;

    IF duplicate_count > 0 THEN
        RAISE EXCEPTION 'place enrichment replay keys must be reconciled before migration';
    END IF;
END $$;
```

**Idempotent constraint addition:**
```sql
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'place_enrichments_place_type_prompt_unique'
    ) THEN
        ALTER TABLE travel.place_enrichments
            ADD CONSTRAINT place_enrichments_place_type_prompt_unique
            UNIQUE NULLS NOT DISTINCT (place_id, enrichment_type, prompt_version);
    END IF;
END $$;
```

**Key design decisions:**
- Three-column constraint allows same place_id+type with different prompt_version (for version bumps)
- `NULLS NOT DISTINCT` treats NULL values as equal keys (PostgreSQL 16 null-safe uniqueness)
- Fail-closed preflight prevents migration if duplicates exist (no live audit performed)
- Constraint name follows pattern: `{table}_{column_purpose}_unique`

### 2. Writer Updates for Conflict Safety

Updated all three place_enrichment writers:

#### `review_attribute_batch.py` (Lines 761-797)
**Behavior:** Insert only for accepted rows, no-op on conflict
**Conflict handling:** `ON CONFLICT (place_id, enrichment_type, prompt_version) DO NOTHING`

```sql
-- Only executed when row.accepted is True
INSERT INTO travel.place_enrichments (...)
VALUES (...)
ON CONFLICT (place_id, enrichment_type, prompt_version) DO NOTHING
```

**Test coverage:** Added behavioral fake-cursor test for accepted row INSERT execution

#### `local_place_enrichment.py` (Lines 228-253)
**Behavior:** Two distinct SQL paths based on `replace_existing` parameter
**Conflict handling:**
- `replace_existing=False`: `ON CONFLICT DO NOTHING` (append-only)
- `replace_existing=True`: `ON CONFLICT DO UPDATE SET` (update existing enrichment fields)

```sql
-- replace_existing=False: preserve existing enrichments
ON CONFLICT (place_id, enrichment_type, prompt_version) DO NOTHING

-- replace_existing=True: update english_text fields on same replay key
ON CONFLICT (place_id, enrichment_type, prompt_version)
DO UPDATE SET
    name_en = EXCLUDED.name_en,
    address_en = EXCLUDED.address_en,
    region_name_en = EXCLUDED.region_name_en,
    attributes = EXCLUDED.attributes,
    confidence = EXCLUDED.confidence
```

**Test coverage:** Added tests for both conflict handling paths

#### `enrich_place_ai_columns.py` (Lines 408-435)
**Behavior:** Insert with conflict detection, maintains place update on conflict
**Conflict handling:** `ON CONFLICT (place_id, enrichment_type, prompt_version) DO NOTHING`

```sql
INSERT INTO travel.place_enrichments (...)
VALUES (...)
ON CONFLICT (place_id, enrichment_type, prompt_version) DO NOTHING
```

**Test coverage:** Added execution-level fake-DB assertion for same-key place_profile idempotence

### 3. Schema Contract Updates

**`canonical_sql.py`:**
- Added `064_place_enrichment_replay_uniqueness.sql` to `CANONICAL_MIGRATION_ORDER`
- Updated `CANONICAL_MIGRATION_LATEST` to `"064_place_enrichment_replay_uniqueness.sql"`

**`db_schema.py`:**
- Added `"travel.place_enrichments(place_id,enrichment_type,prompt_version)"` to `REQUIRED_UNIQUE_CONSTRAINTS`

### 4. Test Updates

**`test_canonical_sql.py`:**
- Updated `EXPECTED_CANONICAL_MIGRATION_ORDER` to include 064
- Updated future migration test to use 065 (after this PR owns 064)
- Updated latest migration assertion to expect 064

**`test_place_enrichment_uniqueness.py` (NEW):**
- Fake-DB/SQL contract tests without live database calls
- Behavioral fake-cursor tests for accepted row INSERT execution
- Tests for both local enrichment conflict paths (DO NOTHING and DO UPDATE)
- Tests for place_profile same-key idempotence
- Repository-root path resolution for CI compatibility
- Removed unused imports and trailing whitespace

**`test_local_place_enrichment.py`:**
- Added test for `replace_existing=True` DO UPDATE conflict handling

**`test_place_ai_enrichment.py`:**
- Added test for same-key place_profile rerun idempotence

## Technical Approach

### Why UNIQUE NULLS NOT DISTINCT?

PostgreSQL 16 `UNIQUE NULLS NOT DISTINCT` ensures:
1. Multiple NULL prompt_versions are treated as equal (not distinct)
2. Non-NULL combinations are properly unique
3. Future prompt_version bumps can coexist with historical data

### Why Different ON CONFLICT Strategies?

Different enrichment writers have different semantics:
- **Review attributes:** Append-only, first write wins (DO NOTHING)
- **AI place profiling:** Append-only, first write wins (DO NOTHING)
- **Local enrichment:** Supports both append (DO NOTHING) and replace (DO UPDATE) modes

### Why Fail-Closed Preflight?

The duplicate preflight before constraint addition ensures:
1. Migration fails fast if duplicates exist
2. No silent data loss from constraint enforcement
3. Generic error message (no data exposure)
4. No live duplicate audit was performed (design-time safety only)

## Testing Strategy

### Fake-DB/SQL Contract Tests

Created comprehensive fake-DB tests without live database calls:
- `FakeCursor`/`FakeConnection` classes simulate database behavior
- Behavioral tests verify SQL execution paths (not just string matching)
- Repository-root path resolution for CI compatibility

### Test Coverage

- ✅ Migration SQL uses `UNIQUE NULLS NOT DISTINCT` with correct columns
- ✅ Migration includes fail-closed duplicate preflight
- ✅ Constraint addition is idempotent via `pg_constraint` check
- ✅ Review attribute batch executes INSERT for accepted rows only
- ✅ Local enrichment supports both DO NOTHING and DO UPDATE paths
- ✅ AI place profiling maintains place update idempotence on conflict
- ✅ All ON CONFLICT clauses use correct three-column specification
- ✅ db_schema.py requires the new constraint

## Files Changed

### SQL Migrations
- `sql/canonical/064_place_enrichment_replay_uniqueness.sql` (NEW)

### Services
- `apps/api/app/services/canonical_sql.py` (baseline update)
- `apps/api/app/services/db_schema.py` (constraint requirement)
- `apps/api/app/services/review_attribute_batch.py` (fixed accepted row INSERT)
- `apps/api/app/services/local_place_enrichment.py` (dual conflict paths)
- `apps/api/app/tools/enrich_place_ai_columns.py` (ON CONFLICT)

### Tests
- `apps/api/tests/test_canonical_sql.py` (baseline expectations, future migration)
- `apps/api/tests/test_place_enrichment_uniqueness.py` (NEW - fake-DB contract tests)
- `apps/api/tests/test_local_place_enrichment.py` (replace_existing test)
- `apps/api/tests/test_place_ai_enrichment.py` (idempotence test)

### Documentation
- `docs/devlogs/2026-08-05-p1-2-place-enrichment-uniqueness.md` (NEW - this file)

## Validation

### Code Quality Fixes Applied
- ✅ Removed unused imports and trailing whitespace from test files
- ✅ Replaced hard-coded absolute paths with repository-root resolution
- ✅ Fixed incorrect indentation that made accepted-row INSERT unreachable
- ✅ Added behavioral fake-cursor tests (not just source-string verification)
- ✅ Corrected comment about NULLS NOT DISTINCT behavior

### Technical Correctness
- ✅ Migration is additive and idempotent (DO block with pg_constraint check)
- ✅ Duplicate preflight fails closed with generic error message
- ✅ No destructive patterns (DROP, TRUNCATE, DELETE FROM)
- ✅ All ON CONFLICT clauses use correct three-column specification
- ✅ Writer semantics correctly documented (not all append-only)
- ✅ No live duplicate audit was performed (design-time safety only)

### Expected Behavior After Deployment

1. **Idempotent enrichment runs:** Same place_id+type+version can be re-applied safely
2. **Prompt version bumps:** New versions can coexist with historical data
3. **Duplicate prevention:** Database constraint prevents atomic duplicates
4. **Writer-specific semantics:**
   - Review attributes: First write wins, later writes silently ignored
   - AI place profiling: First write wins, place updates still execute
   - Local enrichment: Configurable append-only vs. replace behavior

## Rollback Plan

If issues arise post-deployment:

1. **Constraint removal:** `ALTER TABLE travel.place_enrichments DROP CONSTRAINT IF EXISTS place_enrichments_place_type_prompt_unique;`
2. **Writer reversion:** Revert ON CONFLICT changes to previous patterns
3. **Baseline revert:** Remove 064 from `CANONICAL_MIGRATION_ORDER`

## Related Documentation

- **P1-2 Planning:** See execution playbook for checkpoint context
- **Migration Baselines:** `sql/canonical/` directory for all canonical migrations
- **Schema Contracts:** `apps/api/app/services/db_schema.py` for required schema objects

## Next Steps

This implementation is complete for P1-2. Future considerations:
- **P1-3:** May need additional uniqueness constraints if new enrichment types added
- **Monitoring:** Track place_enrichments growth rate to ensure constraint doesn't cause excessive conflicts
- **Cleanup:** If prompt_version standardizes, consider NULLS NOT DISTINCT necessity

## Sign-off

- ✅ All writers conflict-safe with appropriate semantics
- ✅ Additive, re-runnable migration with fail-closed preflight
- ✅ Fake-DB/SQL contract tests with behavioral coverage
- ✅ Schema contracts updated
- ✅ Test suite expects new baseline
- ✅ Code quality fixes applied
- ✅ Truthful documentation (no false claims about IF NOT EXISTS, append-only, or live audit)

**Implementation complete. Ready for commit, push, and Draft PR.**
