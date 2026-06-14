-- Source, culture, economy, and analytics tables used by recommendation batches.

CREATE TABLE IF NOT EXISTS ingest.source_files (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source_name text NOT NULL,
    dataset_name text NOT NULL,
    file_name text NOT NULL,
    file_sha256 text,
    downloaded_at timestamptz NOT NULL DEFAULT now(),
    local_path text
);

CREATE TABLE IF NOT EXISTS culture.events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id text NOT NULL UNIQUE,
    title_ko text NOT NULL,
    title_en text,
    event_type text,
    venue_name_ko text,
    venue_place_id text,
    region_name_ko text,
    starts_on date,
    ends_on date,
    url text,
    primary_source text NOT NULL,
    source_record_id text,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_culture_events_region_name_ko
    ON culture.events (region_name_ko);

CREATE TABLE IF NOT EXISTS economy.card_spending_area_monthly (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    month date NOT NULL,
    region_name_ko text NOT NULL,
    industry_code text,
    industry_name_ko text,
    spend_amount numeric(18, 2),
    transaction_count integer,
    visitor_type text,
    primary_source text NOT NULL,
    source_file_id uuid REFERENCES ingest.source_files(id)
);

CREATE INDEX IF NOT EXISTS idx_card_spending_area_monthly_region_month
    ON economy.card_spending_area_monthly (region_name_ko, month DESC);

CREATE TABLE IF NOT EXISTS economy.card_spending_demographics (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    month date NOT NULL,
    region_name_ko text NOT NULL,
    industry_code text,
    gender text,
    age_group text,
    spend_amount numeric(18, 2),
    transaction_count integer,
    primary_source text NOT NULL,
    source_file_id uuid REFERENCES ingest.source_files(id)
);

CREATE INDEX IF NOT EXISTS idx_card_spending_demographics_region_month
    ON economy.card_spending_demographics (region_name_ko, month DESC);

CREATE TABLE IF NOT EXISTS analytics.place_score_snapshots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    place_id text NOT NULL,
    scored_at timestamptz NOT NULL DEFAULT now(),
    local_spending_score numeric(7, 4),
    demand_dispersion_score numeric(7, 4),
    weather_fit_score numeric(7, 4),
    review_quality_score numeric(7, 4),
    culture_relevance_score numeric(7, 4),
    final_score numeric(7, 4) NOT NULL,
    formula_version text NOT NULL,
    features jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_place_score_snapshots_place_scored_at
    ON analytics.place_score_snapshots (place_id, scored_at DESC);
