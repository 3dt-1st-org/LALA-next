from __future__ import annotations

from datetime import UTC, datetime
import hashlib
from typing import Any

from apps.api.app.core.errors import ServiceError
from apps.api.app.schemas.docent import DocentAudioRequest, DocentScriptRequest
from apps.api.app.services import ai_service, db_repository, speech_service
from apps.api.app.services.normalization import display_language, format_celsius_label
from apps.api.app.services.request_identity import generation_identity


def generate_script(request: DocentScriptRequest) -> dict:
    grounding_context = db_repository.fetch_docent_knowledge_context(
        place_id=request.place_id,
        limit=3,
    )
    identity = script_identity(request, grounding_context=grounding_context)
    has_score_context = _has_score_context(request)
    has_grounding_context = bool(grounding_context)
    has_request_context = _has_request_context(request)
    if not has_score_context and not has_grounding_context and not has_request_context:
        cached = db_repository.fetch_docent_script_cache(
            place_id=request.place_id,
            category=request.category,
            language=request.language,
            mode=request.mode,
        )
        if cached:
            return {**cached, **_grounding_meta([]), **identity}
        raise ServiceError(
            status_code=422,
            code="DOCENT_CONTEXT_REQUIRED",
            message=(
                "Docent script generation requires score context, "
                "location/source context, or RAG grounding."
            ),
            retryable=False,
        )

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
    grounding_context = grounding_context or []
    place_label = _grounded_place_label(
        request,
        grounding_context=grounding_context,
    ) or _readable_place_id(
        request.place_id,
        language=request.language,
    )
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
        weather_context = _ko_weather_sentence(request)
        grounding_sentence = _ko_grounding_sentence(grounding_context)
        place_subject = _ko_topic(place_label)
        if request.mode == "detail":
            return _join_script_parts(
                [
                    f"{place_subject} LALA가 현재 위치 주변에서 고른 {category_label}입니다.",
                    context,
                    score_context,
                    weather_context,
                    grounding_sentence,
                    category_context,
                    "방문 전 운영 시간과 날씨를 확인하고, 가까운 다음 장소까지 무리 없는 동선으로 이어가 보세요.",
                ]
            )
        return _join_script_parts(
            [
                f"{place_subject} 현재 위치와 공식 데이터를 함께 보고 고른 {category_label}입니다.",
                context,
                score_context,
                weather_context,
                grounding_sentence,
                category_context,
            ]
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
    weather_context = _en_weather_sentence(request)
    grounding_sentence = _en_grounding_sentence(grounding_context)
    if request.mode == "detail":
        return _join_script_parts(
            [
                f"{place_label} is a {request.category.replace('_', ' ')} recommended by LALA.",
                context,
                score_context,
                weather_context,
                grounding_sentence,
                category_context,
                "Before visiting, check opening hours and weather, then continue to the next nearby stop on foot where possible.",
            ]
        )
    return _join_script_parts(
        [
            f"{place_label} is a {language_label} LALA stop selected from official tourism, culture, and local spending signals.",
            context,
            score_context,
            weather_context,
            grounding_sentence,
            category_context,
        ]
    )


def _join_script_parts(parts: list[str]) -> str:
    return " ".join(part.strip() for part in parts if part and part.strip())


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


def _has_request_context(request: DocentScriptRequest) -> bool:
    return any(
        value is not None
        for value in (
            request.address,
            request.region_ko,
            request.region_en,
            request.distance_m,
            request.upstream_source,
        )
    )


def _has_weather_context(request: DocentScriptRequest) -> bool:
    return any(
        value is not None
        for value in (
            request.weather_temp,
            request.weather_outdoor_status,
            request.dust_grade,
            request.dust_pm10,
            request.dust_pm25,
            request.dust_pm10_grade,
            request.dust_pm25_grade,
        )
    )


def _grounded_place_label(
    request: DocentScriptRequest,
    *,
    grounding_context: list[dict[str, Any]],
) -> str | None:
    canonical = _canonical_grounding_title(grounding_context)
    if canonical:
        return canonical
    return request.place_name


def _canonical_grounding_title(grounding_context: list[dict[str, Any]]) -> str | None:
    for item in grounding_context:
        if str(item.get("source_type") or "").strip() != "place_profile":
            continue
        title = str(item.get("title_ko") or "").strip()
        if title:
            return title
    for item in grounding_context:
        title = str(item.get("title_ko") or "").strip()
        if title:
            return title
    return None


def _ko_score_sentence(request: DocentScriptRequest) -> str:
    highlights: list[str] = []
    if _score_at_least(request.local_spending_score, 0.6):
        highlights.append("실제 내국인 소비 흐름")
    if _score_at_least(request.small_merchant_fit_score, 0.6):
        highlights.append("소상공인 상권과의 연결성")
    if _score_at_least(request.demand_dispersion_score, 0.6):
        highlights.append("붐비는 관광지에만 몰리지 않는 관광 수요 분산 동선")
    if _score_at_least(request.weather_fit_score, 0.6):
        highlights.append("오늘 날씨와 무리 없는 이동성")
    if _score_at_least(request.culture_relevance_score, 0.6):
        highlights.append("문화 경험과 이어지는 맥락")
    if not highlights and request.final_score is not None:
        highlights.append("공식 데이터와 현재 위치 조건의 균형")
    if not highlights:
        return ""
    return f"LALA는 {_join_natural_ko(highlights)}을 함께 보고 이 장소를 고릅니다."


def _en_score_sentence(request: DocentScriptRequest) -> str:
    highlights: list[str] = []
    if _score_at_least(request.local_spending_score, 0.6):
        highlights.append("real domestic spending patterns")
    if _score_at_least(request.small_merchant_fit_score, 0.6):
        highlights.append("small local business fit")
    if _score_at_least(request.demand_dispersion_score, 0.6):
        highlights.append("a route that disperses demand beyond crowded spots")
    if _score_at_least(request.weather_fit_score, 0.6):
        highlights.append("weather-friendly movement")
    if _score_at_least(request.culture_relevance_score, 0.6):
        highlights.append("clear culture relevance")
    if not highlights and request.final_score is not None:
        highlights.append("a balanced match between official data and your location")
    if not highlights:
        return ""
    return f"LALA selected this stop by reading {_join_natural_en(highlights)} together."


def _ko_weather_sentence(request: DocentScriptRequest) -> str:
    parts: list[str] = []
    if temperature := format_celsius_label(request.weather_temp):
        parts.append(f"기온 {temperature}")
    dust_parts: list[str] = []
    if request.dust_pm10_grade and request.dust_pm10:
        dust_parts.append(f"미세먼지 {request.dust_pm10_grade}(PM10 {request.dust_pm10})")
    elif request.dust_pm10_grade:
        dust_parts.append(f"미세먼지 {request.dust_pm10_grade}")
    if request.dust_pm25_grade and request.dust_pm25:
        dust_parts.append(f"초미세먼지 {request.dust_pm25_grade}(PM2.5 {request.dust_pm25})")
    elif request.dust_pm25_grade:
        dust_parts.append(f"초미세먼지 {request.dust_pm25_grade}")
    if dust_parts:
        parts.append(" · ".join(dust_parts))
    elif request.dust_grade:
        parts.append(f"미세먼지 {request.dust_grade}")
    if not parts:
        return ""
    status = (
        "외부 활동에 무리가 적은 편입니다."
        if request.weather_outdoor_status == "good"
        else "날씨와 대기 상황을 보며 동선을 짧게 조정하는 편이 좋습니다."
    )
    return f"현재 날씨는 {', '.join(parts)}입니다. {status}"


def _en_weather_sentence(request: DocentScriptRequest) -> str:
    parts: list[str] = []
    if temperature := format_celsius_label(request.weather_temp):
        parts.append(temperature)
    dust_parts: list[str] = []
    if request.dust_pm10_grade and request.dust_pm10:
        dust_parts.append(f"PM10 {request.dust_pm10_grade} ({request.dust_pm10})")
    elif request.dust_pm10_grade:
        dust_parts.append(f"PM10 {request.dust_pm10_grade}")
    if request.dust_pm25_grade and request.dust_pm25:
        dust_parts.append(f"PM2.5 {request.dust_pm25_grade} ({request.dust_pm25})")
    elif request.dust_pm25_grade:
        dust_parts.append(f"PM2.5 {request.dust_pm25_grade}")
    if dust_parts:
        parts.append(" / ".join(dust_parts))
    elif request.dust_grade:
        parts.append(f"dust {request.dust_grade}")
    if not parts:
        return ""
    status = (
        "suitable for walking"
        if request.weather_outdoor_status == "good"
        else "better for a shorter route"
    )
    return f"Current weather is {', '.join(parts)}, so this stop is {status}."


def _score_at_least(value: float | None, threshold: float) -> bool:
    return value is not None and max(0.0, min(1.0, value)) >= threshold


def _join_natural_ko(items: list[str]) -> str:
    if len(items) <= 1:
        return "".join(items)
    return ", ".join(items[:-1]) + f", 그리고 {items[-1]}"


def _join_natural_en(items: list[str]) -> str:
    if len(items) <= 1:
        return "".join(items)
    return ", ".join(items[:-1]) + f", and {items[-1]}"


def _ko_topic(value: str) -> str:
    suffix = "은" if _has_final_consonant(value) else "는"
    return f"{value}{suffix}"


def _has_final_consonant(value: str) -> bool:
    for char in reversed(value.strip()):
        codepoint = ord(char)
        if 0xAC00 <= codepoint <= 0xD7A3:
            return (codepoint - 0xAC00) % 28 != 0
        if char.isalnum():
            return False
    return False


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
    return "공식 데이터와 장소 맥락에서는 " + " ".join(summaries)


def _en_grounding_sentence(grounding_context: list[dict[str, Any]]) -> str:
    summaries = _grounding_summaries(grounding_context, language="en")
    if not summaries:
        return ""
    return "Official place context notes " + " ".join(summaries)


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
        summary = _compact_grounding_text(body, language=language)
        if not summary:
            continue
        if title and title not in summary:
            summary = f"{title}: {summary}"
        summaries.append(summary)
    return summaries


def _compact_grounding_text(text: str, *, language: str) -> str:
    cleaned = _localize_internal_terms(" ".join(text.split()), language=language)
    cleaned = _remove_internal_grounding_fragments(cleaned, language=language)
    if not cleaned:
        return ""
    if len(cleaned) <= 120:
        return cleaned
    return cleaned[:117].rstrip() + "..."


def _remove_internal_grounding_fragments(text: str, *, language: str) -> str:
    banned_terms = (
        ("final score", "recommendation score", "score is", "weather filter")
        if language == "en"
        else ("최종 추천 점수", "추천 점수", "점수는", "날씨 필터 기준")
    )
    pieces = [piece.strip() for piece in text.split(".")]
    kept = [
        piece
        for piece in pieces
        if piece and not any(term in piece for term in banned_terms)
    ]
    if not kept:
        return ""
    return ". ".join(kept) + "."


def _localize_internal_terms(text: str, *, language: str) -> str:
    if language == "en":
        replacements = {
            "culture_venue": "culture venue",
            "attraction": "attraction",
            "restaurant": "restaurant",
            "event": "event",
            "tour_api": "Korea Tourism Organization data",
            "kcisa": "Korea Culture Information Service data",
            "kopis": "KOPIS performing arts data",
        }
    else:
        replacements = {
            "culture_venue": "문화공간",
            "attraction": "명소",
            "restaurant": "맛집",
            "event": "행사",
            "tour_api": "한국관광공사 데이터",
            "kcisa": "문화정보원 데이터",
            "kopis": "공연예술통합전산망 데이터",
        }
    for source, replacement in replacements.items():
        text = text.replace(source, replacement)
    return text


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
    return speech_service.synthesize_docent_audio(request)


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
    if _has_request_context(request) or _has_weather_context(request):
        payload.update(
            {
                "place_name": request.place_name,
                "address": request.address,
                "region_ko": request.region_ko,
                "region_en": request.region_en,
                "distance_m": request.distance_m,
                "source": request.source,
                "upstream_source": request.upstream_source,
                "weather_temp": request.weather_temp,
                "weather_outdoor_status": request.weather_outdoor_status,
                "dust_grade": request.dust_grade,
                "dust_pm10": request.dust_pm10,
                "dust_pm25": request.dust_pm25,
                "dust_pm10_grade": request.dust_pm10_grade,
                "dust_pm25_grade": request.dust_pm25_grade,
            }
        )
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
