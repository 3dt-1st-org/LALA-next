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

4. **Stable opaque identity.** `external_key` is a digest-derived token of the
   form `naver_<provider>_sha256:<hex16>` (reusing the governance module's
   digest approach), **never** the raw post URL. Same input ⇒ same digest;
   collision-resistant; the URL never persists.

5. **Provenance preserved.** Acquisition is keyed on a concrete
   `travel.places` row. Every emitted record and every aggregate carries
   `place_id`, `region_slug`, and `category` from that row. The query, keyword,
   and place identity are deterministic and auditable.

6. **No raw text stored, served, or logged (DG-11/G-TRUST).**
   - The tool **must not** write `title`/`body`/`post_url` to
     `community.posts` (or anywhere). Those fields are read into memory solely
     to hash and to run the deterministic filters, then dropped.
   - `content_sha256` (sha256 of cleaned title+description) is the only
     retained identity for dedupe.
   - Preview output is **counts only** (places, candidates, ad-filtered,
     organic, aggregated, per-provider failure categories/counts). Titles,
     snippets, and full URLs are never printed or logged.

7. **Feed the existing filters + aggregate Local Signals path.** Reuse
   `review_mention_ingest.clean_review_text` and `classify_post` (deterministic
   ad / category / food-noise policy) in memory, then route the normalized,
   organic-only batch through
   `review_ingest_governance.persist_review_ingest_run` (gate + cross-run
   receipt dedupe + quarantine + single-transaction accounting), and finally
   map the accepted `ApprovedReviewAggregate` outputs into
   `community.place_mentions_weekly` via the existing guarded aggregate upsert.
   Local Signals read `place_mentions_weekly`; nothing reads a raw Naver body.

8. **Transactionally accurate counts.** One DB connection, one transaction.
   `inserted`/`duplicate`/`quarantined` come from the governance boundary's
   rowcount-backed result (`ReviewIngestResult.run`), never from
   `len(results)`. The tool also reports `candidates`, `ad_filtered_out`, and
   per-provider failure tallies. `review_mention_ingest.record_job_run` records
   the run. No per-place connection, no partial commits.

9. **Apply guardrails.** `--preview` is non-mutating (no DB writes, counts
   only). `--apply` requires `--confirm APPLY_NAVER_REVIEW_COLLECT` **and**
   `ALLOW_NAVER_REVIEW_COLLECT_APPLY=1` **and** a passing DG-1 source gate. Any
   missing ⇒ fail closed, write nothing.

## Required tests (focused; reconcile PR body count with reality)

- DG-1 gate fail-closed: no/disabled/rejected/mismatched source ⇒ no network
  call, no DB write, governance code returned.
- Honest failures: auth_missing / quota_exceeded / network_error / parse_error
  / empty each reported with correct category; none swallowed; no raw payload
  in the outcome.
- Opaque identity: identical input ⇒ identical digest; raw URL never appears in
  `external_key` or any persisted/logged field.
- Provenance: every record/aggregate carries the source row's place_id +
  region_slug + category.
- Idempotency: re-running the same window ⇒ 0 new aggregates, accurate
  duplicate count.
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
