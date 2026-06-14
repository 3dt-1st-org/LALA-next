-- Provider-neutral community data producer tables.

CREATE TABLE IF NOT EXISTS community.keyword_watchlist (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    keyword text NOT NULL,
    region_slug text NOT NULL,
    enabled boolean NOT NULL DEFAULT true,
    UNIQUE (keyword, region_slug)
);

CREATE TABLE IF NOT EXISTS community.ingest_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider text NOT NULL,
    status text NOT NULL,
    started_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    error_message text
);

CREATE TABLE IF NOT EXISTS community.ingest_tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id uuid NOT NULL REFERENCES community.ingest_runs(id),
    keyword text NOT NULL,
    region_slug text NOT NULL,
    status text NOT NULL,
    started_at timestamptz,
    finished_at timestamptz,
    error_message text
);

CREATE TABLE IF NOT EXISTS community.posts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider text NOT NULL,
    external_key text NOT NULL UNIQUE,
    keyword text,
    region_slug text,
    title text,
    body text,
    post_url text,
    created_at_source timestamptz,
    collected_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS community.place_mentions_weekly (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    week_start date NOT NULL,
    place_id text,
    place_name_ko text NOT NULL,
    provider text NOT NULL,
    category text NOT NULL,
    mention_count integer NOT NULL DEFAULT 0,
    organic_mention_count integer,
    sentiment_score numeric(5, 4),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (week_start, place_name_ko, provider, category)
);
