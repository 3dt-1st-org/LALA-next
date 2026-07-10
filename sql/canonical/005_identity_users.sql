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
