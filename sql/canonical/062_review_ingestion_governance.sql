-- Review-ingestion governance foundation (licensed-source-ready).
-- Additive only: CREATE TABLE IF NOT EXISTS / ADD COLUMN IF NOT EXISTS /
-- CREATE INDEX IF NOT EXISTS. Re-runnable. No destructive statements, no secrets.
--
-- This migration establishes three governance concepts the review/mention
-- pipeline needs before any acquisition lane is wired:
--   1. ingest.review_sources          -- provenance registry (provider/license/terms)
--   2. community.ingest_runs extension -- immutable ingest-run ledger (idempotent + counted)
--   3. community.ingest_quarantine     -- dead-letter for malformed/unsafe records
--
-- Security invariant: none of these tables store raw review text, post URLs,
-- user identifiers, or secret values. Quarantine carries record identity
-- (provider, external_key), a content hash, and a reason only -- never a body.
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

-- 2. Immutable ingest-run ledger extension.
-- community.ingest_runs already exists (030) as the community run ledger; this
-- extends it additively for review-ingestion governance. New columns are
-- nullable so existing community-keyword-watchlist usage is unaffected.
-- Enums (license_class, failure_category) are enforced in the service layer
-- (Pydantic Literal validators) rather than via ADD CONSTRAINT because
-- ADD CONSTRAINT is not idempotent and the canonical SQL must be re-runnable.
ALTER TABLE community.ingest_runs
    ADD COLUMN IF NOT EXISTS run_key text;

ALTER TABLE community.ingest_runs
    ADD COLUMN IF NOT EXISTS source_name text;

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

-- 3. Review ingestion quarantine / dead-letter.
-- Holds malformed, low-confidence, ambiguous, or terms-violating records until
-- an operator resolves them. Nothing here reaches scoring or RAG until
-- resolution = 'approved'. No raw payload column by design (see header).
CREATE TABLE IF NOT EXISTS community.ingest_quarantine (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source_run_id uuid REFERENCES community.ingest_runs(id),
    source_name text,
    provider text NOT NULL,
    external_key text NOT NULL,
    content_sha256 text NOT NULL,
    reason_category text NOT NULL,
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
