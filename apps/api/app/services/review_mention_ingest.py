from __future__ import annotations

import hashlib
import html
import re
from collections import defaultdict
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any

PROMPT_VERSION = "review-mention-preprocess-v1"
JOB_NAME = "review-mention-ingest"
MIN_MATCH_CONFIDENCE = 0.85

AD_MARKERS = (
    "광고",
    "협찬",
    "원고료",
    "체험단",
    "제공받아",
    "제공 받아",
    "소정의",
    "파트너스",
    "쿠폰",
    "할인코드",
    "예약문의",
    "문의주세요",
    "내돈내산아님",
)
FOOD_ONLY_TERMS = (
    "맛집",
    "카페",
    "식당",
    "디저트",
    "메뉴판",
    "존맛",
    "커피",
    "브런치",
    "고기",
    "반찬",
)
PLACE_EVIDENCE_TERMS = (
    "전시",
    "박물관",
    "미술관",
    "공원",
    "산책",
    "건축",
    "역사",
    "문화",
    "공연",
    "축제",
    "해설",
    "동선",
    "야경",
    "포토존",
)
ATTRIBUTE_TERMS = {
    "taste": ("맛있", "맛집", "메뉴", "커피", "디저트", "고기", "반찬", "브런치"),
    "service": ("친절", "서비스", "응대", "안내", "편리"),
    "atmosphere": ("조용", "쾌적", "분위기", "예쁘", "멋", "야경", "포토존"),
    "local_experience": (
        "전시",
        "산책",
        "역사",
        "문화",
        "공연",
        "축제",
        "동선",
        "해설",
        "공원",
        "미술관",
    ),
}


@dataclass(frozen=True)
class ReviewMentionPost:
    provider: str
    external_key: str
    keyword: str | None
    region_slug: str | None
    title: str | None
    body: str | None
    post_url: str | None
    created_at_source: datetime | None
    collected_at: datetime


@dataclass(frozen=True)
class ReviewMentionPlace:
    place_id: str
    name_ko: str
    category: str
    region_name_ko: str | None


@dataclass(frozen=True)
class ReviewMentionDecision:
    post: ReviewMentionPost
    place: ReviewMentionPlace | None
    normalized_text: str
    content_sha256: str
    is_ad: bool
    is_relevant: bool
    retained: bool
    reason: str
    match_confidence: float | None
    match_method: str | None
    category_policy: str
    week_start: date
    top_terms: tuple[str, ...]

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "provider": self.post.provider,
            "external_key": self.post.external_key,
            "place_id": self.place.place_id if self.place else None,
            "place_name_ko": self.place.name_ko if self.place else None,
            "category": self.place.category if self.place else None,
            "week_start": self.week_start.isoformat(),
            "retained": self.retained,
            "is_ad": self.is_ad,
            "is_relevant": self.is_relevant,
            "reason": self.reason,
            "match_confidence": self.match_confidence,
            "match_method": self.match_method,
            "category_policy": self.category_policy,
            "top_terms": list(self.top_terms),
            "content_sha256": self.content_sha256,
        }


@dataclass(frozen=True)
class ReviewMentionWeeklyAggregate:
    week_start: date
    place_id: str
    place_name_ko: str
    provider: str
    category: str
    mention_count: int
    organic_mention_count: int
    sentiment_score: float | None
    attributes: dict[str, Any]

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "week_start": self.week_start.isoformat(),
            "place_id": self.place_id,
            "place_name_ko": self.place_name_ko,
            "provider": self.provider,
            "category": self.category,
            "mention_count": self.mention_count,
            "organic_mention_count": self.organic_mention_count,
            "sentiment_score": self.sentiment_score,
            "attributes": self.attributes,
        }


@dataclass(frozen=True)
class ReviewMentionIngestResult:
    post_count: int
    decision_count: int
    retained_count: int
    ad_filtered_count: int
    irrelevant_count: int
    unmatched_count: int
    ambiguous_count: int
    aggregate_count: int
    decisions: tuple[ReviewMentionDecision, ...]
    aggregates: tuple[ReviewMentionWeeklyAggregate, ...]

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "post_count": self.post_count,
            "decision_count": self.decision_count,
            "retained_count": self.retained_count,
            "ad_filtered_count": self.ad_filtered_count,
            "irrelevant_count": self.irrelevant_count,
            "unmatched_count": self.unmatched_count,
            "ambiguous_count": self.ambiguous_count,
            "aggregate_count": self.aggregate_count,
            "preview": {
                "decisions": [item.to_public_dict() for item in self.decisions[:5]],
                "aggregates": [item.to_public_dict() for item in self.aggregates[:5]],
            },
        }


def clean_review_text(*parts: Any) -> str:
    text = " ".join(str(part or "") for part in parts if str(part or "").strip())
    text = html.unescape(text)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"[#＃]+", " ", text)
    text = re.sub(r"([!?.,])\1{2,}", r"\1\1", text)
    return re.sub(r"\s+", " ", text).strip()


def build_review_mention_result(
    *,
    posts: Sequence[ReviewMentionPost],
    places: Sequence[ReviewMentionPlace],
    limit: int,
) -> ReviewMentionIngestResult:
    decisions: list[ReviewMentionDecision] = []
    seen_hashes: set[str] = set()
    for post in posts[:limit]:
        decision = classify_post(post=post, places=places)
        if decision.content_sha256 in seen_hashes:
            decision = _replace_decision(
                decision,
                retained=False,
                is_relevant=False,
                reason="duplicate_content",
            )
        seen_hashes.add(decision.content_sha256)
        decisions.append(decision)

    aggregates = aggregate_decisions(decisions)
    return ReviewMentionIngestResult(
        post_count=len(posts[:limit]),
        decision_count=len(decisions),
        retained_count=sum(1 for item in decisions if item.retained),
        ad_filtered_count=sum(1 for item in decisions if item.is_ad),
        irrelevant_count=sum(
            1 for item in decisions if not item.is_relevant and item.reason != "ambiguous_match"
        ),
        unmatched_count=sum(1 for item in decisions if item.reason == "no_place_match"),
        ambiguous_count=sum(1 for item in decisions if item.reason == "ambiguous_match"),
        aggregate_count=len(aggregates),
        decisions=tuple(decisions),
        aggregates=tuple(aggregates),
    )


def classify_post(
    *,
    post: ReviewMentionPost,
    places: Sequence[ReviewMentionPlace],
) -> ReviewMentionDecision:
    normalized_text = clean_review_text(post.keyword, post.title, post.body)
    content_sha256 = hashlib.sha256(
        f"{post.provider}|{post.external_key}|{normalized_text}".encode()
    ).hexdigest()
    week_start = _week_start(post.created_at_source or post.collected_at)
    match = _match_place(normalized_text, places)
    is_ad = _contains_any(normalized_text, AD_MARKERS)
    top_terms = _top_terms(normalized_text)

    if match is None:
        return ReviewMentionDecision(
            post=post,
            place=None,
            normalized_text=normalized_text,
            content_sha256=content_sha256,
            is_ad=is_ad,
            is_relevant=False,
            retained=False,
            reason="no_place_match",
            match_confidence=None,
            match_method=None,
            category_policy="unmatched_manual_review",
            week_start=week_start,
            top_terms=top_terms,
        )

    place, confidence, method, ambiguous = match
    category_policy, relevant = _category_policy(
        place.category,
        normalized_text,
        place_name_ko=place.name_ko,
    )
    if ambiguous:
        reason = "ambiguous_match"
        retained = False
        relevant = False
    elif confidence < MIN_MATCH_CONFIDENCE:
        reason = "low_match_confidence"
        retained = False
        relevant = False
    elif is_ad:
        reason = "advertising_filtered"
        retained = False
    elif not relevant:
        reason = category_policy
        retained = False
    else:
        reason = "organic_retained"
        retained = True

    return ReviewMentionDecision(
        post=post,
        place=place,
        normalized_text=normalized_text,
        content_sha256=content_sha256,
        is_ad=is_ad,
        is_relevant=relevant,
        retained=retained,
        reason=reason,
        match_confidence=confidence,
        match_method=method,
        category_policy=category_policy,
        week_start=week_start,
        top_terms=top_terms,
    )


def aggregate_decisions(
    decisions: Sequence[ReviewMentionDecision],
) -> tuple[ReviewMentionWeeklyAggregate, ...]:
    grouped: dict[tuple[Any, ...], list[ReviewMentionDecision]] = defaultdict(list)
    for decision in decisions:
        if decision.place is None:
            continue
        key = (
            decision.week_start,
            decision.place.place_id,
            decision.place.name_ko,
            decision.post.provider,
            decision.place.category,
        )
        grouped[key].append(decision)

    aggregates: list[ReviewMentionWeeklyAggregate] = []
    for key, items in sorted(grouped.items(), key=lambda item: item[0]):
        retained = [item for item in items if item.retained]
        ad_count = sum(1 for item in items if item.is_ad)
        top_terms = _merge_top_terms(item.top_terms for item in retained or items)
        confidence_values = [
            item.match_confidence for item in retained if item.match_confidence is not None
        ]
        attributes = {
            "prompt_version": PROMPT_VERSION,
            "organic_review_count": len(retained),
            "filtered_ad_count": ad_count,
            "filtered_irrelevant_count": sum(1 for item in items if not item.is_relevant),
            "match_confidence_avg": _avg(confidence_values),
            "top_terms": top_terms,
            "source_mix": {key[3]: len(items)},
            "category_policy": _dominant_policy(items),
            "preprocess": {
                "schema_version": PROMPT_VERSION,
                "retained_external_keys": [item.post.external_key for item in retained[:20]],
                "filtered_external_keys": [
                    item.post.external_key for item in items if not item.retained
                ][:20],
            },
        }
        sentiment_score = _sentiment_score(retained)
        review_attributes = _review_attributes_summary(
            retained,
            category=key[4],
            sentiment_score=sentiment_score,
        )
        if review_attributes is not None:
            attributes["review_attributes"] = review_attributes
            review_quality = _review_quality_summary(
                category=key[4],
                mention_count=len(items),
                organic_count=len(retained),
                filtered_ad_count=ad_count,
                review_attributes=review_attributes,
                sentiment_score=sentiment_score,
            )
            if review_quality is not None:
                attributes["review_quality"] = review_quality
        aggregates.append(
            ReviewMentionWeeklyAggregate(
                week_start=key[0],
                place_id=key[1],
                place_name_ko=key[2],
                provider=key[3],
                category=key[4],
                mention_count=len(items),
                organic_mention_count=len(retained),
                sentiment_score=sentiment_score,
                attributes=attributes,
            )
        )
    return tuple(aggregates)


def fetch_review_mention_inputs(
    *,
    dsn: str,
    limit: int,
    provider: str,
    connect_timeout: int,
) -> tuple[list[ReviewMentionPost], list[ReviewMentionPlace]]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    provider_filter = "" if provider == "all" else "WHERE provider = %(provider)s"
    post_sql = f"""
        SELECT
            provider,
            external_key,
            keyword,
            region_slug,
            title,
            body,
            post_url,
            created_at_source,
            collected_at
        FROM community.posts
        {provider_filter}
        ORDER BY coalesce(created_at_source, collected_at) DESC, external_key
        LIMIT %(limit)s
    """
    place_sql = """
        SELECT place_id, name_ko, category, region_name_ko
        FROM travel.places
        WHERE name_ko IS NOT NULL
        ORDER BY name_ko
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(post_sql, {"provider": provider, "limit": limit})
            posts = [_post_from_row(row) for row in cur.fetchall()]
            cur.execute(place_sql)
            places = [_place_from_row(row) for row in cur.fetchall()]
    return posts, places


def insert_review_mention_aggregates(
    *,
    dsn: str,
    aggregates: Sequence[ReviewMentionWeeklyAggregate],
    connect_timeout: int,
) -> int:
    import psycopg2
    from psycopg2.extras import Json

    sql = """
        INSERT INTO community.place_mentions_weekly (
            week_start,
            place_id,
            place_name_ko,
            provider,
            category,
            mention_count,
            organic_mention_count,
            sentiment_score,
            attributes,
            updated_at
        )
        VALUES (
            %(week_start)s,
            %(place_id)s,
            %(place_name_ko)s,
            %(provider)s,
            %(category)s,
            %(mention_count)s,
            %(organic_mention_count)s,
            %(sentiment_score)s,
            %(attributes)s,
            now()
        )
        ON CONFLICT (week_start, place_name_ko, provider, category)
        DO UPDATE SET
            place_id = EXCLUDED.place_id,
            mention_count = EXCLUDED.mention_count,
            organic_mention_count = EXCLUDED.organic_mention_count,
            sentiment_score = EXCLUDED.sentiment_score,
            attributes = (
                EXCLUDED.attributes
                || CASE
                    WHEN community.place_mentions_weekly.attributes ? 'review_attributes'
                     AND coalesce(
                        community.place_mentions_weekly.attributes #>> '{review_attributes,schema_version}',
                        ''
                     ) NOT LIKE 'review-attributes-deterministic-%%'
                    THEN jsonb_build_object(
                        'review_attributes',
                        community.place_mentions_weekly.attributes->'review_attributes'
                    )
                    ELSE '{}'::jsonb
                END
                || CASE
                    WHEN community.place_mentions_weekly.attributes ? 'review_quality'
                     AND coalesce(
                        community.place_mentions_weekly.attributes #>> '{review_attributes,schema_version}',
                        ''
                     ) NOT LIKE 'review-attributes-deterministic-%%'
                    THEN jsonb_build_object(
                        'review_quality',
                        community.place_mentions_weekly.attributes->'review_quality'
                    )
                    ELSE '{}'::jsonb
                END
            ),
            updated_at = now()
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        inserted = 0
        with conn.cursor() as cur:
            for aggregate in aggregates:
                cur.execute(
                    sql,
                    {
                        "week_start": aggregate.week_start,
                        "place_id": aggregate.place_id,
                        "place_name_ko": aggregate.place_name_ko,
                        "provider": aggregate.provider,
                        "category": aggregate.category,
                        "mention_count": aggregate.mention_count,
                        "organic_mention_count": aggregate.organic_mention_count,
                        "sentiment_score": aggregate.sentiment_score,
                        "attributes": Json(aggregate.attributes),
                    },
                )
                inserted += int(cur.rowcount or 0)
        conn.commit()
    return inserted


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


def _match_place(
    text: str,
    places: Sequence[ReviewMentionPlace],
) -> tuple[ReviewMentionPlace, float, str, bool] | None:
    normalized = _compact(text)
    matches = [place for place in places if place.name_ko and _compact(place.name_ko) in normalized]
    if not matches:
        return None
    exact_length = max(len(_compact(place.name_ko)) for place in matches)
    strongest = [place for place in matches if len(_compact(place.name_ko)) == exact_length]
    if len(strongest) > 1:
        return strongest[0], 0.7, "exact_name_in_text", True
    return strongest[0], 0.92, "exact_name_in_text", False


def _category_policy(category: str, text: str, *, place_name_ko: str = "") -> tuple[str, bool]:
    lowered = text.lower()
    evidence_text = lowered
    if place_name_ko:
        evidence_text = re.sub(re.escape(place_name_ko.lower()), " ", evidence_text)
    has_food = _contains_any(lowered, FOOD_ONLY_TERMS)
    has_place = _contains_any(evidence_text, PLACE_EVIDENCE_TERMS)
    if category == "restaurant":
        return "restaurant_food_terms_retained", True
    if has_food and not has_place:
        return "attraction_food_only_review_rejected", False
    return "place_experience_terms_retained", True


def _top_terms(text: str) -> tuple[str, ...]:
    terms = []
    for term in PLACE_EVIDENCE_TERMS + FOOD_ONLY_TERMS:
        if term in text and term not in terms:
            terms.append(term)
    if terms:
        return tuple(terms[:8])
    tokens = [
        token
        for token in re.findall(r"[가-힣A-Za-z0-9]{2,}", text)
        if token not in {"그리고", "오늘", "정말", "공개", "예시"}
    ]
    return tuple(dict.fromkeys(tokens[:8]))


def _merge_top_terms(term_groups: Iterable[Sequence[str]]) -> list[str]:
    merged: list[str] = []
    for group in term_groups:
        for term in group:
            if term and term not in merged:
                merged.append(term)
            if len(merged) >= 12:
                return merged
    return merged


def _sentiment_score(items: Sequence[ReviewMentionDecision]) -> float | None:
    if not items:
        return None
    positive_terms = ("좋", "추천", "친절", "조용", "멋", "예쁘", "맛있", "쾌적")
    negative_terms = ("별로", "불친절", "복잡", "비싸", "실망", "나쁨")
    score = 0
    for item in items:
        text = item.normalized_text
        score += sum(1 for term in positive_terms if term in text)
        score -= sum(1 for term in negative_terms if term in text)
    normalized = max(-1.0, min(1.0, score / max(3, len(items) * 2)))
    return round(normalized, 4)


def _review_attributes_summary(
    items: Sequence[ReviewMentionDecision],
    *,
    category: str,
    sentiment_score: float | None,
) -> dict[str, Any] | None:
    if not items:
        return None
    attribute_names = (
        ("taste", "service", "atmosphere")
        if category == "restaurant"
        else ("local_experience", "atmosphere", "service")
    )
    text = " ".join(item.normalized_text for item in items)
    scores: dict[str, float] = {}
    evidence_terms: dict[str, list[str]] = {}
    for name in attribute_names:
        terms = [term for term in ATTRIBUTE_TERMS[name] if term in text]
        evidence_terms[name] = terms[:8]
        scores[name] = _attribute_score(len(terms), len(items))
    attribute_mean = _avg(list(scores.values()))
    confidence = round(min(0.85, 0.45 + len(items) / 20), 4)
    return {
        "schema_version": "review-attributes-deterministic-v1",
        "source": "deterministic_preprocess",
        "attribute_scores": scores,
        "attribute_mean": attribute_mean,
        "attribute_confidence_avg": confidence,
        "sentiment_score": sentiment_score,
        "sentiment_confidence": confidence,
        "evidence_terms": evidence_terms,
    }


def _review_quality_summary(
    *,
    category: str,
    mention_count: int,
    organic_count: int,
    filtered_ad_count: int,
    review_attributes: dict[str, Any],
    sentiment_score: float | None,
) -> dict[str, Any] | None:
    if organic_count < 3:
        return None
    attribute_mean = review_attributes.get("attribute_mean")
    confidence = review_attributes.get("attribute_confidence_avg")
    if attribute_mean is None or sentiment_score is None or confidence is None:
        return None
    organic_coverage = min(1.0, organic_count / _review_category_target(category))
    ad_quality = 1.0 - min(1.0, filtered_ad_count / max(mention_count, 1))
    sentiment_norm = (max(-1.0, min(1.0, sentiment_score)) + 1.0) / 2.0
    score = (
        0.35 * float(attribute_mean)
        + 0.25 * sentiment_norm
        + 0.20 * organic_coverage
        + 0.10 * ad_quality
        + 0.10 * float(confidence)
    )
    if filtered_ad_count / max(mention_count, 1) > 0.50:
        score = min(score, 0.60)
    return {
        "schema_version": "review-quality-deterministic-v1",
        "source": "deterministic_preprocess",
        "score": round(max(0.0, min(1.0, score)), 4),
        "organic_review_count": organic_count,
        "mention_count": mention_count,
        "confidence": confidence,
    }


def _attribute_score(term_count: int, organic_count: int) -> float:
    if organic_count <= 0:
        return 0.0
    return round(min(0.9, 0.45 + min(0.45, term_count / max(organic_count, 1) * 0.18)), 4)


def _review_category_target(category: str) -> float:
    if category == "restaurant":
        return 30.0
    if category == "event":
        return 15.0
    return 20.0


def _dominant_policy(items: Sequence[ReviewMentionDecision]) -> str:
    counts: dict[str, int] = defaultdict(int)
    for item in items:
        counts[item.category_policy] += 1
    return max(counts, key=counts.get)


def _avg(values: Sequence[float]) -> float | None:
    if not values:
        return None
    return round(sum(values) / len(values), 4)


def _week_start(value: datetime) -> date:
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    day = value.date()
    return day - timedelta(days=day.weekday())


def _contains_any(text: str, terms: Sequence[str]) -> bool:
    return any(term.lower() in text.lower() for term in terms)


def _compact(value: str) -> str:
    return re.sub(r"\s+", "", value).lower()


def _replace_decision(
    decision: ReviewMentionDecision,
    **changes: Any,
) -> ReviewMentionDecision:
    values = decision.__dict__ | changes
    return ReviewMentionDecision(**values)


def _post_from_row(row: dict[str, Any]) -> ReviewMentionPost:
    return ReviewMentionPost(
        provider=str(row.get("provider") or ""),
        external_key=str(row.get("external_key") or ""),
        keyword=row.get("keyword"),
        region_slug=row.get("region_slug"),
        title=row.get("title"),
        body=row.get("body"),
        post_url=row.get("post_url"),
        created_at_source=row.get("created_at_source"),
        collected_at=row.get("collected_at") or datetime.now(UTC),
    )


def _place_from_row(row: dict[str, Any]) -> ReviewMentionPlace:
    return ReviewMentionPlace(
        place_id=str(row.get("place_id") or ""),
        name_ko=str(row.get("name_ko") or ""),
        category=str(row.get("category") or "attraction"),
        region_name_ko=row.get("region_name_ko"),
    )
