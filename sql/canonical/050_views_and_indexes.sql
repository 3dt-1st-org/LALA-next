-- Stable read views for API, compatibility, and reporting.

CREATE OR REPLACE VIEW travel.public_places AS
SELECT
    place_id,
    name_ko,
    name_en,
    category,
    address_ko,
    address_en,
    region_name_ko,
    region_name_en,
    region_name_ko AS region_ko,
    region_name_en AS region_en,
    province_code,
    city_code,
    lat,
    lng,
    is_indoor,
    primary_source AS source,
    primary_source,
    source_record_id,
    updated_at,
    image_url
FROM travel.places;

CREATE OR REPLACE VIEW compat.legacy_places_api AS
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
    is_indoor,
    image_url,
    false AS is_approximate_location,
    NULL::text AS event_start_date,
    NULL::text AS event_end_date,
    NULL::text AS event_url,
    category AS source_type,
    source AS upstream_source,
    updated_at
FROM travel.public_places;

CREATE OR REPLACE VIEW compat.legacy_docent_scripts_api AS
SELECT
    place_id,
    category,
    language,
    mode,
    script,
    source_method AS upstream_source,
    generated_at AS created_at,
    generated_at,
    expires_at,
    CASE
        WHEN expires_at IS NULL THEN NULL
        ELSE GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (expires_at - now())))::integer)
    END AS ttl_sec
FROM travel.docent_scripts
WHERE expires_at IS NULL OR expires_at > now();

CREATE OR REPLACE VIEW travel.latest_weather AS
SELECT DISTINCT ON (location_name)
    location_name AS location,
    temperature_c AS temperature,
    temperature_c::text AS temp,
    precipitation_type,
    pm10,
    pm25,
    is_rain_snow,
    is_bad_dust,
    is_heatwave,
    is_coldwave,
    is_strong_wind,
    observed_at AS record_time,
    collected_at AS created_at
FROM travel.weather_observations
ORDER BY location_name, observed_at DESC;

CREATE OR REPLACE VIEW ops.dependency_latest AS
SELECT DISTINCT ON (dependency_name)
    dependency_name,
    status,
    latency_ms,
    checked_at
FROM ops.dependency_checks
ORDER BY dependency_name, checked_at DESC;
