-- Local Signals contract: first-party, place/route-scoped community signals.
-- Additive and re-runnable. This migration deliberately has no coordinates,
-- third-party provider payload, review URL, or public identity projection.

CREATE TABLE IF NOT EXISTS community.local_signals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    author_issuer text,
    author_subject text,
    kind text NOT NULL,
    status text NOT NULL DEFAULT 'draft',
    moderation_state text NOT NULL DEFAULT 'unreviewed',
    visibility text NOT NULL DEFAULT 'private',
    source_language text NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    locality_level text NOT NULL DEFAULT 'district',
    locality_code text,
    commercial_disclosure text NOT NULL DEFAULT 'none',
    observation_date date NOT NULL,
    aggregate_opt_in boolean NOT NULL DEFAULT false,
    source_kind text NOT NULL DEFAULT 'first_party',
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_local_signals_author
        FOREIGN KEY (author_issuer, author_subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE SET NULL,
    CONSTRAINT local_signals_author_pair_check CHECK (
        (author_issuer IS NULL AND author_subject IS NULL)
        OR (author_issuer IS NOT NULL AND author_subject IS NOT NULL)
    ),
    CONSTRAINT local_signals_kind_check CHECK (
        kind IN (
            'place_tip',
            'route_note',
            'local_question',
            'accessibility_note',
            'seasonal_update',
            'correction',
            'local_story'
        )
    ),
    CONSTRAINT local_signals_status_check CHECK (
        status IN ('draft', 'submitted', 'published', 'hidden', 'removed', 'deleted')
    ),
    CONSTRAINT local_signals_moderation_state_check CHECK (
        moderation_state IN ('unreviewed', 'pending', 'approved', 'rejected')
    ),
    CONSTRAINT local_signals_visibility_check CHECK (
        visibility IN ('private', 'pending_review', 'public', 'unlisted')
    ),
    CONSTRAINT local_signals_language_check CHECK (source_language IN ('ko', 'en')),
    CONSTRAINT local_signals_title_length_check CHECK (char_length(title) BETWEEN 1 AND 160),
    CONSTRAINT local_signals_body_length_check CHECK (char_length(body) BETWEEN 1 AND 4000),
    CONSTRAINT local_signals_locality_check CHECK (
        locality_level IN ('none', 'province', 'city', 'district', 'place')
    ),
    CONSTRAINT local_signals_locality_code_check CHECK (
        locality_code IS NULL
        OR locality_code ~ '^[A-Za-z0-9][A-Za-z0-9:_-]{0,63}$'
    ),
    CONSTRAINT local_signals_disclosure_check CHECK (
        commercial_disclosure IN ('none', 'visitor', 'owner_or_staff', 'paid_or_gifted')
    ),
    CONSTRAINT local_signals_source_kind_check CHECK (source_kind = 'first_party'),
    CONSTRAINT local_signals_publication_check CHECK (
        status <> 'published' OR published_at IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS idx_local_signals_public_feed
    ON community.local_signals (published_at DESC, id DESC)
    WHERE status = 'published' AND visibility = 'public';
CREATE INDEX IF NOT EXISTS idx_local_signals_locality
    ON community.local_signals (locality_level, locality_code, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_local_signals_author
    ON community.local_signals (author_issuer, author_subject, created_at DESC);

CREATE TABLE IF NOT EXISTS community.local_signal_places (
    signal_id uuid NOT NULL REFERENCES community.local_signals(id) ON DELETE CASCADE,
    place_id text NOT NULL REFERENCES travel.places(place_id),
    relation text NOT NULL DEFAULT 'primary',
    source_confidence numeric(5, 4),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (signal_id, place_id, relation),
    CONSTRAINT local_signal_places_relation_check CHECK (
        relation IN ('primary', 'context', 'route_stop')
    ),
    CONSTRAINT local_signal_places_confidence_check CHECK (
        source_confidence IS NULL OR source_confidence BETWEEN 0 AND 1
    )
);

CREATE INDEX IF NOT EXISTS idx_local_signal_places_place
    ON community.local_signal_places (place_id, signal_id);

CREATE TABLE IF NOT EXISTS community.local_signal_routes (
    signal_id uuid PRIMARY KEY REFERENCES community.local_signals(id) ON DELETE CASCADE,
    route_snapshot_ref text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT local_signal_routes_ref_check CHECK (
        route_snapshot_ref ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
    )
);

CREATE TABLE IF NOT EXISTS community.local_signal_translations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    signal_id uuid NOT NULL REFERENCES community.local_signals(id) ON DELETE CASCADE,
    target_language text NOT NULL,
    body text NOT NULL,
    translation_method text NOT NULL,
    translator_version text NOT NULL,
    source_content_hash text NOT NULL,
    provenance text NOT NULL,
    review_state text NOT NULL DEFAULT 'pending',
    reviewed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT local_signal_translations_language_check CHECK (
        target_language IN ('ko', 'en')
    ),
    CONSTRAINT local_signal_translations_body_length_check CHECK (
        char_length(body) BETWEEN 1 AND 4000
    ),
    CONSTRAINT local_signal_translations_method_check CHECK (
        translation_method IN ('human', 'machine', 'community_reviewed')
    ),
    CONSTRAINT local_signal_translations_hash_check CHECK (
        source_content_hash ~ '^[0-9a-f]{64}$'
    ),
    CONSTRAINT local_signal_translations_provenance_check CHECK (
        provenance IN ('author_source', 'human_review', 'machine_reviewed', 'community_reviewed')
    ),
    CONSTRAINT local_signal_translations_state_check CHECK (
        review_state IN ('pending', 'available', 'stale', 'rejected')
    ),
    UNIQUE (signal_id, target_language, source_content_hash)
);

CREATE INDEX IF NOT EXISTS idx_local_signal_translations_signal
    ON community.local_signal_translations (signal_id, target_language, review_state);

CREATE TABLE IF NOT EXISTS community.local_signal_reactions (
    signal_id uuid NOT NULL REFERENCES community.local_signals(id) ON DELETE CASCADE,
    issuer text NOT NULL,
    subject text NOT NULL,
    reaction_type text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (signal_id, issuer, subject, reaction_type),
    CONSTRAINT fk_local_signal_reactions_actor
        FOREIGN KEY (issuer, subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE,
    CONSTRAINT local_signal_reactions_type_check CHECK (
        reaction_type IN ('useful', 'respectful', 'needs_confirmation')
    )
);

CREATE TABLE IF NOT EXISTS community.local_signal_comments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    signal_id uuid NOT NULL REFERENCES community.local_signals(id) ON DELETE CASCADE,
    parent_id uuid REFERENCES community.local_signal_comments(id) ON DELETE CASCADE,
    author_issuer text,
    author_subject text,
    source_language text NOT NULL,
    body text NOT NULL,
    status text NOT NULL DEFAULT 'submitted',
    depth smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_local_signal_comments_author
        FOREIGN KEY (author_issuer, author_subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE SET NULL,
    CONSTRAINT local_signal_comments_author_pair_check CHECK (
        (author_issuer IS NULL AND author_subject IS NULL)
        OR (author_issuer IS NOT NULL AND author_subject IS NOT NULL)
    ),
    CONSTRAINT local_signal_comments_language_check CHECK (source_language IN ('ko', 'en')),
    CONSTRAINT local_signal_comments_body_length_check CHECK (char_length(body) BETWEEN 1 AND 1200),
    CONSTRAINT local_signal_comments_status_check CHECK (
        status IN ('submitted', 'published', 'hidden', 'removed', 'deleted')
    ),
    CONSTRAINT local_signal_comments_depth_check CHECK (
        (parent_id IS NULL AND depth = 0) OR (parent_id IS NOT NULL AND depth = 1)
    )
);

CREATE INDEX IF NOT EXISTS idx_local_signal_comments_signal
    ON community.local_signal_comments (signal_id, created_at ASC, id ASC);

CREATE TABLE IF NOT EXISTS community.local_signal_saves (
    signal_id uuid NOT NULL REFERENCES community.local_signals(id) ON DELETE CASCADE,
    issuer text NOT NULL,
    subject text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (signal_id, issuer, subject),
    CONSTRAINT fk_local_signal_saves_actor
        FOREIGN KEY (issuer, subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS community.local_signal_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    reporter_issuer text,
    reporter_subject text,
    reason_code text NOT NULL,
    status text NOT NULL DEFAULT 'open',
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    CONSTRAINT fk_local_signal_reports_reporter
        FOREIGN KEY (reporter_issuer, reporter_subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE SET NULL,
    CONSTRAINT local_signal_reports_reporter_pair_check CHECK (
        (reporter_issuer IS NULL AND reporter_subject IS NULL)
        OR (reporter_issuer IS NOT NULL AND reporter_subject IS NOT NULL)
    ),
    CONSTRAINT local_signal_reports_target_check CHECK (
        target_type IN ('signal', 'comment')
    ),
    CONSTRAINT local_signal_reports_reason_check CHECK (
        reason_code IN (
            'unsafe_content',
            'privacy_exposure',
            'misleading_place',
            'promotion_not_disclosed',
            'translation_issue',
            'other_policy'
        )
    ),
    CONSTRAINT local_signal_reports_status_check CHECK (
        status IN ('open', 'triaged', 'actioned', 'dismissed')
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_local_signal_reports_unresolved
    ON community.local_signal_reports (reporter_issuer, reporter_subject, target_type, target_id, reason_code)
    WHERE status IN ('open', 'triaged');

CREATE TABLE IF NOT EXISTS community.local_signal_moderation_actions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    action_type text NOT NULL,
    reason_code text NOT NULL,
    actor_issuer text,
    actor_subject text,
    policy_version text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_local_signal_moderation_actor
        FOREIGN KEY (actor_issuer, actor_subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE SET NULL,
    CONSTRAINT local_signal_moderation_actor_pair_check CHECK (
        (actor_issuer IS NULL AND actor_subject IS NULL)
        OR (actor_issuer IS NOT NULL AND actor_subject IS NOT NULL)
    ),
    CONSTRAINT local_signal_moderation_target_check CHECK (
        target_type IN ('signal', 'comment')
    ),
    CONSTRAINT local_signal_moderation_action_check CHECK (
        action_type IN ('submit', 'publish', 'hide', 'remove', 'restore', 'delete', 'redact')
    )
);

CREATE INDEX IF NOT EXISTS idx_local_signal_moderation_target
    ON community.local_signal_moderation_actions (target_type, target_id, created_at DESC);

CREATE TABLE IF NOT EXISTS community.local_signal_capabilities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    signal_id uuid NOT NULL REFERENCES community.local_signals(id) ON DELETE CASCADE,
    token_sha256 bytea NOT NULL,
    scope text NOT NULL DEFAULT 'read',
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT local_signal_capabilities_hash_check CHECK (octet_length(token_sha256) = 32),
    CONSTRAINT local_signal_capabilities_scope_check CHECK (scope = 'read')
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_local_signal_capabilities_active
    ON community.local_signal_capabilities (signal_id, token_sha256)
    WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS community.local_signal_aggregate_eligibility (
    signal_id uuid PRIMARY KEY REFERENCES community.local_signals(id) ON DELETE CASCADE,
    eligibility_status text NOT NULL DEFAULT 'ineligible',
    aggregate_opt_in boolean NOT NULL DEFAULT false,
    moderation_passed boolean NOT NULL DEFAULT false,
    independent_signal_count integer NOT NULL DEFAULT 0,
    minimum_signal_count integer NOT NULL DEFAULT 3,
    aggregate_scope text,
    delayed_until timestamptz,
    safe_summary_hash text,
    policy_version text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT local_signal_aggregate_status_check CHECK (
        eligibility_status IN ('ineligible', 'eligible', 'revoked')
    ),
    CONSTRAINT local_signal_aggregate_count_check CHECK (
        independent_signal_count >= 0 AND minimum_signal_count >= 3
    ),
    CONSTRAINT local_signal_aggregate_scope_check CHECK (
        aggregate_scope IS NULL OR aggregate_scope IN ('place_week', 'district_week')
    ),
    CONSTRAINT local_signal_aggregate_hash_check CHECK (
        safe_summary_hash IS NULL OR safe_summary_hash ~ '^[0-9a-f]{64}$'
    ),
    CONSTRAINT local_signal_aggregate_eligible_gate CHECK (
        eligibility_status <> 'eligible'
        OR (
            aggregate_opt_in
            AND moderation_passed
            AND aggregate_scope IS NOT NULL
            AND safe_summary_hash IS NOT NULL
        )
    )
);

-- Public reads use this projection so author identity and moderation internals
-- cannot leak through a normal community query.
CREATE OR REPLACE VIEW community.local_signal_public AS
SELECT
    id,
    kind,
    source_language,
    title,
    body,
    locality_level,
    locality_code,
    commercial_disclosure,
    observation_date,
    published_at,
    created_at,
    updated_at
FROM community.local_signals
WHERE status = 'published'
  AND moderation_state = 'approved'
  AND visibility = 'public';

-- RAG/aggregate workers receive eligibility metadata only; the signal body is
-- intentionally absent so a worker cannot embed an individual contribution.
CREATE OR REPLACE VIEW community.local_signal_aggregate_candidates AS
SELECT
    eligibility.signal_id,
    signal.kind,
    signal.source_language,
    signal.locality_level,
    signal.locality_code,
    signal.observation_date,
    eligibility.aggregate_scope,
    eligibility.independent_signal_count,
    eligibility.minimum_signal_count,
    eligibility.delayed_until,
    eligibility.safe_summary_hash,
    eligibility.policy_version
FROM community.local_signal_aggregate_eligibility AS eligibility
JOIN community.local_signals AS signal ON signal.id = eligibility.signal_id
WHERE signal.status = 'published'
  AND signal.moderation_state = 'approved'
  AND signal.visibility = 'public'
  AND eligibility.eligibility_status = 'eligible';
