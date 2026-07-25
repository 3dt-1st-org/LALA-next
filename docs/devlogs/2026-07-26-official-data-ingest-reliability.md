# 2026-07-26 — Official Static/Source Ingestion Reliability

Branch: `geondongkim/official-data-ingest-reliability` (Draft PR, off `origin/main`).
Spec: `docs/planning/official-data-ingest-reliability-implementation.md`.

## What landed

A clean-room slice that hardens the five official-source ingests (TourAPI,
KCISA culture info, KOPIS, Gyeonggi card spending, 공정위 franchise brand
reference) plus the franchise-identity batch against one reliability contract,
without any external API call, file download, DB migration apply, or mock data.

Shared primitives (new focused modules):

- `apps/api/app/services/official_source_errors.py` — typed, fixed-reason
  `OfficialSourceError` (`auth`, `http_status`, `malformed_response`, `empty`,
  `window_too_wide`, `unavailable`). Upstream `resultMsg`/`SERVICE_KEY`-bearing
  text is consumed only to classify the category and is never echoed.
- `apps/api/app/services/official_source_receipts.py` — replay-safe
  `ingest.source_files` receipts by `(source_name, dataset_name, file_sha256)`
  via a pre-flight SELECT guarded by a transaction-scoped advisory lock (there
  is no unique constraint to rely on until canonical 063 applies), plus
  `reconcile_partial_run`.
- `apps/api/app/services/official_ingest_validation.py` — coordinate bounds
  (`[-90,90]`/`[-180,180]`, `(0,0)` null-island drop) and a bounded
  `OfficialRejectionCounter`.

Per-source changes (all reuse existing tables/columns):

- **Idempotency/replay**: tour_api, culture_info, kopis, and franchise_reference
  now write a replay-safe receipt and short-circuit redundant fact upserts when
  the fetch fingerprint is unchanged. card_spending already had this; it is now
  covered by an explicit replay test.
- **Pagination/partial-run integrity**: tour_api reads `totalCount` and flags
  `partial_run` when collected < total; culture_info compares its existing total
  to collected; franchise_reference reconciles parsed vs total. KOPIS reports no
  total, so it honestly surfaces `total_count=null` and `partial_run=false`
  (unknown, not "complete"). A partial upstream response is never presented as a
  complete catalog.
- **Validation/rejection counters**: invalid coordinates (out of bounds),
  missing required fields, unmapped categories, and non-allowlisted image URLs
  are rejected and counted with a bounded summary reason.
- **Image URL policy**: `official_media.official_image_url_or_none` stores
  allowlisted official-source image hosts only (`tong.visitkorea.or.kr`,
  `www.culture.go.kr`, `www.kopis.or.kr`), upgrades http→https, and drops
  non-official hosts and non-http(s) schemes. No images are downloaded or
  generated. The read-path `normalize_official_image_url` stays lenient so
  legacy rows still render.
- **Bounded failures**: every `_raise_for_error`/`_extract_items`/`_fetch_page`
  now raises `OfficialSourceError` instead of embedding raw upstream text
  (KOPIS's `SERVICE_KEY` auth text no longer leaks).
- **Job-run audit**: tour_api, franchise_reference, and franchise_identity now
  record `ops.job_runs` on apply (culture/kopis/card already did).
- **Nationwide honesty**: Gyeonggi defaults are explicitly labeled in the
  TourAPI plan payload; production sweeps use the shared `region_catalog`. No AI
  translation was introduced.
- **Card/franchise are decision-input/provenance only**: `chain_scale_score` is
  a deterministic transform of upstream store count; `main_product` stays
  `None`; no fabricated consumer classification.

## Unapplied additive SQL

`sql/canonical/063_official_source_provenance.sql` documents the schema gap and
is **kept unapplied** (`ADD COLUMN IF NOT EXISTS` / `CREATE UNIQUE INDEX IF NOT
EXISTS` only; non-destructive): adds `source_url`, `row_count`, `status`,
`source_updated_at`, `schema_version` and a receipt-identity unique index to
`ingest.source_files`, and an `image_url` column to `culture.events`. Runtime
code does not depend on these columns; they await a separate
`ALLOW_CANONICAL_SQL_APPLY=1` rollout.

## External blockers (documented, not invented)

- **Card spending nationwide**: only Gyeonggi is drop-in. Other regions are
  adapter-pending, license-restricted, or have no pinned raw URL. Non-Gyeonggi
  `local_spending_score` stays NULL — never inferred, copied, or mocked.
- **Live API access**: TourAPI/KCISA/KOPIS/공정위 keys are approved-but-gated;
  no live calls were made in this slice.
- **Source file download**: card-spending raw files are an operator step; this
  slice parses already-present files only.
- **DB apply**: `063_*.sql` is not applied here.
- **English enrichment**: explicitly deferred — no AI translation introduced.
- **`culture.events` image column**: blocked on the unapplied SQL; until then
  KOPIS posters / KCISA thumbnails are carried in the result payload only.

## Verification

Focused boundary tests added at every changed boundary
(`test_official_source_errors.py`, `test_official_source_receipts.py`,
`test_official_ingest_validation.py`, `test_official_media.py`, plus extended
tour/culture/kopis/card/franchise suites): replay-safe receipts, partial-run
flags, coordinate/category/image validation, bounded errors with no raw upstream
text leak, replay idempotency, non-Gyeonggi no-fabrication, and the restaurant
category-preservation guard. ruff clean; `063_*.sql` is non-destructive.
