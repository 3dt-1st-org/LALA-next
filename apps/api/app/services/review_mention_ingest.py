from __future__ import annotations

import hashlib
import html
import json
import re
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from contextlib import closing
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any, Iterable, Sequence

PROMPT_VERSION = "review-mention-preprocess-v1"
DEFAULT_PROVIDER = "naver_blog"
NAVER_BLOG_SEARCH_URL = "https://openapi.naver.com/v1/search/blog.json"
SUPPORTED_CATEGORIES = {"all", "attraction", "restaurant", "event", "culture_venue"}
AD_TERMS = (
    "협찬",
    "광고",
    "체험단",
    "원고료",
    "제공받아",
    "제공 받",
    "파트너스",
    "홍보",
    "소정의 수수료",
    "업체로부터",
    "이 글은",
)
CALL_TO_ACTION_TERMS = ("예약", "문의", "할인", "쿠폰", "이벤트", "구매", "바로가기")
FOOD_TERMS = (
    "맛집",
    "카페",
    "식당",
    "디저트",
    "메뉴판",
    "존맛",
    "음식",
    "맛있",
    "고기",
    "커피",
    "브런치",
)
PLACE_EVIDENCE_TERMS = (
    "전시",
    "산책",
    "공원",
    "박물관",
    "미술관",
    "공연",
    "축제",
    "역사",
    "건축",
    "풍경",
    "야경",
    "관람",
    "체험",
    "동선",
    "문화",
    "여행",
    "코스",
    "포토",
)
RESTAURANT_TERMS = (
    "맛",
    "메뉴",
    "친절",
    "서비스",
    "분위기",
    "웨이팅",
    "가격",
    "반찬",
    "재방문",
    "양",
)
GENERAL_TERMS = (
    "조용",
    "깔끔",
    "가족",
    "아이",
    "데이트",
    "혼잡",
    "추천",
    "주차",
    "접근",
    "사진",
)


@dataclass(frozen=True)
class ReviewMentionTarget:
    place_id: str
    name_ko: str
    category: str
    region_name_ko: str | None

    @property
    def search_query(self) -> str:
        parts = [self.region_name_ko or "", self.name_ko]
        if self.category == "restaurant":
            parts.append("맛집 후기")
        else:
            parts.append("후기")
        return " ".join(part for part in parts if part).strip()

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "place_id": self.place_id,
            "name_ko": self.name_ko,
            "category": self.category,
            "region_name_ko": self.region_name_ko,
            "search_query": self.search_query,
        }


@dataclass(frozen=True)
class NaverBlogItem:
    title: str
    description: str
    link: str
    postdate: str | None = None


@dataclass(frozen=True)
class ReviewMentionCandidate:
    provider: str
    external_key: str
    place_id: str
    place_name_ko: str
    category: str
    region_name_ko: str | None
    title: str
    body: str
    post_url: str | None
    created_at_source: datetime | None
    normalized_text: str
    content_sha256: str
    is_duplicate: bool
    is_ad: bool
    is_relevant: bool
    rejection_reasons: tuple[str, ...]
    organic_excerpt: str | None
    match_confidence: float
    match_method: str
    retained_terms: tuple[str, ...]

    @property
    def is_organic(self) -> bool:
        return not self.is_duplicate and not self.is_ad and self.is_relevant

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "provider": self.provider,
            "external_key": self.external_key,
            "place_id": self.place_id,
            "place_name_ko": self.place_name_ko,
            "category": self.category,
            "title": self.title,
            "post_url": self.post_url,
            "created_at_source": self.created_at_source.isoformat()
            if self.created_at_source
            else None,
            "is_duplicate": self.is_duplicate,
            "is_ad": self.is_ad,
            "is_relevant": self.is_relevant,
            "is_organic": self.is_organic,
            "rejection_reasons": list(self.rejection_reasons),
            "organic_excerpt": self.organic_excerpt,
            "match_confidence": self.match_confidence,
            "match_method": self.match_method,
            "retained_terms": list(self.retained_terms),
            "content_sha256": self.content_sha256,
        }


@dataclass(frozen=True)
class PlaceMentionWeeklyAggregate:
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
    provider: str
    targets: tuple[ReviewMentionTarget, ...]
    candidates: tuple[ReviewMentionCandidate, ...]
    aggregates: tuple[PlaceMentionWeeklyAggregate, ...]

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "provider": self.provider,
            "target_count": len(self.targets),
            "candidate_count": len(self.candidates),
            "aggregate_count": len(self.aggregates),
            "organic_candidate_count": sum(1 for item in self.candidates if item.is_organic),
            "filtered_ad_count": sum(1 for item in self.candidates if item.is_ad),
            "duplicate_count": sum(1 for item in self.candidates if item.is_duplicate),
            "targets": [target.to_public_dict() for target in self.targets[:10]],
            "preview_candidates": [item.to_public_dict() for item in self.candidates[:10]],
            "preview_aggregates": [item.to_public_dict() for item in self.aggregates[:10]],
        }


def fetch_review_mention_targets(
    *,
    dsn: str,
    category: str,
    limit: int,
    connect_timeout: int,
) -> tuple[ReviewMentionTarget, ...]:
    if category not in SUPPORTED_CATEGORIES:
        raise ValueError(f"Unsupported category: {category}")
    if limit <= 0:
        raise ValueError("limit must be positive.")

    import psycopg2
    from psycopg2.extras import RealDictCursor

    sql = """
        SELECT place_id, name_ko, category, region_name_ko
        FROM travel.places
        WHERE name_ko IS NOT NULL
          AND trim(name_ko) <> ''
          AND (%s = 'all' OR category = %s)
        ORDER BY
          CASE category
            WHEN 'restaurant' THEN 0
            WHEN 'attraction' THEN 1
            WHEN 'culture_venue' THEN 2
            ELSE 3
          END,
          updated_at DESC,
          place_id
        LIMIT %s
    """
    with closing(psycopg2.connect(dsn, connect_timeout=connect_timeout)) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, (category, category, limit))
            rows = cur.fetchall()
    return tuple(
        ReviewMentionTarget(
            place_id=str(row["place_id"]),
            name_ko=str(row["name_ko"]),
            category=str(row["category"]),
            region_name_ko=_optional_text(row.get("region_name_ko")),
        )
        for row in rows
    )


def fetch_naver_blog_items(
    *,
    query: str,
    client_id: str,
    client_secret: str,
    display: int,
    timeout: int,
) -> tuple[NaverBlogItem, ...]:
    if not client_id or not client_secret:
        raise ValueError("NAVER_CLIENT_ID and NAVER_CLIENT_SECRET are required.")
    if display <= 0:
        raise ValueError("display must be positive.")

    params = urllib.parse.urlencode(
        {"query": query, "display": min(display, 100), "sort": "sim"}
    )
    request = urllib.request.Request(f"{NAVER_BLOG_SEARCH_URL}?{params}")
    request.add_header("X-Naver-Client-Id", client_id)
    request.add_header("X-Naver-Client-Secret", client_secret)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode("utf-8"))
    items = payload.get("items") if isinstance(payload, dict) else []
    if not isinstance(items, list):
        return ()
    return tuple(
        NaverBlogItem(
            title=str(item.get("title") or ""),
            description=str(item.get("description") or ""),
            link=str(item.get("link") or ""),
            postdate=_optional_text(item.get("postdate")),
        )
        for item in items
        if isinstance(item, dict)
    )


def build_review_mention_result(
    *,
    targets: Sequence[ReviewMentionTarget],
    provider: str,
    items_by_place_id: dict[str, Sequence[NaverBlogItem]],
    week_start: date | None = None,
) -> ReviewMentionIngestResult:
    seen_hashes: set[str] = set()
    candidates: list[ReviewMentionCandidate] = []
    for target in targets:
        for item in items_by_place_id.get(target.place_id, ()):
            candidate = preprocess_naver_blog_item(
                target=target,
                item=item,
                provider=provider,
                seen_hashes=seen_hashes,
            )
            candidates.append(candidate)
    aggregates = aggregate_weekly_mentions(candidates, week_start=week_start)
    return ReviewMentionIngestResult(
        provider=provider,
        targets=tuple(targets),
        candidates=tuple(candidates),
        aggregates=tuple(aggregates),
    )


def preprocess_naver_blog_item(
    *,
    target: ReviewMentionTarget,
    item: NaverBlogItem,
    provider: str = DEFAULT_PROVIDER,
    seen_hashes: set[str] | None = None,
) -> ReviewMentionCandidate:
    title = clean_review_text(item.title)
    body = clean_review_text(item.description)
    normalized_text = normalize_review_text(f"{title} {body}")
    content_sha256 = _sha256_text(normalized_text or item.link or title)
    external_key = item.link or f"{provider}:{content_sha256}"
    duplicate = content_sha256 in seen_hashes if seen_hashes is not None else False
    if seen_hashes is not None:
        seen_hashes.add(content_sha256)

    ad_reasons = _ad_reasons(normalized_text)
    category_reasons = _category_rejection_reasons(
        text=normalized_text,
        category=target.category,
    )
    relevant = not category_reasons and _target_name_is_present(target, normalized_text)
    rejection_reasons = tuple(ad_reasons + category_reasons)
    retained_terms = extract_retained_terms(normalized_text, category=target.category)
    organic_excerpt = _excerpt(body or title) if not ad_reasons and relevant and not duplicate else None

    return ReviewMentionCandidate(
        provider=provider,
        external_key=external_key,
        place_id=target.place_id,
        place_name_ko=target.name_ko,
        category=target.category,
        region_name_ko=target.region_name_ko,
        title=title,
        body=body,
        post_url=item.link or None,
        created_at_source=_parse_naver_postdate(item.postdate),
        normalized_text=normalized_text,
        content_sha256=content_sha256,
        is_duplicate=duplicate,
        is_ad=bool(ad_reasons),
        is_relevant=relevant,
        rejection_reasons=rejection_reasons,
        organic_excerpt=organic_excerpt,
        match_confidence=0.94 if relevant else 0.0,
        match_method="targeted_name_region_query" if relevant else "rejected_by_policy",
        retained_terms=retained_terms,
    )


def aggregate_weekly_mentions(
    candidates: Iterable[ReviewMentionCandidate],
    *,
    week_start: date | None = None,
) -> list[PlaceMentionWeeklyAggregate]:
    grouped: dict[tuple[date, str, str, str, str], list[ReviewMentionCandidate]] = defaultdict(list)
    for candidate in candidates:
        candidate_week = week_start or _week_start(candidate.created_at_source)
        grouped[
            (
                candidate_week,
                candidate.place_id,
                candidate.place_name_ko,
                candidate.provider,
                candidate.category,
            )
        ].append(candidate)

    aggregates: list[PlaceMentionWeeklyAggregate] = []
    for key, rows in sorted(grouped.items(), key=lambda item: item[0]):
        organic_rows = [row for row in rows if row.is_organic]
        all_terms = Counter(term for row in organic_rows for term in row.retained_terms)
        rejection_counts = Counter(reason for row in rows for reason in row.rejection_reasons)
        match_confidences = [row.match_confidence for row in organic_rows]
        attributes = {
            "prompt_version": PROMPT_VERSION,
            "organic_review_count": len(organic_rows),
            "filtered_ad_count": sum(1 for row in rows if row.is_ad),
            "duplicate_count": sum(1 for row in rows if row.is_duplicate),
            "rejected_irrelevant_count": sum(1 for row in rows if not row.is_relevant),
            "rejection_counts": dict(sorted(rejection_counts.items())),
            "match_confidence_avg": round(sum(match_confidences) / len(match_confidences), 4)
            if match_confidences
            else None,
            "top_terms": [term for term, _count in all_terms.most_common(8)],
            "source_mix": {rows[0].provider: len(rows)},
            "category_policy": _category_policy(rows[0].category),
            "sample_urls": [row.post_url for row in organic_rows[:3] if row.post_url],
        }
        aggregates.append(
            PlaceMentionWeeklyAggregate(
                week_start=key[0],
                place_id=key[1],
                place_name_ko=key[2],
                provider=key[3],
                category=key[4],
                mention_count=len(rows),
                organic_mention_count=len(organic_rows),
                sentiment_score=None,
                attributes=attributes,
            )
        )
    return aggregates


def upsert_review_mention_result(
    *,
    dsn: str,
    result: ReviewMentionIngestResult,
    connect_timeout: int,
) -> dict[str, Any]:
    if not dsn:
        raise ValueError("DB_DSN is required to persist review mentions.")

    import psycopg2
    from psycopg2.extras import Json

    post_sql = """
        INSERT INTO community.posts (
            provider,
            external_key,
            keyword,
            region_slug,
            title,
            body,
            post_url,
            created_at_source
        )
        VALUES (
            %(provider)s,
            %(external_key)s,
            %(keyword)s,
            %(region_slug)s,
            %(title)s,
            %(body)s,
            %(post_url)s,
            %(created_at_source)s
        )
        ON CONFLICT (external_key) DO NOTHING
    """
    aggregate_sql = """
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
            attributes = EXCLUDED.attributes,
            updated_at = now()
    """
    inserted_posts = 0
    upserted_aggregates = 0
    with closing(psycopg2.connect(dsn, connect_timeout=connect_timeout)) as conn:
        with conn.cursor() as cur:
            for candidate in result.candidates:
                if not candidate.is_organic:
                    continue
                cur.execute(
                    post_sql,
                    {
                        "provider": candidate.provider,
                        "external_key": candidate.external_key,
                        "keyword": candidate.place_name_ko,
                        "region_slug": candidate.region_name_ko,
                        "title": candidate.title,
                        "body": candidate.organic_excerpt or candidate.body,
                        "post_url": candidate.post_url,
                        "created_at_source": candidate.created_at_source,
                    },
                )
                inserted_posts += cur.rowcount
            for aggregate in result.aggregates:
                cur.execute(
                    aggregate_sql,
                    {
                        "week_start": aggregate.week_start,
                        "place_id": aggregate.place_id,
                        "place_name_ko": aggregate.place_name_ko,
                        "provider": aggregate.provider,
                        "category": aggregate.category,
                        "mention_count": aggregate.mention_count,
                        "organic_mention_count": aggregate.organic_mention_count,
                        "sentiment_score": aggregate.sentiment_score,
                        "attributes": Json(aggregate.attributes, dumps=_json_dumps),
                    },
                )
                upserted_aggregates += cur.rowcount
        conn.commit()
    return {
        "ok": True,
        "inserted_posts": inserted_posts,
        "upserted_aggregates": upserted_aggregates,
    }


def clean_review_text(value: Any) -> str:
    text = html.unescape(str(value or ""))
    text = re.sub(r"<[^>]+>", " ", text)
    text = text.replace("\u200b", " ")
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def normalize_review_text(value: Any) -> str:
    text = clean_review_text(value).lower()
    text = re.sub(r"[#@]", " ", text)
    text = re.sub(r"[!?.]{2,}", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def extract_retained_terms(text: str, *, category: str) -> tuple[str, ...]:
    term_pool = GENERAL_TERMS + PLACE_EVIDENCE_TERMS
    if category == "restaurant":
        term_pool = RESTAURANT_TERMS + FOOD_TERMS + GENERAL_TERMS
    found = []
    for term in term_pool:
        if term.lower() in text and term not in found:
            found.append(term)
    return tuple(found[:12])


def _ad_reasons(text: str) -> list[str]:
    reasons = [f"ad_term:{term}" for term in AD_TERMS if term.lower() in text]
    cta_count = sum(1 for term in CALL_TO_ACTION_TERMS if term in text)
    if cta_count >= 4:
        reasons.append("excessive_call_to_action")
    return reasons


def _category_rejection_reasons(*, text: str, category: str) -> list[str]:
    if category == "restaurant":
        return []
    has_food = any(term.lower() in text for term in FOOD_TERMS)
    has_place = any(term.lower() in text for term in PLACE_EVIDENCE_TERMS)
    if has_food and not has_place:
        return ["food_only_non_restaurant"]
    return []


def _target_name_is_present(target: ReviewMentionTarget, text: str) -> bool:
    name = normalize_review_text(target.name_ko)
    if name and name in text:
        return True
    compact_name = name.replace(" ", "")
    compact_text = text.replace(" ", "")
    if compact_name and compact_name in compact_text:
        return True
    tokens = [token for token in re.split(r"\s+", name) if len(token) > 1]
    return bool(tokens and all(token in text for token in tokens))


def _category_policy(category: str) -> str:
    if category == "restaurant":
        return "restaurant_food_terms_retained"
    return "non_restaurant_food_only_review_rejected"


def _parse_naver_postdate(value: str | None) -> datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return datetime.strptime(text, "%Y%m%d").replace(tzinfo=UTC)
    except ValueError:
        return None


def _week_start(value: datetime | None = None) -> date:
    base = (value or datetime.now(UTC)).date()
    return base - timedelta(days=base.weekday())


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _excerpt(value: str, limit: int = 220) -> str:
    text = clean_review_text(value)
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


def _optional_text(value: Any) -> str | None:
    text = str(value or "").strip()
    return text or None


def _json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)
