-- Travel domain tables used by weather, docent, and planning flows.

CREATE TABLE IF NOT EXISTS travel.weather_observations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    location_name text NOT NULL,
    temperature_c double precision,
    precipitation_type text,
    pm10 double precision,
    pm25 double precision,
    is_rain_snow boolean NOT NULL DEFAULT false,
    is_bad_dust boolean NOT NULL DEFAULT false,
    is_heatwave boolean NOT NULL DEFAULT false,
    is_coldwave boolean NOT NULL DEFAULT false,
    is_strong_wind boolean NOT NULL DEFAULT false,
    observed_at timestamptz NOT NULL,
    collected_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_weather_observations_location_observed_at
    ON travel.weather_observations (location_name, observed_at DESC);

CREATE TABLE IF NOT EXISTS travel.docent_scripts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    place_id text NOT NULL,
    category text NOT NULL,
    language text NOT NULL,
    mode text NOT NULL,
    script text NOT NULL,
    source_method text NOT NULL,
    generated_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    UNIQUE (place_id, category, language, mode)
);

CREATE TABLE IF NOT EXISTS travel.place_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    place_id text NOT NULL,
    title text NOT NULL,
    starts_at timestamptz,
    ends_at timestamptz,
    url text,
    updated_at timestamptz NOT NULL DEFAULT now()
);
