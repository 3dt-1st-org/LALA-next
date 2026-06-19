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

CREATE TABLE IF NOT EXISTS economy.franchise_brands (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    brand_id text,
    brand_name_ko text NOT NULL,
    normalized_brand_name text NOT NULL,
    headquarters_name_ko text,
    business_category text,
    main_product text,
    franchise_store_count integer,
    average_sales_amount numeric(18, 2),
    chain_scale_score numeric(7, 4),
    primary_source text NOT NULL DEFAULT 'fair_trade_commission',
    source_record_id text,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT franchise_brands_scale_check CHECK (
        chain_scale_score IS NULL OR (chain_scale_score >= 0 AND chain_scale_score <= 1)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_franchise_brands_source_record
    ON economy.franchise_brands (primary_source, source_record_id)
    WHERE source_record_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_franchise_brands_normalized_name
    ON economy.franchise_brands (normalized_brand_name);

CREATE TABLE IF NOT EXISTS economy.franchise_locations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    franchise_location_id text,
    brand_id text,
    brand_name_ko text NOT NULL,
    normalized_brand_name text NOT NULL,
    store_name_ko text,
    normalized_store_name text,
    region_name_ko text,
    address_ko text,
    lat double precision,
    lng double precision,
    primary_source text NOT NULL DEFAULT 'fair_trade_commission',
    source_record_id text,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_franchise_locations_source_record
    ON economy.franchise_locations (primary_source, source_record_id)
    WHERE source_record_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_franchise_locations_normalized_brand
    ON economy.franchise_locations (normalized_brand_name);

CREATE INDEX IF NOT EXISTS idx_franchise_locations_lat_lng
    ON economy.franchise_locations (lat, lng)
    WHERE lat IS NOT NULL AND lng IS NOT NULL;

CREATE TABLE IF NOT EXISTS analytics.place_business_identity (
    place_id text PRIMARY KEY REFERENCES travel.places(place_id),
    business_identity_type text NOT NULL DEFAULT 'unknown',
    is_franchise boolean,
    franchise_brand_name text,
    franchise_match_confidence numeric(5, 4),
    chain_scale_score numeric(7, 4),
    small_merchant_fit_score numeric(7, 4),
    matched_source text,
    matched_at timestamptz NOT NULL DEFAULT now(),
    features jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT place_business_identity_type_check CHECK (
        business_identity_type IN (
            'independent_local',
            'local_small_chain',
            'franchise_store',
            'national_franchise',
            'corporate_chain',
            'unknown'
        )
    ),
    CONSTRAINT place_business_identity_confidence_check CHECK (
        franchise_match_confidence IS NULL OR (
            franchise_match_confidence >= 0 AND franchise_match_confidence <= 1
        )
    ),
    CONSTRAINT place_business_identity_small_score_check CHECK (
        small_merchant_fit_score IS NULL OR (
            small_merchant_fit_score >= 0 AND small_merchant_fit_score <= 1
        )
    )
);

CREATE INDEX IF NOT EXISTS idx_place_business_identity_type
    ON analytics.place_business_identity (business_identity_type);

CREATE TABLE IF NOT EXISTS analytics.place_score_snapshots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    place_id text NOT NULL,
    scored_at timestamptz NOT NULL DEFAULT now(),
    local_spending_score numeric(7, 4),
    small_merchant_fit_score numeric(7, 4),
    demand_dispersion_score numeric(7, 4),
    culture_relevance_score numeric(7, 4),
    weather_fit_score numeric(7, 4),
    review_quality_score numeric(7, 4),
    accessibility_fit_score numeric(7, 4),
    final_score numeric(7, 4) NOT NULL,
    formula_version text NOT NULL,
    features jsonb NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE analytics.place_score_snapshots
    ADD COLUMN IF NOT EXISTS small_merchant_fit_score numeric(7, 4);

ALTER TABLE analytics.place_score_snapshots
    ADD COLUMN IF NOT EXISTS accessibility_fit_score numeric(7, 4);

CREATE INDEX IF NOT EXISTS idx_place_score_snapshots_place_scored_at
    ON analytics.place_score_snapshots (place_id, scored_at DESC);
