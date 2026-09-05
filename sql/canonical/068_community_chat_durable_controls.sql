-- P7 durable community/chat controls (Session B, 2026-09-05).
-- Additive-only extension of 061_community_chat_tables.sql:
--   1. Explicit room visibility (public default preserves existing rooms and
--      the existing guest-readable public-room semantics) plus a nullable
--      creator identity for ownership.
--   2. Explicit room membership (owner/member rows); private access is only
--      membership/ownership based, never guesswork.
--   3. Durable idempotency keys for retryable community writes: DB unique
--      constraint is the concurrency truth, response replay survives restart.
--   4. Durable single-use WebSocket handshake tickets (sha256-hashed at rest;
--      the raw ticket exists only in the issued response and the query param).
-- Rollback note: every statement is additive and idempotent; reverse by
-- dropping the two new tables/columns added here in a dedicated reversal
-- migration (see devlog runbook).

-- 1. Room visibility + creator. Existing rooms stay public.
ALTER TABLE community.chat_rooms
    ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public';

ALTER TABLE community.chat_rooms
    ADD COLUMN IF NOT EXISTS created_by_issuer text;

ALTER TABLE community.chat_rooms
    ADD COLUMN IF NOT EXISTS created_by_subject text;

ALTER TABLE community.chat_rooms
    DROP CONSTRAINT IF EXISTS chat_rooms_visibility_check;

ALTER TABLE community.chat_rooms
    ADD CONSTRAINT chat_rooms_visibility_check
    CHECK (visibility IN ('public', 'private'));

ALTER TABLE community.chat_rooms
    DROP CONSTRAINT IF EXISTS fk_chat_rooms_creator;

ALTER TABLE community.chat_rooms
    ADD CONSTRAINT fk_chat_rooms_creator
        FOREIGN KEY (created_by_issuer, created_by_subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE SET NULL;

-- A private room must record its creator: this is enforced by the API layer
-- (room creation requires verified OAuth identity) rather than by a CHECK.
-- Reason: created_by_* is ON DELETE SET NULL so account deletion cannot be
-- blocked by this table. After creator deletion a private room simply loses
-- its owner anchor; it stays private (visibility column), remaining member
-- rows keep explicit access, and a room with no owner and no members becomes
-- inert (invisible to everyone, never leaked to public). See devlog runbook.

CREATE INDEX IF NOT EXISTS idx_chat_rooms_visibility
    ON community.chat_rooms (visibility, created_at DESC);

-- 2. Explicit membership. The creator of a private room is inserted as the
-- first 'owner' row by the API in the same transaction that creates the room.
CREATE TABLE IF NOT EXISTS community.chat_room_members (
    room_id uuid NOT NULL,
    issuer text NOT NULL,
    subject text NOT NULL,
    role text NOT NULL DEFAULT 'member',
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (room_id, issuer, subject),
    CONSTRAINT fk_chat_room_members_room
        FOREIGN KEY (room_id)
        REFERENCES community.chat_rooms (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_chat_room_members_member
        FOREIGN KEY (issuer, subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE,
    CONSTRAINT chat_room_members_role_check
        CHECK (role IN ('owner', 'member'))
);

CREATE INDEX IF NOT EXISTS idx_chat_room_members_member
    ON community.chat_room_members (issuer, subject);

-- 3. Durable idempotency records. Primary key is the concurrency truth:
-- concurrent same-key writers serialize here; the loser replays the stored
-- response or is rejected as a payload conflict. A writer first claims the key
-- with response_json = JSON null, performs the guarded insert, then stores the
-- real response -- all in one transaction, so the committed row always carries
-- the full response; a failed business insert rolls the claim back entirely
-- (the key is never burned by a failure). Retention lifecycle is intentional:
-- the actor FK CASCADEs on account deletion (no replay copies of a deleted
-- account's writes survive), and expired rows are purged scope-wide by the API
-- (TTL 24h, see devlog) so retention is bounded even for inactive actors.
CREATE TABLE IF NOT EXISTS community.idempotency_keys (
    scope text NOT NULL,
    actor_issuer text NOT NULL,
    actor_subject text NOT NULL,
    idempotency_key text NOT NULL,
    request_hash text NOT NULL,
    response_json jsonb NOT NULL,
    status_code int NOT NULL DEFAULT 200,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    CONSTRAINT idempotency_keys_scope_check
        CHECK (scope IN ('community.post.create', 'community.chat.message.create')),
    CONSTRAINT idempotency_keys_key_len_check
        CHECK (char_length(idempotency_key) BETWEEN 1 AND 200),
    CONSTRAINT idempotency_keys_hash_len_check
        CHECK (char_length(request_hash) = 64),
    CONSTRAINT fk_idempotency_keys_actor
        FOREIGN KEY (actor_issuer, actor_subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE,
    PRIMARY KEY (scope, actor_issuer, actor_subject, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_idempotency_keys_expiry
    ON community.idempotency_keys (expires_at);

-- 4. WebSocket handshake tickets. Only the sha256 of the raw ticket is
-- stored; `used_at` NULL means claimable. The single UPDATE-with-predicate
-- claim (used_at IS NULL AND expires_at > now()) is atomic in Postgres, so
-- one ticket can open exactly one handshake on any instance. Expired/used
-- rows are pruned per-actor by the issuing endpoint.
CREATE TABLE IF NOT EXISTS community.chat_ws_tickets (
    ticket_hash text PRIMARY KEY,
    room_id uuid NOT NULL,
    issuer text NOT NULL,
    subject text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    CONSTRAINT fk_chat_ws_tickets_room
        FOREIGN KEY (room_id)
        REFERENCES community.chat_rooms (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_chat_ws_tickets_actor
        FOREIGN KEY (issuer, subject)
        REFERENCES identity.users (issuer, subject)
        ON DELETE CASCADE,
    CONSTRAINT chat_ws_tickets_ticket_hash_check
        CHECK (char_length(ticket_hash) = 64)
);

CREATE INDEX IF NOT EXISTS idx_chat_ws_tickets_actor_expiry
    ON community.chat_ws_tickets (issuer, subject, expires_at);
