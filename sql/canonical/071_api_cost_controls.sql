-- Shared paid API admission, conservative daily units, and generation leases.
-- Session advisory locks fence generation owners; leases permit crash recovery.
CREATE SCHEMA IF NOT EXISTS ops;
CREATE TABLE IF NOT EXISTS ops.api_paid_budgets (
    actor text NOT NULL,
    day date NOT NULL,
    requests bigint NOT NULL CHECK (requests >= 0),
    units bigint NOT NULL CHECK (units >= 0),
    PRIMARY KEY (actor, day)
);
CREATE TABLE IF NOT EXISTS ops.api_paid_generations (
    key text PRIMARY KEY,
    response bytea,
    expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS api_paid_generations_expiry ON ops.api_paid_generations(expires_at);
CREATE TABLE IF NOT EXISTS ops.api_paid_windows (
    key text PRIMARY KEY,
    count bigint NOT NULL CHECK (count >= 0),
    expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS api_paid_windows_expiry ON ops.api_paid_windows(expires_at);
