-- Durable work survives user removal and can be resumed without a user token.
CREATE TABLE IF NOT EXISTS identity.deletion_jobs (
    identity_digest bytea PRIMARY KEY CHECK (octet_length(identity_digest) = 32),
    issuer text NOT NULL,
    subject text NOT NULL,
    phase text NOT NULL DEFAULT 'pending_external'
        CHECK (phase IN ('pending_external', 'external_deleted')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    requested_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    next_attempt_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS identity_deletion_jobs_due_idx
    ON identity.deletion_jobs (next_attempt_at, requested_at);

-- Adopt interrupted deletions from before durable jobs were introduced.
INSERT INTO identity.deletion_jobs (identity_digest, issuer, subject, requested_at)
SELECT digest(convert_to(issuer, 'UTF8') || decode('00', 'hex') || convert_to(subject, 'UTF8'), 'sha256'),
       issuer, subject, COALESCE(deletion_requested_at, now())
FROM identity.users WHERE status = 'deleting'
ON CONFLICT (identity_digest) DO NOTHING;
