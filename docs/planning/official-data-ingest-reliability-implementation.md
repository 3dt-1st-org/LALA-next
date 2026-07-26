# Official Static/Source Ingestion Reliability — Clean-Room Implementation

Last updated: 2026-07-26 KST
Branch: `geondongkim/official-data-ingest-reliability` (Draft PR, off `origin/main`)

This is a clean-room slice that hardens the **official static/source ingestion
lane** — TourAPI (Korean Tourism Organization), KCISA culture info, KOPIS
performing arts, Gyeonggi card-spending, and 공정위 franchise brand reference —
against one reliability contract. It builds real code/tests/docs gaps surfaced by
a source-by-source comparison. It does **not** call any external API, download any
file, apply any database migration, or invent any data.

## Mission and Non-Negotiables

Hard constraints (carry forward from the slice brief):

- No live external API call, no file download, no DB migration apply, no
  production deploy, no cloud changes, no secrets exposed or inspected.
- No mock/demo/static runtime fallback in the normal data path. Plan/preview are
  read-only and honest — an empty or partial upstream response is reported as
  such, never dressed up as a complete catalog.
- Reuse existing canonical tables and columns. Schema changes are additive
  operator-pending SQL **outside `sql/canonical/`** (never run against a live DB
  in this slice). Runtime code must not depend on pending columns.
- Keep public CLI payloads and wrapper-script contracts stable. The guarded
  plan/preview/apply style and `ALLOW_*_APPLY=1` + `--confirm APPLY_*` gates stay.
- Standard OpenAI only where AI is involved (not in this slice — no AI lane is
  touched here). Never print `DB_DSN`, `PUBLIC_DATA_SERVICE_KEY`, `KOPIS_API_KEY`,
  or any upstream raw response text.
- LALA AI policy is unchanged; this slice introduces no AI translation. English
  enrichment remains explicitly deferred.

## Legacy Reference — Retained vs. Rejected

Read-only source: `/Users/geondongkim/3dt-1st-Project`. The official lane is
mostly net-new in LALA-next; only the TourAPI-events and card-spending legacy
scripts exist there.

| Legacy behavior | Decision | Reason |
|---|---|---|
| TourAPI `totalCount`-based page stop (`fetch_tourapi_events.py`) | **Retain** | Stops paging once `len(rows) >= totalCount`; the honest termination signal. Generalize to tour_api/kcisa/kopis. |
| Card-spending staging-then-insert load shape | **Retain** | Stage → hash → insert is sound; LALA-next already re-derives it in Python with SHA-256 dedup. |
| Restaurant license-master provenance (`gg_restaurant_info`) | **Retain concept** | `primary_source = data_portal` + business-status + category is the honest base. |
| `classify_tourist_indoor.py` "only fill NULLs" idempotency | **Retain shape** | Idempotent per-key enrichment; LALA-next re-derives `is_indoor` with model+prompt version. |
| `TRUNCATE`-then-bulk-INSERT (events, card) | **Reject** | Destroys append-only history and provenance; LALA-next upserts with stable identity keys. |
| Manual test-event `INSERT`s for Suwon + `redate_events_2026.py` | **Reject** | Fabrication for demo currency. LALA-next reports honest empty/partial state. |
| Region hard-filters (`DELETE … WHERE sigun_nm NOT IN (수원,평택,용인)`) | **Reject** | No Gyeonggi-only assumption; nationwide is opt-in via shared `region_catalog`. |
| City parsed from filename suffix (`load_gyeonggi_card_spending.sh`) | **Reject** | Fragile; LALA-next maps region from inside the row. |
| Naver blog raw review scrape + raw-text embed | **Reject** | ToS/privacy; LALA-next uses aggregated attributes only (review lane, separate PR). |
| KCISA / KOPIS / franchise ingest | **Net-new** | Absent in legacy; LALA-next owns it. |

## Per-Source Gap Table (current state, from the comparison)

`Y` = present and correct · `P` = partial · `N` = absent/risky · `—` = not applicable

| Dimension | tour_api | culture_info (KCISA) | kopis | card_spending | franchise_reference |
|---|---|---|---|---|---|
| Per-source provenance (`primary_source`/`source_record_id`) | Y | Y | Y | Y | Y |
| `ingest.source_files` receipt on every pull | P (plain INSERT) | P (plain INSERT) | P (plain INSERT) | Y (sha dedup) | **N (none)** |
| Replay-safe receipt (no duplicate row/run) | **N** | **N** | **N** | Y | **N** |
| Upstream freshness carried to operator | N (modifiedtime dropped) | N | P (date window only) | Y (file sha) | N |
| Pagination `totalCount` honored | N (breaks on page len) | P (read, not compared) | N (no total) | — | P (page-stop only) |
| Partial-run never shown as complete | **N** | **N** | **N** | Y (row reconciliation) | **N** |
| Coord bounds validation | **N** | **N** | — | — | — |
| Rejected-row counter (parse failures) | **N** (silent None) | **N** (silent None) | **N** (silent None) | Y | Y |
| Image URL forward-only + host allowlist | P (scheme upgrade only, any host) | P | P | — | — |
| Image persisted for events | — | **N (no column)** | **N (no column)** | — | — |
| Bounded failures (no raw upstream text) | **N** (raw resultMsg) | **N** (raw resultMsg) | **N** (raw + SERVICE_KEY text) | P | **N** (raw resultMsg) |
| `ops.job_runs` audit on apply | **N** | Y | Y | Y | **N** |
| Nationwide region (no Gyeonggi default) | P (opt-in flag) | P (opt-in flag) | P (opt-in flag) | P (Gyeonggi map; extensible) | Y (year-based) |
| No fabricated classification/signal | Y | Y | Y | Y (pass-through aggregates) | Y (chain_scale is a transform) |
| Restaurant food/cuisine filter introduced | **No** (preserved) | — | — | — | — |

## The Reliability Contract (what "done" means per source)

Every official ingest must satisfy, within the existing schema and CLI shape:

1. **Provenance** — `primary_source` + `source_record_id` per row, plus an
   `ingest.source_files` receipt per pull that records source/dataset, a
   content/file SHA-256, and a retrieval timestamp.
2. **Idempotency/replay** — re-running the same pull against unchanged upstream
   data must not duplicate the receipt and must upsert fact rows deterministically.
   Identity keys: tour_api `tour-api-{content_id}`, kcisa `kcisa-culture-info-{seq}`,
   kopis `kopis-{mt20id}`, franchise `{year}:{hq}:{brand}`; receipts by
   `(source_name, dataset_name, file_sha256)`.
3. **Pagination/partial-run integrity** — when the upstream reports a total,
   paging stops at the total; if the collected count is below the total, the
   result is flagged `partial_run=true` and never presented as a complete catalog.
4. **Nationwide region integrity** — production sweeps use the shared
   `region_catalog` (all 17 ROK provinces); Gyeonggi defaults are explicit and
   labeled, never hidden. No AI translation.
5. **Validation/rejection counters** — invalid coordinates (lat outside
   `[-90, 90]`, lon outside `[-180, 180]`), unparseable dates, unmappable
   categories, and bad image URLs are rejected and counted with bounded reasons;
   no raw row text or secret leaks.
6. **Image URL handling** — store/forward **allowlisted official-source URLs
   only**; never download or generate images. Non-allowlisted hosts are dropped.
7. **Dry-run/plan interface** — plan states exactly what it can and cannot mutate,
   the image policy, validation bounds, and the region scope; no static/mock
   fallback in normal runtime.
8. **Card spending & franchise reference are decision-input/provenance only** —
   no fabricated business classifications or consumer signals. `chain_scale_score`
   stays a deterministic transform of upstream store count.
9. **Restaurant recommendations** — no new food/cuisine filtering requirement;
   existing category and evidence policies are preserved.
10. **External blockers documented** — approved-but-unavailable API access, source
    file download/operator steps, and actual DB apply are listed as blockers, not
    completed by invention.

## Bounded Implementation Scope

Work is grouped into small, independently-testable commits. All runtime changes
reuse existing tables/columns; the only new SQL is an additive operator proposal
under `sql/operator-pending/`, outside the canonical runner.

### I1 — Shared reliability primitives (new focused modules)

- **`apps/api/app/services/official_source_errors.py`** (new): a typed bounded
  failure contract. `OfficialSourceError(category, *, source)` where
  `category ∈ {auth, http_status, malformed_response, empty, window_too_wide,
  unavailable}` carries a **fixed** human reason string (never the raw upstream
  `resultMsg`). A `raise_for_official_response` helper maps non-zero upstream
  codes and `SERVICE_KEY`-bearing text to the `auth` category without echoing the
  key or message. This is the single chokepoint that keeps upstream text out of
  operator-facing payloads.
- **`apps/api/app/services/official_source_receipts.py`** (new): replay-safe
  `ingest.source_files` recording. `record_official_source_receipt(conn, *,
  source_name, dataset_name, file_name, file_sha256, local_path=None)` does the
  pre-flight `(source_name, dataset_name, file_sha256)` SELECT (the
  card_spending pattern — there is no unique constraint to `ON CONFLICT` on) and
  returns `(source_file_id, replayed)`. Also a `reconcile_partial_run(*, total,
  collected)` helper returning a `{total, collected, partial_run}` dict.
- **`apps/api/app/services/official_ingest_validation.py`** (new): bounded input
  validators + a rejection counter. `validate_official_coordinate(lat, lon)` →
  `(lat, lon) | None` with `[-90,90]`/`[-180,180]` bounds; `OfficialRejectionCounter`
  tallies `{invalid_coordinate, invalid_date, unmapped_category, invalid_image_url}`
  with a single bounded summary reason (no raw row text).

### I2 — Forward-only image URL allowlist (`official_media.py`)

- Add `OFFICIAL_IMAGE_HOST_ALLOWLIST` (the official source hosts already known to
  `HTTPS_UPGRADE_IMAGE_HOSTS`, plus the API-bearing image hosts the lane actually
  serves). `normalize_official_image_url` becomes: drop non-http(s) schemes, then
  **require** an allowlisted host (after http→https upgrade), else return `None`.
  This is forward-only storage of allowed source URLs — no download, no generation.

### I3 — TourAPI (`tour_api_ingest.py` + `run_tour_api_ingest.py`)

- Pagination: read upstream `totalCount`; stop at total; surface `total_count`,
  `collected_count`, `partial_run`, and a `rejected_row_count` (parse-None rows
  + invalid coords + bad image URLs) in the result.
- Receipt: replace the plain `INSERT INTO ingest.source_files` with
  `record_official_source_receipt`; encode upstream `modifiedtime` into the
  deterministic `file_name` so a freshness change produces a new sha (and thus a
  new receipt) using only existing columns.
- Image: `_fill_missing_official_images` already only fetches a URL (not binary);
  route every stored URL through the new allowlist.
- Errors: `_extract_items` raises `OfficialSourceError`, not raw `resultMsg`.
- CLI: add `JOB_NAME` + `record_job_run` on apply success/failure; add
  `live_api_call` consistency; enrich plan payload with `image_policy`,
  `validation`, `region_scope`, and `cannot_mutate`.

### I4 — KCISA culture info (`culture_info_ingest.py` + runner)

- Pagination: it already reads `totalCount`; add the `collected vs total`
  comparison + `partial_run` + `rejected_row_count`.
- Receipt: replay-safe via `record_official_source_receipt`.
- Image: route `thumbnail_url` through the allowlist (note: `culture.events`
  has no image column today — see I7; the URL is carried in the result payload
  for the operator and for the future column).
- Errors: `_raise_for_error` → `OfficialSourceError`.

### I5 — KOPIS (`kopis_ingest.py` + runner)

- Pagination: extract upstream total from the XML; add `collected vs total` +
  `partial_run` + `rejected_row_count`.
- Receipt: replay-safe via `record_official_source_receipt`.
- Image: route `poster_url` through the allowlist.
- Errors: `_raise_for_error` → `OfficialSourceError`; the `SERVICE_KEY`-bearing
  auth text is mapped to the `auth` category without echoing the key.
- Runner dead expression at line 79 (`signgucodes[0] if … else "multi"`) removed.

### I6 — Franchise reference (`franchise_reference_ingest.py` + runner)

- Receipt: add an `ingest.source_files` receipt (currently writes none) via
  `record_official_source_receipt`, hashing the parsed JSON payload.
- Pagination: add a final `parsed vs total` reconciliation + `partial_run`.
- Errors: `_fetch_page` raw `ValueError(resultMsg)` → `OfficialSourceError`.
- CLI: add `JOB_NAME` + `record_job_run`; add execution-error redaction test
  (currently only the guard path is tested).
- Decision-input guard: `chain_scale_score` stays a deterministic transform;
  `main_product` stays `None` (never invented). A focused test asserts no
  fabricated consumer classification.

### I7 — Operator-pending additive SQL (`sql/operator-pending/063_official_source_provenance.sql`)

Documents the schema gap honestly and is **kept outside `sql/canonical/`**.
Non-destructive
(`ADD COLUMN IF NOT EXISTS` / `CREATE INDEX IF NOT EXISTS` only, so it passes the
shared destructive-statement safety test):

- `ingest.source_files`: add `source_url text`, `row_count integer`, `status text`,
  `source_updated_at timestamptz`, `schema_version text`. Plus a unique index on
  `(source_name, dataset_name, file_sha256)` to make replay dedup declarative.
- `culture.events`: add `image_url text` so KOPIS posters / KCISA thumbnails can
  be persisted (today they are dropped).

Runtime code in I3–I6 does **not** depend on these columns (apply still works on
the current applied schema); it carries the equivalent facts in result payloads
and in existing columns until this SQL is applied in a separate, gated rollout.

### I8 — Documentation

- Update `docs/data/data-dictionary.md` ingest sections where the contract
  changes (receipt replay, partial-run flag, image allowlist, validation
  counters, bounded failures).
- Update `docs/operations/nationwide-expansion-plan.md` to note the partial-run
  and image-allowlist hardening.
- A short devlog under `docs/devlogs/` recording what landed and the explicit
  external blockers.

## External Blockers (documented, not invented)

- **Card spending nationwide**: only Gyeonggi is drop-in. Seoul/Sejong/Gyeongnam
  need adapter confirmation; Busan's public metric is a daily average, not a
  monthly total; several regions are license-restricted (Chungnam prohibits
  commercial use/redistribution) or have no pinned raw URL. Non-Gyeonggi
  `local_spending_score` stays NULL — never inferred, copied, or mocked.
- **Live API access**: TourAPI/KCISA/KOPIS/공정위 keys are approved-but-gated;
  this slice adds no live calls. Operators run `--apply` in their own gated env.
- **Source file download**: card-spending raw files are an operator download
  step; this slice parses already-present files only.
- **DB apply / pending SQL**: `sql/operator-pending/063_official_source_provenance.sql`
  is not applied here and is not discovered by the canonical runner. It awaits
  a separately approved operator migration.
- **English enrichment**: explicitly deferred — no AI translation is introduced.
- **`culture.events` image column**: blocked on the pending SQL above; until
  then posters/thumbnails are carried in the result payload only.

## Test Matrix

Focused tests at every changed boundary (no live API/DB/secret exposure):

- `test_official_source_errors.py` — each category maps to a fixed reason; raw
  upstream `resultMsg` and `SERVICE_KEY`-bearing text never appear in the raised
  message; `redact_secret_text` round-trips.
- `test_official_source_receipts.py` — replay with the same sha returns the same
  `source_file_id` and `replayed=True`, inserts no duplicate row; a changed sha
  inserts a new row; partial-run reconciliation flags `partial_run` correctly.
- `test_official_ingest_validation.py` — coord bounds reject/accept correctly;
  `OfficialRejectionCounter` summarizes without raw row text.
- `test_official_media.py` (extend) — allowlisted host http→https retained;
  non-allowlisted host → `None`; non-http(s) scheme → `None`.
- Extend `test_tour_api_ingest.py` / `test_culture_info_ingest.py` /
  `test_kopis_ingest.py`: partial-run flag when collected < total;
  `rejected_row_count` increments on invalid coords/dates/category; image URL
  with a non-allowlisted host is dropped; replay-safe receipt (run twice → one
  row); bounded error raises `OfficialSourceError` with no raw upstream text;
  tour_api apply records a succeeded/failed `ops.job_runs`.
- Extend `test_franchise_reference_ingest.py`: receipt row written;
  execution-error redaction (not just the guard); partial-run reconciliation;
  no fabricated `main_product`/consumer classification.
- Extend `test_card_spending_ingest.py`: idempotent re-apply determinism;
  non-Gyeonggi region stays NULL (no fabrication).
- Extend `test_franchise_identity.py`: restaurants are scored, not filtered by a
  new cuisine requirement; `live_api_call` key present in plan payload.
- `test_safety_contracts.py` — canonical safety remains strict; pending SQL is
  reviewed separately and is not part of the canonical execution plan.

Plus relevant full-API suites and the repo-wide safety contracts; ruff; scoped
pre-commit on owned files; `git diff --check`.

## Out of Scope

- Any live external call, file download, DB migration apply, deploy, or secret use.
- AI translation / English enrichment; review/mention lane (separate PR).
- Onboarding new card-spending regions; separately approving and applying the
  operator-pending SQL.
- Changing public CLI argument shapes or wrapper-script guards.
- Editing `main` directly; merging this Draft PR.
