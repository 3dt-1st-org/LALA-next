-- Real-time community chat rooms and messages (P3c).
-- Ported from GEOND_OPIc CommunityRoom/CommunityRoomMessage models, adapted to
-- the LALA identity.users SSOT (author_issuer + author_subject composite) and
-- the community schema established in 060_community_tables.sql.
--
-- Room membership is intentionally lightweight (no owner column) to match the
-- LALA contract: rooms are created via the API and authors are identified by
-- the (issuer, subject) composite which targets identity.users_issuer_subject_key.

CREATE TABLE IF NOT EXISTS community.chat_rooms (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_rooms_created_at
    ON community.chat_rooms (created_at DESC);

CREATE TABLE IF NOT EXISTS community.chat_messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id uuid NOT NULL,
    author_issuer text NOT NULL,
    author_subject text NOT NULL,
    body text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_chat_messages_room
        FOREIGN KEY (room_id)
        REFERENCES community.chat_rooms (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_chat_messages_author
        FOREIGN KEY (author_issuer, author_subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_room
    ON community.chat_messages (room_id, created_at ASC);
