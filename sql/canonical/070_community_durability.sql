-- Durable Local Signals mutation/response records share the actor-scoped store.
ALTER TABLE community.idempotency_keys
    DROP CONSTRAINT IF EXISTS idempotency_keys_scope_check;
ALTER TABLE community.idempotency_keys
    ADD CONSTRAINT idempotency_keys_scope_check
    CHECK (scope IN ('community.post.create', 'community.chat.message.create',
                     'community.local_signals'));
