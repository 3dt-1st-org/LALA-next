from __future__ import annotations

import pytest

from apps.api.app.services import rag_retrieval
from apps.api.app.services.rag_index import RagSearchResult


def _result(
    source_type: str,
    source_id: str,
    *,
    similarity: float = 0.0,
    place_id: str | None = None,
    category: str | None = None,
    region_slug: str | None = None,
    language_avail: list[str] | None = None,
    is_indoor: bool | None = None,
) -> RagSearchResult:
    metadata: dict[str, object] = {}
    if category is not None:
        metadata["category"] = category
    if region_slug is not None:
        metadata["region_slug"] = region_slug
    if language_avail is not None:
        metadata["language_avail"] = language_avail
    if is_indoor is not None:
        metadata["is_indoor"] = is_indoor
    return RagSearchResult(
        source_type=source_type,
        source_id=source_id,
        source_table="travel.places",
        title_ko=source_id,
        body_ko=source_id + " 본문",
        place_id=place_id,
        metadata=metadata,
        similarity=similarity,
        embedding_model="local-hash-v1",
        updated_at="2026-07-26T00:00:00+00:00",
    )


def test_rrf_chunk_in_both_legs_outranks_single_leg():
    ann = [
        _result("place_profile", "a", similarity=0.9),
        _result("place_profile", "b", similarity=0.8),
    ]
    keyword = [_result("place_profile", "b"), _result("place_profile", "c")]

    fused = rag_retrieval.reciprocal_rank_fusion(ann, keyword)

    ids = [(c.source_type, c.source_id) for c in fused]
    # 'b' is surfaced by both legs -> highest fused score, ranked first.
    assert ids[0] == ("place_profile", "b")
    assert set(ids) == {("place_profile", "a"), ("place_profile", "b"), ("place_profile", "c")}
    assert len(fused) == 3  # deduped to one entry per (source_type, source_id)


def test_rrf_dedups_and_keeps_higher_similarity_object():
    ann = [_result("place_profile", "a", similarity=0.9)]
    keyword = [_result("place_profile", "a", similarity=0.0)]

    fused = rag_retrieval.reciprocal_rank_fusion(ann, keyword)

    assert len(fused) == 1
    # On a merged key the higher-similarity (ANN) object is retained.
    assert fused[0].similarity == 0.9


def test_rrf_is_deterministic_on_ties():
    ann = [_result("culture_event", "z"), _result("place_profile", "a")]

    fused = rag_retrieval.reciprocal_rank_fusion(ann, [])

    # No keyword leg -> scores follow ANN rank; ties broken by (source_type, source_id).
    assert [(c.source_type, c.source_id) for c in fused] == [
        ("culture_event", "z"),
        ("place_profile", "a"),
    ]


def test_rrf_rejects_non_positive_k():
    with pytest.raises(ValueError):
        rag_retrieval.reciprocal_rank_fusion([], [], k=0)


def test_apply_retrieval_filters_category_and_place():
    candidates = [
        _result("place_profile", "a", place_id="p1", category="restaurant"),
        _result("place_profile", "b", place_id="p1", category="attraction"),
        _result("place_profile", "c", place_id="p2", category="restaurant"),
    ]

    kept = rag_retrieval.apply_retrieval_filters(
        candidates, rag_retrieval.RetrievalFilters(place_id="p1", category="restaurant")
    )

    assert [c.source_id for c in kept] == ["a"]


def test_apply_retrieval_filters_defensive_when_metadata_missing():
    # category filter is set but the chunk's metadata does not carry 'category' -> kept, not
    # dropped (safe before metadata enrichment lands).
    candidates = [_result("place_profile", "a", place_id="p1")]

    kept = rag_retrieval.apply_retrieval_filters(
        candidates, rag_retrieval.RetrievalFilters(place_id="p1", category="restaurant")
    )

    assert [c.source_id for c in kept] == ["a"]


def test_apply_retrieval_filters_language_and_indoor():
    candidates = [
        _result("place_profile", "a", place_id="p1", language_avail=["ko", "en"], is_indoor=True),
        _result("place_profile", "b", place_id="p1", language_avail=["ko"], is_indoor=False),
    ]

    kept = rag_retrieval.apply_retrieval_filters(
        candidates, rag_retrieval.RetrievalFilters(place_id="p1", language="en", is_indoor=True)
    )

    assert [c.source_id for c in kept] == ["a"]


def test_fetch_hybrid_candidates_fuses_legs_without_external_call(monkeypatch):
    ann = [
        _result("place_profile", "a", similarity=0.9),
        _result("place_profile", "b", similarity=0.8),
    ]
    keyword = [_result("place_profile", "b")]
    monkeypatch.setattr(rag_retrieval, "_ann_candidates", lambda **kw: ann)
    monkeypatch.setattr(rag_retrieval, "_keyword_candidates", lambda **kw: keyword)

    # local-hash build_embedding is a pure deterministic fixture -> no live OpenAI call.
    fused = rag_retrieval.fetch_hybrid_candidates(
        dsn="postgresql://redacted",
        query="수원 명소",
        embedding_method="local-hash",
        filters=rag_retrieval.RetrievalFilters(),
        candidate_pool=10,
    )

    assert [c.source_id for c in fused] == ["b", "a"]


def test_fetch_hybrid_candidates_truncates_to_candidate_pool(monkeypatch):
    ann = [_result("place_profile", str(i), similarity=0.9 - i * 0.01) for i in range(5)]
    monkeypatch.setattr(rag_retrieval, "_ann_candidates", lambda **kw: ann)
    monkeypatch.setattr(rag_retrieval, "_keyword_candidates", lambda **kw: [])

    fused = rag_retrieval.fetch_hybrid_candidates(
        dsn="postgresql://redacted",
        query="수원 명소",
        embedding_method="local-hash",
        filters=rag_retrieval.RetrievalFilters(),
        candidate_pool=3,
    )

    assert len(fused) == 3
    assert [c.source_id for c in fused] == ["0", "1", "2"]


def test_fetch_hybrid_candidates_rejects_blank_query():
    with pytest.raises(ValueError):
        rag_retrieval.fetch_hybrid_candidates(
            dsn="postgresql://redacted",
            query="   ",
            embedding_method="local-hash",
            filters=rag_retrieval.RetrievalFilters(),
        )
