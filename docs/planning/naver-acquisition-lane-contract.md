# Naver Review/Mention Acquisition Lane — Corrected Contract

Status: DRAFT contract for the correction PR. Governs
`apps/api/app/services/naver_search_service.py` and
`apps/api/app/tools/run_naver_review_collect.py`.

This contract replaces the unsafe lane merged in PR #117. PR #117 bypassed the
existing governance boundary, stored raw provider text, and reported failures
dishonestly. The correction makes the lane **governed, aggregate-only, and
fail-closed**.

## Authority (what this defers to)

- `apps/api/app/services/review_ingest_governance.py` — the existing DB-backed
  governance boundary. It owns the source gate, typed quarantine, single-
  transaction persistence, and accurate accounting. This lane must **reuse** it,
  not reimplement it.
- `apps/canonical/062_review_ingestion_governance.sql` — `ingest.review_sources`
  (provenance/license gate), `ingest.review_ingest_receipts` (cross-run dedupe),
  `community.ingest_runs` (run accounting), `community.ingest_quarantine`.
- `apps/api/app/services/review_mention_ingest.py` — the existing deterministic
  cleanup / ad / category / dedupe filters and the guarded weekly-aggregate
  upsert into `community.place_mentions_weekly` (the Local Signals table).
- Decision gates from `docs/planning/cleanroom-reimplementation-execution-program.md`:
  - **DG-1** (BLOCKED_EXTERNAL): no live external acquisition until a source is
    registered `licensed`/`public_processed`/`approved_export` with legal
    sign-off on retention/summarization.
  - **DG-11** (BLOCKED_EXTERNAL): no raw review-body storage/serving/logging/
    embedding until a legal/retention/access decision clears.
  - **G-TRUST**: no endpoint emits `community.posts.body`; RAG has no raw chunks.
  - **G-LEGAL**: licensed/public/processed/de-identified sources only.

## Lane shape (collect → filter in memory → govern → aggregate)

The collector is an **acquisition + normalization adapter**. Raw provider text
lives only in process memory, long enough to run the deterministic filters, and
is then discarded. Only hashes, opaque identities, provenance, and aggregate
counts leave the lane.

1. **DG-1 gate (fail-closed).** Before any network call, the tool must call
   `review_ingest_governance.load_active_review_source` for
   `source_name="naver_search"` with the expected provider/terms. If the source
   is absent, disabled, `rejected`, or provider/terms-mismatched, the run aborts
   with the governance code and writes **nothing**. No registration ⇒ no
   acquisition. This is the explicit legal/access decision point.

2. **Official API only.** Naver Search Open API (`blog`, `cafearticle`) via
   `openapi.naver.com`. No scraping, no crawling, **no Daangn**, no third-party
  scrapers.

3. **Honest per-provider failure reporting.** Replace blanket
   `contextlib.suppress(Exception)` with typed classification. Each provider
   call returns an `AcquisitionOutcome` carrying a `category` ∈
   `{ok, auth_missing, quota_exceeded, network_error, parse_error, empty}` plus
   bounded metadata (retryable flag, http_status int, attempted_count) and
   **no raw payload**. Unexpected errors propagate; they are never swallowed.
   A network/auth/quota failure must never look like an honest zero-result
   success.

4. **Stable opaque place-aware identity — full digests everywhere.**
   `external_key` is a place-aware, full-digest token of the form
   `naver_<provider>_sha256:<hex64>` — the full 64-hex sha256 over (provider +
   link + postdate + place_id), **never** the raw post URL and **never**
   truncated. `content_sha256` is a full 64-hex sha256 over (provider + link +
   postdate + place_id + cleaned-title-hash + cleaned-desc-hash).
   `ApprovedReviewAggregate.aggregate_key` is `sha256:<full 64-hex>` — no
   `[:16]` truncation in any identity, dedupe, receipt, or audit path. Same
   input + place ⇒ same digest; the same post for two distinct places yields two
   distinct keys so both get independent receipts and aggregates. The URL never
   persists.

5. **Provenance preserved.** Acquisition is keyed on a concrete
   `travel.places` row. Every emitted record and every aggregate carries
   `place_id`, `region_name_ko` (the actual column on `travel.places`), and
   `category` from that row. The query, keyword, and place identity are
   deterministic and auditable.

6. **No raw text stored, served, or logged (DG-11/G-TRUST).**
   - The tool **must not** write `title`/`body`/`post_url` to
     `community.posts` (or anywhere). Those fields are read into memory solely
     to hash and to run the deterministic filters, then dropped.
   - `content_sha256` (place-aware full sha256 over provider + link + postdate
     + place_id + cleaned-title-hash + cleaned-desc-hash) is the only retained
     identity for dedupe. Same post for two places yields two distinct digests.
   - Preview output is **counts only** (places, candidates, ad-filtered,
     organic, aggregated, per-provider failure categories/counts). Titles,
     snippets, and full URLs are never printed or logged.

7. **Three-phase apply: preflight gate → acquire (no DB) → atomic write.**
   The apply path NEVER holds a DB transaction open during Naver network I/O.

   - **Phase 1 (preflight, short-lived):** open a connection, call
     `load_active_review_source` (DG-1 fail-fast before any network call), read
     `travel.places` with provenance, close the connection.
   - **Phase 2 (acquire, NO connection):** run the Naver acquisition loop +
     in-memory deterministic filtering (`clean_review_text`/`classify_post`) +
     build governed records, with zero PostgreSQL connections open.
   - **Phase 3 (atomic write transaction):** open ONE connection, `with conn:` →
     `govern_review_ingest_on_cursor(cur, records=organic, ...)` which
     RE-CHECKS the DG-1 gate inside the transaction (authoritative fail-closed),
     writes receipts/quarantine/accounting; then
     `insert_review_mention_aggregates_on_cursor(cur, aggregates)`; commit once.
     Any failure rolls back receipts + aggregates together. `record_job_run` is
     a separate best-effort accounting write outside the data transaction.

   The gate is checked twice: once read-only before network I/O (fail fast),
   once authoritatively inside the write transaction (fail-closed).

8. **Transactionally accurate counts.** `inserted`/`duplicate`/`quarantined`
   come from the governance boundary's rowcount-backed result
   (`ReviewIngestResult.run`), never from `len(results)`. The tool also reports
   `candidates`, `ad_filtered_out`, and per-provider failure tallies.

9. **Apply guardrails + visible partial-failure degradation.** `--preview` is
   non-mutating (no DB writes, counts only). `--apply` requires `--confirm
   APPLY_NAVER_REVIEW_COLLECT` **and** `ALLOW_NAVER_REVIEW_COLLECT_APPLY=1`
   **and** a passing DG-1 source gate. Any missing ⇒ fail closed, write nothing.
   If ANY provider acquisition returns auth_missing / quota_exceeded /
   network_error / parse_error OR governance quarantines records, the top-level
   status is `degraded` (not unconditional success), carrying per-provider
   failure categories + counts. If ALL providers fail, status is `failed`.
   Only a fully clean run (all ok/empty, zero quarantine) is `succeeded`.

## Required tests (focused; reconcile PR body count with reality)

- DG-1 gate fail-closed: no/disabled/rejected/mismatched source ⇒ no network
  call, no DB write, governance code returned.
- Honest failures: auth_missing / quota_exceeded / network_error / parse_error
  / empty each reported with correct category; none swallowed; no raw payload
  in the outcome.
- Opaque place-aware identity: identical input+place ⇒ identical digest; raw
  URL never appears in `external_key` or any persisted/logged field; digest is
  full 64 hex (not truncated); same post for two places yields distinct keys.
- Provenance: every record/aggregate carries the source row's place_id +
  region_name_ko + category.
- Atomicity/idempotency: inject a failure at the aggregate-upsert step ⇒ NO
  rows in receipts AND none in `place_mentions_weekly` (rollback). Re-run
  without failure ⇒ both present (full recovery). Re-running the same window
  ⇒ 0 new aggregates, accurate duplicate count.
- Two-place same-post: the same Naver post for two distinct places yields two
  distinct `content_sha256`/`external_key`, two accepted records, and BOTH
  places get an aggregate.
- Partial-failure degradation: one provider fails ⇒ status `degraded` with the
  failure category surfaced; all providers fail ⇒ status `failed`; clean run ⇒
  `succeeded`.
- Redaction: preview/apply stdout and logs contain no title/body/url
  (asserted by substring absence on a captured ad-bearing fixture).
- Accurate counts: inserted/duplicate/quarantined match rowcount, not
  attempt count; ad-bearing candidates are excluded from organic.
- Non-mutating preview: preview writes no rows (assert row counts unchanged).

## Out of scope / unrelated

- The `apps/flutter_app/ios/Podfile.lock` accidentally added in PR #117 is
  unrelated to this backend collector and **must not** appear in this PR's diff.

## Explicit external gate (where this PR stops)

This PR lands **code only**. It does **not**:
- register the `naver_search` row in `ingest.review_sources` with an operator-
  approved `license_class` / `terms_version` / retention / redaction policy
  (DG-1 legal sign-off); nor
- run `--apply` live (which would acquire from Naver at all).

Both require an explicit operator/legal decision. The PR ships the registration
command shape but leaves the actual registration + live apply to that gate.
