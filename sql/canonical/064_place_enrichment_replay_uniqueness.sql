-- Place enrichment replay uniqueness constraint.
-- Additive and re-runnable. Enforces null-safe three-column uniqueness so that
-- enrichment pipelines remain idempotent across prompt version bumps.
-- PostgreSQL 16 UNIQUE NULLS NOT DISTINCT treats NULL values as equal keys.

-- Preflight: fail-closed check for any duplicate replay keys before adding constraint.
-- Groups by (place_id, enrichment_type, prompt_version) including NULLs, raises a generic
-- error if any duplicates exist, never prints row values or counts.
DO $$
DECLARE
    duplicate_count int;
BEGIN
    SELECT count(*) INTO duplicate_count
    FROM (
        SELECT place_id, enrichment_type, prompt_version
        FROM travel.place_enrichments
        GROUP BY place_id, enrichment_type, prompt_version
        HAVING count(*) > 1
    ) duplicates;

    IF duplicate_count > 0 THEN
        RAISE EXCEPTION 'place enrichment replay keys must be reconciled before migration';
    END IF;
END $$;

-- Add the uniqueness constraint idempotently.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'place_enrichments_place_type_prompt_unique'
    ) THEN
        ALTER TABLE travel.place_enrichments
            ADD CONSTRAINT place_enrichments_place_type_prompt_unique
            UNIQUE NULLS NOT DISTINCT (place_id, enrichment_type, prompt_version);
    END IF;
END $$;
