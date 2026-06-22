from __future__ import annotations

import json
from collections.abc import Sequence
from contextlib import closing
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from typing import Any

SCHEMA_VERSION = "review-attributes-v1"
PROMPT_VERSION = "review-attributes-rule-v1"
SOURCE_METHOD = "rule_based_review_terms"
SUPPORTED_CATEGORIES = {"all", "attraction", "restaurant", "event", "culture_venue"}

MIN_ORGANIC_REVIEWS = 3

CATEGORY_TARGET_COUNTS = {
    "restaurant": 20,
    "attraction": 12,
    "culture_venue": 10,
    "event": 10,
}

ATTRIBUTE_WEIGHTS = {
    "restaurant": {
        "taste": 0.30,
        "service": 0.20,
        "price": 0.15,
        "atmosphere": 0.15,
        "cleanliness": 0.10,
        "wait_crowding": 0.10,
    },
    "attraction": {
        "cultural_story": 0.25,
        "atmosphere": 0.20,
        "walking_comfort": 0.15,
        "photo_view": 0.15,
        "practical_tip": 0.15,
        "crowding": 0.10,
    },
    "culture_venue": {
        "cultural_story": 0.25,
        "atmosphere": 0.20,
        "walking_comfort": 0.15,
        "photo_view": 0.15,
        "practical_tip": 0.15,
        "crowding": 0.10,
    },
    "event": {
        "program_quality": 0.30,
        "family_friendliness": 0.15,
        "foreign_visitor_fit": 0.15,
        "access": 0.15,
        "weather_indoor_fit": 0.15,
        "crowding": 0.10,
    },
}

ATTRIBUTE_TERMS = {
    "restaurant": {
        "taste": ("맛", "맛있", "존맛", "메뉴", "고기", "커피", "브런치", "디저트", "음식", "반찬"),
        "service": ("친절", "서비스"),
        "price": ("가격", "양", "가성비"),
        "atmosphere": ("분위기", "조용", "깔끔", "데이트", "가족"),
        "cleanliness": ("깔끔", "청결", "위생"),
        "wait_crowding": ("웨이팅", "혼잡", "줄", "대기"),
    },
    "attraction": {
        "cultural_story": ("역사", "문화", "건축", "전시", "박물관", "미술관", "관람"),
        "atmosphere": ("분위기", "조용", "풍경", "야경", "깔끔", "추천"),
        "walking_comfort": ("산책", "동선", "코스", "접근", "아이", "가족"),
        "photo_view": ("사진", "포토", "풍경", "야경", "뷰"),
        "practical_tip": ("주차", "예약", "접근", "체험", "관람", "코스"),
        "crowding": ("혼잡", "웨이팅", "줄", "여유", "조용"),
    },
    "culture_venue": {
        "cultural_story": ("역사", "문화", "건축", "전시", "박물관", "미술관", "관람", "공연"),
        "atmosphere": ("분위기", "조용", "풍경", "야경", "깔끔", "추천"),
        "walking_comfort": ("산책", "동선", "코스", "접근", "아이", "가족"),
        "photo_view": ("사진", "포토", "풍경", "야경", "뷰"),
        "practical_tip": ("주차", "예약", "접근", "체험", "관람", "코스"),
        "crowding": ("혼잡", "웨이팅", "줄", "여유", "조용"),
    },
    "event": {
        "program_quality": ("공연", "축제", "체험", "전시", "문화", "프로그램", "행사"),
        "family_friendliness": ("가족", "아이", "체험", "추천"),
        "foreign_visitor_fit": ("외국", "영어", "안내", "문화", "관람"),
        "access": ("접근", "주차", "동선", "코스"),
        "weather_indoor_fit": ("실내", "그늘", "비", "날씨", "야외"),
        "crowding": ("혼잡", "웨이팅", "줄", "여유", "조용"),
    },
}

POSITIVE_TERMS = (
    "좋",
    "추천",
    "깔끔",
    "친절",
    "조용",
    "재방문",
    "풍경",
    "야경",
    "사진",
    "분위기",
    "체험",
    "관람",
    "산책",
    "가족",
    "아이",
)

NEGATIVE_TERMS = (
    "불친절",
    "별로",
    "최악",
    "더럽",
    "복잡",
    "혼잡",
    "비싸",
    "웨이팅",
    "실망",
)


@dataclass(frozen=True)
class ReviewMentionAggregate:
    id: str
    week_start: date
    place_id: str
    place_name_ko: str
    provider: str
    category: str
    mention_count: int
    organic_mention_count: int
    sentiment_score: float | None
    attributes: dict[str, Any]

    @classmethod
    def from_row(cls, row: dict[str, Any]) -> "ReviewMentionAggregate":
        return cls(
            id=str(row.get("id") or ""),
            week_start=_date_value(row.get("week_start")),
            place_id=str(row.get("place_id") or ""),
            place_name_ko=str(row.get("place_name_ko") or ""),
            provider=str(row.get("provider") or ""),
            category=str(row.get("category") or ""),
            mention_count=_optional_int(row.get("mention_count")) or 0,
            organic_mention_count=_optional_int(row.get("organic_mention_count")) or 0,
            sentiment_score=_optional_float(row.get("sentiment_score")),
            attributes=_dict_value(row.get("attributes")),
        )

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "week_start": self.week_start.isoformat(),
            "place_id": self.place_id,
            "place_name_ko": self.place_name_ko,
            "provider": self.provider,
            "category": self.category,
            "mention_count": self.mention_count,
            "organic_mention_count": self.organic_mention_count,
            "sentiment_score": self.sentiment_score,
            "top_terms": _top_terms(self.attributes),
        }


@dataclass(frozen=True)
class AttributeValue:
    score: float
    count: int
    confidence: float
    evidence_terms: tuple[str, ...]

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "score": self.score,
            "count": self.count,
            "confidence": self.confidence,
            "evidence_terms": list(self.evidence_terms),
        }


@dataclass(frozen=True)
class ReviewAttributeScore:
    aggregate_id: str
    week_start: date
    place_id: str
    place_name_ko: str
    provider: str
    category: str
    mention_count: int
    organic_mention_count: int
    filtered_ad_count: int
    sentiment_score: float
    sentiment_confidence: float
    attributes: dict[str, AttributeValue]
    attribute_mean: float
    attribute_confidence_avg: float
    review_quality_score: float | None
    confidence: float
    top_terms: tuple[str, ...]
    insufficient_reason: str | None = None

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "aggregate_id": self.aggregate_id,
            "week_start": self.week_start.isoformat(),
            "place_id": self.place_id,
            "place_name_ko": self.place_name_ko,
            "provider": self.provider,
            "category": self.category,
            "mention_count": self.mention_count,
            "organic_mention_count": self.organic_mention_count,
            "filtered_ad_count": self.filtered_ad_count,
            "sentiment_score": self.sentiment_score,
            "sentiment_confidence": self.sentiment_confidence,
            "attribute_mean": self.attribute_mean,
            "attribute_confidence_avg": self.attribute_confidence_avg,
            "review_quality_score": self.review_quality_score,
            "confidence": self.confidence,
            "insufficient_reason": self.insufficient_reason,
            "attributes": {
                key: value.to_public_dict() for key, value in self.attributes.items()
            },
            "top_terms": list(self.top_terms),
        }

    def weekly_attribute_patch(self) -> dict[str, Any]:
        return {
            "review_attributes": {
                "schema_version": SCHEMA_VERSION,
                "prompt_version": PROMPT_VERSION,
                "source_method": SOURCE_METHOD,
                "category": self.category,
                "sentiment_score": self.sentiment_score,
                "sentiment_confidence": self.sentiment_confidence,
                "attribute_mean": self.attribute_mean,
                "attribute_confidence_avg": self.attribute_confidence_avg,
                "attributes": {
                    key: value.to_public_dict() for key, value in self.attributes.items()
                },
                "top_terms": list(self.top_terms),
            },
            "review_quality": {
                "score": self.review_quality_score,
                "confidence": self.confidence,
                "organic_review_count": self.organic_mention_count,
                "filtered_ad_count": self.filtered_ad_count,
                "mention_count": self.mention_count,
                "insufficient_reason": self.insufficient_reason,
                "formula": "0.35 attribute + 0.25 sentiment + 0.20 coverage + 0.10 ad quality + 0.10 confidence",
            },
        }

    def enrichment_attributes(self) -> dict[str, Any]:
        payload = self.weekly_attribute_patch()
        payload["source_week_start"] = self.week_start.isoformat()
        payload["source_provider"] = self.provider
        payload["source_table"] = "community.place_mentions_weekly"
        return payload


def fetch_review_attribute_candidates(
    *,
    dsn: str,
    category: str,
    limit: int,
    connect_timeout: int,
) -> list[ReviewMentionAggregate]:
    if category not in SUPPORTED_CATEGORIES:
        raise ValueError(f"Unsupported category: {category}")
    if limit <= 0:
        raise ValueError("limit must be positive.")

    import psycopg2
    from psycopg2.extras import RealDictCursor

    sql = """
        SELECT
            id,
            week_start,
            place_id,
            place_name_ko,
            provider,
            category,
            mention_count,
            organic_mention_count,
            sentiment_score,
            attributes
        FROM community.place_mentions_weekly
        WHERE place_id IS NOT NULL
          AND trim(place_id) <> ''
          AND coalesce(organic_mention_count, 0) > 0
          AND (%s = 'all' OR category = %s)
        ORDER BY week_start DESC, updated_at DESC, place_id
        LIMIT %s
    """
    with closing(psycopg2.connect(dsn, connect_timeout=connect_timeout)) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, (category, category, limit))
            return [ReviewMentionAggregate.from_row(dict(row)) for row in cur.fetchall()]


def build_review_attribute_scores(
    aggregates: Sequence[ReviewMentionAggregate],
) -> list[ReviewAttributeScore]:
    return [score_review_aggregate(aggregate) for aggregate in aggregates]


def score_review_aggregate(aggregate: ReviewMentionAggregate) -> ReviewAttributeScore:
    top_terms = tuple(_top_terms(aggregate.attributes))
    category = aggregate.category if aggregate.category in ATTRIBUTE_WEIGHTS else "attraction"
    raw_count = max(aggregate.mention_count, aggregate.organic_mention_count)
    filtered_ad_count = _optional_int(aggregate.attributes.get("filtered_ad_count")) or 0
    ad_ratio = min(1.0, filtered_ad_count / max(1, raw_count))
    sentiment = _sentiment_score(
        top_terms=top_terms,
        organic_count=aggregate.organic_mention_count,
        ad_ratio=ad_ratio,
    )
    sentiment_confidence = _sentiment_confidence(
        top_terms=top_terms,
        organic_count=aggregate.organic_mention_count,
    )
    attributes = _attribute_values(
        category=category,
        top_terms=top_terms,
        organic_count=aggregate.organic_mention_count,
    )
    attribute_mean = _weighted_attribute_mean(category, attributes)
    attribute_confidence_avg = _attribute_confidence_avg(attributes)
    confidence = min(sentiment_confidence, attribute_confidence_avg)
    insufficient_reason = None
    review_quality_score = None

    if aggregate.organic_mention_count < MIN_ORGANIC_REVIEWS:
        insufficient_reason = "insufficient_organic_review_count"
    elif not top_terms:
        insufficient_reason = "missing_attribute_terms"
    else:
        if aggregate.organic_mention_count < 10:
            confidence = min(confidence, 0.65)
        coverage = min(
            1.0,
            aggregate.organic_mention_count / CATEGORY_TARGET_COUNTS.get(category, 10),
        )
        ad_quality = 1.0 - ad_ratio
        sentiment_norm = (sentiment + 1.0) / 2.0
        score = (
            0.35 * attribute_mean
            + 0.25 * sentiment_norm
            + 0.20 * coverage
            + 0.10 * ad_quality
            + 0.10 * confidence
        )
        if ad_ratio > 0.50:
            score = min(score, 0.60)
        review_quality_score = _round_score(score)

    return ReviewAttributeScore(
        aggregate_id=aggregate.id,
        week_start=aggregate.week_start,
        place_id=aggregate.place_id,
        place_name_ko=aggregate.place_name_ko,
        provider=aggregate.provider,
        category=category,
        mention_count=aggregate.mention_count,
        organic_mention_count=aggregate.organic_mention_count,
        filtered_ad_count=filtered_ad_count,
        sentiment_score=sentiment,
        sentiment_confidence=sentiment_confidence,
        attributes=attributes,
        attribute_mean=attribute_mean,
        attribute_confidence_avg=attribute_confidence_avg,
        review_quality_score=review_quality_score,
        confidence=_round_score(confidence),
        top_terms=top_terms,
        insufficient_reason=insufficient_reason,
    )


def apply_review_attribute_scores(
    *,
    dsn: str,
    scores: Sequence[ReviewAttributeScore],
    connect_timeout: int,
) -> dict[str, int]:
    if not dsn:
        raise ValueError("DB_DSN is required to persist review attributes.")
    if not scores:
        return {"updated_weekly_aggregates": 0, "inserted_enrichments": 0}

    import psycopg2
    from psycopg2.extras import Json

    weekly_sql = """
        UPDATE community.place_mentions_weekly
        SET
            sentiment_score = %(sentiment_score)s,
            attributes = coalesce(attributes, '{}'::jsonb) || %(attributes)s,
            updated_at = now()
        WHERE id = %(aggregate_id)s
    """
    enrichment_sql = """
        INSERT INTO travel.place_enrichments (
            place_id,
            enrichment_type,
            attributes,
            confidence,
            source_method,
            model_name,
            prompt_version
        )
        VALUES (
            %(place_id)s,
            'review_attributes',
            %(attributes)s,
            %(confidence)s,
            %(source_method)s,
            NULL,
            %(prompt_version)s
        )
    """
    updated_weekly = 0
    inserted_enrichments = 0
    with closing(psycopg2.connect(dsn, connect_timeout=connect_timeout)) as conn:
        with conn.cursor() as cur:
            for score in scores:
                patch = Json(score.weekly_attribute_patch(), dumps=_json_dumps)
                cur.execute(
                    weekly_sql,
                    {
                        "aggregate_id": score.aggregate_id,
                        "sentiment_score": score.sentiment_score,
                        "attributes": patch,
                    },
                )
                updated_weekly += cur.rowcount
                if score.review_quality_score is None:
                    continue
                cur.execute(
                    enrichment_sql,
                    {
                        "place_id": score.place_id,
                        "attributes": Json(score.enrichment_attributes(), dumps=_json_dumps),
                        "confidence": score.confidence,
                        "source_method": SOURCE_METHOD,
                        "prompt_version": PROMPT_VERSION,
                    },
                )
                inserted_enrichments += cur.rowcount
        conn.commit()
    return {
        "updated_weekly_aggregates": updated_weekly,
        "inserted_enrichments": inserted_enrichments,
    }


def _sentiment_score(
    *,
    top_terms: Sequence[str],
    organic_count: int,
    ad_ratio: float,
) -> float:
    text = " ".join(top_terms)
    positive_hits = sum(1 for term in POSITIVE_TERMS if term in text)
    negative_hits = sum(1 for term in NEGATIVE_TERMS if term in text)
    score = 0.08 + min(0.24, organic_count * 0.012)
    score += min(0.30, positive_hits * 0.08)
    score -= min(0.45, negative_hits * 0.12)
    score -= ad_ratio * 0.20
    return _round_score(_clamp(score, -1.0, 1.0))


def _sentiment_confidence(*, top_terms: Sequence[str], organic_count: int) -> float:
    evidence_bonus = min(0.25, len(top_terms) * 0.035)
    count_bonus = min(0.30, organic_count * 0.035)
    return _round_score(_clamp(0.35 + evidence_bonus + count_bonus, 0.0, 0.95))


def _attribute_values(
    *,
    category: str,
    top_terms: Sequence[str],
    organic_count: int,
) -> dict[str, AttributeValue]:
    text = " ".join(top_terms)
    values: dict[str, AttributeValue] = {}
    for attribute, terms in ATTRIBUTE_TERMS[category].items():
        evidence = tuple(term for term in terms if term in text)
        negative_hits = sum(1 for term in evidence if term in NEGATIVE_TERMS)
        positive_hits = sum(1 for term in evidence if term in POSITIVE_TERMS)
        if evidence:
            score = 0.62 + min(0.18, len(evidence) * 0.045)
            score += min(0.10, positive_hits * 0.035)
            score -= min(0.18, negative_hits * 0.07)
            confidence = 0.48 + min(0.22, len(evidence) * 0.055)
        else:
            score = 0.54
            confidence = 0.30
        confidence += min(0.18, organic_count * 0.012)
        values[attribute] = AttributeValue(
            score=_round_score(_clamp(score, 0.0, 1.0)),
            count=len(evidence),
            confidence=_round_score(_clamp(confidence, 0.0, 0.95)),
            evidence_terms=evidence[:5],
        )
    return values


def _weighted_attribute_mean(
    category: str,
    attributes: dict[str, AttributeValue],
) -> float:
    total = 0.0
    active_weight = 0.0
    for attribute, weight in ATTRIBUTE_WEIGHTS[category].items():
        value = attributes.get(attribute)
        if not value:
            continue
        total += value.score * weight
        active_weight += weight
    if active_weight <= 0:
        return 0.0
    return _round_score(total / active_weight)


def _attribute_confidence_avg(attributes: dict[str, AttributeValue]) -> float:
    if not attributes:
        return 0.0
    return _round_score(
        sum(value.confidence for value in attributes.values()) / len(attributes)
    )


def _top_terms(attributes: dict[str, Any]) -> list[str]:
    raw_terms = attributes.get("top_terms")
    if not isinstance(raw_terms, list):
        return []
    terms: list[str] = []
    for value in raw_terms:
        text = str(value or "").strip()
        if text and text not in terms:
            terms.append(text)
    return terms[:20]


def _date_value(value: Any) -> date:
    if isinstance(value, date):
        return value
    return date.fromisoformat(str(value))


def _dict_value(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        parsed = json.loads(value)
        return parsed if isinstance(parsed, dict) else {}
    return {}


def _optional_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _optional_int(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def _round_score(value: float) -> float:
    return float(Decimal(str(value)).quantize(Decimal("0.0001")))


def _json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)
