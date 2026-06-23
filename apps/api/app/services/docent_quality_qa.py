from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass, replace
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Sequence


CATEGORY_ORDER = ("attraction", "restaurant", "event", "culture_venue")
CATEGORY_TARGETS_40 = {
    "attraction": 8,
    "restaurant": 8,
    "event": 6,
    "culture_venue": 8,
}
SCRIPT_SOURCE_BLOCKLIST = re.compile(
    r"(?:mock|demo|dummy|placeholder|fallback|sample|목데이터|데모|샘플|임시)",
    re.IGNORECASE,
)
RAW_SCORE_RE = re.compile(
    r"(?:final_score|local_spending_score|small_merchant_fit_score|"
    r"demand_dispersion_score|weather_fit_score|review_quality_score|"
    r"culture_relevance_score|\bscore\b|점수)\s*[:=]?\s*\d+(?:\.\d+)?",
    re.IGNORECASE,
)
SECRET_LIKE_RE = re.compile(
    r"(?:postgres(?:ql)?://|sk-[A-Za-z0-9]|Key Vault|vault\.azure\.net|"
    r"Bearer\s+[A-Za-z0-9._-]+)",
    re.IGNORECASE,
)
KO_SENTENCE_RE = re.compile(r"[.!?。]|[다요죠]\.")
HANGUL_RE = re.compile(r"[가-힣]")
LONG_ASCII_WORD_RE = re.compile(r"\b(?!PM10\b|PM2\.5\b|AI\b)[A-Za-z]{6,}\b")


@dataclass(frozen=True)
class DocentQaCandidate:
    place_id: str
    name_ko: str
    category: str
    region_name_ko: str | None = None
    province_code: str | None = None
    is_indoor: bool | None = None
    primary_source: str | None = None
    image_url: str | None = None
    final_score: float | None = None
    local_spending_score: float | None = None
    small_merchant_fit_score: float | None = None
    review_quality_score: float | None = None
    rag_chunk_count: int = 0
    dynamic_rag_chunk_count: int = 0
    review_mention_count: int | None = None
    review_organic_mention_count: int | None = None
    weather_pm10: float | None = None
    weather_pm25: float | None = None
    weather_temperature_c: float | None = None
    script: str | None = None
    script_source_method: str | None = None
    script_generated_at: str | None = None
    script_generation_error: str | None = None

    @classmethod
    def from_row(cls, row: dict[str, Any]) -> "DocentQaCandidate":
        return cls(
            place_id=_text(row.get("place_id")) or "",
            name_ko=_text(row.get("name_ko")) or "",
            category=_text(row.get("category")) or "",
            region_name_ko=_text(row.get("region_name_ko")),
            province_code=_text(row.get("province_code")),
            is_indoor=_bool(row.get("is_indoor")),
            primary_source=_text(row.get("primary_source")),
            image_url=_text(row.get("image_url")),
            final_score=_float(row.get("final_score")),
            local_spending_score=_float(row.get("local_spending_score")),
            small_merchant_fit_score=_float(row.get("small_merchant_fit_score")),
            review_quality_score=_float(row.get("review_quality_score")),
            rag_chunk_count=_int(row.get("rag_chunk_count")) or 0,
            dynamic_rag_chunk_count=_int(row.get("dynamic_rag_chunk_count")) or 0,
            review_mention_count=_int(row.get("review_mention_count")),
            review_organic_mention_count=_int(row.get("review_organic_mention_count")),
            weather_pm10=_float(row.get("weather_pm10")),
            weather_pm25=_float(row.get("weather_pm25")),
            weather_temperature_c=_float(row.get("weather_temperature_c")),
            script=_text(row.get("script")),
            script_source_method=_text(row.get("script_source_method")),
            script_generated_at=_datetime_text(row.get("script_generated_at")),
            script_generation_error=_text(row.get("script_generation_error")),
        )

    def to_public_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        if payload.get("script"):
            payload["script_excerpt"] = _script_excerpt(str(payload["script"]))
        payload.pop("script", None)
        return payload


@dataclass(frozen=True)
class DocentQualityCheck:
    auto_precheck_score: int | None
    blocker: bool
    issue_tags: list[str]
    rubric_scores: dict[str, int]
    legacy_parity: str = "not_reviewed"

    def to_public_dict(self) -> dict[str, Any]:
        return asdict(self)


def fetch_docent_qa_candidates(
    *,
    dsn: str,
    category: str,
    limit: int,
    language: str,
    mode: str,
    connect_timeout: int,
) -> list[DocentQaCandidate]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    per_category_limit = max(limit, 50)
    db_limit = per_category_limit * len(CATEGORY_ORDER)
    sql = """
        WITH latest_scores AS (
            SELECT DISTINCT ON (place_id)
                place_id,
                final_score,
                local_spending_score,
                small_merchant_fit_score,
                review_quality_score
            FROM analytics.place_score_snapshots
            ORDER BY place_id, scored_at DESC
        ),
        rag_counts AS (
            SELECT
                place_id,
                COUNT(*)::int AS rag_chunk_count,
                COUNT(*) FILTER (
                    WHERE source_type IN (
                        'culture_event',
                        'community_post',
                        'place_mention',
                        'weather_context'
                    )
                )::int AS dynamic_rag_chunk_count
            FROM rag.knowledge_chunks
            WHERE place_id IS NOT NULL
            GROUP BY place_id
        ),
        latest_mentions AS (
            SELECT DISTINCT ON (place_id)
                place_id,
                mention_count,
                organic_mention_count
            FROM community.place_mentions_weekly
            WHERE NULLIF(TRIM(place_id), '') IS NOT NULL
            ORDER BY place_id, week_start DESC, updated_at DESC
        ),
        latest_scripts AS (
            SELECT DISTINCT ON (place_id, category)
                place_id,
                category,
                script,
                source_method AS script_source_method,
                generated_at AS script_generated_at
            FROM travel.docent_scripts
            WHERE language = %s
              AND mode = %s
              AND (expires_at IS NULL OR expires_at > now())
            ORDER BY place_id, category, generated_at DESC
        ),
        latest_weather AS (
            SELECT DISTINCT ON (location_name)
                location_name,
                temperature_c,
                pm10,
                pm25
            FROM travel.weather_observations
            ORDER BY location_name, observed_at DESC, collected_at DESC
        ),
        ranked_candidates AS (
            SELECT
                places.place_id,
                places.name_ko,
                places.category,
                places.region_name_ko,
                places.province_code,
                places.is_indoor,
                places.primary_source,
                places.image_url,
                latest_scores.final_score,
                latest_scores.local_spending_score,
                latest_scores.small_merchant_fit_score,
                latest_scores.review_quality_score,
                COALESCE(rag_counts.rag_chunk_count, 0) AS rag_chunk_count,
                COALESCE(rag_counts.dynamic_rag_chunk_count, 0) AS dynamic_rag_chunk_count,
                latest_mentions.mention_count AS review_mention_count,
                latest_mentions.organic_mention_count AS review_organic_mention_count,
                latest_weather.temperature_c AS weather_temperature_c,
                latest_weather.pm10 AS weather_pm10,
                latest_weather.pm25 AS weather_pm25,
                latest_scripts.script,
                latest_scripts.script_source_method,
                latest_scripts.script_generated_at,
                ROW_NUMBER() OVER (
                    PARTITION BY places.category
                    ORDER BY
                        latest_scores.final_score DESC NULLS LAST,
                        COALESCE(rag_counts.rag_chunk_count, 0) DESC,
                        places.updated_at DESC,
                        places.place_id
                ) AS category_rank
            FROM travel.places places
            LEFT JOIN latest_scores ON latest_scores.place_id = places.place_id
            LEFT JOIN rag_counts ON rag_counts.place_id = places.place_id
            LEFT JOIN latest_mentions ON latest_mentions.place_id = places.place_id
            LEFT JOIN latest_weather ON latest_weather.location_name = places.region_name_ko
            LEFT JOIN latest_scripts
              ON latest_scripts.place_id = places.place_id
             AND latest_scripts.category = places.category
            WHERE (%s = 'all' OR places.category = %s)
        )
        SELECT *
        FROM ranked_candidates
        WHERE (%s <> 'all' OR category_rank <= %s)
        ORDER BY
            CASE category
                WHEN 'attraction' THEN 0
                WHEN 'restaurant' THEN 1
                WHEN 'event' THEN 2
                WHEN 'culture_venue' THEN 3
                ELSE 4
            END,
            region_name_ko,
            final_score DESC NULLS LAST,
            place_id
        LIMIT %s
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                sql,
                (
                    language,
                    mode,
                    category,
                    category,
                    category,
                    per_category_limit,
                    db_limit,
                ),
            )
            rows = [dict(row) for row in cur.fetchall()]
    return [DocentQaCandidate.from_row(row) for row in rows]


def select_representative_candidates(
    candidates: Sequence[DocentQaCandidate],
    *,
    limit: int,
) -> list[DocentQaCandidate]:
    if limit <= 0:
        return []
    unique: dict[str, DocentQaCandidate] = {}
    for candidate in candidates:
        if candidate.place_id and candidate.place_id not in unique:
            unique[candidate.place_id] = candidate
    pool = sorted(unique.values(), key=_candidate_sort_key)
    selected: list[DocentQaCandidate] = []
    selected_ids: set[str] = set()

    if limit >= 30:
        for category in CATEGORY_ORDER:
            desired = min(CATEGORY_TARGETS_40[category], limit - len(selected))
            if desired <= 0:
                break
            _take_candidates(
                selected=selected,
                selected_ids=selected_ids,
                candidates=[item for item in pool if item.category == category],
                count=desired,
            )

    remaining_by_category = {
        category: [
            item
            for item in pool
            if item.category == category and item.place_id not in selected_ids
        ]
        for category in CATEGORY_ORDER
    }
    while len(selected) < limit:
        added = False
        for category in CATEGORY_ORDER:
            while remaining_by_category[category]:
                candidate = remaining_by_category[category].pop(0)
                if candidate.place_id in selected_ids:
                    continue
                selected.append(candidate)
                selected_ids.add(candidate.place_id)
                added = True
                break
            if len(selected) >= limit:
                break
        if not added:
            break

    for candidate in pool:
        if len(selected) >= limit:
            break
        if candidate.place_id not in selected_ids:
            selected.append(candidate)
            selected_ids.add(candidate.place_id)
    return selected


def build_docent_qa_records(
    candidates: Sequence[DocentQaCandidate],
    *,
    language: str,
    mode: str,
    qa_date: str | None = None,
) -> list[dict[str, Any]]:
    qa_date = qa_date or datetime.now(UTC).date().isoformat()
    return [
        {
            "qa_date": qa_date,
            "reviewer": "",
            "place_id": candidate.place_id,
            "place_name": candidate.name_ko,
            "category": candidate.category,
            "region": candidate.region_name_ko,
            "language": language,
            "mode": mode,
            "grounding_count": candidate.rag_chunk_count,
            "grounding_sources": _grounding_sources(candidate),
            "weather_context": _weather_context(candidate),
            "script_source_method": candidate.script_source_method,
            "script_generated_at": candidate.script_generated_at,
            "script_generation_error": candidate.script_generation_error,
            "auto_precheck": evaluate_docent_script(candidate, language=language).to_public_dict(),
            "manual_score_total": None,
            "manual_blocker": None,
            "manual_issue_tags": [],
            "notes": "",
            "fix_owner": "",
            "retest_status": "pending",
            "legacy_parity": "not_reviewed",
            "sample_features": _sample_features(candidate),
            "script_excerpt": _script_excerpt(candidate.script),
        }
        for candidate in candidates
    ]


def generate_docent_scripts_for_qa(
    candidates: Sequence[DocentQaCandidate],
    *,
    language: str,
    mode: str,
) -> list[DocentQaCandidate]:
    from apps.api.app.core.errors import ServiceError
    from apps.api.app.schemas.docent import DocentScriptRequest
    from apps.api.app.services import docent_service

    hydrated: list[DocentQaCandidate] = []
    for candidate in candidates:
        if (candidate.script or "").strip():
            hydrated.append(candidate)
            continue
        request = DocentScriptRequest(
            place_id=candidate.place_id,
            place_name=candidate.name_ko,
            region_ko=candidate.region_name_ko,
            source="db",
            upstream_source=candidate.primary_source,
            final_score=candidate.final_score,
            local_spending_score=candidate.local_spending_score,
            small_merchant_fit_score=candidate.small_merchant_fit_score,
            weather_temp=_number_text(candidate.weather_temperature_c),
            weather_outdoor_status=_weather_outdoor_status(candidate),
            dust_pm10=_number_text(candidate.weather_pm10),
            dust_pm25=_number_text(candidate.weather_pm25),
            dust_pm10_grade=_pm_grade(candidate.weather_pm10, pollutant="pm10"),
            dust_pm25_grade=_pm_grade(candidate.weather_pm25, pollutant="pm25"),
            category=candidate.category,  # type: ignore[arg-type]
            language=language,
            mode=mode,
        )
        try:
            payload = docent_service.generate_script(request)
        except ServiceError as exc:
            hydrated.append(
                replace(
                    candidate,
                    script_generation_error=f"{exc.code}:{exc.message}",
                )
            )
            continue
        except Exception as exc:
            hydrated.append(
                replace(
                    candidate,
                    script_generation_error=exc.__class__.__name__,
                )
            )
            continue

        hydrated.append(
            replace(
                candidate,
                script=_text(payload.get("script")),
                script_source_method=_text(payload.get("source")),
                script_generated_at=_text(payload.get("generated_at")),
                script_generation_error=None,
            )
        )
    return hydrated


def evaluate_docent_script(
    candidate: DocentQaCandidate,
    *,
    language: str,
) -> DocentQualityCheck:
    script = (candidate.script or "").strip()
    if not script:
        return DocentQualityCheck(
            auto_precheck_score=None,
            blocker=False,
            issue_tags=["needs_script_generation"],
            rubric_scores={},
        )

    issue_tags: list[str] = []
    source = (candidate.script_source_method or "").strip()
    if SCRIPT_SOURCE_BLOCKLIST.search(script) or SCRIPT_SOURCE_BLOCKLIST.search(source):
        issue_tags.append("fallback_or_mock_wording")
    if RAW_SCORE_RE.search(script):
        issue_tags.append("raw_score_leakage")
    if SECRET_LIKE_RE.search(script):
        issue_tags.append("secret_like_text")
    if candidate.name_ko and candidate.name_ko not in script:
        issue_tags.append("missing_place_name")
    if _has_weather_values(candidate) and not _mentions_pm_context(script):
        issue_tags.append("missing_pm_context")
    if not _has_route_action(script, language):
        issue_tags.append("route_action_missing")
    if not _has_category_persona(script, candidate.category):
        issue_tags.append("category_persona_weak")
    if _has_review_evidence(candidate) and not _uses_review_context(script, candidate.category):
        issue_tags.append("review_context_missing")
    if candidate.rag_chunk_count <= 0:
        issue_tags.append("no_rag_chunks")
    if _language_purity_failed(script, language):
        issue_tags.append("language_purity")

    rubric_scores = {
        "factual_grounding": _score_factual_grounding(candidate, script),
        "category_persona": 15 if "category_persona_weak" not in issue_tags else 8,
        "local_value": 15 if _mentions_local_value(script) else 8,
        "weather_pm_context": 10 if "missing_pm_context" not in issue_tags else 3,
        "route_usefulness": 10 if "route_action_missing" not in issue_tags else 4,
        "review_mention_quality": _score_review_context(candidate, script),
        "language_purity": 8 if "language_purity" not in issue_tags else 2,
        "tone_listenability": _score_listenability(script),
        "safety_presentation": _score_safety(issue_tags),
    }
    score = sum(rubric_scores.values())
    blockers = {
        "fallback_or_mock_wording",
        "raw_score_leakage",
        "secret_like_text",
        "missing_place_name",
        "language_purity",
    }
    if _has_weather_values(candidate):
        blockers.add("missing_pm_context")
    return DocentQualityCheck(
        auto_precheck_score=score,
        blocker=any(tag in blockers for tag in issue_tags),
        issue_tags=issue_tags,
        rubric_scores=rubric_scores,
    )


def summarize_qa_records(records: Sequence[dict[str, Any]]) -> dict[str, Any]:
    scored = [
        int(record["auto_precheck"]["auto_precheck_score"])
        for record in records
        if record.get("auto_precheck", {}).get("auto_precheck_score") is not None
    ]
    blockers = [
        record
        for record in records
        if bool(record.get("auto_precheck", {}).get("blocker"))
    ]
    pending = [
        record
        for record in records
        if "needs_script_generation"
        in (record.get("auto_precheck", {}).get("issue_tags") or [])
    ]
    generation_errors = [
        record for record in records if record.get("script_generation_error")
    ]
    category_counts: dict[str, int] = {}
    category_scores: dict[str, list[int]] = {}
    for record in records:
        category = str(record.get("category") or "unknown")
        category_counts[category] = category_counts.get(category, 0) + 1
        score = record.get("auto_precheck", {}).get("auto_precheck_score")
        if score is not None:
            category_scores.setdefault(category, []).append(int(score))
    return {
        "record_count": len(records),
        "scored_count": len(scored),
        "pending_generation_count": len(pending),
        "generation_error_count": len(generation_errors),
        "blocker_count": len(blockers),
        "average_auto_precheck_score": round(sum(scored) / len(scored), 2)
        if scored
        else None,
        "category_counts": category_counts,
        "category_average_auto_precheck_score": {
            category: round(sum(values) / len(values), 2)
            for category, values in sorted(category_scores.items())
            if values
        },
        "issue_counts": _issue_counts(records),
    }


def write_local_qa_artifacts(
    *,
    records: Sequence[dict[str, Any]],
    output_dir: Path,
    label: str | None = None,
) -> dict[str, str]:
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    label = _safe_label(label or "docent-quality-qa")
    base = f"{label}-{timestamp}"
    summary = summarize_qa_records(records)
    payload = {
        "generated_at": timestamp,
        "summary": summary,
        "records": list(records),
    }
    json_path = output_dir / f"{base}.json"
    md_path = output_dir / f"{base}.md"
    json_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    md_path.write_text(_records_to_markdown(payload), encoding="utf-8")
    return {"json_path": str(json_path), "markdown_path": str(md_path)}


def _take_candidates(
    *,
    selected: list[DocentQaCandidate],
    selected_ids: set[str],
    candidates: Sequence[DocentQaCandidate],
    count: int,
) -> None:
    for candidate in candidates:
        if len([item for item in selected if item.category == candidate.category]) >= count:
            break
        if candidate.place_id in selected_ids:
            continue
        selected.append(candidate)
        selected_ids.add(candidate.place_id)


def _candidate_sort_key(candidate: DocentQaCandidate) -> tuple[Any, ...]:
    return (
        CATEGORY_ORDER.index(candidate.category)
        if candidate.category in CATEGORY_ORDER
        else len(CATEGORY_ORDER),
        candidate.region_name_ko or "",
        -1 if candidate.script else 0,
        -(candidate.final_score or 0.0),
        -candidate.rag_chunk_count,
        -int(candidate.review_organic_mention_count or 0),
        candidate.place_id,
    )


def _grounding_sources(candidate: DocentQaCandidate) -> list[str]:
    sources = ["travel.places"]
    if candidate.rag_chunk_count:
        sources.append("rag.knowledge_chunks")
    if candidate.review_organic_mention_count:
        sources.append("community.place_mentions_weekly")
    if _has_weather_values(candidate):
        sources.append("travel.weather_observations")
    if candidate.final_score is not None:
        sources.append("analytics.place_score_snapshots")
    return sources


def _weather_context(candidate: DocentQaCandidate) -> dict[str, float | None]:
    return {
        "temperature_c": candidate.weather_temperature_c,
        "pm10": candidate.weather_pm10,
        "pm25": candidate.weather_pm25,
    }


def _sample_features(candidate: DocentQaCandidate) -> dict[str, Any]:
    return {
        "primary_source": candidate.primary_source,
        "has_image": bool(candidate.image_url),
        "is_indoor": candidate.is_indoor,
        "final_score": candidate.final_score,
        "local_spending_score": candidate.local_spending_score,
        "small_merchant_fit_score": candidate.small_merchant_fit_score,
        "review_quality_score": candidate.review_quality_score,
        "review_organic_mention_count": candidate.review_organic_mention_count,
        "rag_chunk_count": candidate.rag_chunk_count,
        "dynamic_rag_chunk_count": candidate.dynamic_rag_chunk_count,
    }


def _score_factual_grounding(candidate: DocentQaCandidate, script: str) -> int:
    score = 8
    if candidate.name_ko and candidate.name_ko in script:
        score += 6
    if candidate.rag_chunk_count > 0:
        score += 4
    if candidate.dynamic_rag_chunk_count > 0:
        score += 2
    return min(score, 20)


def _score_review_context(candidate: DocentQaCandidate, script: str) -> int:
    if not _has_review_evidence(candidate):
        return 8
    return 10 if _uses_review_context(script, candidate.category) else 4


def _score_listenability(script: str) -> int:
    length = len(script)
    sentence_count = len([match for match in KO_SENTENCE_RE.finditer(script)])
    if 80 <= length <= 800 and sentence_count >= 2:
        return 7
    if 40 <= length <= 1000:
        return 5
    return 3


def _score_safety(issue_tags: Sequence[str]) -> int:
    penalty_tags = {
        "fallback_or_mock_wording",
        "raw_score_leakage",
        "secret_like_text",
    }
    return 0 if any(tag in penalty_tags for tag in issue_tags) else 5


def _has_weather_values(candidate: DocentQaCandidate) -> bool:
    return candidate.weather_pm10 is not None or candidate.weather_pm25 is not None


def _mentions_pm_context(script: str) -> bool:
    normalized = script.lower().replace(" ", "")
    return (
        "pm10" in normalized
        and ("pm2.5" in normalized or "pm25" in normalized)
    ) or ("미세먼지" in script and "초미세먼지" in script)


def _has_route_action(script: str, language: str) -> bool:
    if language == "en":
        return bool(re.search(r"\b(route|walk|course|before|after|nearby|stop by)\b", script, re.I))
    return any(token in script for token in ("동선", "코스", "이동", "산책", "들러", "가기 전", "나온 뒤", "근처"))


def _has_category_persona(script: str, category: str) -> bool:
    category_tokens = {
        "attraction": ("이야기", "역사", "공간", "산책", "풍경", "문화"),
        "culture_venue": ("전시", "작품", "공연", "문화", "관람", "공간"),
        "restaurant": ("맛", "메뉴", "식사", "서비스", "동네", "주문"),
        "event": ("행사", "축제", "일정", "프로그램", "현장", "동선"),
    }
    return any(token in script for token in category_tokens.get(category, ()))


def _has_review_evidence(candidate: DocentQaCandidate) -> bool:
    return (candidate.review_organic_mention_count or 0) >= 3 or (
        candidate.review_quality_score is not None
    )


def _uses_review_context(script: str, category: str) -> bool:
    if category == "restaurant":
        tokens = ("맛", "메뉴", "서비스", "분위기", "추천", "주문")
    elif category == "event":
        tokens = ("후기", "현장", "프로그램", "가족", "대기", "동선")
    else:
        tokens = ("후기", "분위기", "산책", "관람", "팁", "주변")
    return any(token in script for token in tokens)


def _mentions_local_value(script: str) -> bool:
    return any(
        token in script
        for token in (
            "지역",
            "동네",
            "상권",
            "소상공",
            "로컬",
            "골목",
            "분산",
            "주변",
        )
    )


def _language_purity_failed(script: str, language: str) -> bool:
    if language == "en":
        return bool(HANGUL_RE.search(script))
    ascii_words = [
        word
        for word in LONG_ASCII_WORD_RE.findall(script)
        if word.lower()
        not in {
            "airkorea",
            "kakao",
            "tourapi",
            "kcisa",
            "kopis",
        }
    ]
    return len(ascii_words) >= 3


def _issue_counts(records: Sequence[dict[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for record in records:
        for tag in record.get("auto_precheck", {}).get("issue_tags") or []:
            counts[str(tag)] = counts.get(str(tag), 0) + 1
    return dict(sorted(counts.items()))


def _records_to_markdown(payload: dict[str, Any]) -> str:
    summary = payload["summary"]
    lines = [
        "# LALA Docent Quality QA Seed",
        "",
        f"- Generated at: `{payload['generated_at']}`",
        f"- Records: `{summary['record_count']}`",
        f"- Scored: `{summary['scored_count']}`",
        f"- Pending generation: `{summary['pending_generation_count']}`",
        f"- Generation errors: `{summary['generation_error_count']}`",
        f"- Blockers: `{summary['blocker_count']}`",
        f"- Average auto precheck: `{summary['average_auto_precheck_score']}`",
        "",
        "## Category Counts",
        "",
    ]
    for category, count in summary["category_counts"].items():
        lines.append(f"- `{category}`: {count}")
    lines.extend(
        [
            "",
            "## QA Rows",
            "",
            "| Place | Category | Region | Score | Blocker | Issues | Retest |",
            "|---|---|---|---:|---|---|---|",
        ]
    )
    for record in payload["records"]:
        precheck = record["auto_precheck"]
        issues = ", ".join(precheck.get("issue_tags") or [])
        lines.append(
            "| {place} | `{category}` | {region} | {score} | {blocker} | {issues} | {retest} |".format(
                place=_md_cell(record.get("place_name")),
                category=_md_cell(record.get("category")),
                region=_md_cell(record.get("region")),
                score=precheck.get("auto_precheck_score"),
                blocker="yes" if precheck.get("blocker") else "no",
                issues=_md_cell(issues),
                retest=_md_cell(record.get("retest_status")),
            )
        )
    lines.append("")
    return "\n".join(lines)


def _script_excerpt(value: str | None, limit: int = 160) -> str:
    text = " ".join((value or "").split())
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "..."


def _number_text(value: float | None) -> str | None:
    if value is None:
        return None
    if float(value).is_integer():
        return str(int(value))
    return f"{value:.1f}".rstrip("0").rstrip(".")


def _pm_grade(value: float | None, *, pollutant: str) -> str | None:
    if value is None:
        return None
    thresholds = (30, 80, 150) if pollutant == "pm10" else (15, 35, 75)
    if value <= thresholds[0]:
        return "좋음"
    if value <= thresholds[1]:
        return "보통"
    if value <= thresholds[2]:
        return "나쁨"
    return "매우 나쁨"


def _weather_outdoor_status(candidate: DocentQaCandidate) -> str | None:
    values = [candidate.weather_pm10, candidate.weather_pm25]
    known = [value for value in values if value is not None]
    if not known:
        return None
    pm10_ok = candidate.weather_pm10 is None or candidate.weather_pm10 <= 80
    pm25_ok = candidate.weather_pm25 is None or candidate.weather_pm25 <= 35
    return "good" if pm10_ok and pm25_ok else "caution"


def _safe_label(value: str) -> str:
    cleaned = re.sub(r"[^0-9A-Za-z._-]+", "-", value.strip())
    return cleaned.strip("-") or "docent-quality-qa"


def _md_cell(value: Any) -> str:
    text = str(value or "").replace("|", "\\|")
    return text or "-"


def _text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _int(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _bool(value: Any) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    if text in {"true", "1", "yes", "y"}:
        return True
    if text in {"false", "0", "no", "n"}:
        return False
    return None


def _datetime_text(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.isoformat()
    text = str(value).strip()
    return text or None
