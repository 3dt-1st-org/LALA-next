# P1-3 Source-Governance Registry + Accepted-Fixture Registry (offline contract)

Date: 2026-07-30 KST
Role: implementation (single slice)
Base: `origin/main` `3fd52b55061511e5827979623c54f3be6e52478f` (after PR #81)
Branch: `geondongkim/lala-p1-3-source-governance-registry`

This slice adds two offline registries and one SSOT cleanup. It performs **no**
network, crawl, DB write, migration apply, seed, deploy, AI/TTS, or secret
access. It does not promote any source to live-approved.

## Status

### CURRENT

- `tour_api_ingest.DEFAULT_DATASET_NAME` is the single source of truth for the
  TourAPI dataset name. `TourApiFetchResult.dataset_name` and the
  `official_source_adapters._SOURCE_DEFINITIONS["tour_api"]` entry both
  reference this constant; the duplicated literal is removed.
- The existing official-source inventory/adapters/receipts/errors contracts on
  `main` remain unchanged in their public behavior.
- Canonical SQL remains the 13-file baseline ending at
  `063_local_signals_contract.sql`; this PR adds no migration.

### DRAFT_PR

- `official_source_registry.py` declares the five official sources
  (`tour_api`, `kcisa`, `kopis`, `fair_trade_commission`, `data_portal`) by
  reusing the raw inventory types (`OfficialSourceInventory`,
  `SourceGovernance`, `SourceRefreshPolicy`, `SourcePaginationPolicy`,
  `SourceRecordIdentityPolicy`, `ImageUrlPolicy`, `PlaceAcceptancePolicy`).
  Each entry carries governance, refresh, pagination, identity, and image-URL
  policy.
- `accepted_fixture_registry.py` registers test-only synthetic fixtures with
  explicit provenance (`origin=synthetic`, `approval=approved`,
  `intended_use=test_only`). Unregistered fixtures fail closed on resolve.

### BLOCKED_EXTERNAL (honest gate)

Every declared source has `live_ingest_status = "blocked_external"` and
`governance.source_status = "blocked_external"`. License, terms, retention,
provenance are `None` (not confirmed) and `image_rights_status = "unknown"`.
`is_live_ingest_permitted(source)` returns `False` for all sources, and
`assert_live_ingest_permitted(source)` raises (fail-closed) for all sources and
for any unregistered source. Promotion to live-approved requires external
confirmation of source terms, license, retention, image rights, provenance, and
a separate live-ingest slice; it is out of scope for this PR.

The offline-normalization gate is separate:
`offline_normalization_status = "approved"` for the five registered sources
(the P1-2 adapter owns the actual synthetic-fixture normalization), and only
for registered sources.

## Changed files

New:
- `apps/api/app/services/official_source_registry.py`
- `apps/api/app/services/accepted_fixture_registry.py`
- `apps/api/tests/test_official_source_registry.py`
- `apps/api/tests/test_accepted_fixture_registry.py`
- `docs/planning/p1-3-source-governance-registry.md`

Modified:
- `apps/api/app/services/tour_api_ingest.py` — add `DEFAULT_DATASET_NAME`;
  `TourApiFetchResult.dataset_name` default references it.
- `apps/api/app/services/official_source_adapters.py` —
  `_SOURCE_DEFINITIONS["tour_api"]` imports `tour_api_ingest.DEFAULT_DATASET_NAME`
  (literal removed).

## Verification

Commands run from the worktree root (`uv sync --extra dev` first):

```bash
uv run pytest apps/api/tests -p no:warnings       # 1160 passed
uv run ruff check . && uv run ruff format --check .
uv run pre-commit run --files <changed files>
git diff --check
```

- Full API suite: **1160 passed** (baseline 1124 + 19 registry + 17 fixture);
  zero regressions.
- New registry tests: 19 passed. New fixture-registry tests: 17 passed.
- Adapter tests (14) and tour_api tests still pass after the SSOT change.
- `ruff check` and `ruff format --check` clean on changed files.
- `detect-secrets` (via pre-commit baseline) clean.
- `git diff --check` clean.

Test matrix coverage:

- The registry contains exactly the five sources and each entry validates
  governance/refresh/pagination/identity/image policy.
- Unknown source → rejected; live-ingest gate returns `unknown_source`.
- Every source is honestly `blocked_external` for live (no falsely approved
  source, no verified image rights, no invented license/terms).
- Accepted-fixture registry: unregistered fixture fails closed on resolve;
  secret-shaped payloads and raw-review/author/credential fields are rejected;
  registration is idempotent and tamper-resistant (deep copy + drift rejection).

## Safety

- No live AI/TTS, external API/crawl, DB apply/seed, deploy, or device run.
- No secret value was read, output, copied, or committed (.env / token / DSN /
  ARN / logs untouched). `detect-secrets` baseline passes.
- No mock/demo/invented coverage or invented approval was connected to the
  normal user path; the registries are offline contracts only.
- Diff/logs/fixtures contain no secret, PII, or raw review body.

## Remaining

- Merge dependency: this Draft PR is based on `origin/main=3fd52b5` (PR #81
  merged) and depends on no other open Draft PR.
- External blockers (unchanged): source terms/license/retention, image rights,
  provenance, DB owner/apply window, AI/TTS cost ceiling, travel-time/opening-
  hours authority.
- Next slice (TARGET): a live-ingest slice that consumes
  `assert_live_ingest_permitted` before any acquisition; it may not ship until
  the external blockers above are resolved and a source is promoted to
  `approved` by its owner.
