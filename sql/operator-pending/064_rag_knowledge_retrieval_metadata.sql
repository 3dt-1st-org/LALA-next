-- RAG V1 retrieval + reindex lifecycle metadata (additive).
--
-- UNAPPLIED: this migration is kept unapplied and is applied only through a separate
-- ALLOW_CANONICAL_SQL_APPLY=1 rollout. It is strictly additive (ADD COLUMN IF NOT EXISTS /
-- CREATE INDEX IF NOT EXISTS) and non-destructive — rollback never requires a destructive
-- migration.
--
-- Companion to apps/api/app/services/rag_index.py (embedding_generation reindex lifecycle)
-- and apps/api/app/services/rag_retrieval.py (hybrid retrieval filters). Runtime code that
-- reads embedding_generation degrades safely until this migration is applied.

ALTER TABLE rag.knowledge_chunks
    ADD COLUMN IF NOT EXISTS embedding_generation int NOT NULL DEFAULT 0;

-- Reindex worker stale selection: chunks whose embedding_generation lags the serving
-- generation, or whose embedding is null, are picked up in bounded, resumable batches.
CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_embedding_generation
    ON rag.knowledge_chunks (embedding_generation)
    WHERE embedding IS NOT NULL;

-- Hybrid retrieval narrows by metadata keys (category / region_slug / language_avail /
-- is_indoor). A GIN index lets those filters run without re-joining source tables.
CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_metadata_gin
    ON rag.knowledge_chunks USING GIN (metadata jsonb_path_ops);
