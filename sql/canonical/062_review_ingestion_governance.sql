-- Review-ingestion governance foundation (licensed-source-ready).
-- Additive only: CREATE TABLE IF NOT EXISTS / ADD COLUMN IF NOT EXISTS /
-- CREATE INDEX IF NOT EXISTS. Re-runnable. No destructive statements, no secrets.
--
-- This migration establishes four governance concepts the review/mention
-- pipeline needs before any acquisition lane is wired:
--   1. ingest.review_sources            -- provenance registry (provider/license/terms)
--   2. community.ingest_runs extension  -- idempotent, counted ingest-run accounting
--   3. ingest.review_ingest_receipts    -- persistent aggregate-only dedupe (no raw text)
--   4. community.ingest_quarantine      -- dead-letter for malformed/unsafe records
--
-- Run-ledger note: community.ingest_runs is *idempotent accounting*, not an
-- immutable log. Re-running a (source, window, schema) batch resumes the same
-- row and finalize_*() overwrites its counters with absolute retry-safe
-- values. That is why dedupe/receipts live in their own table (3).
--
-- Security invariant: none of these tables store raw review text, post URLs,
-- user identifiers, or secret values. Quarantine carries record identity
-- (provider, external_key), a content hash, a code-backed reason, and a typed
-- whitelisted metadata blob only -- never a body/title/url/provider response.
-- The only review-derived output permitted downstream is an aggregate payload
-- built in code (apps/api/app/services/review_ingest_governance.py).

-- 1. Review-source provenance registry.
-- One row per approved source/provider. license_class is the governance gate:
-- the bulk/refinement lanes refuse any source not in the allowed set.
CREATE TABLE IF NOT EXISTS ingest.review_sources (
    source_name text PRIMARY KEY,
    provider text NOT NULL,
    license_class text NOT NULL,
    terms_version text NOT NULL,
    collection_method text NOT NULL,
    retention_policy text NOT NULL,
    redaction_policy text NOT NULL,
    source_status text NOT NULL DEFAULT 'active',
    approved_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT review_sources_license_class_check CHECK (
        license_class IN ('licensed', 'public_processed', 'approved_export', 'rejected')
    ),
    CONSTRAINT review_sources_status_check CHECK (
        source_status IN ('active', 'disabled')
    )
);

CREATE INDEX IF NOT EXISTS idx_review_sources_license_class
    ON ingest.review_sources (license_class);

-- 2. Idempotent, counted ingest-run accounting extension.
-- community.ingest_runs already exists (030) as the community run ledger; this
-- extends it additively for review-ingestion governance. New columns are
-- nullable so legacy community-keyword-watchlist rows (NULL run_key, NULL
-- review_source_name) remain valid and are never rejected by the new
-- relationship. Enums (license_class, failure_category) are enforced in the
-- service layer (Pydantic Literal validators) rather than via ADD CONSTRAINT
-- because ADD CONSTRAINT is not idempotent and the canonical SQL must be
-- re-runnable.
ALTER TABLE community.ingest_runs
    ADD COLUMN IF NOT EXISTS run_key text;

ALTER TABLE community.ingest_runs
    ADD COLUMN IF NOT EXISTS source_name text;

-- Integrity relationship (Finding 2): new review-ingest runs refer to a
-- *registered* review source. Legacy rows stay valid (NULL). The free-text
-- source_name column above is retained for back-compat echo only; this FK is
-- the authoritative source-of-truth link. ADD COLUMN IF NOT EXISTS with an
-- inline REFERENCES is idempotent: re-run skips the existing column.
ALTER TABLE community.ingest_runs
    ADD COLUMN IF NOT EXISTS review_source_name text
    REFERENCES ingest.review_sources(source_name);

ALTER TABLE community.ingest_runs
    ADD COLUMN IF NOT EXISTS license_class text;

ALTER TABLE community.ingest_runs
    ADD COLUMN IF NOT EXISTS terms_version text;

ALTER TABLE community.ingest_runs
    ADD COLUMN IF NOT EXISTS schema_version text;

ALTER TABLE community.ingest_runs
    ADD COLUMN IF NOT EXISTS received_count integer;

ALTER TABLE community.ingest_runs
    ADD COLUMN IF NOT EXISTS processed_count integer;

ALTER TABLE community.ingest_runs
    ADD COLUMN IF NOT EXISTS duplicate_count integer;

ALTER TABLE community.ingest_runs
    ADD COLUMN IF NOT EXISTS quarantined_count integer;

ALTER TABLE community.ingest_runs
    ADD COLUMN IF NOT EXISTS failure_category text;

-- Idempotency arbiter: one run per (source, window, schema_version). Partial
-- index so legacy rows with NULL run_key (community-keyword-watchlist) are
-- excluded and never conflict.
CREATE UNIQUE INDEX IF NOT EXISTS idx_community_ingest_runs_run_key
    ON community.ingest_runs (run_key)
    WHERE run_key IS NOT NULL;

-- 3. Persistent aggregate-only dedupe receipts (Finding 3).
-- One row per (registered source, external key, content SHA-256). This is the
-- cross-run dedupe arbiter: a re-attempt that produces the exact same content
-- hash for the same external key is an *exact replay* (INSERT ... ON CONFLICT
-- DO NOTHING -> rowcount 0) and must NOT emit a downstream aggregate again. A
-- different content_sha256 for the same external key is a *content revision*
-- -> new PK row -> emits a fresh aggregate. No raw text, title, url, or
-- provider response is ever stored here; only identity, a hash, and run/time
-- bookkeeping. first_run_id/first_seen_at are set once on insert and never
-- mutated; last_run_id/last_seen_at are refreshed on each exact replay.
CREATE TABLE IF NOT EXISTS ingest.review_ingest_receipts (
    source_name text NOT NULL REFERENCES ingest.review_sources(source_name),
    external_key text NOT NULL,
    content_sha256 text NOT NULL,
    first_run_id uuid NOT NULL REFERENCES community.ingest_runs(id),
    last_run_id uuid NOT NULL REFERENCES community.ingest_runs(id),
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (source_name, external_key, content_sha256)
);

-- Supports "has this external key been seen with a different hash?" (revision
-- detection) and per-source receipt audits, without scanning raw content.
CREATE INDEX IF NOT EXISTS idx_review_ingest_receipts_external_key
    ON ingest.review_ingest_receipts (source_name, external_key);

-- 4. Review ingestion quarantine / dead-letter.
-- Holds malformed, low-confidence, ambiguous, or terms-violating records until
-- an operator resolves them. Nothing here reaches scoring or RAG until
-- resolution = 'approved'. No raw payload column by design (see header). The
-- service layer persists only a code-backed reason (template string), a
-- coarse reason_category, a machine reason_code, and a typed/whitelisted
-- safe_metadata blob -- never raw body/title/url/provider response text.
CREATE TABLE IF NOT EXISTS community.ingest_quarantine (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source_run_id uuid REFERENCES community.ingest_runs(id),
    source_name text,
    provider text NOT NULL,
    external_key text NOT NULL,
    content_sha256 text NOT NULL,
    reason_category text NOT NULL,
    reason_code text,
    reason text NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    quarantined_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    resolution text,
    safe_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ingest_quarantine_reason_category_check CHECK (
        reason_category IN (
            'schema_invalid',
            'terms_violation',
            'source_api_failure',
            'duplicate_suspect',
            'low_confidence',
            'ambiguous_match'
        )
    ),
    CONSTRAINT ingest_quarantine_resolution_check CHECK (
        resolution IS NULL OR resolution IN ('approved', 'rejected', 'retried')
    )
);

CREATE INDEX IF NOT EXISTS idx_community_ingest_quarantine_run
    ON community.ingest_quarantine (source_run_id)
    WHERE source_run_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_community_ingest_quarantine_unresolved
    ON community.ingest_quarantine (quarantined_at DESC)
    WHERE resolved_at IS NULL;

-- Poison-path idempotency: the same record may be quarantined once per
-- reason_category while unresolved, so retrying a failed batch does not
-- duplicate dead-letter rows.
CREATE UNIQUE INDEX IF NOT EXISTS idx_community_ingest_quarantine_dedupe
    ON community.ingest_quarantine (provider, external_key, reason_category)
    WHERE resolved_at IS NULL;
