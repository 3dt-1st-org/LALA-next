-- RAG knowledge chunks for static and dynamic local context.

CREATE TABLE IF NOT EXISTS rag.knowledge_chunks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source_type text NOT NULL,
    source_id text NOT NULL,
    source_table text NOT NULL,
    place_id text REFERENCES travel.places(place_id),
    title_ko text,
    body_ko text NOT NULL,
    body_en text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    embedding vector(1536),
    embedding_model text,
    embedding_method text NOT NULL DEFAULT 'local_hash',
    content_sha256 text NOT NULL,
    last_embedded_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_type, source_id),
    CONSTRAINT knowledge_chunks_source_type_check CHECK (
        source_type IN (
            'place_profile',
            'culture_event',
            'community_post',
            'place_mention',
            'weather_context'
        )
    )
);

CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_place_id
    ON rag.knowledge_chunks (place_id)
    WHERE place_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_source_type_updated_at
    ON rag.knowledge_chunks (source_type, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_content_sha256
    ON rag.knowledge_chunks (content_sha256);

CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_embedding_cosine
    ON rag.knowledge_chunks
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 32)
    WHERE embedding IS NOT NULL;
