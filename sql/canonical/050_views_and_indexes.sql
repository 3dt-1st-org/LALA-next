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

CREATE OR REPLACE VIEW locallink.v_legacy_places_api AS
SELECT
    place_id AS id,
    place_id,
    COALESCE(name_ko, name_en, place_id) AS name,
    name_ko,
    COALESCE(name_en, name_ko, place_id) AS name_en,
    lat,
    lng,
    category,
    COALESCE(address_ko, '') AS address,
    COALESCE(address_ko, '') AS road_addr,
    COALESCE(address_en, address_ko, '') AS address_en,
    COALESCE(region_ko, '') AS region,
    COALESCE(region_en, region_ko, '') AS region_en,
    NULL::text AS image_url,
    false AS is_approximate_location,
    NULL::text AS event_start_date,
    NULL::text AS event_end_date,
    NULL::text AS event_url,
    category AS source_type,
    source AS upstream_source,
    updated_at
FROM locallink.v_public_places;

CREATE OR REPLACE VIEW locallink.v_legacy_docent_script_cache_api AS
SELECT
    place_id,
    category,
    language,
    mode,
    script,
    source AS upstream_source,
    generated_at AS created_at,
    generated_at,
    expires_at,
    CASE
        WHEN expires_at IS NULL THEN NULL
        ELSE GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (expires_at - now())))::integer)
    END AS ttl_sec
FROM locallink.docent_cache
WHERE expires_at IS NULL OR expires_at > now();

CREATE OR REPLACE VIEW locallink.v_latest_weather_api AS
SELECT DISTINCT ON (location)
    location,
    temperature,
    temperature::text AS temp,
    precipitation_type,
    pm10,
    pm25,
    is_rain_snow,
    is_bad_dust,
    is_heatwave,
    is_coldwave,
    is_strong_wind,
    record_time,
    created_at
FROM locallink.realtime_weather_conditions
ORDER BY location, record_time DESC;

CREATE OR REPLACE VIEW monitoring.v_dependency_latest AS
SELECT DISTINCT ON (dependency_name)
    dependency_name,
    status,
    latency_ms,
    checked_at
FROM monitoring.dependency_checks
ORDER BY dependency_name, checked_at DESC;
