-- V5-A persistence foundation: user-owned planning action tables.
-- Save / persisted-plan / visit (check-in) for the V5 conversion layer.
-- Additive and re-runnable. No destructive statements, no secrets.
--
-- Identity follows the codebase-wide (issuer, subject) composite key that
-- references identity.users; there is no integer user_id column. Slot identity
-- is the durable `period` string (morning|lunch|afternoon|dinner) — the real
-- slot key in planner_service — rather than a synthetic numeric index, so a
-- persisted visit stays coherent with the plan it belongs to.
--
-- These files are COMMITTED but NEVER applied to a DB by V5 (apply is an
-- explicit ops action via the gated apply_canonical_sql CLI, never a
-- controller/worker action).

CREATE SCHEMA IF NOT EXISTS planning;

-- User-scoped saved places. place_id only — no coordinates or PII are stored
-- (D2). The composite primary key makes repeat-save a no-op delta, so the
-- toggle save -> unsaved -> save never produces a duplicate row (A4).
CREATE TABLE IF NOT EXISTS planning.user_saved_places (
    issuer text NOT NULL,
    subject text NOT NULL,
    place_id text NOT NULL,
    source text NOT NULL DEFAULT 'public_mvp_snapshot',
    saved_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_user_saved_places_owner
        FOREIGN KEY (issuer, subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE,
    CONSTRAINT user_saved_places_pkey PRIMARY KEY (issuer, subject, place_id)
);

CREATE INDEX IF NOT EXISTS user_saved_places_owner_idx
    ON planning.user_saved_places (issuer, subject);

-- Persisted daily plan envelope, one per user per UTC day (D1). The envelope is
-- the plan DTO serialized as jsonb and is read back through a version guard that
-- degrades corrupt or future-version payloads to null (D8). schema_version is
-- the persisted-envelope version, independent of any future migration numbering.
CREATE TABLE IF NOT EXISTS planning.user_plans (
    issuer text NOT NULL,
    subject text NOT NULL,
    plan_date date NOT NULL,
    schema_version integer NOT NULL,
    envelope jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_user_plans_owner
        FOREIGN KEY (issuer, subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE,
    CONSTRAINT user_plans_pkey PRIMARY KEY (issuer, subject, plan_date),
    CONSTRAINT user_plans_schema_version_check CHECK (schema_version > 0)
);

-- Per-slot check-in status (D3). Keyed by (owner, plan_date, slot_period) so a
-- re-check-in updates the existing row in place — idempotent, one row (A5).
CREATE TABLE IF NOT EXISTS planning.slot_visits (
    issuer text NOT NULL,
    subject text NOT NULL,
    plan_date date NOT NULL,
    slot_period text NOT NULL,
    place_id text,
    status text NOT NULL DEFAULT 'planned'
        CONSTRAINT slot_visits_status_check CHECK (status IN ('planned', 'visited')),
    visited_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_slot_visits_owner
        FOREIGN KEY (issuer, subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE,
    CONSTRAINT slot_visits_pkey PRIMARY KEY (issuer, subject, plan_date, slot_period),
    CONSTRAINT slot_visits_slot_period_check CHECK (
        slot_period IN ('morning', 'lunch', 'afternoon', 'dinner')
    )
);

CREATE INDEX IF NOT EXISTS slot_visits_owner_date_idx
    ON planning.slot_visits (issuer, subject, plan_date);
