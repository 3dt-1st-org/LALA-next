from __future__ import annotations

import hashlib
import json
import time
from collections.abc import Sequence
from dataclasses import dataclass, replace
from datetime import UTC, date, datetime
from typing import Any

from apps.api.app.core.config import get_settings, resolve_openai_base_url_host
from apps.api.app.services.model_client import resolve
from apps.api.app.services.review_ingest_governance import ALLOWED_LICENSE_CLASSES

PROMPT_VERSION = "review-attributes-v1"
RECHECK_PROMPT_VERSION = "review-attributes-recheck-v1"
DETERMINISTIC_VERSION = "review-attributes-deterministic-v1"
QUALITY_VERSION = "review-quality-v1"
JOB_NAME = "review-attribute-batch"
# Improvement B: enrichments whose attribute or sentiment confidence falls below
# this are routed to the selective mini-model recheck instead of being trusted as
# bulk output. Below the quality-formula's <10-organic cap of 0.65.
RECHECK_CONFIDENCE_THRESHOLD = 0.6
AD_CONFIDENCE_FILTER_THRESHOLD = 0.8
SAFE_AD_REASONS = frozenset(
    {
        "organic",
        "advertising_suspected",
        "sponsored_suspected",
        "ambiguous_ad_signal",
        "insufficient_evidence",
    }
)

ATTRIBUTE_TERMS = {
    "taste": ("맛있", "맛집", "메뉴", "커피", "디저트", "고기", "반찬", "브런치", "향"),
    "service": ("친절", "서비스", "응대", "안내", "편리", "예약", "설명"),
    "price": ("가성비", "가격", "비싸", "저렴", "합리"),
    "atmosphere": ("조용", "쾌적", "분위기", "예쁘", "멋", "야경", "포토존", "감성"),
    "cleanliness": ("깨끗", "청결", "깔끔"),
    "wait_crowding": ("웨이팅", "대기", "붐비", "혼잡", "한산"),
    "cultural_story": ("역사", "문화", "전시", "작품", "건축", "이야기", "해설"),
    "walking_comfort": ("산책", "동선", "걷기", "그늘", "길", "코스"),
    "photo_view": ("사진", "포토존", "전망", "뷰", "야경"),
    "practical_tip": ("주차", "예약", "시간", "입장", "동선", "팁"),
    "crowding": ("붐비", "혼잡", "한산", "여유"),
    "program_quality": ("공연", "프로그램", "축제", "무대", "체험", "전시"),
    "family_friendliness": ("아이", "가족", "어르신", "부모", "함께"),
    "foreign_visitor_fit": ("외국인", "영어", "안내", "표지", "언어"),
    "access": ("역", "버스", "주차", "접근", "도보"),
    "weather_indoor_fit": ("실내", "우천", "더위", "추위", "비", "눈"),
    "local_experience": ("로컬", "동네", "주변", "시장", "골목", "지역", "상권"),
}

RESTAURANT_ATTRIBUTES = (
    "taste",
    "service",
    "price",
    "atmosphere",
    "cleanliness",
    "wait_crowding",
)
ATTRACTION_ATTRIBUTES = (
    "cultural_story",
    "atmosphere",
    "walking_comfort",
    "photo_view",
    "practical_tip",
    "crowding",
)
EVENT_ATTRIBUTES = (
    "program_quality",
    "family_friendliness",
    "foreign_visitor_fit",
    "access",
    "weather_indoor_fit",
    "crowding",
)

BULK_SYSTEM_PROMPT = """\
You extract structured review attributes for LALA, a Korean local travel app.

Return ONLY a JSON object:
{
  "results": [
    {
      "mention_id": "same id as input",
      "schema_version": "review-attributes-v1",
      "sentiment_score": -1.0 to 1.0,
      "sentiment_confidence": 0.0 to 1.0,
      "attribute_scores": {"attribute_name": 0.0 to 1.0},
      "attribute_confidence_avg": 0.0 to 1.0,
      "is_ad": true or false,
      "ad_confidence": 0.0 to 1.0,
      "ad_reason": "organic|advertising_suspected|sponsored_suspected|ambiguous_ad_signal|insufficient_evidence"
    }
  ]
}

Rules:
1. Use only supplied retained organic review snippets and aggregate terms.
2. Do not invent hours, prices, menus, historical facts, weather, or crowd status.
3. Restaurants may use taste, menu, service, price, atmosphere, cleanliness, and wait/crowding evidence.
4. Attractions and culture venues must not treat unrelated food/cafe text as place quality.
5. Events should prioritize program quality, access, family/foreign visitor fit, weather/indoor fit, and crowding.
6. Do not return evidence phrases, summaries, raw text, or free-form reasons.
7. Return every input mention_id exactly once, with all required fields.
"""

# Recheck is deliberately a resolution lane, not a docent or final-QA lane.
RECHECK_SYSTEM_PROMPT = """\
You selectively recheck uncertain structured review attributes for LALA.

Return ONLY a JSON object with one result per input mention:
{
  "results": [
    {
      "mention_id": "same id as input",
      "schema_version": "review-attributes-recheck-v1",
      "decision": "confirmed|still_uncertain|rejected",
      "sentiment_score": -1.0 to 1.0,
      "sentiment_confidence": 0.0 to 1.0,
      "attribute_scores": {"attribute_name": 0.0 to 1.0},
      "attribute_confidence_avg": 0.0 to 1.0,
      "is_ad": true or false,
      "ad_confidence": 0.0 to 1.0,
      "ad_reason": "organic|advertising_suspected|sponsored_suspected|ambiguous_ad_signal|insufficient_evidence"
    }
  ]
}

Use only the supplied retained organic snippets and aggregate terms. Do not
return evidence phrases, summaries, raw text, or free-form reasons. A
still_uncertain or rejected result is quarantined and is not a user, RAG, or
quality-score output. This is only a selective review recheck; it must not
generate docent content or replace final docent QA.
"""

# Compatibility name for callers that imported the old bulk prompt.
SYSTEM_PROMPT = BULK_SYSTEM_PROMPT


@dataclass(frozen=True)
class ReviewAttributeCandidate:
    mention_id: str
    week_start: date
    place_id: str
    place_name_ko: str
    provider: str
    category: str
    mention_count: int
    organic_mention_count: int
    sentiment_score: float | None
    attributes: dict[str, Any]
    posts: tuple[dict[str, str | None], ...]
    source_content_sha256: str = ""
    source_name: str = ""
    license_class: str = ""
    terms_version: str = ""

    @classmethod
    def from_row(cls, row: dict[str, Any]) -> ReviewAttributeCandidate:
        posts = row.get("posts")
        if isinstance(posts, str):
            posts = json.loads(posts)
        if not isinstance(posts, list):
            posts = []
        return cls(
            mention_id=str(row.get("id") or ""),
            week_start=row.get("week_start"),
            place_id=str(row.get("place_id") or ""),
            place_name_ko=str(row.get("place_name_ko") or ""),
            provider=str(row.get("provider") or ""),
            category=str(row.get("category") or "attraction"),
            mention_count=int(row.get("mention_count") or 0),
            organic_mention_count=int(row.get("organic_mention_count") or 0),
            sentiment_score=_optional_sentiment(row.get("sentiment_score")),
            attributes=_json_object(row.get("attributes")),
            posts=tuple(_post_sample(item) for item in posts if isinstance(item, dict)),
            source_content_sha256=_source_content_hash(
                provider=str(row.get("provider") or ""),
                posts=posts,
            ),
            source_name=str(row.get("source_name") or ""),
            license_class=str(row.get("license_class") or ""),
            terms_version=str(row.get("terms_version") or ""),
        )

    def to_prompt_record(self) -> dict[str, Any]:
        return {
            "mention_id": self.mention_id,
            "place_id": self.place_id,
            "place_name_ko": self.place_name_ko,
            "category": self.category,
            "provider": self.provider,
            "week_start": self.week_start.isoformat(),
            "mention_count": self.mention_count,
            "organic_mention_count": self.organic_mention_count,
            "top_terms": self.attributes.get("top_terms") or [],
            "category_policy": self.attributes.get("category_policy"),
            "allowed_attributes": list(attribute_names_for_category(self.category)),
            "source_content_sha256": self.source_content_sha256,
            "source_name": self.source_name,
            "license_class": self.license_class,
            "terms_version": self.terms_version,
            "retained_snippets": [
                _compact_text(
                    sample.get("title"),
                    sample.get("body"),
                    max_chars=360,
                )
                for sample in self.posts[:8]
            ],
        }

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "mention_id": self.mention_id,
            "place_id": self.place_id,
            "place_name_ko": self.place_name_ko,
            "category": self.category,
            "provider": self.provider,
            "week_start": self.week_start.isoformat(),
            "mention_count": self.mention_count,
            "organic_mention_count": self.organic_mention_count,
            "top_terms": self.attributes.get("top_terms") or [],
            "post_sample_count": len(self.posts),
            "source_content_sha256": self.source_content_sha256,
            "source_name": self.source_name,
            "license_class": self.license_class,
            "terms_version": self.terms_version,
        }


@dataclass(frozen=True)
class ReviewAttributeEnrichment:
    mention_id: str
    schema_version: str
    sentiment_score: float | None
    sentiment_confidence: float
    attribute_scores: dict[str, float]
    attribute_confidence_avg: float
    evidence_terms: dict[str, list[str]]
    summary_ko: str | None
    reason: str | None
    source_method: str
    source_content_sha256: str = ""
    is_ad: bool = False
    ad_confidence: float = 0.0
    ad_reason: str = "organic"
    status: str = "accepted"

    def attribute_mean(self) -> float | None:
        if not self.attribute_scores:
            return None
        return round(sum(self.attribute_scores.values()) / len(self.attribute_scores), 4)

    def to_attributes_payload(self) -> dict[str, Any]:
        """Return only persisted aggregate/provenance-safe fields.

        ``evidence_terms``, ``summary_ko``, and ``reason`` are transient model
        fields. They may exist while parsing an older injected fixture, but are
        never allowed across the DB/API/RAG boundary.
        """
        return {
            "schema_version": self.schema_version,
            "source": self.source_method,
            "source_content_sha256": self.source_content_sha256 or None,
            "attribute_scores": self.attribute_scores,
            "attribute_mean": self.attribute_mean(),
            "attribute_confidence_avg": self.attribute_confidence_avg,
            "sentiment_score": self.sentiment_score,
            "sentiment_confidence": self.sentiment_confidence,
            "is_ad": self.is_ad,
            "ad_confidence": self.ad_confidence,
            "ad_reason": self.ad_reason,
            "status": self.status,
        }

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "mention_id": self.mention_id,
            "schema_version": self.schema_version,
            "sentiment_score": self.sentiment_score,
            "attribute_mean": self.attribute_mean(),
            "attribute_confidence_avg": self.attribute_confidence_avg,
            "attribute_scores": self.attribute_scores,
            "source_method": self.source_method,
            "source_content_sha256": self.source_content_sha256 or None,
            "is_ad": self.is_ad,
            "ad_confidence": self.ad_confidence,
            "ad_reason": self.ad_reason,
            "status": self.status,
        }


@dataclass(frozen=True)
class ReviewAttributeApplyRow:
    mention_id: str
    sentiment_score: float | None
    review_attributes: dict[str, Any]
    review_quality: dict[str, Any] | None
    source_method: str
    accepted: bool


def attribute_names_for_category(category: str) -> tuple[str, ...]:
    if category == "restaurant":
        return RESTAURANT_ATTRIBUTES
    if category == "event":
        return EVENT_ATTRIBUTES
    return ATTRACTION_ATTRIBUTES


def fetch_review_attribute_candidates(
    *,
    dsn: str,
    category: str,
    min_organic: int,
    limit: int,
    connect_timeout: int,
) -> list[ReviewAttributeCandidate]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    allowed_license_classes = ", ".join(
        f"'{license_class}'" for license_class in ALLOWED_LICENSE_CLASSES
    )
    sql = f"""
        SELECT
            mentions.id,
            mentions.week_start,
            mentions.place_id,
            mentions.place_name_ko,
            mentions.provider,
            mentions.category,
            mentions.mention_count,
            mentions.organic_mention_count,
            mentions.sentiment_score,
            mentions.attributes,
            sources.source_name,
            sources.license_class,
            sources.terms_version,
            COALESCE(
                jsonb_agg(
                    DISTINCT jsonb_build_object(
                        'external_key', posts.external_key,
                        'title', posts.title,
                        'body', left(coalesce(posts.body, ''), 700)
                    )
                ) FILTER (WHERE posts.external_key IS NOT NULL),
                '[]'::jsonb
            ) AS posts
        FROM community.place_mentions_weekly mentions
        JOIN ingest.review_sources sources
          ON sources.source_name = NULLIF(
                 mentions.attributes #>> '{{preprocess,source_name}}', ''
             )
         AND sources.provider = mentions.provider
         AND sources.source_status = 'active'
         AND sources.license_class IN ({allowed_license_classes})
         AND sources.license_class = NULLIF(
                 mentions.attributes #>> '{{preprocess,license_class}}', ''
             )
         AND sources.terms_version = NULLIF(
                 mentions.attributes #>> '{{preprocess,terms_version}}', ''
             )
        LEFT JOIN LATERAL jsonb_array_elements_text(
            COALESCE(
                mentions.attributes->'preprocess'->'retained_external_keys',
                '[]'::jsonb
            )
        ) retained(external_key) ON TRUE
        LEFT JOIN community.posts posts
          ON posts.provider = mentions.provider
         AND posts.external_key = retained.external_key
        WHERE mentions.place_id IS NOT NULL
          AND coalesce(mentions.organic_mention_count, 0) >= %s
          AND (%s = 'all' OR mentions.category = %s)
        GROUP BY
            mentions.id,
            mentions.week_start,
            mentions.place_id,
            mentions.place_name_ko,
            mentions.provider,
            mentions.category,
            mentions.mention_count,
            mentions.organic_mention_count,
            mentions.sentiment_score,
            mentions.attributes,
            sources.source_name,
            sources.license_class,
            sources.terms_version,
            mentions.updated_at
        ORDER BY
            CASE
                WHEN mentions.attributes #>> '{{review_attributes,schema_version}}'
                     = %s THEN 1
                ELSE 0
            END,
            coalesce(mentions.organic_mention_count, 0) DESC,
            mentions.updated_at DESC,
            mentions.place_name_ko
        LIMIT %s
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                sql,
                (min_organic, category, category, PROMPT_VERSION, limit),
            )
            return [ReviewAttributeCandidate.from_row(dict(row)) for row in cur.fetchall()]


def build_deterministic_enrichments(
    candidates: Sequence[ReviewAttributeCandidate],
) -> list[ReviewAttributeEnrichment]:
    return [_deterministic_enrichment(candidate) for candidate in candidates]


def generate_ai_enrichments(
    *,
    candidates: Sequence[ReviewAttributeCandidate],
    batch_size: int,
    retry_attempts: int,
    retry_delay_sec: float,
    client: Any | None = None,
) -> list[ReviewAttributeEnrichment]:
    if not candidates:
        return []
    settings = get_settings()
    if client is None:
        client = _build_openai_client(settings)
    enrichments: list[ReviewAttributeEnrichment] = []
    for start in range(0, len(candidates), batch_size):
        batch = list(candidates[start : start + batch_size])
        response = _create_chat_completion_with_retry(
            client=client,
            model=selected_review_batch_model(settings),
            messages=[
                {"role": "system", "content": BULK_SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": json.dumps(
                        [candidate.to_prompt_record() for candidate in batch],
                        ensure_ascii=False,
                    ),
                },
            ],
            retry_attempts=retry_attempts,
            retry_delay_sec=retry_delay_sec,
        )
        raw = response.choices[0].message.content or ""
        enrichments.extend(parse_ai_response(raw, batch))
    return enrichments


def _build_openai_client(settings: Any) -> Any:
    """Build the standard OpenAI client from settings, or raise a clear RuntimeError.

    Standard OpenAI only (never Azure). Matches the ``rag_index`` OpenAI
    convention: requires ``OPENAI_API_KEY`` and ``LALA_ENABLE_LIVE_AI=true``. The
    key value is never logged or exposed. Extracted so both the bulk lane and the
    selective recheck lane can share it, and so tests can inject a fake client
    without constructing one.
    """
    missing = _missing_openai_settings(settings)
    if missing:
        raise RuntimeError("OpenAI config is missing: " + ", ".join(missing))
    try:
        from openai import OpenAI
    except Exception as exc:
        raise RuntimeError("openai package is required for review attribute AI batch.") from exc
    return OpenAI(
        api_key=settings.openai_api_key,
        base_url=settings.openai_base_url or "https://api.openai.com/v1",
    )


def selected_review_recheck_model(settings: Any | None = None) -> str:
    """Standard OpenAI mini model for the low-confidence selective recheck
    (Improvement B). Resolution is ``openai_review_recheck_model`` with a hard
    default of ``gpt-5.4-mini`` -- so it always resolves to a mini model even
    when the env var is unset or empty, and recheck is always available unless a
    caller overrides this selector. Standard OpenAI only (never Azure).
    """
    return resolve("review_recheck", settings).model_id


def route_low_confidence_enrichments(
    enrichments: Sequence[ReviewAttributeEnrichment],
    *,
    threshold: float = RECHECK_CONFIDENCE_THRESHOLD,
) -> list[ReviewAttributeEnrichment]:
    """Return the subset of enrichments whose attribute or sentiment confidence
    is below [threshold] -- eligible for the selective mini-model recheck.

    Improvement B: bulk output is not silently trusted for uncertain rows.
    """
    return [
        item
        for item in enrichments
        if (
            item.attribute_confidence_avg < threshold
            or item.sentiment_confidence < threshold
            or (item.is_ad and item.ad_confidence < AD_CONFIDENCE_FILTER_THRESHOLD)
        )
    ]


def generate_ai_recheck(
    *,
    candidates: Sequence[ReviewAttributeCandidate],
    enrichments: Sequence[ReviewAttributeEnrichment],
    batch_size: int,
    retry_attempts: int,
    retry_delay_sec: float,
    threshold: float = RECHECK_CONFIDENCE_THRESHOLD,
    client: Any | None = None,
    recheck_stats: dict[str, int] | None = None,
) -> list[ReviewAttributeEnrichment]:
    """Selective mini-model recheck of low-confidence bulk enrichments.

    Non-negotiables (Improvement B): bulk stays on the nano batch model; only
    low-confidence rows are re-asked on the mini (recheck/docent) model. The
    recheck is **best-effort and non-fatal** -- a recheck failure or missing mini
    config leaves the bulk result in place (the row is still scored, never
    dropped, never re-admitted as raw text). Returns a new merged list in bulk
    order where rechecked rows upgrade their result; non-routed rows are untouched.

    Tests inject [client] so no live AI call is made.
    """
    if not enrichments:
        return list(enrichments)
    settings = get_settings()
    routed = route_low_confidence_enrichments(enrichments, threshold=threshold)
    if not routed:
        return list(enrichments)
    recheck_model = selected_review_recheck_model(settings)
    if not recheck_model:
        # No mini deployment configured: keep bulk results as-is (non-fatal).
        return list(enrichments)
    candidate_by_id = {candidate.mention_id: candidate for candidate in candidates}
    routed_ids = {item.mention_id for item in routed}
    recheck_candidates = [
        candidate_by_id[item.mention_id] for item in routed if item.mention_id in candidate_by_id
    ]
    if not recheck_candidates:
        return list(enrichments)
    if client is None:
        try:
            client = _build_openai_client(settings)
        except RuntimeError:
            if recheck_stats is not None:
                recheck_stats["recheck_failed_count"] = (
                    recheck_stats.get("recheck_failed_count", 0) + 1
                )
            return list(enrichments)
    rechecked_by_id: dict[str, ReviewAttributeEnrichment] = {}
    for start in range(0, len(recheck_candidates), batch_size):
        batch = list(recheck_candidates[start : start + batch_size])
        try:
            response = _create_chat_completion_with_retry(
                client=client,
                model=recheck_model,
                messages=[
                    {"role": "system", "content": RECHECK_SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": json.dumps(
                            [candidate.to_prompt_record() for candidate in batch],
                            ensure_ascii=False,
                        ),
                    },
                ],
                retry_attempts=retry_attempts,
                retry_delay_sec=retry_delay_sec,
            )
            raw = response.choices[0].message.content or ""
            for enrichment in parse_ai_response(raw, batch, lane="recheck"):
                # Mark the lane so downstream provenance shows a recheck upgraded it.
                rechecked_by_id[enrichment.mention_id] = replace(
                    enrichment, source_method="openai_recheck"
                )
        except Exception:
            # Best-effort: keep the bulk result for this batch on recheck failure.
            # This includes malformed, empty, or structurally incomplete replies.
            if recheck_stats is not None:
                recheck_stats["recheck_failed_count"] = (
                    recheck_stats.get("recheck_failed_count", 0) + 1
                )
            continue
    # Merge in bulk order: a routed row that got a rechecked upgrade replaces its
    # bulk result; everything else (non-routed, or routed but not re-upgraded) is
    # kept as-is so no evidence is silently dropped.
    return [
        rechecked_by_id[item.mention_id]
        if item.mention_id in routed_ids and item.mention_id in rechecked_by_id
        else item
        for item in enrichments
    ]


def parse_ai_response(
    raw: str,
    candidates: Sequence[ReviewAttributeCandidate],
    *,
    lane: str = "bulk",
) -> list[ReviewAttributeEnrichment]:
    if lane not in {"bulk", "recheck"}:
        raise ValueError(f"OpenAI response lane is unsupported: {lane}.")
    try:
        payload = json.loads(_strip_code_fence(raw))
    except (TypeError, json.JSONDecodeError) as exc:
        raise ValueError("OpenAI JSON response was not valid JSON.") from exc
    items = payload.get("results") if isinstance(payload, dict) else None
    if not isinstance(items, list):
        raise ValueError("OpenAI JSON response did not include a results list.")
    if len(items) != len(candidates):
        raise ValueError("OpenAI JSON response must contain exactly one result per input.")
    candidate_by_id = {candidate.mention_id: candidate for candidate in candidates}
    expected_schema = PROMPT_VERSION if lane == "bulk" else RECHECK_PROMPT_VERSION
    seen_ids: set[str] = set()
    parsed: list[ReviewAttributeEnrichment] = []
    for item in items:
        if not isinstance(item, dict):
            raise ValueError("OpenAI JSON response contained a non-object result.")
        mention_id = str(item.get("mention_id") or "").strip()
        if not mention_id or mention_id in seen_ids:
            raise ValueError("OpenAI JSON response contained a missing or duplicate mention_id.")
        candidate = candidate_by_id.get(mention_id)
        if candidate is None:
            raise ValueError("OpenAI JSON response contained an unknown mention_id.")
        if item.get("schema_version") != expected_schema:
            raise ValueError(f"OpenAI JSON response schema_version must be {expected_schema}.")
        forbidden_fields = {"evidence_terms", "summary_ko", "reason", "organic_excerpt"}
        if forbidden_fields.intersection(item):
            raise ValueError("OpenAI JSON response must not contain raw-derived text fields.")
        if lane == "recheck" and item.get("decision") not in {
            "confirmed",
            "still_uncertain",
            "rejected",
        }:
            raise ValueError("OpenAI recheck response contained an unsupported decision.")
        allowed = set(attribute_names_for_category(candidate.category))
        scores = _strict_attribute_scores(item.get("attribute_scores"), allowed)
        sentiment_score = _strict_sentiment(item.get("sentiment_score"))
        sentiment_confidence = _strict_unit(
            item.get("sentiment_confidence"), "sentiment_confidence"
        )
        attribute_confidence = _strict_unit(
            item.get("attribute_confidence_avg"), "attribute_confidence_avg"
        )
        is_ad = item.get("is_ad")
        if not isinstance(is_ad, bool):
            raise ValueError("OpenAI JSON response is_ad must be boolean.")
        ad_confidence = _strict_unit(item.get("ad_confidence"), "ad_confidence")
        ad_reason = str(item.get("ad_reason") or "").strip()
        if ad_reason not in SAFE_AD_REASONS:
            raise ValueError("OpenAI JSON response contained an unsupported ad_reason.")
        decision = item.get("decision") if lane == "recheck" else None
        status = _enrichment_status(
            is_ad=is_ad,
            ad_confidence=ad_confidence,
            sentiment_confidence=sentiment_confidence,
            attribute_confidence=attribute_confidence,
            decision=decision,
        )
        parsed.append(
            ReviewAttributeEnrichment(
                mention_id=mention_id,
                schema_version=expected_schema,
                sentiment_score=sentiment_score,
                sentiment_confidence=sentiment_confidence,
                attribute_scores=scores,
                attribute_confidence_avg=attribute_confidence,
                evidence_terms={},
                summary_ko=None,
                reason=None,
                source_method="openai_recheck" if lane == "recheck" else "openai",
                source_content_sha256=candidate.source_content_sha256,
                is_ad=is_ad,
                ad_confidence=ad_confidence,
                ad_reason=ad_reason,
                status=status,
            )
        )
        seen_ids.add(mention_id)
    return parsed


def apply_review_attribute_enrichments(
    *,
    dsn: str,
    candidates: Sequence[ReviewAttributeCandidate],
    enrichments: Sequence[ReviewAttributeEnrichment],
    source_method: str,
    connect_timeout: int,
) -> int:
    import psycopg2
    from psycopg2.extras import Json

    candidate_by_id = {candidate.mention_id: candidate for candidate in candidates}
    rows = [
        _apply_row(candidate_by_id[item.mention_id], item, source_method=source_method)
        for item in enrichments
        if item.mention_id in candidate_by_id
    ]
    if not rows:
        return 0

    sql = """
        UPDATE community.place_mentions_weekly
        SET
            sentiment_score = CASE
                WHEN %(accepted)s THEN COALESCE(%(sentiment_score)s, sentiment_score)
                ELSE NULL
            END,
            attributes = (
                attributes - 'review_quality'
                || jsonb_build_object(
                    'review_attributes',
                    %(review_attributes)s::jsonb,
                    'review_attribute_batch',
                    jsonb_build_object(
                        'prompt_version', %(prompt_version)s,
                        'source_method', %(source_method)s,
                        'updated_at', to_jsonb(now())
                    )
                )
                || CASE
                    WHEN %(accepted)s AND %(review_quality)s::jsonb IS NOT NULL
                    THEN jsonb_build_object('review_quality', %(review_quality)s::jsonb)
                    ELSE '{}'::jsonb
                END
            ),
            updated_at = now()
        WHERE id = %(mention_id)s::uuid
    """
    updated = 0
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            for row in rows:
                cur.execute(
                    sql,
                    {
                        "mention_id": row.mention_id,
                        "sentiment_score": row.sentiment_score,
                        "review_attributes": Json(row.review_attributes),
                        "review_quality": Json(row.review_quality)
                        if row.review_quality is not None
                        else None,
                        "accepted": row.accepted,
                        "prompt_version": PROMPT_VERSION,
                        "source_method": row.source_method,
                    },
                )
                updated += cur.rowcount
                if not row.accepted:
                    continue
                cur.execute(
                    """
                    INSERT INTO travel.place_enrichments (
                        place_id,
                        enrichment_type,
                        attributes,
                        confidence,
                        source_method,
                        model_name,
                        prompt_version
                    )
                    SELECT
                        %(place_id)s,
                        'review_attributes',
                        %(review_attributes)s::jsonb,
                        %(confidence)s,
                        %(source_method)s,
                        %(model_name)s,
                        %(prompt_version)s
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM travel.place_enrichments existing
                        WHERE existing.place_id = %(place_id)s
                          AND existing.enrichment_type = 'review_attributes'
                          AND existing.source_method = %(source_method)s
                          AND existing.prompt_version = %(prompt_version)s
                    )
                    """,
                    {
                        "place_id": candidate_by_id[row.mention_id].place_id,
                        "review_attributes": Json(row.review_attributes),
                        "confidence": _enrichment_confidence(row.review_attributes),
                        "source_method": row.source_method,
                        "model_name": (
                            row.review_attributes.get("model_name")
                            if isinstance(row.review_attributes, dict)
                            else None
                        ),
                        "prompt_version": row.review_attributes.get(
                            "schema_version", PROMPT_VERSION
                        ),
                    },
                )
        conn.commit()
    return updated


def record_job_run(
    *,
    dsn: str,
    status: str,
    started_at: datetime,
    finished_at: datetime,
    duration_ms: int,
    error_message: str | None,
    connect_timeout: int,
) -> None:
    import psycopg2

    sql = """
        INSERT INTO ops.job_runs (
            job_name,
            status,
            started_at,
            finished_at,
            duration_ms,
            error_message
        )
        VALUES (%s, %s, %s, %s, %s, %s)
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            cur.execute(
                sql,
                (JOB_NAME, status, started_at, finished_at, duration_ms, error_message),
            )
        conn.commit()


def review_quality_payload(
    candidate: ReviewAttributeCandidate,
    enrichment: ReviewAttributeEnrichment,
) -> dict[str, Any] | None:
    if enrichment.status not in {"accepted"}:
        return None
    organic_count = candidate.organic_mention_count
    if organic_count < 3:
        return None
    attribute_mean = enrichment.attribute_mean()
    sentiment_score = (
        enrichment.sentiment_score
        if enrichment.sentiment_score is not None
        else candidate.sentiment_score
    )
    if attribute_mean is None or sentiment_score is None:
        return None
    organic_coverage = min(1.0, organic_count / _review_category_target(candidate.category))
    filtered_ad_count = int(candidate.attributes.get("filtered_ad_count") or 0)
    ad_quality = 1.0 - min(1.0, filtered_ad_count / max(candidate.mention_count, 1))
    confidence = min(enrichment.sentiment_confidence, enrichment.attribute_confidence_avg)
    if organic_count < 10:
        confidence = min(confidence, 0.65)
    sentiment_norm = (max(-1.0, min(1.0, sentiment_score)) + 1.0) / 2.0
    score = (
        0.35 * attribute_mean
        + 0.25 * sentiment_norm
        + 0.20 * organic_coverage
        + 0.10 * ad_quality
        + 0.10 * confidence
    )
    if filtered_ad_count / max(candidate.mention_count, 1) > 0.50:
        score = min(score, 0.60)
    return {
        "schema_version": QUALITY_VERSION,
        "source": enrichment.source_method,
        "score": round(max(0.0, min(1.0, score)), 4),
        "organic_review_count": organic_count,
        "mention_count": candidate.mention_count,
        "confidence": round(confidence, 4),
    }


def _deterministic_enrichment(
    candidate: ReviewAttributeCandidate,
) -> ReviewAttributeEnrichment:
    allowed = attribute_names_for_category(candidate.category)
    text = " ".join(
        [
            " ".join(str(term) for term in candidate.attributes.get("top_terms") or []),
            " ".join(
                _compact_text(sample.get("title"), sample.get("body"), max_chars=500)
                for sample in candidate.posts
            ),
        ]
    )
    scores: dict[str, float] = {}
    evidence: dict[str, list[str]] = {}
    for name in allowed:
        terms = [term for term in ATTRIBUTE_TERMS.get(name, ()) if term in text]
        evidence[name] = terms[:8]
        scores[name] = _attribute_score(len(terms), candidate.organic_mention_count)
    sentiment = candidate.sentiment_score
    if sentiment is None:
        sentiment = _deterministic_sentiment(text)
    confidence = round(min(0.78, 0.45 + candidate.organic_mention_count / 18), 4)
    summary_terms = [term for terms in evidence.values() for term in terms][:4]
    summary = (
        f"{candidate.place_name_ko} 언급에서 {', '.join(summary_terms)} 신호가 확인됩니다."
        if summary_terms
        else f"{candidate.place_name_ko} 언급은 아직 뚜렷한 속성 신호가 적습니다."
    )
    return ReviewAttributeEnrichment(
        mention_id=candidate.mention_id,
        schema_version=DETERMINISTIC_VERSION,
        sentiment_score=sentiment,
        sentiment_confidence=confidence,
        attribute_scores=scores,
        attribute_confidence_avg=confidence,
        evidence_terms=evidence,
        summary_ko=summary,
        reason="deterministic keyword evidence from retained mentions",
        source_method="deterministic",
        source_content_sha256=candidate.source_content_sha256,
        status="accepted",
    )


def _apply_row(
    candidate: ReviewAttributeCandidate,
    enrichment: ReviewAttributeEnrichment,
    *,
    source_method: str,
) -> ReviewAttributeApplyRow:
    review_attributes = enrichment.to_attributes_payload()
    if enrichment.status != "accepted":
        review_attributes = {
            key: value
            for key in (
                "schema_version",
                "source",
                "source_content_sha256",
                "is_ad",
                "ad_confidence",
                "ad_reason",
                "status",
            )
            if (value := review_attributes.get(key)) is not None
        }
    # Per-enrichment lane wins so a rechecked row is persisted as "openai_recheck"
    # (and bulk as "openai", deterministic as "deterministic") rather than a
    # generic runner-level string. The caller's source_method is only a fallback.
    return ReviewAttributeApplyRow(
        mention_id=enrichment.mention_id,
        sentiment_score=enrichment.sentiment_score if enrichment.status == "accepted" else None,
        review_attributes=review_attributes,
        review_quality=review_quality_payload(candidate, enrichment),
        source_method=enrichment.source_method or source_method,
        accepted=enrichment.status == "accepted",
    )


def _create_chat_completion_with_retry(
    *,
    client: Any,
    model: str,
    messages: list[dict[str, str]],
    retry_attempts: int,
    retry_delay_sec: float,
) -> Any:
    attempts = max(1, retry_attempts)
    delay = max(0.0, retry_delay_sec)
    last_exc: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            return client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=0.1,
                max_completion_tokens=4000,
                response_format={"type": "json_object"},
            )
        except Exception as exc:
            last_exc = exc
            if attempt >= attempts or not _is_retryable_ai_error(exc):
                raise
            time.sleep(delay * attempt)
    if last_exc:
        raise last_exc
    raise RuntimeError("OpenAI completion failed before a request was attempted.")


def _is_retryable_ai_error(exc: Exception) -> bool:
    status_code = getattr(exc, "status_code", None)
    if status_code in {408, 409, 429, 500, 502, 503, 504}:
        return True
    text = str(exc).lower()
    return any(
        marker in text
        for marker in (
            "too many requests",
            "rate limit",
            "timeout",
            "temporarily unavailable",
            "service unavailable",
        )
    )


def _attribute_scores(value: Any, allowed: set[str]) -> dict[str, float]:
    if not isinstance(value, dict):
        return {}
    scores: dict[str, float] = {}
    for key, raw_score in value.items():
        name = str(key)
        if name not in allowed:
            continue
        scores[name] = _optional_unit(raw_score, default=0.5)
    return scores


def _strict_attribute_scores(value: Any, allowed: set[str]) -> dict[str, float]:
    if not isinstance(value, dict) or not value:
        raise ValueError("OpenAI JSON response attribute_scores must be a non-empty object.")
    scores: dict[str, float] = {}
    for key, raw_score in value.items():
        name = str(key)
        if name not in allowed:
            raise ValueError(f"OpenAI JSON response contained unsupported attribute: {name}.")
        scores[name] = _strict_unit(raw_score, f"attribute_scores.{name}")
    return scores


def _strict_unit(value: Any, field_name: str) -> float:
    if isinstance(value, bool):
        raise ValueError(f"OpenAI JSON response {field_name} must be a number from 0 to 1.")
    try:
        parsed = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(
            f"OpenAI JSON response {field_name} must be a number from 0 to 1."
        ) from exc
    if not 0.0 <= parsed <= 1.0:
        raise ValueError(f"OpenAI JSON response {field_name} must be a number from 0 to 1.")
    return round(parsed, 4)


def _strict_sentiment(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool):
        raise ValueError("OpenAI JSON response sentiment_score must be a number from -1 to 1.")
    try:
        parsed = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(
            "OpenAI JSON response sentiment_score must be a number from -1 to 1."
        ) from exc
    if not -1.0 <= parsed <= 1.0:
        raise ValueError("OpenAI JSON response sentiment_score must be a number from -1 to 1.")
    return round(parsed, 4)


def _enrichment_status(
    *,
    is_ad: bool,
    ad_confidence: float,
    sentiment_confidence: float,
    attribute_confidence: float,
    decision: str | None,
) -> str:
    if decision == "rejected":
        return "quarantined"
    if decision == "still_uncertain":
        return "quarantined"
    if is_ad and ad_confidence >= AD_CONFIDENCE_FILTER_THRESHOLD:
        return "ad_filtered"
    if decision == "confirmed":
        return "accepted"
    if (
        sentiment_confidence < RECHECK_CONFIDENCE_THRESHOLD
        or attribute_confidence < RECHECK_CONFIDENCE_THRESHOLD
        or (is_ad and ad_confidence < AD_CONFIDENCE_FILTER_THRESHOLD)
    ):
        return "recheck_required"
    return "accepted"


def _evidence_terms(value: Any, allowed: set[str]) -> dict[str, list[str]]:
    if not isinstance(value, dict):
        return {name: [] for name in sorted(allowed)}
    result: dict[str, list[str]] = {}
    for name in sorted(allowed):
        raw_terms = value.get(name)
        if not isinstance(raw_terms, list):
            result[name] = []
            continue
        result[name] = [
            _compact_text(term, max_chars=28)
            for term in raw_terms
            if _compact_text(term, max_chars=28)
        ][:6]
    return result


def _attribute_score(term_count: int, organic_count: int) -> float:
    if organic_count <= 0:
        return 0.0
    return round(min(0.9, 0.45 + min(0.45, term_count / max(organic_count, 1) * 0.18)), 4)


def _deterministic_sentiment(text: str) -> float:
    positive_terms = ("좋", "추천", "친절", "조용", "멋", "예쁘", "맛있", "쾌적")
    negative_terms = ("별로", "불친절", "복잡", "비싸", "실망", "나쁨")
    score = sum(1 for term in positive_terms if term in text)
    score -= sum(1 for term in negative_terms if term in text)
    return round(max(-1.0, min(1.0, score / 4)), 4)


def _review_category_target(category: str) -> float:
    if category == "restaurant":
        return 30.0
    if category == "event":
        return 15.0
    return 20.0


def _missing_openai_settings(settings: Any) -> list[str]:
    # Standard OpenAI only (never Azure). Matches the rag_index OpenAI convention:
    # key + live-AI gate + a bulk model name. The key value is never logged.
    missing: list[str] = []
    if not getattr(settings, "openai_api_key", ""):
        missing.append("OPENAI_API_KEY")
    if not getattr(settings, "enable_live_ai", False):
        missing.append("LALA_ENABLE_LIVE_AI=true")
    try:
        bulk_model = selected_review_batch_model(settings)
    except ValueError as exc:
        missing.append(str(exc))
        bulk_model = ""
    if not bulk_model:
        missing.append("OPENAI_REVIEW_BATCH_MODEL")
    try:
        resolve_openai_base_url_host(getattr(settings, "openai_base_url", ""))
    except ValueError as exc:
        if str(exc) not in missing:
            missing.append(str(exc))
    return missing


def selected_review_batch_model(settings: Any | None = None) -> str:
    # Standard OpenAI bulk review model (never Azure). Defaults to gpt-5.4-nano.
    return resolve("review_bulk", settings).model_id


def _post_sample(value: dict[str, Any]) -> dict[str, str | None]:
    return {
        "external_key": _optional_text(value.get("external_key")),
        "title": _optional_text(value.get("title")),
        "body": _optional_text(value.get("body")),
    }


def _source_content_hash(*, provider: str, posts: Any) -> str:
    """Hash in-memory source content without retaining it in an output shape."""
    safe_posts = posts if isinstance(posts, list) else []
    material = [provider]
    for item in safe_posts:
        if not isinstance(item, dict):
            continue
        material.extend(
            [
                str(item.get("external_key") or ""),
                str(item.get("title") or ""),
                str(item.get("body") or ""),
            ]
        )
    return hashlib.sha256("\x1f".join(material).encode("utf-8")).hexdigest()


def _enrichment_confidence(attributes: dict[str, Any]) -> float | None:
    values = [
        attributes.get("attribute_confidence_avg"),
        attributes.get("sentiment_confidence"),
    ]
    numeric = [float(value) for value in values if isinstance(value, (int, float))]
    return round(min(numeric), 4) if numeric else None


def _json_object(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return {}
        return parsed if isinstance(parsed, dict) else {}
    return {}


def _compact_text(*parts: Any, max_chars: int = 240) -> str:
    text = " ".join(str(part or "").strip() for part in parts if str(part or "").strip())
    text = " ".join(text.split())
    return text[:max_chars]


def _optional_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text or text.lower() in {"null", "none", "n/a", "unknown"}:
        return None
    return text


def _optional_unit(value: Any, *, default: float) -> float:
    if value is None:
        return default
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return default
    return round(min(max(parsed, 0.0), 1.0), 4)


def _optional_sentiment(value: Any) -> float | None:
    if value is None:
        return None
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    return round(min(max(parsed, -1.0), 1.0), 4)


def _strip_code_fence(raw: str) -> str:
    text = (raw or "").strip()
    if not text.startswith("```"):
        return text
    lines = text.splitlines()
    if len(lines) >= 3 and lines[-1].strip() == "```":
        return "\n".join(lines[1:-1]).removeprefix("json").strip()
    return text.strip("`").strip()


def duration_ms(started_at: datetime, finished_at: datetime) -> int:
    if started_at.tzinfo is None:
        started_at = started_at.replace(tzinfo=UTC)
    if finished_at.tzinfo is None:
        finished_at = finished_at.replace(tzinfo=UTC)
    return int((finished_at - started_at).total_seconds() * 1000)
