from __future__ import annotations

from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.services import ai_service, db_repository


def fetch_grounding_context(
    *,
    place_id: str,
    query: str,
    category: str | None,
    language: str | None,
    top_k: int = 3,
) -> dict[str, Any]:
    settings = get_settings()
    mode = _retrieval_mode(settings)
    if mode != "hybrid":
        return {
            "rows": db_repository.fetch_docent_knowledge_context(place_id=place_id, limit=top_k),
            "retrieval": None,
            "mode": mode,
        }
    rerank_enabled = ai_service.rerank_ai_enabled(settings)
    result = db_repository.fetch_docent_knowledge_context_hybrid_result(
        place_id=place_id,
        query=query,
        category=category,
        language=language,
        top_k=top_k,
        embedding_method=None,
        completion_fn=ai_service.rerank_docent_candidates if rerank_enabled else None,
    )
    return {
        "rows": result["rows"],
        "retrieval": result["retrieval"],
        "mode": "hybrid",
    }


def _retrieval_mode(settings: object) -> str:
    mode = str(getattr(settings, "rag_retrieval_mode", "legacy") or "legacy").strip().lower()
    return "hybrid" if mode == "hybrid" else "legacy"
