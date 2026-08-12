from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
import requests

from apps.api.app.core.errors import ServiceError
from apps.api.app.schemas.docent import DocentAudioRequest
from apps.api.app.services import speech_service


class FakeResponse:
    """Fake requests.Response for offline testing."""

    def __init__(self, status_code: int, content: bytes = b"fake audio") -> None:
        self.status_code = status_code
        self.content = content


def _make_audio_request(**overrides) -> DocentAudioRequest:
    defaults: dict[str, object] = {"script": "테스트 대본", "language": "ko"}
    defaults.update(overrides)
    return DocentAudioRequest(**defaults)


# ---------------------------------------------------------------------------
# _build_ssml: SSML structure, locale mapping, voice embedding, text escape
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "language", "voice", "expected_locale"),
    [
        ("안녕하세요", "ko", "ko-KR-SunHiNeural", "ko-KR"),
        ("Hello", "en", "en-US-JennyNeural", "en-US"),
        ("안녕", "ko", "custom-voice", "ko-KR"),
        ("Hi", "en", "another-voice", "en-US"),
    ],
)
def test_build_ssml_maps_language_to_locale(
    text: str, language: str, voice: str, expected_locale: str
) -> None:
    ssml = speech_service._build_ssml(text=text, language=language, voice=voice)

    assert f'xml:lang="{expected_locale}"' in ssml
    assert f'<voice name="{voice}">' in ssml
    assert "</voice>" in ssml
    assert "<speak" in ssml
    assert 'version="1.0"' in ssml
    assert 'xmlns="http://www.w3.org/2001/10/synthesis"' in ssml
    assert ssml.startswith("<speak")
    assert ssml.endswith("</speak>")


def test_build_ssml_escapes_html_injection_chars() -> None:
    # Text with dangerous HTML chars that could inject SSML markup
    dangerous = "Hello <script> & goodbye"
    ssml = speech_service._build_ssml(text=dangerous, language="en", voice="test")

    # Escaped form should appear
    assert "&lt;script&gt;" in ssml
    assert "&amp;" in ssml

    # Raw dangerous chars must NOT appear inside <voice> body
    voice_start = ssml.find("<voice")
    voice_end = ssml.find("</voice>")
    voice_body = ssml[voice_start:voice_end]

    assert "<script>" not in voice_body
    # Check that unescaped > and & don't appear after voice opening tag
    after_voice_tag = voice_body.split(">", 1)[1] if ">" in voice_body else voice_body
    assert "&" not in after_voice_tag.split("&lt;")[0]  # First & before &lt;


def test_build_ssml_strips_leading_trailing_whitespace() -> None:
    text = "  \t\n  테스트  \n\t  "
    ssml = speech_service._build_ssml(text=text, language="ko", voice="test")

    # Stripped text appears inside voice, not surrounding whitespace
    assert '<voice name="test">테스트</voice>' in ssml


def test_build_ssml_voice_name_embedded_correctly() -> None:
    ssml = speech_service._build_ssml(text="test", language="ko", voice="custom-voice-123")

    assert '<voice name="custom-voice-123">' in ssml
    assert "</voice>" in ssml  # Voice name only appears in opening tag


# ---------------------------------------------------------------------------
# _speech_tts_url: region vs endpoint URL construction
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("region", "endpoint", "expected_url"),
    [
        (
            "koreacentral",
            "https://custom.endpoint/",
            "https://koreacentral.tts.speech.microsoft.com/cognitiveservices/v1",
        ),
        (
            "eastus",
            "https://ignored.com",
            "https://eastus.tts.speech.microsoft.com/cognitiveservices/v1",
        ),
        (
            "",
            "https://custom.endpoint",
            "https://custom.endpoint/cognitiveservices/v1",
        ),
        (
            "",
            "https://custom.endpoint/",
            "https://custom.endpoint/cognitiveservices/v1",
        ),
        (
            "",
            "https://custom.endpoint////",
            "https://custom.endpoint/cognitiveservices/v1",
        ),
    ],
)
def test_speech_tts_url_prefers_region_over_endpoint(
    region: str, endpoint: str, expected_url: str
) -> None:
    url = speech_service._speech_tts_url(region, endpoint)
    assert url == expected_url


# ---------------------------------------------------------------------------
# live_speech_enabled: settings guard for live Azure Speech
# ---------------------------------------------------------------------------


def _stub_settings(
    monkeypatch: pytest.MonkeyPatch,
    *,
    enable_live_speech: bool = False,
    azure_speech_key: str | None = None,
    azure_speech_region: str | None = None,
    azure_speech_endpoint: str | None = None,
) -> None:
    monkeypatch.setattr(
        speech_service,
        "get_settings",
        lambda: SimpleNamespace(
            enable_live_speech=enable_live_speech,
            azure_speech_key=azure_speech_key,
            azure_speech_region=azure_speech_region,
            azure_speech_endpoint=azure_speech_endpoint,
        ),
    )


@pytest.mark.parametrize(
    (
        "enable_live_speech",
        "azure_speech_key",
        "azure_speech_region",
        "azure_speech_endpoint",
        "expected",
    ),
    [
        # All on → True
        (True, "key", "region", None, True),
        (True, "key", None, "endpoint", True),
        (True, "key", "region", "endpoint", True),
        # Flag off → False (even if key present)
        (False, "key", "region", None, False),
        (False, "key", None, "endpoint", False),
        # Key missing → False (even if flag on)
        (True, None, "region", None, False),
        (True, None, None, "endpoint", False),
        (True, None, "region", "endpoint", False),
        # Region-only → True (with flag and key)
        (True, "key", "region", None, True),
        # Endpoint-only → True (with flag and key)
        (True, "key", None, "endpoint", True),
        # Flag+key but neither region nor endpoint → False
        (True, "key", None, None, False),
        # Empty string treated as falsy
        (True, "", "region", None, False),
        (True, "key", "", None, False),
        (True, "key", None, "", False),
    ],
)
def test_live_speech_enabled_checks_all_required_settings(
    monkeypatch: pytest.MonkeyPatch,
    enable_live_speech: bool,
    azure_speech_key: str | None,
    azure_speech_region: str | None,
    azure_speech_endpoint: str | None,
    expected: bool,
) -> None:
    _stub_settings(
        monkeypatch,
        enable_live_speech=enable_live_speech,
        azure_speech_key=azure_speech_key,
        azure_speech_region=azure_speech_region,
        azure_speech_endpoint=azure_speech_endpoint,
    )

    assert speech_service.live_speech_enabled() is expected


# ---------------------------------------------------------------------------
# synthesize_docent_audio: offline branches (no live Azure call)
# ---------------------------------------------------------------------------


def _stub_requests_post(
    monkeypatch: pytest.MonkeyPatch,
    *,
    response: FakeResponse | None = None,
    raise_exception: type[Exception] | None = None,
) -> MagicMock:
    import requests as requests_module

    mock_post = MagicMock()
    if raise_exception:
        mock_post.side_effect = raise_exception("Network error")
    else:
        mock_post.return_value = response or FakeResponse(status_code=200)
    monkeypatch.setattr(requests_module, "post", mock_post)
    return mock_post


def test_synthesize_docent_audio_raises_503_when_live_speech_disabled(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_settings(
        monkeypatch,
        enable_live_speech=False,
        azure_speech_key=None,
        azure_speech_region=None,
    )
    request = _make_audio_request()

    with pytest.raises(ServiceError) as exc:
        speech_service.synthesize_docent_audio(request)

    assert exc.value.status_code == 503
    assert exc.value.code == "SPEECH_NOT_CONFIGURED"
    assert exc.value.retryable is False


def test_synthesize_docent_audio_raises_502_on_requests_exception(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_settings(
        monkeypatch,
        enable_live_speech=True,
        azure_speech_key="fake-key",
        azure_speech_region="region",
    )
    _stub_requests_post(monkeypatch, raise_exception=requests.RequestException)

    request = _make_audio_request()

    with pytest.raises(ServiceError) as exc:
        speech_service.synthesize_docent_audio(request)

    assert exc.value.status_code == 502
    assert exc.value.code == "SPEECH_SYNTHESIS_FAILED"
    assert exc.value.retryable is True


def test_synthesize_docent_audio_raises_502_on_http_error_response(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_settings(
        monkeypatch,
        enable_live_speech=True,
        azure_speech_key="fake-key",
        azure_speech_region="region",
    )
    _stub_requests_post(monkeypatch, response=FakeResponse(status_code=400))

    request = _make_audio_request()

    with pytest.raises(ServiceError) as exc:
        speech_service.synthesize_docent_audio(request)

    assert exc.value.status_code == 502
    assert exc.value.code == "SPEECH_SYNTHESIS_FAILED"
    assert exc.value.retryable is True


def test_synthesize_docent_audio_raises_502_on_empty_response_content(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_settings(
        monkeypatch,
        enable_live_speech=True,
        azure_speech_key="fake-key",
        azure_speech_region="region",
    )
    _stub_requests_post(monkeypatch, response=FakeResponse(status_code=200, content=b""))

    request = _make_audio_request()

    with pytest.raises(ServiceError) as exc:
        speech_service.synthesize_docent_audio(request)

    assert exc.value.status_code == 502
    assert exc.value.code == "SPEECH_EMPTY_RESPONSE"
    assert exc.value.retryable is True


def test_synthesize_docent_audio_returns_audio_content_on_success(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fake_audio = b"fake mp3 audio content"
    _stub_settings(
        monkeypatch,
        enable_live_speech=True,
        azure_speech_key="fake-key",
        azure_speech_region="region",
    )
    _stub_requests_post(monkeypatch, response=FakeResponse(status_code=200, content=fake_audio))

    request = _make_audio_request(script="테스트 대본", language="ko")

    result = speech_service.synthesize_docent_audio(request)

    assert result == fake_audio


def test_synthesize_docent_audio_posts_correct_url_and_headers(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_settings(
        monkeypatch,
        enable_live_speech=True,
        azure_speech_key="fake-key",
        azure_speech_region="koreacentral",
        azure_speech_endpoint=None,
    )
    mock_post = _stub_requests_post(
        monkeypatch, response=FakeResponse(status_code=200, content=b"audio")
    )

    request = _make_audio_request(script="Hello", language="en")

    speech_service.synthesize_docent_audio(request)

    # Verify requests.post was called
    assert mock_post.called is True
    call_args = mock_post.call_args

    # URL from _speech_tts_url
    url = call_args[1]["url"] if "url" in call_args[1] else call_args[0][0]
    assert url == "https://koreacentral.tts.speech.microsoft.com/cognitiveservices/v1"

    # Headers
    headers = call_args[1]["headers"]
    assert headers["Content-Type"] == "application/ssml+xml"
    assert headers["X-Microsoft-OutputFormat"] == "audio-16khz-128kbitrate-mono-mp3"
    assert headers["User-Agent"] == "lala-next-api"

    # Subscription key header is present (never assert its value)
    assert "Ocp-Apim-Subscription-Key" in headers


def test_synthesize_docent_audio_posts_correct_ssml_body(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_settings(
        monkeypatch,
        enable_live_speech=True,
        azure_speech_key="fake-key",
        azure_speech_region="region",
    )
    mock_post = _stub_requests_post(
        monkeypatch, response=FakeResponse(status_code=200, content=b"audio")
    )

    request = _make_audio_request(script="안녕하세요", language="ko")

    speech_service.synthesize_docent_audio(request)

    call_args = mock_post.call_args
    data = call_args[1]["data"]

    # Verify SSML structure
    ssml = data.decode("utf-8")
    assert "<speak" in ssml
    assert 'xml:lang="ko-KR"' in ssml
    assert '<voice name="ko-KR-SunHiNeural">' in ssml
    assert "안녕하세요" in ssml
    assert "</voice>" in ssml
    assert "</speak>" in ssml


def test_synthesize_docent_audio_uses_endpoint_when_region_missing(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    custom_endpoint = "https://custom.speech.endpoint/"
    _stub_settings(
        monkeypatch,
        enable_live_speech=True,
        azure_speech_key="fake-key",
        azure_speech_region=None,
        azure_speech_endpoint=custom_endpoint,
    )
    mock_post = _stub_requests_post(
        monkeypatch, response=FakeResponse(status_code=200, content=b"audio")
    )

    request = _make_audio_request()

    speech_service.synthesize_docent_audio(request)

    call_args = mock_post.call_args
    url = call_args[1]["url"] if "url" in call_args[1] else call_args[0][0]
    # Trailing slash stripped, /cognitiveservices/v1 appended
    assert url == "https://custom.speech.endpoint/cognitiveservices/v1"


def test_synthesize_docent_audio_selects_correct_voice_by_language(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_settings(
        monkeypatch,
        enable_live_speech=True,
        azure_speech_key="fake-key",
        azure_speech_region="region",
    )
    mock_post = _stub_requests_post(
        monkeypatch, response=FakeResponse(status_code=200, content=b"audio")
    )

    # Korean voice
    ko_request = _make_audio_request(script="안녕", language="ko")
    speech_service.synthesize_docent_audio(ko_request)

    ko_ssml = mock_post.call_args[1]["data"].decode("utf-8")
    assert "ko-KR-SunHiNeural" in ko_ssml

    # English voice
    en_request = _make_audio_request(script="Hello", language="en")
    speech_service.synthesize_docent_audio(en_request)

    en_ssml = mock_post.call_args[1]["data"].decode("utf-8")
    assert "en-US-JennyNeural" in en_ssml
