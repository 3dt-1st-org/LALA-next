-- Domain tables used by weather, docent, and planning flows.

CREATE TABLE IF NOT EXISTS locallink.realtime_weather_conditions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    location text NOT NULL,
    temperature double precision,
    precipitation_type text,
    pm10 double precision,
    pm25 double precision,
    is_rain_snow boolean NOT NULL DEFAULT false,
    is_bad_dust boolean NOT NULL DEFAULT false,
    is_heatwave boolean NOT NULL DEFAULT false,
    is_coldwave boolean NOT NULL DEFAULT false,
    is_strong_wind boolean NOT NULL DEFAULT false,
    record_time timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_weather_location_record_time
    ON locallink.realtime_weather_conditions (location, record_time DESC);

CREATE TABLE IF NOT EXISTS locallink.docent_cache (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    place_id text NOT NULL,
    category text NOT NULL,
    language text NOT NULL,
    mode text NOT NULL,
    script text NOT NULL,
    source text NOT NULL,
    generated_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    UNIQUE (place_id, category, language, mode)
);

CREATE TABLE IF NOT EXISTS locallink.place_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    place_id text NOT NULL,
    title text NOT NULL,
    starts_at timestamptz,
    ends_at timestamptz,
    url text,
    updated_at timestamptz NOT NULL DEFAULT now()
);

