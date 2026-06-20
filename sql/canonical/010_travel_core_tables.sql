-- Core travel tables for Flutter-facing API reads.

CREATE TABLE IF NOT EXISTS travel.places (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    place_id text NOT NULL UNIQUE,
    name_ko text NOT NULL,
    name_en text,
    category text NOT NULL,
    address_ko text,
    address_en text,
    image_url text,
    region_name_ko text,
    region_name_en text,
    province_code text,
    city_code text,
    lat double precision NOT NULL,
    lng double precision NOT NULL,
    is_indoor boolean,
    primary_source text NOT NULL DEFAULT 'canonical',
    source_record_id text,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT places_category_check CHECK (
        category IN ('attraction', 'restaurant', 'event', 'culture_venue')
    )
);

CREATE INDEX IF NOT EXISTS idx_places_category ON travel.places (category);
CREATE INDEX IF NOT EXISTS idx_places_lat_lng ON travel.places (lat, lng);
CREATE INDEX IF NOT EXISTS idx_places_geog_expr
    ON travel.places USING GIST ((ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography));
CREATE INDEX IF NOT EXISTS idx_places_region_name_ko ON travel.places (region_name_ko);

ALTER TABLE travel.places
    ADD COLUMN IF NOT EXISTS image_url text;

CREATE TABLE IF NOT EXISTS travel.place_enrichments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    place_id text NOT NULL REFERENCES travel.places(place_id),
    enrichment_type text NOT NULL,
    name_en text,
    address_en text,
    region_name_en text,
    is_indoor boolean,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    confidence numeric(5, 4),
    source_method text NOT NULL,
    model_name text,
    prompt_version text,
    generated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_place_enrichments_place_id
    ON travel.place_enrichments (place_id, generated_at DESC);
