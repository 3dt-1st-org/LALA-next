from __future__ import annotations

import hashlib
import json
import math
import re
from dataclasses import asdict, dataclass
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Iterable, Literal

from apps.api.app.core.config import get_settings

VECTOR_DIMENSIONS = 1536
LOCAL_HASH_EMBEDDING_MODEL = "local-hash-v1"
EmbeddingMethod = Literal["local-hash", "azure-openai"]
SourceScope = Literal["all", "static", "dynamic"]

STATIC_SOURCE_TYPES = ("place_profile",)
DYNAMIC_SOURCE_TYPES = (
    "culture_event",
    "community_post",
    "place_mention",
    "weather_context",
)


@dataclass(frozen=True)
class KnowledgeChunk:
    source_type: str
    source_id: str
    source_table: str
    body_ko: str
    title_ko: str | None = None
    body_en: str | None = None
    place_id: str | None = None
    metadata: dict[str, Any] | None = None

    @property
    def text_for_embedding(self) -> str:
        parts = [self.title_ko or "", self.body_ko or "", self.body_en or ""]
        return "\n".join(part for part in parts if part.strip())

    @property
    def content_sha256(self) -> str:
        payload = {
            "source_type": self.source_type,
            "source_id": self.source_id,
            "title_ko": self.title_ko,
            "body_ko": self.body_ko,
            "body_en": self.body_en,
            "metadata": self.metadata or {},
        }
        return hashlib.sha256(
            json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
        ).hexdigest()

    def to_public_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["content_sha256"] = self.content_sha256
        return payload


@dataclass(frozen=True)
class RagSearchResult:
    source_type: str
    source_id: str
    source_table: str
    title_ko: str | None
    body_ko: str
    place_id: str | None
    metadata: dict[str, Any]
    similarity: float
    embedding_model: str | None
    updated_at: str | None

    @classmethod
    def from_row(cls, row: dict[str, Any]) -> "RagSearchResult":
        return cls(
            source_type=str(row.get("source_type") or ""),
            source_id=str(row.get("source_id") or ""),
            source_table=str(row.get("source_table") or ""),
            title_ko=_optional_text(row.get("title_ko")),
            body_ko=str(row.get("body_ko") or ""),
            place_id=_optional_text(row.get("place_id")),
            metadata=_json_object(row.get("metadata")),
            similarity=float(row.get("similarity") or 0.0),
            embedding_model=_optional_text(row.get("embedding_model")),
            updated_at=_isoformat(row.get("updated_at")),
        )

    def to_public_dict(self) -> dict[str, Any]:
        return asdict(self)


def build_local_embedding(text: str, *, dimensions: int = VECTOR_DIMENSIONS) -> list[float]:
    if dimensions <= 0:
        raise ValueError("dimensions must be positive.")

    vector = [0.0] * dimensions
    features = list(_text_features(text))
    if not features:
        return vector

    for feature in features:
        digest = hashlib.blake2b(feature.encode("utf-8"), digest_size=16).digest()
        index = int.from_bytes(digest[:8], "big") % dimensions
        sign = 1.0 if digest[8] % 2 == 0 else -1.0
        weight = 1.0
        if feature.startswith("char:"):
            weight = 0.35
        elif feature.startswith("pair:"):
            weight = 0.65
        vector[index] += sign * weight

    norm = math.sqrt(sum(value * value for value in vector))
    if norm == 0:
        return vector
    return [round(value / norm, 8) for value in vector]


def build_embedding(text: str, *, method: EmbeddingMethod) -> tuple[list[float], str]:
    if method == "local-hash":
        return build_local_embedding(text), LOCAL_HASH_EMBEDDING_MODEL
    if method == "azure-openai":
        return build_azure_openai_embedding(text), _azure_embedding_model_name()
    raise ValueError(f"Unsupported embedding method: {method}")


def build_azure_openai_embedding(text: str) -> list[float]:
    settings = get_settings()
    missing = _missing_azure_embedding_settings(settings)
    if missing:
        raise RuntimeError("Azure OpenAI embedding config is missing: " + ", ".join(missing))
    if not settings.enable_live_ai:
        raise RuntimeError("Azure OpenAI embedding requires LALA_ENABLE_LIVE_AI=true.")

    try:
        from openai import AzureOpenAI
    except Exception as exc:
        raise RuntimeError("openai package is required for Azure OpenAI embeddings.") from exc

    client = AzureOpenAI(
        azure_endpoint=settings.azure_openai_endpoint,
        api_key=settings.azure_openai_key,
        api_version=settings.azure_openai_embedding_api_version or settings.azure_openai_api_version,
    )
    response = client.embeddings.create(
        model=settings.azure_openai_embedding_deployment,
        input=text,
    )
    embedding = list(response.data[0].embedding)
    if len(embedding) != VECTOR_DIMENSIONS:
        raise RuntimeError(
            f"Expected {VECTOR_DIMENSIONS} embedding dimensions, got {len(embedding)}."
        )
    return [float(value) for value in embedding]


def vector_to_pgvector(values: Iterable[float]) -> str:
    return "[" + ",".join(f"{float(value):.8f}" for value in values) + "]"


def fetch_candidate_chunks(
    *,
    dsn: str,
    source: SourceScope,
    limit: int,
    connect_timeout: int,
) -> list[KnowledgeChunk]:
    if not dsn:
        raise ValueError("DB_DSN is required.")
    if limit <= 0:
        raise ValueError("limit must be positive.")
    if source not in {"all", "static", "dynamic"}:
        raise ValueError(f"Unsupported source scope: {source}")

    chunks: list[KnowledgeChunk] = []
    if source in {"all", "static"}:
        chunks.extend(
            fetch_place_profile_chunks(
                dsn=dsn,
                limit=limit,
                connect_timeout=connect_timeout,
            )
        )
    if source in {"all", "dynamic"} and len(chunks) < limit:
        chunks.extend(
            fetch_dynamic_context_chunks(
                dsn=dsn,
                limit=max(limit - len(chunks), 1),
                connect_timeout=connect_timeout,
            )
        )
    return chunks[:limit]


def fetch_place_profile_chunks(
    *,
    dsn: str,
    limit: int,
    connect_timeout: int,
) -> list[KnowledgeChunk]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    sql = """
        WITH latest_scores AS (
            SELECT DISTINCT ON (place_id)
                place_id,
                local_spending_score,
                demand_dispersion_score,
                weather_fit_score,
                review_quality_score,
                culture_relevance_score,
                final_score,
                formula_version,
                features
            FROM analytics.place_score_snapshots
            ORDER BY place_id, scored_at DESC
        )
        SELECT
            p.place_id,
            p.name_ko,
            p.name_en,
            p.category,
            p.address_ko,
            p.address_en,
            p.region_name_ko,
            p.region_name_en,
            p.is_indoor,
            p.primary_source,
            p.source_record_id,
            s.local_spending_score,
            s.demand_dispersion_score,
            s.weather_fit_score,
            s.review_quality_score,
            s.culture_relevance_score,
            s.final_score,
            s.formula_version,
            s.features
        FROM travel.places p
        LEFT JOIN latest_scores s ON s.place_id = p.place_id
        ORDER BY p.updated_at DESC, p.place_id
        LIMIT %s
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, (limit,))
            return [_place_profile_chunk(dict(row)) for row in cur.fetchall()]


def fetch_dynamic_context_chunks(
    *,
    dsn: str,
    limit: int,
    connect_timeout: int,
) -> list[KnowledgeChunk]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    per_source_limit = max(1, limit)
    chunks: list[KnowledgeChunk] = []
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT
                    event_id,
                    title_ko,
                    title_en,
                    event_type,
                    venue_name_ko,
                    venue_place_id,
                    region_name_ko,
                    starts_on,
                    ends_on,
                    url,
                    primary_source,
                    source_record_id
                FROM culture.events
                ORDER BY updated_at DESC, event_id
                LIMIT %s
                """,
                (per_source_limit,),
            )
            chunks.extend(_culture_event_chunk(dict(row)) for row in cur.fetchall())

            cur.execute(
                """
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
                ORDER BY collected_at DESC, external_key
                LIMIT %s
                """,
                (per_source_limit,),
            )
            chunks.extend(_community_post_chunk(dict(row)) for row in cur.fetchall())

            cur.execute(
                """
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
                    attributes,
                    updated_at
                FROM community.place_mentions_weekly
                ORDER BY updated_at DESC, place_name_ko
                LIMIT %s
                """,
                (per_source_limit,),
            )
            chunks.extend(_place_mention_chunk(dict(row)) for row in cur.fetchall())

            cur.execute(
                """
                SELECT
                    location_name,
                    temperature_c,
                    precipitation_type,
                    pm10,
                    pm25,
                    is_rain_snow,
                    is_bad_dust,
                    is_heatwave,
                    is_coldwave,
                    is_strong_wind,
                    observed_at,
                    collected_at
                FROM travel.weather_observations
                ORDER BY observed_at DESC, location_name
                LIMIT %s
                """,
                (per_source_limit,),
            )
            chunks.extend(_weather_context_chunk(dict(row)) for row in cur.fetchall())

    return chunks[:limit]


def upsert_knowledge_chunks(
    *,
    dsn: str,
    chunks: Iterable[KnowledgeChunk],
    embedding_method: EmbeddingMethod,
    connect_timeout: int,
) -> int:
    import psycopg2
    from psycopg2.extras import Json

    chunk_list = list(chunks)
    if not chunk_list:
        return 0

    sql = """
        INSERT INTO rag.knowledge_chunks (
            source_type,
            source_id,
            source_table,
            place_id,
            title_ko,
            body_ko,
            body_en,
            metadata,
            embedding,
            embedding_model,
            embedding_method,
            content_sha256,
            last_embedded_at,
            updated_at
        )
        VALUES (
            %(source_type)s,
            %(source_id)s,
            %(source_table)s,
            %(place_id)s,
            %(title_ko)s,
            %(body_ko)s,
            %(body_en)s,
            %(metadata)s,
            %(embedding)s::vector,
            %(embedding_model)s,
            %(embedding_method)s,
            %(content_sha256)s,
            now(),
            now()
        )
        ON CONFLICT (source_type, source_id)
        DO UPDATE SET
            source_table = EXCLUDED.source_table,
            place_id = EXCLUDED.place_id,
            title_ko = EXCLUDED.title_ko,
            body_ko = EXCLUDED.body_ko,
            body_en = EXCLUDED.body_en,
            metadata = EXCLUDED.metadata,
            embedding = EXCLUDED.embedding,
            embedding_model = EXCLUDED.embedding_model,
            embedding_method = EXCLUDED.embedding_method,
            content_sha256 = EXCLUDED.content_sha256,
            last_embedded_at = EXCLUDED.last_embedded_at,
            updated_at = EXCLUDED.updated_at
    """
    rows = []
    for chunk in chunk_list:
        embedding, model_name = build_embedding(chunk.text_for_embedding, method=embedding_method)
        rows.append(
            {
                "source_type": chunk.source_type,
                "source_id": chunk.source_id,
                "source_table": chunk.source_table,
                "place_id": chunk.place_id,
                "title_ko": chunk.title_ko,
                "body_ko": chunk.body_ko,
                "body_en": chunk.body_en,
                "metadata": Json(_json_safe(chunk.metadata or {})),
                "embedding": vector_to_pgvector(embedding),
                "embedding_model": model_name,
                "embedding_method": embedding_method,
                "content_sha256": chunk.content_sha256,
            }
        )

    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            for row in rows:
                cur.execute(sql, row)
        conn.commit()
    return len(rows)


def query_knowledge_chunks(
    *,
    dsn: str,
    query: str,
    source: SourceScope,
    top_k: int,
    embedding_method: EmbeddingMethod,
    connect_timeout: int,
    place_id: str | None = None,
) -> list[RagSearchResult]:
    if not query.strip():
        raise ValueError("query is required.")
    if top_k <= 0:
        raise ValueError("top_k must be positive.")
    if source not in {"all", "static", "dynamic"}:
        raise ValueError(f"Unsupported source scope: {source}")

    import psycopg2
    from psycopg2.extras import RealDictCursor

    query_embedding, _ = build_embedding(query, method=embedding_method)
    query_vector = vector_to_pgvector(query_embedding)
    filters = ["embedding IS NOT NULL"]
    params: list[Any] = [query_vector]

    source_types = _source_types_for_scope(source)
    if source_types:
        placeholders = ", ".join(["%s"] * len(source_types))
        filters.append(f"source_type IN ({placeholders})")
        params.extend(source_types)
    if place_id:
        filters.append("place_id = %s")
        params.append(place_id)

    sql = f"""
        SELECT
            source_type,
            source_id,
            source_table,
            place_id,
            title_ko,
            body_ko,
            metadata,
            embedding_model,
            updated_at,
            1 - (embedding <=> %s::vector) AS similarity
        FROM rag.knowledge_chunks
        WHERE {" AND ".join(filters)}
        ORDER BY embedding <=> %s::vector
        LIMIT %s
    """
    params.extend([query_vector, top_k])

    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, params)
            return [RagSearchResult.from_row(dict(row)) for row in cur.fetchall()]


def _place_profile_chunk(row: dict[str, Any]) -> KnowledgeChunk:
    score_parts = [
        _score_phrase("최종 추천 점수", row.get("final_score")),
        _score_phrase("내국인 소비", row.get("local_spending_score")),
        _score_phrase("관광 수요 분산", row.get("demand_dispersion_score")),
        _score_phrase("날씨 적합도", row.get("weather_fit_score")),
        _score_phrase("리뷰 품질", row.get("review_quality_score")),
        _score_phrase("문화 연계", row.get("culture_relevance_score")),
    ]
    score_text = " ".join(part for part in score_parts if part)
    indoor_text = "실내" if row.get("is_indoor") is True else "야외" if row.get("is_indoor") is False else "실내외 미분류"
    body = _join_sentences(
        [
            f"장소명은 {row.get('name_ko')}입니다.",
            f"카테고리는 {row.get('category')}이고 지역은 {row.get('region_name_ko') or '미분류'}입니다.",
            f"주소는 {row.get('address_ko') or '주소 미상'}입니다.",
            f"날씨 필터 기준은 {indoor_text}입니다.",
            score_text,
            f"대표 원천은 {row.get('primary_source') or 'unknown'}입니다.",
        ]
    )
    metadata = {
        "category": row.get("category"),
        "name_en": row.get("name_en"),
        "address_en": row.get("address_en"),
        "region_name_ko": row.get("region_name_ko"),
        "region_name_en": row.get("region_name_en"),
        "is_indoor": row.get("is_indoor"),
        "primary_source": row.get("primary_source"),
        "source_record_id": row.get("source_record_id"),
        "score": {
            "final_score": _optional_float(row.get("final_score")),
            "formula_version": row.get("formula_version"),
            "components": {
                "local_spending_score": _optional_float(row.get("local_spending_score")),
                "demand_dispersion_score": _optional_float(row.get("demand_dispersion_score")),
                "weather_fit_score": _optional_float(row.get("weather_fit_score")),
                "review_quality_score": _optional_float(row.get("review_quality_score")),
                "culture_relevance_score": _optional_float(row.get("culture_relevance_score")),
            },
            "features": _json_safe(row.get("features") or {}),
        },
    }
    return KnowledgeChunk(
        source_type="place_profile",
        source_id=f"place:{row.get('place_id')}",
        source_table="travel.places",
        place_id=str(row.get("place_id")),
        title_ko=_optional_text(row.get("name_ko")),
        body_ko=body,
        body_en=_optional_text(row.get("name_en")),
        metadata=_json_object(metadata),
    )


def _culture_event_chunk(row: dict[str, Any]) -> KnowledgeChunk:
    period = _date_range_text(row.get("starts_on"), row.get("ends_on"))
    body = _join_sentences(
        [
            f"문화행사명은 {row.get('title_ko')}입니다.",
            f"유형은 {row.get('event_type') or '미분류'}입니다.",
            f"장소는 {row.get('venue_name_ko') or '장소 미상'}이고 지역은 {row.get('region_name_ko') or '미분류'}입니다.",
            f"기간은 {period}입니다.",
            f"대표 원천은 {row.get('primary_source') or 'unknown'}입니다.",
        ]
    )
    event_id = str(row.get("event_id"))
    return KnowledgeChunk(
        source_type="culture_event",
        source_id=f"event:{event_id}",
        source_table="culture.events",
        place_id=_optional_text(row.get("venue_place_id")),
        title_ko=_optional_text(row.get("title_ko")),
        body_ko=body,
        body_en=_optional_text(row.get("title_en")),
        metadata=_json_object(
            {
                "event_type": row.get("event_type"),
                "venue_name_ko": row.get("venue_name_ko"),
                "region_name_ko": row.get("region_name_ko"),
                "starts_on": _isoformat(row.get("starts_on")),
                "ends_on": _isoformat(row.get("ends_on")),
                "url": row.get("url"),
                "primary_source": row.get("primary_source"),
                "source_record_id": row.get("source_record_id"),
            }
        ),
    )


def _community_post_chunk(row: dict[str, Any]) -> KnowledgeChunk:
    title = _optional_text(row.get("title")) or _optional_text(row.get("keyword")) or "지역 커뮤니티 글"
    body_text = _optional_text(row.get("body")) or "본문 요약이 없습니다."
    body = _join_sentences(
        [
            f"지역 커뮤니티 글 제목은 {title}입니다.",
            f"본문 또는 요약은 {body_text}",
            f"키워드는 {row.get('keyword') or '미분류'}이고 지역은 {row.get('region_slug') or '미분류'}입니다.",
            f"공급자는 {row.get('provider') or 'unknown'}입니다.",
        ]
    )
    return KnowledgeChunk(
        source_type="community_post",
        source_id=f"post:{row.get('provider')}:{row.get('external_key')}",
        source_table="community.posts",
        title_ko=title,
        body_ko=body,
        metadata=_json_object(
            {
                "provider": row.get("provider"),
                "external_key": row.get("external_key"),
                "keyword": row.get("keyword"),
                "region_slug": row.get("region_slug"),
                "post_url": row.get("post_url"),
                "created_at_source": _isoformat(row.get("created_at_source")),
                "collected_at": _isoformat(row.get("collected_at")),
            }
        ),
    )


def _place_mention_chunk(row: dict[str, Any]) -> KnowledgeChunk:
    attributes = _json_object(row.get("attributes"))
    body = _join_sentences(
        [
            f"{row.get('place_name_ko')}의 주간 로컬 언급 신호입니다.",
            f"전체 언급은 {row.get('mention_count')}회, 광고 필터 후 유기적 언급은 {row.get('organic_mention_count') or '미집계'}회입니다.",
            f"감성 점수는 {row.get('sentiment_score') if row.get('sentiment_score') is not None else '미집계'}입니다.",
            f"속성 점수는 {_attributes_text(attributes)}입니다.",
            f"공급자는 {row.get('provider') or 'unknown'}입니다.",
        ]
    )
    return KnowledgeChunk(
        source_type="place_mention",
        source_id=f"mention:{row.get('id')}",
        source_table="community.place_mentions_weekly",
        place_id=_optional_text(row.get("place_id")),
        title_ko=_optional_text(row.get("place_name_ko")),
        body_ko=body,
        metadata=_json_object(
            {
                "week_start": _isoformat(row.get("week_start")),
                "provider": row.get("provider"),
                "category": row.get("category"),
                "mention_count": row.get("mention_count"),
                "organic_mention_count": row.get("organic_mention_count"),
                "sentiment_score": _optional_float(row.get("sentiment_score")),
                "attributes": attributes,
                "updated_at": _isoformat(row.get("updated_at")),
            }
        ),
    )


def _weather_context_chunk(row: dict[str, Any]) -> KnowledgeChunk:
    location = row.get("location_name") or "지역"
    observed_at = _isoformat(row.get("observed_at")) or "unknown"
    alerts = [
        label
        for key, label in (
            ("is_rain_snow", "비/눈"),
            ("is_bad_dust", "미세먼지 나쁨"),
            ("is_heatwave", "폭염"),
            ("is_coldwave", "한파"),
            ("is_strong_wind", "강풍"),
        )
        if row.get(key)
    ]
    body = _join_sentences(
        [
            f"{location}의 날씨 관측 맥락입니다.",
            f"기온은 {row.get('temperature_c') if row.get('temperature_c') is not None else '미상'}도입니다.",
            f"강수 유형은 {row.get('precipitation_type') or '없음/미상'}입니다.",
            f"PM10은 {row.get('pm10') if row.get('pm10') is not None else '미상'}, PM2.5는 {row.get('pm25') if row.get('pm25') is not None else '미상'}입니다.",
            f"주의 신호는 {', '.join(alerts) if alerts else '없음'}입니다.",
        ]
    )
    return KnowledgeChunk(
        source_type="weather_context",
        source_id=f"weather:{location}:{observed_at}",
        source_table="travel.weather_observations",
        title_ko=f"{location} 날씨",
        body_ko=body,
        metadata=_json_object(
            {
                "location_name": location,
                "observed_at": observed_at,
                "collected_at": _isoformat(row.get("collected_at")),
                "temperature_c": _optional_float(row.get("temperature_c")),
                "precipitation_type": row.get("precipitation_type"),
                "pm10": _optional_float(row.get("pm10")),
                "pm25": _optional_float(row.get("pm25")),
                "alerts": alerts,
            }
        ),
    )


def _source_types_for_scope(source: SourceScope) -> tuple[str, ...]:
    if source == "static":
        return STATIC_SOURCE_TYPES
    if source == "dynamic":
        return DYNAMIC_SOURCE_TYPES
    return ()


def _text_features(text: str) -> Iterable[str]:
    normalized = re.sub(r"\s+", " ", text.lower()).strip()
    for token in re.findall(r"[0-9a-z가-힣]+", normalized):
        if len(token) <= 1:
            continue
        yield f"token:{token}"
        if len(token) >= 3:
            for start in range(0, len(token) - 1):
                yield f"char:{token[start:start + 2]}"
        if len(token) >= 4:
            for start in range(0, len(token) - 2):
                yield f"pair:{token[start:start + 3]}"


def _missing_azure_embedding_settings(settings: Any) -> list[str]:
    missing: list[str] = []
    if not settings.azure_openai_endpoint:
        missing.append("AZURE_OPENAI_ENDPOINT")
    if not settings.azure_openai_key:
        missing.append("AZURE_OPENAI_KEY")
    if not settings.azure_openai_embedding_deployment:
        missing.append("AZURE_OPENAI_EMBEDDING_DEPLOYMENT")
    if not (settings.azure_openai_embedding_api_version or settings.azure_openai_api_version):
        missing.append("AZURE_OPENAI_EMBEDDING_API_VERSION")
    return missing


def _azure_embedding_model_name() -> str:
    settings = get_settings()
    return settings.azure_openai_embedding_deployment or "azure-openai-embedding"


def _join_sentences(parts: Iterable[str | None]) -> str:
    return " ".join(part.strip() for part in parts if part and part.strip())


def _score_phrase(label: str, value: Any) -> str:
    number = _optional_float(value)
    if number is None:
        return ""
    return f"{label}는 {number:.3f}입니다."


def _date_range_text(starts_on: Any, ends_on: Any) -> str:
    start = _isoformat(starts_on)
    end = _isoformat(ends_on)
    if start and end and start != end:
        return f"{start}부터 {end}까지"
    if start:
        return start
    if end:
        return end
    return "미정"


def _attributes_text(attributes: dict[str, Any]) -> str:
    if not attributes:
        return "미집계"
    items = [f"{key}={value}" for key, value in sorted(attributes.items())[:6]]
    return ", ".join(items)


def _optional_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _optional_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _isoformat(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    return str(value)


def _json_object(value: Any) -> dict[str, Any]:
    if not value:
        return {}
    if isinstance(value, dict):
        return _json_safe(value)
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return {"value": value}
        if isinstance(parsed, dict):
            return _json_safe(parsed)
        return {"value": _json_safe(parsed)}
    return {"value": _json_safe(value)}


def _json_safe(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    if isinstance(value, tuple):
        return [_json_safe(item) for item in value]
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    return value
