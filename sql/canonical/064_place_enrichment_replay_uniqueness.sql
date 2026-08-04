-- Place enrichment replay uniqueness constraint.
-- Additive and re-runnable. Enforces null-safe three-column uniqueness so that
-- enrichment pipelines remain idempotent across prompt version bumps.
-- PostgreSQL 16 UNIQUE NULLS NOT DISTINCT treats NULL values as distinct keys.

ALTER TABLE travel.place_enrichments
    ADD CONSTRAINT IF NOT EXISTS place_enrichments_place_type_prompt_unique
    UNIQUE NULLS NOT DISTINCT (place_id, enrichment_type, prompt_version);
