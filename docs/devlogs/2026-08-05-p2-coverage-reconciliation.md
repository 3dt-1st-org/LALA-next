# 2026-08-05 — P2 Official-Data Coverage Reconciliation Contract

Branch: `geondongkim/lala-p2-official-data-coverage-reconciliation` (Draft PR, off `origin/main`).

## What landed

A focused P2 coverage reconciliation contract that extends the existing P1 coverage baseline with reconciliation-specific semantics for full-ingest preparation. The implementation is deliberately offline-only, provider-neutral, and reuses existing inventory/governance/receipt semantics.

Core implementation (`apps/api/app/services/official_coverage_reconciliation.py`):

- **`build_reconciliation_report()`**: Aggregates P1 coverage reports with reconciliation-specific gap detection
  - Tracks `usable`, `blocked_external`, `stale`, `unknown` source states
  - Detects governance gaps, stale coverage, missing coverage, and scope mismatches
  - Computes regional breakdown across 17 provinces (seoul, gyeonggi, incheon, busan, daegu, gwangju, daejeon, ulsan, sejong, gangwon, chungbuk, chungnam, jeonbuk, jeonnam, gyeongbuk, gyeongnam, jeju)
  - Returns JSON-safe `ReconciliationReport` with public projection

- **`validate_full_ingest_dry_run()`**: Validates reconciliation reports against configurable thresholds
  - `require_nationwide_coverage`: Enforce complete 17-province coverage
  - `require_all_sources_usable`: Zero-tolerance for blocked/stale sources  
  - `max_stale_sources`: Configurable threshold for stale source tolerance
  - Returns `FullIngestDryRunValidation` with pass/fail determination and specific blockers

- **`reconcile_receipt_coverage()`**: Lightweight receipt-to-source reconciliation
  - Matches receipts to inventory entries by `(source_name, dataset_name)`
  - Returns coverage summary with gap detection

Dataclasses (frozen, immutable contracts):

- **`CoverageGap`**: Individual gap instances with type classification
- **`RegionalCoverageBreakdown`**: Per-region coverage summaries  
- **`ReconciliationReport`**: Top-level reconciliation aggregation
- **`FullIngestDryRunValidation`**: Validation result with blockers/warnings

## Design principles

1. **Provider-neutral**: No provider-specific logic or API calls
2. **Offline-only**: Pure function contracts with no side effects (no network, DB, filesystem, environment, subprocess)
3. **Reuse existing semantics**: Builds on P1 `OfficialSourceInventory`, `OfficialCoverageReceipt`, `SourceGovernance`
4. **Honest reporting**: Distinguishes `usable`, `blocked_external`, `rejected`, `stale`, `unknown` states
5. **17-province model**: Full administrative coverage for South Korea regions
6. **JSON-safe output**: All public projections use primitive types

## Comprehensive offline testing

Added `apps/api/tests/test_official_coverage_reconciliation.py` with 18 focused unit tests using synthetic in-memory fixtures:

- **Source counting**: `test_counts_usable_sources`, `test_counts_blocked_stale_unknown_sources`, `test_total_distinct_records_aggregates_all_sources`
- **Governance gaps**: `test_detects_governance_blocked_sources`, `test_detects_stale_sources`
- **Coverage gaps**: `test_detects_no_coverage_gaps`, `test_reconcile_specific_source_no_coverage`
- **Regional coverage**: `test_regional_coverage_aggregation`, `test_nationwide_coverage_complete`, `test_nationwide_coverage_incomplete`
- **Validation logic**: `test_validation_fails_on_blocked_sources`, `test_validation_allows_usable_sources`, `test_validation_respects_max_stale_threshold`, `test_validation_requires_nationwide_coverage`
- **Reconciliation functions**: `test_reconcile_receipt_coverage_basic`, `test_reconcile_missing_receipt`, `test_reconcile_stale_detection`

All tests use `_entry()` and `_receipt()` fixture builders with dataclass `replace()` pattern for deterministic synthetic data.

## Relationship to P1 baseline

This P2 contract deliberately extends rather than duplicates the existing P1 coverage reporting in `official_source_inventory.py`:

- **P1**: `build_official_coverage_report()` - Core coverage state aggregation
- **P2**: `build_reconciliation_report()` - Reconciliation-specific gap detection and validation

The P2 contract calls P1 functions and adds reconciliation semantics without modifying P1 boundaries.

## Verification

All 18 unit tests pass with synthetic fixtures. No external dependencies, network calls, or database operations. The contract is fully deterministic and offline-only.

## Follow-up work

This contract is designed to be consumed by a future approved full-ingest dry run. The validation thresholds can be configured per deployment requirements.