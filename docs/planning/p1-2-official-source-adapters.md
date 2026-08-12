# P1-2 Official Source Parser/Normalizer Contract

Date: 2026-07-28 KST
Base: `origin/main` `a96a0b641bb2ae80663a50ada633bf10e94c3aa1`
Branch: `geondongkim/lala-source-parser-normalizer-p1-2`

This slice creates one offline adapter boundary over the existing official
source parsers. It accepts compact supplied fixtures only; it does not acquire,
persist, seed, publish, or expose real source data.

## Status

### CURRENT

- Existing source ownership remains in `tour_api_ingest.py`,
  `culture_info_ingest.py`, `kopis_ingest.py`,
  `franchise_reference_ingest.py`, and `card_spending_ingest.py`.
- Existing `official_source_receipts.py` and `official_source_errors.py`
  remain the receipt and bounded-error boundaries.
- Canonical SQL remains the 13-file baseline ending at
  `063_local_signals_contract.sql`; this PR adds no migration.

### IMPLEMENTED_NOT_RUNTIME_VERIFIED

Merged PR #81 (head 3fd52b5). `official_source_adapters.py` defines one typed
`normalize_official_source_fixture` contract and maps these registered source
names to existing pure parsers and domain models:

| Source | Adapter kind | Existing parser/domain boundary |
|---|---|---|
| `tour_api` | `tourism_place` | `parse_tour_api_place` / `TourApiPlace` |
| `kcisa` | `culture_event` | `parse_culture_info_events` / `CultureInfoEvent` |
| `kopis` | `performance_event` | `parse_kopis_performances` / `KopisPerformance` |
| `fair_trade_commission` | `franchise_reference` | `parse_brand_stats_items` / `FranchiseBrandReference` |
| `data_portal` | `card_spending_aggregate` | `_parse_row` and existing aggregate dimensions |

The adapter output is `NormalizedOfficialRecord` and
`SourceNormalizationResult`. It preserves source identity, deterministic
dedupe hash, source freshness timestamps, language, category, coarse region,
coordinate precision, image-rights status, and bounded rejection reasons.
Only explicit public fields are copied. Raw provider mappings/XML, reviews,
authors, credentials, provider URLs, and RAG-shaped fields never enter the
output.

The adapter has no network, DB, subprocess, environment, fetch, or upsert
path. A malformed, unknown, unsafe, or incomplete fixture returns an explicit
rejected/incomplete result and never invents a count, coverage claim, image
permission, or usable record.

### TARGET

- P1-3 may define a source-governance review and accepted fixture registry only
  after this PR is independently reviewed and merged.
- Live source ingestion remains a separate future slice consuming accepted
  receipts and normalized records; it is not implied by this adapter.

### BLOCKED_EXTERNAL

- Source terms, license, retention, image rights, provenance, and data-file
  access are required before live ingest.
- A DB owner, backup/rollback plan, and apply window are required before any
  persistence or migration decision.
- Provider/API quotas and cost ceilings are required before AI/TTS or bulk
  processing.
- Travel-time and opening-hours authority remains required before planner
  rollout.

## Safety and fixture contract

Fixtures are small synthetic JSON-like mappings, XML-like strings, or row
sequences that contain only documented structural fields. They are test-only
inputs and are not connected to startup, API routes, workers, Flutter,
Local Signals, RAG, docent, planner, or score displays.

The adapter rejects unknown sources, malformed shapes, missing identities,
personal-precise coordinate declarations, non-HTTPS or non-allowlisted image
URLs, unverified image rights when an image is present, unsupported languages,
raw review/author/provider fields, and secret-shaped values. Duplicate source
rows are aggregated or deduplicated according to the source's stable identity
dimensions.

Daangn scraping is rejected. Raw review retention is prohibited. Approved
Naver Blog API or other lawful licensed review evidence remains a separate
future review/mention aggregate pipeline and is not accepted by this adapter.
