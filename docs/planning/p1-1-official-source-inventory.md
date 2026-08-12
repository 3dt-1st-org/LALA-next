# P1-1 Official Source Inventory and Coverage Contract

Date: 2026-07-28 KST
Base: `origin/main` `46eebed122aa7b76bba4be23d120d43e3638713c`
Branch: `geondongkim/lala-official-source-inventory-p1-1`

This is an offline contract for preparing governed official-data ingestion. It
does not acquire data, call providers, write database rows, or wire synthetic
records into a user flow.

## Status vocabulary

- `CURRENT`: merged and verified through the production path. This slice does
  not promote anything to `CURRENT` because live/runtime verification is out of
  scope.
- `DRAFT_PR`: present only in the independent P1-1 Draft PR.
- `TARGET`: the next approved contract or implementation slice.
- `BLOCKED_EXTERNAL`: requires an owner, terms, data access, credentials, cost
  decision, or a prohibited runtime operation.

## Contract

`apps/api/app/services/official_source_inventory.py` defines one typed,
provider-neutral inventory and receipt contract. It reuses the identity of the
existing `ingest.source_files` receipt concept (`source_name`, `dataset_name`,
content fingerprint, and observed time) without creating a competing table or
migration.

An inventory declares:

- source purpose and the fields allowed in a public projection;
- license/terms, retention, provenance, and image-rights readiness;
- refresh cadence and freshness SLA;
- page-cursor, offset, snapshot, or date-window semantics;
- stable source-record fields and deterministic dedupe fields;
- place identity, category, nationwide/coarse-region scope, coordinate
  precision, KO/EN localization, and HTTPS image URL policy.

The report distinguishes `usable`, `blocked_external`, `rejected`, `stale`, and
`unknown`. `approved` governance is an internal prerequisite, not a public
readiness state. Missing governance fails closed. Explicitly rejected sources,
unsafe coordinate precision, unverified image rights, unsupported languages,
and invalid receipt metadata cannot produce coverage.

## Deterministic report rules

- No accepted receipt means `unknown` coverage, no record count, and no claim
  of approval, image permission, or nationwide coverage.
- Receipts are normalized by source/dataset and SHA-256 content fingerprint;
  duplicate fingerprints and duplicate record IDs do not inflate coverage.
- A receipt with no proven record list keeps the count unknown rather than
  treating an absent count as zero.
- An accepted receipt outside the freshness SLA remains `stale`.
- Mixed receipt scopes become `unknown` instead of being upgraded to
  nationwide.
- `to_public_dict()` contains inventory and coverage metadata only. It omits
  source record IDs, fingerprints, provider payloads, raw review text, author
  identity, precise location, and private credentials.
- Raw review bodies and third-party review identity/URL fields are rejected at
  projection and stable-identity boundaries. They are not an input or output
  of this slice, and no RAG/docent path is changed.

## Existing ownership and source boundaries

The existing source-specific boundaries remain authoritative: Tour API and
culture/KCISA place or event services, KOPIS event data, official franchise
reference data, and aggregate card-spending data. Their existing receipt and
bounded-error services remain the persistence/error concepts. The pending
operator SQL file `sql/operator-pending/063_official_source_provenance.sql` is
not canonical, is not edited, and is not applied here.

This PR does not implement Naver collection, crawling, Daangn scraping, review
ingestion, AI classification, translation, bulk ingest, or any external source
call. Approved Naver Blog API or other lawful licensed review evidence remains a
separate future review/mention aggregate pipeline; raw third-party content is
not part of Local Signals, RAG, docent, or operational logs.

## Tests and fixture boundary

`apps/api/tests/test_official_source_inventory.py` uses synthetic in-memory
dataclass fixtures only. It covers normalization, deterministic identity,
duplicate receipt handling, missing governance, unknown/stale/blocked/rejected
states, unsafe image and coordinate policy, and metadata-only output. The
fixtures are not seeds, startup data, API responses, or normal user-flow data.

## Gate status

| Area | Status | Evidence or next condition |
|---|---|---|
| P1-1 offline inventory/report contract | `IMPLEMENTED_NOT_RUNTIME_VERIFIED` | Merged PR #80 (head a96a0b6); code/tests present, real runtime path not verified |
| Nationwide official inventory | `TARGET` | Requires accepted source governance, data access, cursor, and coverage policy |
| Live official ingestion | `BLOCKED_EXTERNAL` | Requires terms/license, retention, image rights, owner, and explicitly authorized execution |
| Canonical SQL change | `CURRENT` | No migration was needed; 063 baseline remains unchanged |
| P1-2 | `TARGET` | Source-specific offline parser/normalizer contract after P1-1 review/merge; no live ingest |

Release gates preserved from the handoff:

- #76: merge only after independent review in a controlled main-deploy window.
- #77: merge only after exact-head Flutter web and real-device smoke.
- #78: merge only after AWS IAM logical-secret inventory and canary /readyz.
- source terms/provenance before live ingest;
  DB owner/backup/apply before migration;
  AI/TTS quota/cost before live batches;
  travel-time/opening-hours authority before planner rollout.
- Daangn scraping is rejected. Raw review retention is prohibited.
