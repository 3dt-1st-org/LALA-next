from __future__ import annotations

import json
import time
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any

from apps.api.app.core.config import get_settings

PROMPT_VERSION = "review-attributes-v1"
DETERMINISTIC_VERSION = "review-attributes-deterministic-v1"
QUALITY_VERSION = "review-quality-v1"
JOB_NAME = "review-attribute-batch"

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

SYSTEM_PROMPT = """\
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
      "evidence_terms": {"attribute_name": ["short Korean evidence phrase"]},
      "summary_ko": "one concise Korean summary",
      "reason": "short reason"
    }
  ]
}

Rules:
1. Use only supplied retained organic review snippets and aggregate terms.
2. Do not invent hours, prices, menus, historical facts, weather, or crowd status.
3. Restaurants may use taste, menu, service, price, atmosphere, cleanliness, and wait/crowding evidence.
4. Attractions and culture venues must not treat unrelated food/cafe text as place quality.
5. Events should prioritize program quality, access, family/foreign visitor fit, weather/indoor fit, and crowding.
6. Evidence phrases must be short and must not quote long review text.
7. Return every input mention_id exactly once.
"""


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

    def attribute_mean(self) -> float | None:
        if not self.attribute_scores:
            return None
        return round(sum(self.attribute_scores.values()) / len(self.attribute_scores), 4)

    def to_attributes_payload(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "source": self.source_method,
            "attribute_scores": self.attribute_scores,
            "attribute_mean": self.attribute_mean(),
            "attribute_confidence_avg": self.attribute_confidence_avg,
            "sentiment_score": self.sentiment_score,
            "sentiment_confidence": self.sentiment_confidence,
            "evidence_terms": self.evidence_terms,
            "summary_ko": self.summary_ko,
            "reason": self.reason,
        }

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "mention_id": self.mention_id,
            "schema_version": self.schema_version,
            "sentiment_score": self.sentiment_score,
            "attribute_mean": self.attribute_mean(),
            "attribute_confidence_avg": self.attribute_confidence_avg,
            "attribute_scores": self.attribute_scores,
            "summary_ko": self.summary_ko,
            "source_method": self.source_method,
        }


@dataclass(frozen=True)
class ReviewAttributeApplyRow:
    mention_id: str
    sentiment_score: float | None
    review_attributes: dict[str, Any]
    review_quality: dict[str, Any] | None
    source_method: str


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

    sql = """
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
            mentions.updated_at
        ORDER BY
            CASE
                WHEN mentions.attributes #>> '{review_attributes,schema_version}'
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
) -> list[ReviewAttributeEnrichment]:
    if not candidates:
        return []
    settings = get_settings()
    missing = _missing_aoai_settings(settings)
    if missing:
        raise RuntimeError("Azure OpenAI config is missing: " + ", ".join(missing))

    try:
        from openai import AzureOpenAI
    except Exception as exc:
        raise RuntimeError("openai package is required for review attribute AI batch.") from exc

    client = AzureOpenAI(
        azure_endpoint=settings.azure_openai_endpoint,
        api_key=settings.azure_openai_key,
        api_version=settings.azure_openai_api_version,
    )
    enrichments: list[ReviewAttributeEnrichment] = []
    for start in range(0, len(candidates), batch_size):
        batch = list(candidates[start : start + batch_size])
        response = _create_chat_completion_with_retry(
            client=client,
            model=selected_review_batch_model(settings),
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
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


def parse_ai_response(
    raw: str,
    candidates: Sequence[ReviewAttributeCandidate],
) -> list[ReviewAttributeEnrichment]:
    payload = json.loads(_strip_code_fence(raw))
    items = payload.get("results") if isinstance(payload, dict) else None
    if not isinstance(items, list):
        raise ValueError("Azure OpenAI JSON response did not include a results list.")
    candidate_by_id = {candidate.mention_id: candidate for candidate in candidates}
    parsed: list[ReviewAttributeEnrichment] = []
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        fallback_id = candidates[index].mention_id if index < len(candidates) else ""
        mention_id = str(item.get("mention_id") or item.get("id") or fallback_id)
        candidate = candidate_by_id.get(mention_id)
        if candidate is None and index < len(candidates):
            candidate = candidates[index]
            mention_id = candidate.mention_id
        if candidate is None:
            continue
        allowed = set(attribute_names_for_category(candidate.category))
        scores = _attribute_scores(item.get("attribute_scores"), allowed)
        if not scores:
            scores = _deterministic_enrichment(candidate).attribute_scores
        parsed.append(
            ReviewAttributeEnrichment(
                mention_id=mention_id,
                schema_version=PROMPT_VERSION,
                sentiment_score=_optional_sentiment(item.get("sentiment_score")),
                sentiment_confidence=_optional_unit(item.get("sentiment_confidence"), default=0.55),
                attribute_scores=scores,
                attribute_confidence_avg=_optional_unit(
                    item.get("attribute_confidence_avg"),
                    default=0.55,
                ),
                evidence_terms=_evidence_terms(item.get("evidence_terms"), allowed),
                summary_ko=_optional_text(item.get("summary_ko")),
                reason=_optional_text(item.get("reason")),
                source_method="azure_openai",
            )
        )
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
            sentiment_score = COALESCE(%(sentiment_score)s, sentiment_score),
            attributes = attributes
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
                    WHEN %(review_quality)s::jsonb IS NULL THEN '{}'::jsonb
                    ELSE jsonb_build_object('review_quality', %(review_quality)s::jsonb)
                END,
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
                        "prompt_version": PROMPT_VERSION,
                        "source_method": source_method,
                    },
                )
                updated += cur.rowcount
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
    )


def _apply_row(
    candidate: ReviewAttributeCandidate,
    enrichment: ReviewAttributeEnrichment,
    *,
    source_method: str,
) -> ReviewAttributeApplyRow:
    review_attributes = enrichment.to_attributes_payload()
    return ReviewAttributeApplyRow(
        mention_id=enrichment.mention_id,
        sentiment_score=enrichment.sentiment_score,
        review_attributes=review_attributes,
        review_quality=review_quality_payload(candidate, enrichment),
        source_method=source_method,
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
                max_tokens=4000,
                response_format={"type": "json_object"},
            )
        except Exception as exc:
            last_exc = exc
            if attempt >= attempts or not _is_retryable_ai_error(exc):
                raise
            time.sleep(delay * attempt)
    if last_exc:
        raise last_exc
    raise RuntimeError("Azure OpenAI completion failed before a request was attempted.")


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


def _missing_aoai_settings(settings: Any) -> list[str]:
    missing: list[str] = []
    if not settings.azure_openai_endpoint:
        missing.append("AZURE_OPENAI_ENDPOINT")
    if not settings.azure_openai_key:
        missing.append("AZURE_OPENAI_KEY")
    if not selected_review_batch_model(settings):
        missing.append("AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT or AZURE_OPENAI_DEPLOYMENT")
    if not settings.azure_openai_api_version:
        missing.append("AZURE_OPENAI_API_VERSION")
    return missing


def selected_review_batch_model(settings: Any | None = None) -> str:
    if settings is None:
        settings = get_settings()
    role_specific = getattr(settings, "azure_openai_review_batch_deployment", "") or ""
    generic = getattr(settings, "azure_openai_deployment", "") or ""
    return str(role_specific or generic).strip()


def _post_sample(value: dict[str, Any]) -> dict[str, str | None]:
    return {
        "external_key": _optional_text(value.get("external_key")),
        "title": _optional_text(value.get("title")),
        "body": _optional_text(value.get("body")),
    }


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
