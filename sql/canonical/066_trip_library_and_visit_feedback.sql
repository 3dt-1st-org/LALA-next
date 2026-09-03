-- Canonical trip-library extension for S-22 through S-25.
-- Additive and re-runnable. Application startup never applies this file;
-- production application remains an explicit operations gate.

CREATE TABLE IF NOT EXISTS planning.trip_preference_overrides (
    issuer text NOT NULL,
    subject text NOT NULL,
    plan_date date NOT NULL,
    schema_version integer NOT NULL DEFAULT 1,
    revision bigint NOT NULL DEFAULT 1,
    payload jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_trip_preference_overrides_owner
        FOREIGN KEY (issuer, subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE,
    CONSTRAINT trip_preference_overrides_pkey
        PRIMARY KEY (issuer, subject, plan_date),
    CONSTRAINT trip_preference_overrides_schema_version_check
        CHECK (schema_version = 1),
    CONSTRAINT trip_preference_overrides_revision_check CHECK (revision > 0),
    CONSTRAINT trip_preference_overrides_payload_object_check
        CHECK (jsonb_typeof(payload) = 'object')
);

CREATE INDEX IF NOT EXISTS trip_preference_overrides_owner_date_idx
    ON planning.trip_preference_overrides (issuer, subject, plan_date DESC);

ALTER TABLE planning.slot_visits
    ADD COLUMN IF NOT EXISTS reason_code text;

ALTER TABLE planning.slot_visits
    ADD COLUMN IF NOT EXISTS use_for_recommendations boolean NOT NULL DEFAULT false;

ALTER TABLE planning.slot_visits
    ADD COLUMN IF NOT EXISTS confirmed_at timestamptz;

ALTER TABLE planning.slot_visits
    DROP CONSTRAINT IF EXISTS slot_visits_status_check;

ALTER TABLE planning.slot_visits
    ADD CONSTRAINT slot_visits_status_check
    CHECK (status IN ('planned', 'visited', 'not_visited'));

ALTER TABLE planning.slot_visits
    DROP CONSTRAINT IF EXISTS slot_visits_reason_code_check;

ALTER TABLE planning.slot_visits
    ADD CONSTRAINT slot_visits_reason_code_check
    CHECK (
        reason_code IS NULL OR reason_code IN (
            'closed', 'weather', 'crowded', 'time',
            'transport', 'changed_mind', 'other'
        )
    );

ALTER TABLE planning.slot_visits
    DROP CONSTRAINT IF EXISTS slot_visits_feedback_shape_check;

ALTER TABLE planning.slot_visits
    ADD CONSTRAINT slot_visits_feedback_shape_check
    CHECK (
        ((status = 'not_visited') OR (reason_code IS NULL))
        AND
        ((status <> 'planned') OR (use_for_recommendations = false))
    );
