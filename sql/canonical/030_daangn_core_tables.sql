-- Daangn/community data producer tables.

CREATE TABLE IF NOT EXISTS daangn.weekly_keywords (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    keyword text NOT NULL,
    dong_slug text NOT NULL,
    enabled boolean NOT NULL DEFAULT true,
    UNIQUE (keyword, dong_slug)
);

CREATE TABLE IF NOT EXISTS daangn.crawl_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    status text NOT NULL,
    started_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    error_message text
);

CREATE TABLE IF NOT EXISTS daangn.crawl_tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id uuid NOT NULL REFERENCES daangn.crawl_runs(id),
    keyword text NOT NULL,
    dong_slug text NOT NULL,
    status text NOT NULL,
    started_at timestamptz,
    finished_at timestamptz,
    error_message text
);

CREATE TABLE IF NOT EXISTS daangn.community_posts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    external_key text NOT NULL UNIQUE,
    keyword text,
    dong_slug text,
    title text,
    body text,
    post_url text,
    created_at_source timestamptz,
    collected_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS daangn.place_mentions_weekly (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    week_start date NOT NULL,
    place_name text NOT NULL,
    category text NOT NULL,
    mention_count integer NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (week_start, place_name, category)
);

