-- Monitoring and Power BI source tables.

CREATE TABLE IF NOT EXISTS monitoring.function_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    function_name text NOT NULL,
    status text NOT NULL,
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    duration_ms integer,
    error_message text
);

CREATE TABLE IF NOT EXISTS monitoring.dependency_checks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dependency_name text NOT NULL,
    status text NOT NULL,
    latency_ms integer,
    checked_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS monitoring.cost_daily (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    usage_date date NOT NULL,
    resource_name text NOT NULL,
    cost_amount numeric(14, 4) NOT NULL DEFAULT 0,
    currency text NOT NULL DEFAULT 'KRW',
    UNIQUE (usage_date, resource_name)
);

