-- Account-owned travel preferences. Additive, re-runnable, and not applied by
-- application startup. Applying canonical SQL remains an explicit ops gate.
--
-- Logto owns authentication only. Preference and explicitly declared dietary
-- or accessibility constraints stay in the LALA database and are removed by
-- the existing identity.users ON DELETE CASCADE boundary.

CREATE SCHEMA IF NOT EXISTS profile;

CREATE TABLE IF NOT EXISTS profile.user_travel_preferences (
    issuer text NOT NULL,
    subject text NOT NULL,
    schema_version integer NOT NULL DEFAULT 1,
    revision bigint NOT NULL DEFAULT 1,
    payload jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_user_travel_preferences_owner
        FOREIGN KEY (issuer, subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE,
    CONSTRAINT user_travel_preferences_pkey PRIMARY KEY (issuer, subject),
    CONSTRAINT user_travel_preferences_schema_version_check
        CHECK (schema_version = 1),
    CONSTRAINT user_travel_preferences_revision_check CHECK (revision > 0),
    CONSTRAINT user_travel_preferences_payload_object_check
        CHECK (jsonb_typeof(payload) = 'object')
);

CREATE INDEX IF NOT EXISTS user_travel_preferences_updated_idx
    ON profile.user_travel_preferences (updated_at DESC);
