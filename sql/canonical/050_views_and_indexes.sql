-- Stable read views for API and reporting.

CREATE OR REPLACE VIEW locallink.v_public_places AS
SELECT
    place_id,
    name_ko,
    name_en,
    category,
    address_ko,
    address_en,
    region_ko,
    region_en,
    lat,
    lng,
    source,
    updated_at
FROM locallink.places;

CREATE OR REPLACE VIEW monitoring.v_dependency_latest AS
SELECT DISTINCT ON (dependency_name)
    dependency_name,
    status,
    latency_ms,
    checked_at
FROM monitoring.dependency_checks
ORDER BY dependency_name, checked_at DESC;

