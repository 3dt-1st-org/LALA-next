"""Hybrid retrieval seam for the RAG docent grounding path.

Combines an ANN cosine leg with a keyword ``ILIKE`` leg (proper-noun strength, the legacy
keyword-RAG parity), narrows both by metadata filters, and fuses them with deterministic
reciprocal-rank fusion. RRF-only by design — there is deliberately **no online mini rerank**
in this slice; ``reranker`` is reported as ``rrf``.

The repository seam ``db_repository.fetch_docent_knowledge_context_hybrid`` consumes
``fetch_hybrid_candidates`` and maps the result onto the legacy grounding row shape so the
docent can use either path behind ``rag_retrieval_mode``.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

from apps.api.app.services.rag_index import (
    EmbeddingMethod,
    RagSearchResult,
    build_embedding,
    vector_to_pgvector,
)

RRF_K_DEFAULT = 60


@dataclass(frozen=True)
class RetrievalFilters:
    """Metadata filters applied to both retrieval legs.

    Filters narrow but never drop a chunk for a key the chunk's metadata does not yet carry,
    so the seam stays safe before metadata enrichment (plan §5.1) lands.
    """

    place_id: str | None = None
    category: str | None = None
    region_slug: str | None = None
    language: str | None = None
    is_indoor: bool | None = None
    source_types: tuple[str, ...] = ()

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def reciprocal_rank_fusion(
    ann_ranked: list[RagSearchResult],
    keyword_ranked: list[RagSearchResult],
    *,
    k: int = RRF_K_DEFAULT,
) -> list[RagSearchResult]:
    """Deterministic reciprocal-rank fusion of ANN and keyword candidate lists.

    Each input list is in rank order (0 = best). ``score(key) = sum 1/(k + rank)`` over every
    list the key appears in, so a chunk surfaced by both legs outranks one surfaced by either
    alone. Output is deduplicated by ``(source_type, source_id)`` and ordered by descending
    fused score; ties are broken by ``(source_type, source_id)`` for stable output. When a key
    appears in both legs the higher-similarity object is kept.
    """
    if k <= 0:
        raise ValueError("k must be positive.")

    scores: dict[tuple[str, str], float] = {}
    best: dict[tuple[str, str], RagSearchResult] = {}

    def track(ranked: list[RagSearchResult]) -> None:
        for rank, item in enumerate(ranked):
            key = (item.source_type, item.source_id)
            scores[key] = scores.get(key, 0.0) + 1.0 / (k + rank)
            prior = best.get(key)
            if prior is None or item.similarity > prior.similarity:
                best[key] = item

    track(ann_ranked)
    track(keyword_ranked)

    ordered = sorted(scores, key=lambda key: (-scores[key], key[0], key[1]))
    return [best[key] for key in ordered]


def apply_retrieval_filters(
    candidates: list[RagSearchResult],
    filters: RetrievalFilters,
) -> list[RagSearchResult]:
    """Narrow candidates by ``RetrievalFilters``. A filter is only applied when the chunk's
    metadata actually carries the corresponding key (defensive against partial enrichment)."""
    return [item for item in candidates if _matches_filters(item, filters)]


def _matches_filters(item: RagSearchResult, filters: RetrievalFilters) -> bool:
    if filters.place_id and (item.place_id or None) != filters.place_id:
        return False
    if filters.source_types and item.source_type not in filters.source_types:
        return False
    meta = item.metadata or {}
    if filters.category:
        chunk_category = meta.get("category")
        if (
            chunk_category is not None
            and str(chunk_category).strip().lower() != filters.category.lower()
        ):
            return False
    if filters.region_slug:
        chunk_region = meta.get("region_slug") or meta.get("region_name_ko")
        if (
            chunk_region is not None
            and filters.region_slug.lower() not in str(chunk_region).lower()
        ):
            return False
    if filters.language:
        language_avail = meta.get("language_avail")
        if (
            isinstance(language_avail, list)
            and language_avail
            and filters.language not in language_avail
        ):
            return False
    if filters.is_indoor is not None:
        chunk_indoor = meta.get("is_indoor")
        if chunk_indoor is not None and bool(chunk_indoor) != filters.is_indoor:
            return False
    return True


def fetch_hybrid_candidates(
    *,
    dsn: str,
    query: str,
    embedding_method: EmbeddingMethod,
    filters: RetrievalFilters,
    candidate_pool: int = 20,
    ann_top_k: int | None = None,
    keyword_top_k: int | None = None,
    connect_timeout: int = 3,
) -> list[RagSearchResult]:
    """Run ANN + keyword legs, narrow each by ``filters``, fuse by deterministic RRF.

    Returns the deduplicated, RRF-ordered candidate list (``RagSearchResult``), truncated to
    ``candidate_pool``. Raises ``ValueError`` on invalid arguments before any DB work.
    """
    if not dsn:
        raise ValueError("DB_DSN is required.")
    if not query.strip():
        raise ValueError("query is required.")
    if candidate_pool <= 0:
        raise ValueError("candidate_pool must be positive.")

    ann_k = ann_top_k or candidate_pool
    keyword_k = keyword_top_k or candidate_pool
    place_id = filters.place_id
    source_types = filters.source_types

    query_embedding, _ = build_embedding(query, method=embedding_method)
    ann = apply_retrieval_filters(
        _ann_candidates(
            dsn=dsn,
            query_embedding=query_embedding,
            top_k=ann_k,
            place_id=place_id,
            source_types=source_types,
            connect_timeout=connect_timeout,
        ),
        filters,
    )
    keyword = apply_retrieval_filters(
        _keyword_candidates(
            dsn=dsn,
            query=query.strip(),
            top_k=keyword_k,
            place_id=place_id,
            source_types=source_types,
            connect_timeout=connect_timeout,
        ),
        filters,
    )
    fused = reciprocal_rank_fusion(ann, keyword, k=RRF_K_DEFAULT)
    return fused[:candidate_pool]


def _ann_candidates(
    *,
    dsn: str,
    query_embedding: list[float],
    top_k: int,
    place_id: str | None,
    source_types: tuple[str, ...],
    connect_timeout: int,
) -> list[RagSearchResult]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    query_vector = vector_to_pgvector(query_embedding)
    clauses = ["embedding IS NOT NULL"]
    params: list[Any] = [query_vector]
    if place_id:
        clauses.append("place_id = %s")
        params.append(place_id)
    if source_types:
        placeholders = ", ".join(["%s"] * len(source_types))
        clauses.append(f"source_type IN ({placeholders})")
        params.extend(source_types)
    sql = f"""
        SELECT
            source_type, source_id, source_table, place_id, title_ko, body_ko, body_en,
            metadata, content_sha256, embedding_model, updated_at,
            1 - (embedding <=> %s::vector) AS similarity
        FROM rag.knowledge_chunks
        WHERE {" AND ".join(clauses)}
        ORDER BY embedding <=> %s::vector
        LIMIT %s
    """
    params.extend([query_vector, top_k])
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, params)
            return [RagSearchResult.from_row(dict(row)) for row in cur.fetchall()]


def _keyword_candidates(
    *,
    dsn: str,
    query: str,
    top_k: int,
    place_id: str | None,
    source_types: tuple[str, ...],
    connect_timeout: int,
) -> list[RagSearchResult]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    clauses = [
        "NULLIF(TRIM(body_ko), '') IS NOT NULL",
        "(COALESCE(title_ko,'') || ' ' || COALESCE(body_ko,'') || ' ' || COALESCE(body_en,'')) ILIKE %s",
    ]
    params: list[Any] = [f"%{query}%"]
    if place_id:
        clauses.append("place_id = %s")
        params.append(place_id)
    if source_types:
        placeholders = ", ".join(["%s"] * len(source_types))
        clauses.append(f"source_type IN ({placeholders})")
        params.extend(source_types)
    # Keyword leg carries no cosine similarity; similarity stays 0 so it never wins an
    # RRF object tie against a real ANN hit (RRF rank, not similarity, drives fusion order).
    sql = f"""
        SELECT
            source_type, source_id, source_table, place_id, title_ko, body_ko, body_en,
            metadata, content_sha256, embedding_model, updated_at,
            0.0::float AS similarity
        FROM rag.knowledge_chunks
        WHERE {" AND ".join(clauses)}
        ORDER BY updated_at DESC, source_id
        LIMIT %s
    """
    params.append(top_k)
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, params)
            return [RagSearchResult.from_row(dict(row)) for row in cur.fetchall()]
