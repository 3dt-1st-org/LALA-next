from __future__ import annotations

from html import escape

import requests

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.schemas.docent import DocentAudioRequest

_OUTPUT_FORMAT = "audio-16khz-128kbitrate-mono-mp3"
_DEFAULT_VOICES = {
    "ko": "ko-KR-SunHiNeural",
    "en": "en-US-JennyNeural",
}


def live_speech_enabled() -> bool:
    settings = get_settings()
    return bool(
        settings.enable_live_speech
        and settings.azure_speech_key
        and (settings.azure_speech_region or settings.azure_speech_endpoint)
    )


def synthesize_docent_audio(request: DocentAudioRequest) -> bytes:
    if not live_speech_enabled():
        raise ServiceError(
            status_code=503,
            code="SPEECH_NOT_CONFIGURED",
            message="Azure Speech live synthesis is not enabled.",
            retryable=False,
        )

    settings = get_settings()
    voice = _DEFAULT_VOICES[request.language]
    ssml = _build_ssml(text=request.script, language=request.language, voice=voice)
    try:
        response = requests.post(
            _speech_tts_url(settings.azure_speech_region, settings.azure_speech_endpoint),
            headers={
                "Ocp-Apim-Subscription-Key": settings.azure_speech_key,
                "Content-Type": "application/ssml+xml",
                "X-Microsoft-OutputFormat": _OUTPUT_FORMAT,
                "User-Agent": "lala-next-api",
            },
            data=ssml.encode("utf-8"),
            timeout=20,
        )
    except requests.RequestException as exc:
        raise ServiceError(
            status_code=502,
            code="SPEECH_SYNTHESIS_FAILED",
            message="Azure Speech synthesis request failed.",
            retryable=True,
        ) from exc

    if response.status_code >= 400:
        raise ServiceError(
            status_code=502,
            code="SPEECH_SYNTHESIS_FAILED",
            message="Azure Speech synthesis returned an error.",
            retryable=True,
        )
    if not response.content:
        raise ServiceError(
            status_code=502,
            code="SPEECH_EMPTY_RESPONSE",
            message="Azure Speech returned an empty audio response.",
            retryable=True,
        )
    return response.content


def _build_ssml(*, text: str, language: str, voice: str) -> str:
    locale = "ko-KR" if language == "ko" else "en-US"
    escaped_text = escape(text.strip(), quote=False)
    return (
        f'<speak version="1.0" xml:lang="{locale}" '
        'xmlns="http://www.w3.org/2001/10/synthesis">'
        f'<voice name="{voice}">{escaped_text}</voice>'
        "</speak>"
    )


def _speech_tts_url(region: str, endpoint: str) -> str:
    if region:
        return f"https://{region}.tts.speech.microsoft.com/cognitiveservices/v1"
    return endpoint.rstrip("/") + "/cognitiveservices/v1"
