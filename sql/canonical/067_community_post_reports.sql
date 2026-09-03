-- Governed community post reports (F-080).
-- Mirrors the community.local_signal_reports governance shape: bounded reason
-- codes, a moderation status lifecycle, and no free-text report body. One
-- unresolved report per reporter/post; re-submitting is an idempotent receipt
-- that keeps the originally recorded reason_code.
CREATE TABLE IF NOT EXISTS community.post_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id uuid NOT NULL REFERENCES community.user_posts(id) ON DELETE CASCADE,
    reporter_issuer text NOT NULL,
    reporter_subject text NOT NULL,
    reason_code text NOT NULL,
    status text NOT NULL DEFAULT 'open',
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    CONSTRAINT fk_post_reports_reporter
        FOREIGN KEY (reporter_issuer, reporter_subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE,
    CONSTRAINT post_reports_reason_check CHECK (
        reason_code IN (
            'spam_promotion',
            'harassment_hate',
            'explicit_content',
            'privacy_exposure',
            'misinformation',
            'other_policy'
        )
    ),
    CONSTRAINT post_reports_status_check CHECK (
        status IN ('open', 'triaged', 'actioned', 'dismissed')
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_post_reports_unresolved
    ON community.post_reports (reporter_issuer, reporter_subject, post_id)
    WHERE status IN ('open', 'triaged');
