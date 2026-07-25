"""Governed review-evidence -> RAG handoff (Improvement C).

Bridge that turns an :class:`ApprovedReviewAggregate` (the only review-derived
payload the governance boundary emits) into a grounded, aggregate-only
``place_mention`` :class:`rag_index.KnowledgeChunk`, plus an explicit rebuild /
invalidation signal that a later apply step consumes via the existing
``rag_index.upsert_knowledge_chunks``.

This module is deliberately **outside** ``review_ingest_governance``: governance
must not couple to the RAG write path
(``test_governance_module_does_not_couple_to_rag_write_path``). It is the one
directional seam that *reads* aggregates and *produces* RAG inputs.

Hard contract:
  * The chunk body and metadata are built **only** from aggregate signals --
    place name, category, counts, sentiment, attribute scores, schema versions.
    No body/title/url/post_link is ever read or emitted. Every metadata payload
    is guarded by ``enforce_no_raw_review_text``.
  * The chunk ``content_sha256`` is deterministic in the aggregate, so an exact
    replay yields the same chunk id and the rebuild signal reports ``changed=False``
    (no duplicate RAG work). A content revision changes the sha and is the
    explicit rebuild trigger.
  * The handoff performs **no DB write** and no network call. It only builds
    chunks + signals; the apply step (``upsert_knowledge_chunks``) owns the write
    behind the existing apply-guard / transaction conventions.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import Any

from apps.api.app.services.rag_index import KnowledgeChunk
from apps.api.app.services.review_ingest_governance import (
    GOVERNANCE_SCHEMA_VERSION,
    ApprovedReviewAggregate,
    enforce_no_raw_review_text,
)

# source_table label for governed review-evidence chunks. Honest about origin:
# these chunks are derived from governed review ingest receipts/aggregates, not
# from any raw review table.
GOVERNED_EVIDENCE_SOURCE_TABLE = "ingest.review_ingest_receipts"
# ad_filter_version carried in chunk metadata, matching the preprocessing
# strategy doc contract (rag-regeneration-strategy.md:119-127).
AD_FILTER_VERSION = "review-mention-preprocess-v1"


def _category_label_ko(category: str | None) -> str:
    return {
        "restaurant": "맛집",
        "attraction": "명소",
        "event": "행사",
        "culture_venue": "문화공간",
    }.get((category or "").strip(), "장소")


def aggregate_to_place_mention_chunk(
    aggregate: ApprovedReviewAggregate,
    *,
    place_id: str,
    place_name_ko: str,
) -> KnowledgeChunk:
    """Build a grounded, aggregate-only ``place_mention`` chunk for an accepted
    review aggregate.

    The body is assembled from controlled aggregate fields only -- never from
    review text. ``category`` is carried in metadata so the docent-side food-rule
    guard (``_is_noisy_attraction_review_context``) keeps working for governed
    evidence. Raises if any forbidden raw-text field somehow enters metadata.
    """
    category = aggregate.category
    mention_count = int(aggregate.mention_count)
    organic_count = int(aggregate.organic_mention_count)
    sentiment = aggregate.sentiment_score
    attribute_scores = dict(aggregate.attribute_scores)

    # Body is aggregate-only by construction (counts/scores/labels). No raw text
    # is read or interpolated -- the aggregate carries none.
    body_parts: list[str] = [
        f"{place_name_ko}의 거버넌스 통과 리뷰 집계 신호입니다.",
        f"카테고리는 {_category_label_ko(category)}입니다.",
        f"전체 언급은 {mention_count}회, 광고/비유기적 제외 후 유기적 언급은 {organic_count}회입니다.",
    ]
    if sentiment is not None:
        body_parts.append(f"감성 점수는 {round(float(sentiment), 4)}입니다.")
    if attribute_scores:
        rendered = ", ".join(
            f"{key}={round(float(value), 4)}" for key, value in sorted(attribute_scores.items())
        )
        body_parts.append(f"속성 점수는 {rendered}입니다.")
    body_ko = " ".join(body_parts)

    metadata: dict[str, Any] = {
        "schema_version": GOVERNANCE_SCHEMA_VERSION,
        "ad_filter_version": AD_FILTER_VERSION,
        "prompt_version": GOVERNANCE_SCHEMA_VERSION,
        "category": category,
        "source_name": aggregate.source_name,
        "aggregate_key": aggregate.aggregate_key,
        "mention_count": mention_count,
        "organic_mention_count": organic_count,
        "sentiment_score": (round(float(sentiment), 4) if sentiment is not None else None),
        "attribute_scores": attribute_scores,
        "source_freshness": "governed_aggregate",
    }
    # Defense-in-depth: metadata must never carry a raw-text field.
    enforce_no_raw_review_text(metadata, label="governed_place_mention_metadata")

    return KnowledgeChunk(
        source_type="place_mention",
        source_id=f"governed_mention:{aggregate.aggregate_key}",
        source_table=GOVERNED_EVIDENCE_SOURCE_TABLE,
        place_id=place_id or None,
        title_ko=place_name_ko,
        body_ko=body_ko,
        metadata=metadata,
    )


def rebuild_signals(
    chunks: Iterable[KnowledgeChunk],
    *,
    previous_shas: Mapping[str, str] | None = None,
) -> list[dict[str, Any]]:
    """Compute the explicit rebuild / invalidation signal for a set of chunks.

    ``previous_shas`` maps ``source_id`` -> the currently-stored
    ``content_sha256`` (read before upsert). A chunk whose sha differs (or is new)
    reports ``changed=True`` -- the explicit rebuild trigger the RAG apply step
    must act on. An exact replay (same sha) reports ``changed=False`` so the
    apply step does not re-emit / double-count RAG work.
    """
    prior = previous_shas or {}
    signals: list[dict[str, Any]] = []
    for chunk in chunks:
        previous = prior.get(chunk.source_id)
        signals.append(
            {
                "source_type": chunk.source_type,
                "source_id": chunk.source_id,
                "content_sha256": chunk.content_sha256,
                "changed": previous != chunk.content_sha256,
            }
        )
    return signals


def changed_signals(
    chunks: Iterable[KnowledgeChunk],
    *,
    previous_shas: Mapping[str, str] | None = None,
) -> list[dict[str, Any]]:
    """Convenience: only the rebuild signals that require action (``changed=True``)."""
    return [
        signal
        for signal in rebuild_signals(chunks, previous_shas=previous_shas)
        if signal["changed"]
    ]
