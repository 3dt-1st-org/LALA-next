from __future__ import annotations

import json
import re
from collections import Counter
from contextlib import closing
from dataclasses import asdict, dataclass
from decimal import Decimal
from typing import Any, Sequence

SUPPORTED_CATEGORIES = {"all", "attraction", "restaurant", "event", "culture_venue"}
DEFAULT_QA_LIMIT = 40
MIN_QA_LIMIT = 30
MAX_QA_LIMIT = 50

RUBRIC_AREAS = {
    "factual_grounding": 20,
    "category_persona": 15,
    "local_value": 15,
    "weather_pm_context": 10,
    "route_usefulness": 10,
    "review_mention_quality": 10,
    "language_purity": 8,
    "tone_listenability": 7,
    "safety_presentation": 5,
}

BLOCKER_TERMS = (
    "mock",
    "demo",
    "placeholder",
    "skeleton",
    "public_mvp_snapshot",
    "local_fixture",
    "tour_api",
    "culture_venue",
)

QA_MODE_MATRIX = (
    ("ko", "brief"),
    ("ko", "detail"),
    ("en", "brief"),
)


@dataclass(frozen=True)
class DocentQACandidate:
    place_id: str
    name_ko: str
    name_en: str | None
    category: str
    region_name_ko: str | None
    primary_source: str | None
    is_indoor: bool | None
    has_image_url: bool
    final_score: float | None
    local_spending_score: float | None
    small_merchant_fit_score: float | None
    review_quality_score: float | None
    rag_chunk_count: int
    place_profile_chunk_count: int
    place_mention_chunk_count: int
    culture_event_chunk_count: int
    weather_context_chunk_count: int
    has_weather_observation: bool
    missing_signals: tuple[str, ...]

    @classmethod
    def from_row(cls, row: dict[str, Any]) -> "DocentQACandidate":
        features = _json_object(row.get("features"))
        missing_signals = features.get("missing_signals") or []
        if not isinstance(missing_signals, list):
            missing_signals = []
        return cls(
            place_id=str(row.get("place_id") or ""),
            name_ko=str(row.get("name_ko") or ""),
            name_en=_optional_text(row.get("name_en")),
            category=str(row.get("category") or ""),
            region_name_ko=_optional_text(row.get("region_name_ko")),
            primary_source=_optional_text(row.get("primary_source")),
            is_indoor=_optional_bool(row.get("is_indoor")),
            has_image_url=bool(_optional_text(row.get("image_url"))),
            final_score=_optional_float(row.get("final_score")),
            local_spending_score=_optional_float(row.get("local_spending_score")),
            small_merchant_fit_score=_optional_float(row.get("small_merchant_fit_score")),
            review_quality_score=_optional_float(row.get("review_quality_score")),
            rag_chunk_count=_optional_int(row.get("rag_chunk_count")) or 0,
            place_profile_chunk_count=_optional_int(row.get("place_profile_chunk_count")) or 0,
            place_mention_chunk_count=_optional_int(row.get("place_mention_chunk_count")) or 0,
            culture_event_chunk_count=_optional_int(row.get("culture_event_chunk_count")) or 0,
            weather_context_chunk_count=_optional_int(row.get("weather_context_chunk_count")) or 0,
            has_weather_observation=bool(row.get("has_weather_observation")),
            missing_signals=tuple(str(item) for item in missing_signals),
        )

    @property
    def region_bucket(self) -> str:
        region = self.region_name_ko or ""
        if region.endswith("구") or region in {"서울특별시", "서울시"}:
            return "seoul"
        if region.endswith("시") or region.endswith("군"):
            return "gyeonggi_or_local_city"
        return "unknown"

    @property
    def coverage_tags(self) -> tuple[str, ...]:
        tags = [self.region_bucket, self.category]
        tags.append("indoor" if self.is_indoor is True else "outdoor" if self.is_indoor is False else "indoor_unknown")
        tags.append("has_image" if self.has_image_url else "missing_image")
        tags.append("has_review_quality" if self.review_quality_score is not None else "missing_review_quality")
        tags.append("has_place_mention_rag" if self.place_mention_chunk_count > 0 else "missing_place_mention_rag")
        tags.append("has_weather" if self.has_weather_observation else "missing_weather")
        if self.local_spending_score is not None:
            tags.append("has_card_spending")
        if self.small_merchant_fit_score is not None:
            tags.append("has_small_merchant_signal")
        return tuple(tags)

    @property
    def qa_modes(self) -> tuple[dict[str, str], ...]:
        modes = []
        for language, mode in QA_MODE_MATRIX:
            if language == "en" and not self.name_en:
                continue
            modes.append({"language": language, "mode": mode})
        return tuple(modes)

    def selection_score(self) -> float:
        score = self.final_score or 0.0
        score += 0.10 if self.review_quality_score is not None else 0.0
        score += 0.08 if self.place_mention_chunk_count > 0 else 0.0
        score += 0.06 if self.has_weather_observation else 0.0
        score += 0.04 if self.has_image_url else 0.0
        score += min(self.rag_chunk_count, 4) * 0.015
        return score

    def to_public_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["coverage_tags"] = list(self.coverage_tags)
        payload["qa_modes"] = list(self.qa_modes)
        payload["selection_score"] = round(self.selection_score(), 4)
        payload["missing_signals"] = list(self.missing_signals)
        return payload


@dataclass(frozen=True)
class DocentQAPlan:
    candidates: tuple[DocentQACandidate, ...]
    coverage: dict[str, Any]
    rubric: dict[str, int]
    record_template: dict[str, str]

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "candidate_count": len(self.candidates),
            "candidates": [item.to_public_dict() for item in self.candidates],
            "coverage": self.coverage,
            "rubric": self.rubric,
            "record_template": self.record_template,
        }


def fetch_docent_qa_candidates(
    *,
    dsn: str,
    category: str,
    limit: int,
    connect_timeout: int,
) -> list[DocentQACandidate]:
    if category not in SUPPORTED_CATEGORIES:
        raise ValueError(f"Unsupported category: {category}")
    if limit <= 0:
        raise ValueError("limit must be positive.")

    import psycopg2
    from psycopg2.extras import RealDictCursor

    fetch_limit = max(limit * 8, 200)
    sql = """
        WITH latest_scores AS (
            SELECT DISTINCT ON (place_id)
                place_id,
                final_score,
                local_spending_score,
                small_merchant_fit_score,
                review_quality_score,
                features
            FROM analytics.place_score_snapshots
            ORDER BY place_id, scored_at DESC
        ),
        rag_counts AS (
            SELECT
                place_id,
                count(*) AS rag_chunk_count,
                count(*) FILTER (WHERE source_type = 'place_profile')
                    AS place_profile_chunk_count,
                count(*) FILTER (WHERE source_type = 'place_mention')
                    AS place_mention_chunk_count,
                count(*) FILTER (WHERE source_type = 'culture_event')
                    AS culture_event_chunk_count,
                count(*) FILTER (WHERE source_type = 'weather_context')
                    AS weather_context_chunk_count
            FROM rag.knowledge_chunks
            WHERE place_id IS NOT NULL
            GROUP BY place_id
        ),
        latest_weather_regions AS (
            SELECT DISTINCT location_name
            FROM travel.weather_observations
        )
        SELECT
            places.place_id,
            places.name_ko,
            places.name_en,
            places.category,
            places.region_name_ko,
            places.primary_source,
            places.is_indoor,
            places.image_url,
            latest_scores.final_score,
            latest_scores.local_spending_score,
            latest_scores.small_merchant_fit_score,
            latest_scores.review_quality_score,
            latest_scores.features,
            coalesce(rag_counts.rag_chunk_count, 0) AS rag_chunk_count,
            coalesce(rag_counts.place_profile_chunk_count, 0) AS place_profile_chunk_count,
            coalesce(rag_counts.place_mention_chunk_count, 0) AS place_mention_chunk_count,
            coalesce(rag_counts.culture_event_chunk_count, 0) AS culture_event_chunk_count,
            coalesce(rag_counts.weather_context_chunk_count, 0) AS weather_context_chunk_count,
            latest_weather_regions.location_name IS NOT NULL AS has_weather_observation
        FROM travel.places places
        LEFT JOIN latest_scores ON latest_scores.place_id = places.place_id
        LEFT JOIN rag_counts ON rag_counts.place_id = places.place_id
        LEFT JOIN latest_weather_regions
          ON latest_weather_regions.location_name = places.region_name_ko
        WHERE places.name_ko IS NOT NULL
          AND trim(places.name_ko) <> ''
          AND (%s = 'all' OR places.category = %s)
        ORDER BY
          coalesce(latest_scores.review_quality_score, 0) DESC,
          coalesce(rag_counts.place_mention_chunk_count, 0) DESC,
          coalesce(latest_scores.final_score, 0) DESC,
          places.region_name_ko,
          places.category,
          places.place_id
        LIMIT %s
    """
    with closing(psycopg2.connect(dsn, connect_timeout=connect_timeout)) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, (category, category, fetch_limit))
            rows = [dict(row) for row in cur.fetchall()]
    return select_docent_qa_candidates(
        [DocentQACandidate.from_row(row) for row in rows],
        limit=limit,
    )


def select_docent_qa_candidates(
    candidates: Sequence[DocentQACandidate],
    *,
    limit: int,
) -> list[DocentQACandidate]:
    if limit <= 0:
        raise ValueError("limit must be positive.")
    category_targets = _category_targets(limit)
    selected: list[DocentQACandidate] = []
    remaining = sorted(
        candidates,
        key=lambda item: (
            item.category,
            item.region_bucket,
            -item.selection_score(),
            item.place_id,
        ),
    )

    for category, target_count in category_targets.items():
        category_rows = [item for item in remaining if item.category == category]
        selected.extend(_balanced_take(category_rows, target_count))

    selected_ids = {item.place_id for item in selected}
    if len(selected) < limit:
        backfill = sorted(
            (item for item in candidates if item.place_id not in selected_ids),
            key=lambda item: (-item.selection_score(), item.region_bucket, item.category, item.place_id),
        )
        selected.extend(backfill[: max(0, limit - len(selected))])

    return selected[:limit]


def build_docent_qa_plan(candidates: Sequence[DocentQACandidate]) -> DocentQAPlan:
    selected = tuple(candidates)
    return DocentQAPlan(
        candidates=selected,
        coverage=_coverage(selected),
        rubric=dict(RUBRIC_AREAS),
        record_template={
            "qa_date": "",
            "reviewer": "",
            "place_id": "",
            "place_name": "",
            "category": "",
            "region": "",
            "language": "ko/en",
            "mode": "brief/detail",
            "grounding_count": "",
            "grounding_sources": "",
            "weather_context": "temp, PM10, PM2.5",
            "score_total": "0-100",
            "blocker": "yes/no",
            "legacy_parity": "stronger_than_legacy/legacy_equivalent/weaker_than_legacy/not_comparable",
            "issue_tags": "grounding,tone,weather,language,review_noise,route_action",
            "notes": "",
            "fix_owner": "",
            "retest_status": "pending/pass/fail",
        },
    )


def evaluate_docent_script(
    *,
    script: str,
    language: str,
    source: str,
    grounding_count: int,
    grounding_sources: Sequence[str],
    weather_context_expected: bool,
) -> dict[str, Any]:
    text = script.strip()
    lowered = text.lower()
    blockers: list[str] = []
    issue_tags: list[str] = []

    if not text or len(text) < 40:
        blockers.append("script_too_short")
    if any(term in lowered for term in BLOCKER_TERMS):
        blockers.append("internal_or_mock_wording")
    if re.search(r"(추천 점수|리뷰 품질|내국인 소비|문화 연계)(?:는|은|:)?\s*\d", text):
        blockers.append("raw_score_leak")
    if source in {"public_mvp_snapshot", "static_snapshot_fallback", "mock"}:
        blockers.append("fallback_source")
    if grounding_count < 1 or not grounding_sources:
        blockers.append("missing_grounding")
        issue_tags.append("grounding")
    if language == "ko" and _looks_bilingual_or_english_heavy(text):
        blockers.append("wrong_language")
        issue_tags.append("language")
    if weather_context_expected and not any(term in text for term in ("PM10", "PM2.5", "초미세먼지", "미세먼지")):
        issue_tags.append("weather")
    if not any(term in text for term in ("동선", "방문 전후", "이어", "continue to the next")):
        issue_tags.append("route_action")
    if not any(term in text for term in ("리뷰", "언급", "방문객", "로컬", "후기")):
        issue_tags.append("review_mention")

    score = 100
    score -= len(blockers) * 25
    score -= len(set(issue_tags)) * 5
    return {
        "score_total": max(0, score),
        "blocker": bool(blockers),
        "blockers": blockers,
        "issue_tags": sorted(set(issue_tags)),
    }


def _balanced_take(
    candidates: Sequence[DocentQACandidate],
    target_count: int,
) -> list[DocentQACandidate]:
    selected: list[DocentQACandidate] = []
    by_region = {
        "seoul": [item for item in candidates if item.region_bucket == "seoul"],
        "gyeonggi_or_local_city": [
            item for item in candidates if item.region_bucket == "gyeonggi_or_local_city"
        ],
        "unknown": [item for item in candidates if item.region_bucket == "unknown"],
    }
    while len(selected) < target_count:
        before = len(selected)
        for rows in by_region.values():
            if len(selected) >= target_count:
                break
            for item in sorted(rows, key=lambda row: (-row.selection_score(), row.place_id)):
                if item not in selected:
                    selected.append(item)
                    break
        if len(selected) == before:
            break
    return selected


def _category_targets(limit: int) -> dict[str, int]:
    base = {
        "attraction": 8,
        "culture_venue": 8,
        "restaurant": 8,
        "event": 6,
    }
    if limit <= sum(base.values()):
        scale = limit / sum(base.values())
        return {key: max(1, int(value * scale)) for key, value in base.items()}
    remaining = limit - sum(base.values())
    targets = dict(base)
    order = ("attraction", "culture_venue", "restaurant", "event")
    for index in range(remaining):
        targets[order[index % len(order)]] += 1
    return targets


def _coverage(candidates: Sequence[DocentQACandidate]) -> dict[str, Any]:
    category_counts = Counter(item.category for item in candidates)
    region_counts = Counter(item.region_bucket for item in candidates)
    tags = Counter(tag for item in candidates for tag in item.coverage_tags)
    qa_script_count = sum(len(item.qa_modes) for item in candidates)
    return {
        "category_counts": dict(sorted(category_counts.items())),
        "region_counts": dict(sorted(region_counts.items())),
        "tag_counts": dict(sorted(tags.items())),
        "candidate_count": len(candidates),
        "planned_script_count": qa_script_count,
        "passes_sample_size_target": MIN_QA_LIMIT <= len(candidates) <= MAX_QA_LIMIT,
        "has_seoul_and_gyeonggi": bool(region_counts.get("seoul"))
        and bool(region_counts.get("gyeonggi_or_local_city")),
        "has_review_rich_places": tags.get("has_review_quality", 0) >= 4
        or tags.get("has_place_mention_rag", 0) >= 10,
    }


def _looks_bilingual_or_english_heavy(text: str) -> bool:
    ascii_letters = len(re.findall(r"[A-Za-z]", text))
    hangul = len(re.findall(r"[가-힣]", text))
    if hangul == 0:
        return True
    return ascii_letters / max(1, hangul) > 0.30


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


def _optional_int(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _optional_bool(value: Any) -> bool | None:
    if value is None or isinstance(value, bool):
        return value
    if isinstance(value, (int, float, Decimal)):
        return bool(value)
    text = str(value).strip().lower()
    if text in {"true", "1", "yes", "y", "실내"}:
        return True
    if text in {"false", "0", "no", "n", "실외"}:
        return False
    return None


def _json_object(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        parsed = json.loads(value)
        return parsed if isinstance(parsed, dict) else {}
    return {}
