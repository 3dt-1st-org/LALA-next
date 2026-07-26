-- Official static/source ingestion provenance columns.
--
-- Additive, re-runnable, non-destructive (ADD COLUMN IF NOT EXISTS / CREATE INDEX
-- IF NOT EXISTS only). Documents the schema gap surfaced by the official-source
-- ingestion reliability slice. This file is INTENTIONALLY NOT APPLIED by the
-- slice: runtime code reuses the existing columns and surfaces the equivalent
-- facts in operator-facing payloads until a separate ALLOW_CANONICAL_SQL_APPLY=1
-- rollout applies it.
--
-- Why these columns:
--   * ingest.source_files today only carries (source_name, dataset_name,
--     file_name, file_sha256, downloaded_at, local_path). It has no place to
--     store the upstream source URL, the row count seen, a run status, the
--     upstream last-modified timestamp (freshness), or a schema version. The
--     replay guard works by a pre-flight SELECT plus a transaction-scoped
--     pg_advisory_xact_lock (apps/api/app/services/official_source_receipts.py)
--     -- not by a database uniqueness constraint (see index note below).
--   * culture.events has no image column, so KOPIS posters and KCISA thumbnails
--     are dropped on persist today.

ALTER TABLE ingest.source_files
    ADD COLUMN IF NOT EXISTS source_url text;

ALTER TABLE ingest.source_files
    ADD COLUMN IF NOT EXISTS row_count integer;

ALTER TABLE ingest.source_files
    ADD COLUMN IF NOT EXISTS status text;

ALTER TABLE ingest.source_files
    ADD COLUMN IF NOT EXISTS source_updated_at timestamptz;

ALTER TABLE ingest.source_files
    ADD COLUMN IF NOT EXISTS schema_version text;

-- NON-UNIQUE lookup index only -- this is NOT a uniqueness constraint (F3).
-- ingest.source_files has never had a uniqueness constraint, and every prior
-- runtime version inserted a fresh receipt row on every pull, so a live
-- environment is likely to already carry duplicate (source_name, dataset_name,
-- file_sha256) rows. A CREATE UNIQUE INDEX here would fail -- and, because the
-- canonical plan executes every file in a single transaction
-- (apps/api/app/services/canonical_sql.py), roll back this entire rollout, not
-- just this file. Runtime duplicate prevention during a rollout window is
-- already handled by pg_advisory_xact_lock, not by this index -- this index
-- only accelerates the pre-flight SELECT. A true UNIQUE constraint on
-- (source_name, dataset_name, file_sha256) MUST be applied by a SEPARATE,
-- operator-run migration OUTSIDE this canonical plan, after an operator has
-- de-duplicated any existing rows. Cleanup cannot live in sql/canonical/: a
-- row-deleting statement is a forbidden pattern for the canonical safety
-- scanner (apps/api/app/services/canonical_sql.py DESTRUCTIVE_PATTERNS). This
-- file remains additive, re-runnable, and unapplied.
CREATE INDEX IF NOT EXISTS idx_source_files_receipt_identity
    ON ingest.source_files (source_name, dataset_name, file_sha256)
    WHERE file_sha256 IS NOT NULL;

ALTER TABLE culture.events
    ADD COLUMN IF NOT EXISTS image_url text;
