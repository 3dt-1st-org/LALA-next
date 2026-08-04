# 2026-08-05 — P2 Official-Data Coverage Reconciliation Contract

Branch: `geondongkim/lala-p2-official-data-coverage-reconciliation` (Draft PR, off `origin/main`).

## What landed

A focused P2 coverage reconciliation contract that extends the existing P1 coverage baseline with reconciliation-specific semantics for full-ingest preparation. The implementation is deliberately offline-only, provider-neutral, and reuses existing inventory/governance/receipt semantics.

### CI and truthfulness corrections applied

The initial implementation was useful but the independent audit found both CI defects and truthfulness defects. All have been corrected:

1. **Ruff formatting and import cleanup**: Removed unused imports (`hashlib`, `json`, `Mapping`, `field`, `replace`, `Final`), combined nested conditionals flagged by SIM102, ordered imports alphabetically, and removed all trailing whitespace.

2. **No invented regional counts**: Deleted the "Approximate regional count as proportional share" logic. Existing `OfficialCoverageReceipt` has no proven per-region count, so `RegionalCoverageBreakdown.record_count` is now always `None` unless explicit per-region counts are supplied. Added focused test `test_regional_counts_remain_none_with_only_global_record_ids` proving receipts with only global record IDs keep every regional count `None`.

3. **Five state distinctions preserved**: Added explicit `rejected_sources` count to `ReconciliationReport` and its public summary. The field `rejected` is no longer folded into `unknown`. Updated gap mapping in `reconcile_receipt_coverage` with deterministic state transitions: `blocked_external -> governance_blocked`, `rejected -> rejected_source`, `stale -> stale_coverage`, `unknown -> no_coverage`, and `usable -> minimum-record check`. Extended `ReconciliationGap` literal to include `"rejected_source"`. Added test `test_all_five_state_distinctions_preserved`.

4. **Honest naming for source-scoped counts**: Renamed `total_distinct_records` to `total_source_scoped_record_count` with updated docstring and public key stating this is not a deduplicated cross-provider place count. Updated test `test_total_source_scoped_record_count_aggregates_all_sources`. The implementation only has source-scoped opaque IDs and sums them—**no** global identity union.

5. **Denominator-safe quality metrics**: Introduced `CoverageQualityMetrics` type keyed by `(source_name, dataset_name)` with non-negative numerator/denominator validation. Supports category counts/coverage, valid-coordinate count and rate, image-rights-ready count and rate, operating-hours available count and rate, duplicate/quarantined/failed counts and rates, and optional database comparison as unavailable/mismatch metadata. When metrics are absent, exposes `None`/`unknown`, never inferred percentages. Added tests for missing denominator, valid denominator, negative/impossible numerator, and validation that rejects invalid metrics. Bounded public-safe category keys.

6. **17-province gate deterministic**: Complete only when all expected region codes are explicitly present in accepted usable coverage. Preserves empty/unknown rows and does not claim a full count per region without proven per-region evidence. Added test `test_regional_counts_preserve_empty_rows`.

### Core implementation (`apps/api/app/services/official_coverage_reconciliation.py`)

- **`build_reconciliation_report()`**: Aggregates P1 coverage reports with reconciliation-specific gap detection
  - Tracks all five source states: `usable`, `blocked_external`, `rejected`, `stale`, `unknown`
  - Detects governance gaps, rejected sources, stale coverage, missing coverage, and scope mismatches
  - Computes regional breakdown across 17 provinces with `None` record counts unless per-region evidence provided
  - Accepts optional denominator-safe `CoverageQualityMetrics` keyed by (source_name, dataset_name)
  - Returns JSON-safe `ReconciliationReport` with public projection including quality metrics

- **`validate_full_ingest_dry_run()`**: Validates reconciliation reports against configurable thresholds
  - `require_nationwide_coverage`: Enforce complete 17-province coverage
  - `require_all_sources_usable`: Zero-tolerance for blocked/rejected/stale/unknown sources
  - `max_stale_sources`: Configurable threshold for stale source tolerance
  - Returns `FullIngestDryRunValidation` with pass/fail determination and specific blockers

- **`reconcile_receipt_coverage()`**: Lightweight receipt-to-source reconciliation
  - Matches receipts to inventory entries by `(source_name, dataset_name)`
  - Maps readiness states deterministically to gap types
  - Returns coverage summary with gap detection

### Dataclasses (frozen, immutable contracts)

- **`CoverageGap`**: Individual gap instances with type classification (including `rejected_source`)
- **`RegionalCoverageBreakdown`**: Per-region coverage summaries with `None` record counts
- **`ReconciliationReport`**: Top-level reconciliation aggregation with all five state counts and quality metrics
- **`FullIngestDryRunValidation`**: Validation result with blockers/warnings
- **`CoverageQualityMetrics`**: Denominator-safe quality metrics with validation and rate computation

## Design principles

1. **Provider-neutral**: No provider-specific logic or API calls
2. **Offline-only**: Pure function contracts with no side effects (no network, DB, filesystem, environment, subprocess)
3. **Reuse existing semantics**: Builds on P1 `OfficialSourceInventory`, `OfficialCoverageReceipt`, `SourceGovernance`
4. **Honest reporting**: Distinguishes all five states (`usable`, `blocked_external`, `rejected`, `stale`, `unknown`) without folding
5. **17-province model**: Full administrative coverage for South Korea regions with explicit gate determinism
6. **JSON-safe output**: All public projections use primitive types
7. **Denominator-safe metrics**: No inferred percentages, explicit validation, `None`/`unknown` when absent
8. **Source-scoped counts**: Honest naming that clarifies no cross-provider deduplication

## Comprehensive offline testing

Added `apps/api/tests/test_official_coverage_reconciliation.py` with 38 focused unit tests using synthetic in-memory fixtures:

- **Source counting**: `test_reconciliation_report_counts_all_sources`, `test_total_source_scoped_record_count_aggregates_all_sources`, `test_all_five_state_distinctions_preserved`
- **Governance gaps**: `test_reconciliation_report_identifies_governance_blocked_sources`, `test_rejected_sources_create_specific_gaps`
- **Coverage gaps**: `test_reconciliation_report_identifies_stale_coverage`, `test_reconciliation_report_identifies_unknown_coverage`, `test_reconcile_specific_source_no_coverage`
- **Regional coverage**: `test_regional_breakdown_identifies_missing_regions`, `test_regional_breakdown_complete_coverage`, `test_regional_counts_remain_none_with_only_global_record_ids`, `test_regional_counts_preserve_empty_rows`
- **Multiple sources**: `test_multiple_nationwide_sources_aggregate_regional_coverage`
- **Validation logic**: `test_full_ingest_validation_fails_on_incomplete_nationwide`, `test_full_ingest_validation_fails_on_governance_blocked`, `test_full_ingest_validation_allows_lax_requirements`, `test_validation_respects_max_stale_threshold`, `test_warnings_for_non_critical_issues`
- **Reconciliation functions**: `test_reconcile_specific_source_missing_from_inventory`, `test_reconcile_specific_source_below_minimum`, `test_reconcile_specific_source_adequate_coverage`, `test_reconcile_specific_source_rejected_state`
- **Quality metrics**: `test_quality_metrics_missing_denominator_returns_unknown`, `test_quality_metrics_valid_denominator_computes_rate`, `test_quality_metrics_rejects_negative_counts`, `test_quality_metrics_rejects_impossible_numerator`, `test_quality_metrics_included_in_report`, `test_quality_metrics_invalid_creates_gap`
- **Public projection**: `test_public_dict_contains_metadata_only`

All tests use `_entry()` and `_receipt()` fixture builders with dataclass `replace()` pattern for deterministic synthetic data.

## Relationship to P1 baseline

This P2 contract deliberately extends rather than duplicates the existing P1 coverage reporting in `official_source_inventory.py`:

- **P1**: `build_official_coverage_report()` - Core coverage state aggregation
- **P2**: `build_reconciliation_report()` - Reconciliation-specific gap detection and validation

The P2 contract calls P1 functions and adds reconciliation semantics without modifying P1 boundaries.

## External gates and boundaries

This contract maintains explicit boundaries:

- **No live nationwide coverage claims**: The contract validates coverage but does not assert live nationwide availability
- **No mock normal path**: The implementation uses synthetic fixtures and does not mock external services
- **Database comparison as metadata only**: `CoverageQualityMetrics.db_comparison_count` and `db_comparison_status` are metadata fields, never DB calls
- **17-province gate deterministic**: Complete only when all expected region codes are explicitly present in accepted usable coverage

## Verification

All 38 unit tests pass with synthetic fixtures. No external dependencies, network calls, or database operations. The contract is fully deterministic and offline-only. All ruff checks pass with clean formatting and no unused imports.

## Follow-up work

This contract is designed to be consumed by a future approved full-ingest dry run. The validation thresholds can be configured per deployment requirements. Quality metrics can be supplied when explicit denominators are available.

## Final hardening (2026-08-05)

An independent audit identified remaining hardening issues. All have been fixed:

1. **Unused local removed**: Deleted `source_status_by_region` unused dict and `defaultdict` import. Ruff now passes clean.

2. **Bounded category validation**: Added `CANONICAL_QUALITY_CATEGORIES` frozen set enforcing the six public categories (`attraction`, `culture_venue`, `lodging`, `restaurant`, `shopping`, `transport`). Rejects unknown/secret-shaped keys and negative category counts with generic safe validation error. CoverageGap descriptions no longer include raw exception text. Added tests for unknown category and negative category count.

3. **Denominator-safe quality rates**: Added `duplicate_rate`, `quarantined_rate`, and `failed_validation_rate` to `CoverageQualityMetrics`. Computed only when `total_quality_checked > 0`, otherwise `None`/unknown. Rates included in public projection. Added tests for valid/zero/missing denominators.

4. **Immutable nationwide gate**: Defined `CANONICAL_NATIONWIDE_REGIONS` 17-code tuple as module constant. Used as default for `build_reconciliation_report()` and regional breakdown. Non-canonical `expected_regions` creates `scope_mismatch` gap and marks `nationwide_coverage_complete=False`. Added test proving reduced custom region lists cannot approve nationwide coverage. Preserves all 17 canonical regions in breakdown.

5. **Five states preserved**: All state distinctions remain distinct across summary, validation, and output. `total_source_scoped_record_count` remains honest with `None` regional counts when no per-region evidence exists. No proportional/inferred logic reintroduced.

6. **Pure aggregate metadata**: `CoverageQualityMetrics` contains no raw rows, URLs, coordinates, provider payloads, or credentials. No DB/network/filesystem behavior. Invalid metrics use generic `quality_metrics_invalid` reason without raw exception strings.

7. **File hygiene**: Removed trailing whitespace and ensured exactly one final newline in devlog and both Python files.

## Verification

All verification commands pass offline:
- `uv run pytest apps/api/tests/test_official_coverage_reconciliation.py -q` - 38 tests pass
- `uv run pytest apps/api/tests -q` - All tests pass
- `uv run ruff check .` - Clean
- `uv run ruff format --check .` - Clean
- `uv run pre-commit run --all-files` - Clean
- `git diff --check origin/main...HEAD` - Clean

The implementation is ready for final commit. GitHub CI status will be checked after push.
