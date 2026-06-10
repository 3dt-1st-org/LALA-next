-- Core place table for Flutter-facing API reads.

CREATE TABLE IF NOT EXISTS locallink.places (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    place_id text NOT NULL UNIQUE,
    name_ko text NOT NULL,
    name_en text,
    category text NOT NULL,
    address_ko text,
    address_en text,
    region_ko text,
    region_en text,
    lat double precision NOT NULL,
    lng double precision NOT NULL,
    source text NOT NULL DEFAULT 'canonical',
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT places_category_check CHECK (category IN ('attraction', 'restaurant', 'event'))
);

CREATE INDEX IF NOT EXISTS idx_places_category ON locallink.places (category);
CREATE INDEX IF NOT EXISTS idx_places_lat_lng ON locallink.places (lat, lng);

