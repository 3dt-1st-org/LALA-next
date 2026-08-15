from __future__ import annotations

import re
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

# Markdown shapes that reach TTS-bound text (docent QA defect F2): emphasis
# markers, link syntax, headings, list bullets, and code fences would be read
# aloud literally by a speech synthesizer.
_MD_LINK_RE = re.compile(r"\[([^\]]+)\]\([^)]*\)")
_MD_HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s*", re.MULTILINE)
_MD_LIST_RE = re.compile(r"^\s{0,3}[-*+]\s+", re.MULTILINE)
_MD_ORDERED_LIST_RE = re.compile(r"^\s{0,3}\d+\.\s+", re.MULTILINE)
_MD_CODE_FENCE_RE = re.compile(r"^\s*(?:```|~~~).*?(?:```|~~~)\s*$", re.MULTILINE | re.DOTALL)
_MD_EMPHASIS_RES = (
    re.compile(r"\*\*\*(.+?)\*\*\*"),
    re.compile(r"___(.+?)___"),
    re.compile(r"\*\*(.+?)\*\*"),
    re.compile(r"__(.+?)__"),
    re.compile(r"\*(.+?)\*"),
    re.compile(r"(?<!\w)_(.+?)_(?!\w)"),
    re.compile(r"`([^`]+)`"),
)


def strip_markdown_for_tts(text: str) -> str:
    """Reduce markdown to plain spoken text for the TTS boundary.

    Deterministic, display-preserving counterpart: the caller keeps the
    original formatted script for the screen; only the synthesized voice
    input is stripped.
    """
    cleaned = text
    cleaned = _MD_CODE_FENCE_RE.sub("", cleaned)
    cleaned = _MD_LINK_RE.sub(r"\1", cleaned)
    cleaned = _MD_HEADING_RE.sub("", cleaned)
    cleaned = _MD_LIST_RE.sub("", cleaned)
    cleaned = _MD_ORDERED_LIST_RE.sub("", cleaned)
    for emphasis in _MD_EMPHASIS_RES:
        cleaned = emphasis.sub(r"\1", cleaned)
    # Collapse the whitespace left behind by removed block markers.
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


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
    # TTS reads markdown symbols aloud ("asterisk asterisk"); only the spoken
    # text is sanitized — the display script keeps its formatting.
    tts_text = strip_markdown_for_tts(request.script)
    ssml = _build_ssml(text=tts_text, language=request.language, voice=voice)
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
