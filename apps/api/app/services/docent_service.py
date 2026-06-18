from __future__ import annotations

from datetime import UTC, datetime
import logging

from apps.api.app.core.observability import LOGGER_NAME
from apps.api.app.schemas.docent import DocentAudioRequest, DocentScriptRequest
from apps.api.app.services import ai_service, db_repository, speech_service
from apps.api.app.services.normalization import display_language
from apps.api.app.services.request_identity import generation_identity

logger = logging.getLogger(LOGGER_NAME)


def generate_script(request: DocentScriptRequest) -> dict:
    identity = script_identity(request)
    cached = db_repository.fetch_docent_script_cache(
        place_id=request.place_id,
        category=request.category,
        language=request.language,
        mode=request.mode,
    )
    if cached:
        return {**cached, **identity}

    generated_at = datetime.now(UTC).isoformat()
    if ai_service.live_ai_enabled():
        script = ai_service.generate_docent_script_text(request)
        source = "azure_openai"
    else:
        script = _fallback_script(request)
        source = "skeleton"
    ttl_sec = 604800
    if source == "azure_openai":
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
        **identity,
    }


def _fallback_script(request: DocentScriptRequest) -> str:
    place_label = request.place_name or _readable_place_id(
        request.place_id,
        language=request.language,
    )
    if request.language == "ko":
        mode_label = "자세한" if request.mode == "detail" else "짧은"
        category_label = {
            "attraction": "명소",
            "restaurant": "맛집",
            "event": "행사",
            "culture_venue": "문화공간",
        }.get(request.category, "장소")
        detail_sentence = (
            "방문 전 운영 시간과 동선을 확인하고, 주변 골목과 상권을 함께 걸어보세요."
            if request.mode == "detail"
            else "지도에서 가까운 장소와 함께 보면 지역의 분위기를 더 잘 느낄 수 있습니다."
        )
        return (
            f"{place_label} {category_label}에 대한 {mode_label} 도슨트입니다. "
            "공식 관광·문화 데이터와 지역 소비 신호를 바탕으로 로컬 맥락을 정리했습니다. "
            f"{detail_sentence}"
        )

    language_label = display_language(request.language)
    detail_sentence = (
        "Check opening hours and nearby walking routes before you go."
        if request.mode == "detail"
        else "Pair it with nearby places on the map to read the local rhythm more clearly."
    )
    return (
        f"A {request.mode} {language_label} docent note for "
        f"{place_label}. "
        "LALA connects official tourism and culture data with nearby local spending signals. "
        f"{detail_sentence}"
    )


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


def script_identity(request: DocentScriptRequest) -> dict[str, str]:
    return generation_identity(
        "docent_script",
        {
            "place_id": request.place_id,
            "category": request.category,
            "language": request.language,
            "mode": request.mode,
        },
    )


def audio_identity(request: DocentAudioRequest) -> dict[str, str]:
    return generation_identity(
        "docent_audio",
        {
            "script": request.script.strip(),
            "language": request.language,
        },
    )
