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
--     replay guard currently works by a pre-flight SELECT because there is no
--     unique constraint on the receipt identity.
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

-- Make the receipt identity declarative so the replay guard can rely on the
-- database instead of a pre-flight SELECT. file_sha256 is nullable for legacy
-- rows, so the uniqueness is partial.
CREATE UNIQUE INDEX IF NOT EXISTS idx_source_files_receipt_identity
    ON ingest.source_files (source_name, dataset_name, file_sha256)
    WHERE file_sha256 IS NOT NULL;

ALTER TABLE culture.events
    ADD COLUMN IF NOT EXISTS image_url text;
