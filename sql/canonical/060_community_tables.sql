-- User-generated community content: posts, comments, likes, follows.
-- Ported from GEOND_OPIc community models (CommunityPost/Comment/PostLike/UserFollow),
-- adapted to the LALA identity.users SSOT and envelope contract.
--
-- NOTE: the existing community.posts table (030) holds provider-scraped posts
-- (provider/external_key). To avoid that collision, user-generated content lives
-- under distinct table names: user_posts / post_comments / post_likes / user_follows.
-- Authors are referenced by the (issuer, subject) composite which targets the
-- identity.users_issuer_subject_key unique constraint (identity SSOT).

CREATE TABLE IF NOT EXISTS community.user_posts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    author_issuer text NOT NULL,
    author_subject text NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    tags text[] NOT NULL DEFAULT '{}',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_user_posts_author
        FOREIGN KEY (author_issuer, author_subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_posts_created_at
    ON community.user_posts (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_posts_author
    ON community.user_posts (author_issuer, author_subject, created_at DESC);

CREATE TABLE IF NOT EXISTS community.post_comments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id uuid NOT NULL,
    author_issuer text NOT NULL,
    author_subject text NOT NULL,
    body text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_post_comments_post
        FOREIGN KEY (post_id)
        REFERENCES community.user_posts (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_post_comments_author
        FOREIGN KEY (author_issuer, author_subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_post_comments_post
    ON community.post_comments (post_id, created_at ASC);

CREATE TABLE IF NOT EXISTS community.post_likes (
    post_id uuid NOT NULL,
    issuer text NOT NULL,
    subject text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, issuer, subject),
    CONSTRAINT fk_post_likes_post
        FOREIGN KEY (post_id)
        REFERENCES community.user_posts (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_post_likes_author
        FOREIGN KEY (issuer, subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS community.user_follows (
    follower_issuer text NOT NULL,
    follower_subject text NOT NULL,
    followee_issuer text NOT NULL,
    followee_subject text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_issuer, follower_subject, followee_issuer, followee_subject),
    CONSTRAINT fk_user_follows_follower
        FOREIGN KEY (follower_issuer, follower_subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE,
    CONSTRAINT fk_user_follows_followee
        FOREIGN KEY (followee_issuer, followee_subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_follows_follower
    ON community.user_follows (follower_issuer, follower_subject, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_follows_followee
    ON community.user_follows (followee_issuer, followee_subject, created_at DESC);
