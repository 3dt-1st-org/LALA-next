CREATE TABLE IF NOT EXISTS identity.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    issuer text NOT NULL,
    subject text NOT NULL,
    status text NOT NULL DEFAULT 'active'
        CONSTRAINT identity_users_status_check CHECK (status IN ('active', 'deleting')),
    created_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    deletion_requested_at timestamptz,
    CONSTRAINT identity_users_issuer_subject_key UNIQUE (issuer, subject)
);

CREATE TABLE IF NOT EXISTS identity.deleted_users (
    identity_digest bytea NOT NULL,
    deleted_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT identity_deleted_users_digest_length_check
        CHECK (octet_length(identity_digest) = 32),
    CONSTRAINT identity_deleted_users_identity_digest_key UNIQUE (identity_digest)
);
