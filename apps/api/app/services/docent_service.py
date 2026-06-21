from __future__ import annotations

from datetime import UTC, datetime
import hashlib
import logging
from typing import Any

from apps.api.app.core.observability import LOGGER_NAME
from apps.api.app.schemas.docent import DocentAudioRequest, DocentScriptRequest
from apps.api.app.services import ai_service, db_repository, speech_service
from apps.api.app.services.normalization import display_language
from apps.api.app.services.request_identity import generation_identity

logger = logging.getLogger(LOGGER_NAME)


def generate_script(request: DocentScriptRequest) -> dict:
    grounding_context = db_repository.fetch_docent_knowledge_context(
        place_id=request.place_id,
        limit=3,
    )
    identity = script_identity(request, grounding_context=grounding_context)
    has_score_context = _has_score_context(request)
    has_grounding_context = bool(grounding_context)
    if not has_score_context and not has_grounding_context:
        cached = db_repository.fetch_docent_script_cache(
            place_id=request.place_id,
            category=request.category,
            language=request.language,
            mode=request.mode,
        )
        if cached:
            return {**cached, **_grounding_meta([]), **identity}

    generated_at = datetime.now(UTC).isoformat()
    if ai_service.live_ai_enabled():
        script = ai_service.generate_docent_script_text(
            request,
            grounding_context=grounding_context,
        )
        source = "azure_openai"
    else:
        script = _rule_based_script(request, grounding_context=grounding_context)
        source = "rule_based_curation"
    ttl_sec = 604800
    if source == "azure_openai" and not has_score_context and not has_grounding_context:
        cache_saved = db_repository.save_docent_script_cache(
            place_id=request.place_id,
            category=request.category,
            language=request.language,
            mode=request.mode,
            script=script,
            source=source,
            ttl_sec=ttl_sec,
        )
        if not cache_saved:
            logger.warning(
                (
                    "docent_script_write_failed place_id=%s category=%s "
                    "language=%s mode=%s source=%s"
                ),
                request.place_id,
                request.category,
                request.language,
                request.mode,
                source,
            )
    return {
        "place_id": request.place_id,
        "category": request.category,
        "language": request.language,
        "mode": request.mode,
        "script": script,
        "source": source,
        "generated_at": generated_at,
        "ttl_sec": ttl_sec,
        **_grounding_meta(grounding_context),
        **identity,
    }


def _rule_based_script(
    request: DocentScriptRequest,
    *,
    grounding_context: list[dict[str, Any]] | None = None,
) -> str:
    place_label = request.place_name or _readable_place_id(
        request.place_id,
        language=request.language,
    )
    grounding_context = grounding_context or []
    if request.language == "ko":
        category_label = {
            "attraction": "명소",
            "restaurant": "맛집",
            "event": "행사",
            "culture_venue": "문화공간",
        }.get(request.category, "장소")
        category_context = {
            "attraction": "주변 산책 동선과 생활권 상권을 함께 보면, 대표 명소가 지역 안에서 어떤 역할을 하는지 더 또렷해집니다.",
            "restaurant": "상호와 주변 소비 흐름을 함께 보며, 프랜차이즈보다 지역 식당의 개성과 골목의 분위기를 우선 살핍니다.",
            "event": "행사 자체뿐 아니라 방문 전후에 머무를 수 있는 근처 문화공간과 소상공인 상권까지 이어서 보는 코스입니다.",
            "culture_venue": "전시나 공연 관람 전후의 짧은 이동 반경 안에서 로컬 카페, 식당, 골목 경험을 함께 연결합니다.",
        }.get(
            request.category,
            "공식 데이터와 주변 장소를 함께 살펴볼 수 있는 로컬 경험입니다.",
        )
        context = _ko_context_sentence(request)
        score_context = _ko_score_sentence(request)
        grounding_sentence = _ko_grounding_sentence(grounding_context)
        if request.mode == "detail":
            return (
                f"{place_label}은 LALA가 현재 위치 주변에서 고른 {category_label}입니다. "
                f"{context} "
                f"{score_context} "
                f"{grounding_sentence} "
                f"{category_context} "
                "방문 전 운영 시간과 날씨를 확인하고, 가까운 다음 장소까지 무리 없는 동선으로 이어가 보세요."
            )
        return (
            f"{place_label}은 현재 위치와 공식 데이터를 함께 보고 고른 {category_label}입니다. "
            f"{context} "
            f"{score_context} "
            f"{grounding_sentence} "
            f"{category_context}"
        )

    language_label = display_language(request.language)
    category_context = {
        "attraction": "Read it together with nearby walking routes and small local businesses to understand its role in the neighborhood.",
        "restaurant": "LALA looks for local character and neighborhood spending signals instead of treating every food stop as a generic listing.",
        "event": "The route is designed to connect the event with nearby culture spaces and small local businesses before or after the visit.",
        "culture_venue": "Use it as an anchor for a short route that connects exhibitions, performances, cafes, restaurants, and nearby streets.",
    }.get(
        request.category, "LALA reads official data together with nearby local context."
    )
    context = _en_context_sentence(request)
    score_context = _en_score_sentence(request)
    grounding_sentence = _en_grounding_sentence(grounding_context)
    if request.mode == "detail":
        return (
            f"{place_label} is a {request.category.replace('_', ' ')} recommended by LALA. "
            f"{context} "
            f"{score_context} "
            f"{grounding_sentence} "
            f"{category_context} "
            "Before visiting, check opening hours and weather, then continue to the next nearby stop on foot where possible."
        )
    return (
        f"{place_label} is a {language_label} LALA stop selected from official tourism, culture, and local spending signals. "
        f"{context} "
        f"{score_context} "
        f"{grounding_sentence} "
        f"{category_context}"
    )


def _has_score_context(request: DocentScriptRequest) -> bool:
    return any(
        value is not None
        for value in (
            request.final_score,
            request.local_spending_score,
            request.small_merchant_fit_score,
            request.demand_dispersion_score,
            request.weather_fit_score,
            request.culture_relevance_score,
        )
    )


def _ko_score_sentence(request: DocentScriptRequest) -> str:
    parts: list[str] = []
    if request.final_score is not None:
        parts.append(f"종합 추천 점수 {_score_percent(request.final_score)}점")
    if request.local_spending_score is not None:
        parts.append(
            f"내국인 소비 신호 {_score_level_ko(request.local_spending_score)}"
        )
    if request.small_merchant_fit_score is not None:
        parts.append(
            f"소상공인 적합도 {_score_level_ko(request.small_merchant_fit_score)}"
        )
    if request.demand_dispersion_score is not None:
        parts.append(
            f"관광 수요 분산 효과 {_score_level_ko(request.demand_dispersion_score)}"
        )
    if request.weather_fit_score is not None:
        parts.append(f"날씨 적합도 {_score_level_ko(request.weather_fit_score)}")
    if request.culture_relevance_score is not None:
        parts.append(f"문화 연계성 {_score_level_ko(request.culture_relevance_score)}")
    if not parts:
        return ""
    return f"추천 근거는 {', '.join(parts)}입니다."


def _en_score_sentence(request: DocentScriptRequest) -> str:
    parts: list[str] = []
    if request.final_score is not None:
        parts.append(
            f"overall recommendation {_score_percent(request.final_score)}/100"
        )
    if request.local_spending_score is not None:
        parts.append(
            f"domestic spending signal {_score_level_en(request.local_spending_score)}"
        )
    if request.small_merchant_fit_score is not None:
        parts.append(
            f"small-merchant fit {_score_level_en(request.small_merchant_fit_score)}"
        )
    if request.demand_dispersion_score is not None:
        parts.append(
            f"demand-dispersion value {_score_level_en(request.demand_dispersion_score)}"
        )
    if request.weather_fit_score is not None:
        parts.append(f"weather fit {_score_level_en(request.weather_fit_score)}")
    if request.culture_relevance_score is not None:
        parts.append(
            f"culture relevance {_score_level_en(request.culture_relevance_score)}"
        )
    if not parts:
        return ""
    return f"The recommendation evidence includes {', '.join(parts)}."


def _score_percent(value: float) -> int:
    return round(max(0.0, min(1.0, value)) * 100)


def _score_level_ko(value: float) -> str:
    score = max(0.0, min(1.0, value))
    if score >= 0.8:
        return "강함"
    if score >= 0.6:
        return "보통 이상"
    return "보완 필요"


def _score_level_en(value: float) -> str:
    score = max(0.0, min(1.0, value))
    if score >= 0.8:
        return "strong"
    if score >= 0.6:
        return "moderate"
    return "needs support"


def _ko_context_sentence(request: DocentScriptRequest) -> str:
    parts: list[str] = []
    region = request.region_ko or request.address
    if region:
        parts.append(f"{region} 맥락")
    if request.distance_m is not None and request.distance_m > 0:
        parts.append(f"현재 위치에서 약 {_format_distance(request.distance_m)}")
    source = _ko_source_label(request.upstream_source or request.source)
    if source:
        parts.append(f"{source} 기반")
    if not parts:
        return "공식 관광·문화 데이터와 위치 기반 거리, 지역 소비 신호를 함께 살펴 방문 맥락을 정리했습니다."
    return f"{', '.join(parts)}으로 공식 관광·문화 데이터와 지역 소비 신호를 함께 해석했습니다."


def _en_context_sentence(request: DocentScriptRequest) -> str:
    parts: list[str] = []
    region = request.region_en or request.region_ko or request.address
    if region:
        parts.append(f"local context around {region}")
    if request.distance_m is not None and request.distance_m > 0:
        parts.append(
            f"about {_format_distance(request.distance_m)} from your current location"
        )
    source = _en_source_label(request.upstream_source or request.source)
    if source:
        parts.append(f"grounded in {source}")
    if not parts:
        return "The recommendation combines official tourism and culture data, location distance, and local spending signals."
    return (
        f"It reads {', '.join(parts)} together with local spending and route signals."
    )


def _ko_grounding_sentence(grounding_context: list[dict[str, Any]]) -> str:
    summaries = _grounding_summaries(grounding_context, language="ko")
    if not summaries:
        return ""
    return (
        "장소 지식 인덱스에서는 " + " ".join(summaries) + " 맥락을 함께 확인했습니다."
    )


def _en_grounding_sentence(grounding_context: list[dict[str, Any]]) -> str:
    summaries = _grounding_summaries(grounding_context, language="en")
    if not summaries:
        return ""
    return "LALA's place context notes " + " ".join(summaries)


def _grounding_summaries(
    grounding_context: list[dict[str, Any]],
    *,
    language: str,
) -> list[str]:
    summaries: list[str] = []
    for item in grounding_context[:2]:
        body_key = "body_en" if language == "en" else "body_ko"
        body = str(item.get(body_key) or item.get("body_ko") or "").strip()
        title = str(item.get("title_ko") or "").strip()
        summary = _compact_grounding_text(body)
        if not summary:
            continue
        if title and title not in summary:
            summary = f"{title}: {summary}"
        summaries.append(summary)
    return summaries


def _compact_grounding_text(text: str) -> str:
    cleaned = " ".join(text.split())
    if not cleaned:
        return ""
    if len(cleaned) <= 120:
        return cleaned
    return cleaned[:117].rstrip() + "..."


def _format_distance(distance_m: int) -> str:
    if distance_m >= 1000:
        return f"{distance_m / 1000:.1f}km"
    return f"{distance_m}m"


def _ko_source_label(source: str | None) -> str | None:
    return {
        "tour_api": "한국관광공사 데이터",
        "kcisa": "문화정보원 데이터",
        "kopis": "공연예술통합전산망 데이터",
        "db": "운영 DB",
        "public_mvp_snapshot": "공식 스냅샷",
    }.get((source or "").strip())


def _en_source_label(source: str | None) -> str | None:
    return {
        "tour_api": "Korea Tourism Organization data",
        "kcisa": "Korea Culture Information Service data",
        "kopis": "KOPIS performing arts data",
        "db": "the live LALA database",
        "public_mvp_snapshot": "official snapshot data",
    }.get((source or "").strip())


def _readable_place_id(place_id: str, *, language: str) -> str:
    value = place_id.strip()
    if value.startswith("tour-api-"):
        return "이 장소" if language == "ko" else "this place"
    normalized = value.replace("_", "-")
    parts = [part for part in normalized.split("-") if part and not part.isdigit()]
    fallback = "이 장소" if language == "ko" else "this place"
    return " ".join(parts) or fallback


def generate_audio(request: DocentAudioRequest) -> bytes:
    script = request.script.strip()
    if speech_service.live_speech_enabled():
        return speech_service.synthesize_docent_audio(request)
    header = b"ID3\x04\x00\x00\x00\x00\x00!"
    body = f"LALA docent audio: {request.language}: {script[:128]}".encode("utf-8")
    return header + body


def script_identity(
    request: DocentScriptRequest,
    *,
    grounding_context: list[dict[str, Any]] | None = None,
) -> dict[str, str]:
    payload: dict[str, object] = {
        "place_id": request.place_id,
        "category": request.category,
        "language": request.language,
        "mode": request.mode,
    }
    if _has_score_context(request):
        payload.update(
            {
                "final_score": request.final_score,
                "local_spending_score": request.local_spending_score,
                "small_merchant_fit_score": request.small_merchant_fit_score,
                "demand_dispersion_score": request.demand_dispersion_score,
                "weather_fit_score": request.weather_fit_score,
                "culture_relevance_score": request.culture_relevance_score,
            }
        )
    if grounding_context:
        payload["grounding_hash"] = _grounding_hash(grounding_context)
    return generation_identity("docent_script", payload)


def audio_identity(request: DocentAudioRequest) -> dict[str, str]:
    return generation_identity(
        "docent_audio",
        {
            "script": request.script.strip(),
            "language": request.language,
        },
    )


def _grounding_meta(grounding_context: list[dict[str, Any]]) -> dict[str, object]:
    return {
        "grounding_count": len(grounding_context),
        "grounding_sources": [
            source
            for source in dict.fromkeys(
                str(item.get("source_type") or "").strip()
                for item in grounding_context
                if str(item.get("source_type") or "").strip()
            )
        ],
    }


def _grounding_hash(grounding_context: list[dict[str, Any]]) -> str:
    parts = [
        "|".join(
            [
                str(item.get("source_type") or ""),
                str(item.get("source_id") or ""),
                str(item.get("content_sha256") or ""),
            ]
        )
        for item in grounding_context
    ]
    return hashlib.sha256("\n".join(parts).encode("utf-8")).hexdigest()
