from __future__ import annotations

import sys
import types
from types import SimpleNamespace

import pytest

from apps.api.app.core.errors import ServiceError
from apps.api.app.schemas.docent import DocentScriptRequest
from apps.api.app.services import ai_service


def test_docent_system_prompt_uses_space_curator_for_official_attraction_context():
    request = DocentScriptRequest(
        place_id="official-attraction",
        place_name="호암미술관",
        category="attraction",
        language="ko",
        mode="brief",
    )

    prompt = ai_service._docent_system_prompt(
        request,
        place_name="호암미술관",
        grounding_context=[
            {
                "source_type": "place_profile",
                "body_ko": "장소명은 호암미술관입니다. 대표 원천은 tour_api입니다.",
            }
        ],
    )

    assert "공간 큐레이터" in prompt
    assert "식당/카페 리뷰처럼 쓰지 마세요" in prompt
    assert "없는 사실을 지어내지 마세요" in prompt
    assert "LALA AI Guide" not in prompt


def test_docent_system_prompt_uses_chief_docent_for_visitor_attraction_context():
    request = DocentScriptRequest(
        place_id="reviewed-attraction",
        place_name="화성행궁",
        category="culture_venue",
        language="ko",
        mode="detail",
    )

    prompt = ai_service._docent_system_prompt(
        request,
        place_name="화성행궁",
        grounding_context=[
            {
                "source_type": "place_mention",
                "body_ko": "방문객 리뷰에서는 야간 산책 동선과 역사 분위기를 좋아한다고 언급됩니다.",
            }
        ],
    )

    assert "LALA'의 활기차고 센스 있는 수석 도슨트" in prompt
    assert "방문객의 목소리" in prompt
    assert "이어폰으로 듣는 상황" in prompt
    assert "식당/카페 리뷰처럼 쓰지 마세요" in prompt


def test_docent_system_prompt_keeps_restaurant_food_review_context():
    request = DocentScriptRequest(
        place_id="restaurant-food-review",
        place_name="김고집숯불갈비",
        category="restaurant",
        language="ko",
        mode="brief",
    )

    prompt = ai_service._docent_system_prompt(
        request,
        place_name="김고집숯불갈비",
        grounding_context=[
            {
                "source_type": "place_mention",
                "body_ko": "리뷰에서는 고기 맛과 반찬 구성이 좋은 로컬 맛집으로 언급됩니다.",
            }
        ],
    )

    assert "LALA AI Guide" in prompt
    assert "분위기와 메뉴 특성" in prompt
    assert "리뷰 인사이트" in prompt
    assert "식당/카페 리뷰처럼 쓰지 마세요" not in prompt


def test_grounding_prompt_uses_verified_place_context_label():
    prompt = ai_service._grounding_context_prompt(
        [
            {
                "source_type": "place_profile",
                "title_ko": "호암미술관",
                "body_ko": "장소명은 호암미술관입니다. 대표 원천은 tour_api입니다.",
            }
        ]
    )

    assert "LALA verified place context" in prompt
    assert "RAG knowledge index" not in prompt


def test_generate_docent_script_uses_short_timeout_without_sdk_retries(monkeypatch):
    captured: dict[str, object] = {}

    class FakeCompletions:
        def create(self, **kwargs):
            captured["completion"] = kwargs
            return SimpleNamespace(
                choices=[
                    SimpleNamespace(message=SimpleNamespace(content="검증된 도슨트 문장입니다."))
                ]
            )

    class FakeOpenAI:
        def __init__(self, **kwargs):
            captured["client"] = kwargs
            self.chat = SimpleNamespace(completions=FakeCompletions())

    fake_openai = types.ModuleType("openai")
    fake_openai.OpenAI = FakeOpenAI
    monkeypatch.setitem(sys.modules, "openai", fake_openai)
    monkeypatch.setattr(
        ai_service,
        "get_settings",
        lambda: SimpleNamespace(
            enable_live_ai=True,
            openai_api_key="test-openai-key",  # pragma: allowlist secret
            openai_base_url="https://api.openai.com/v1",
            openai_docent_model="gpt-5.4-mini",
        ),
    )

    request = DocentScriptRequest(
        place_id="place-1",
        place_name="화성행궁",
        category="attraction",
        language="ko",
        mode="brief",
    )

    text = ai_service.generate_docent_script_text(request)

    assert text == "검증된 도슨트 문장입니다."
    assert captured["client"]["timeout"] == ai_service.DOCENT_AI_TIMEOUT_SECONDS
    assert captured["client"]["max_retries"] == 0
    assert captured["completion"]["model"] == "gpt-5.4-mini"
    assert captured["client"]["base_url"] == "https://api.openai.com/v1"


def test_generate_docent_script_prefers_docent_specific_model(monkeypatch):
    captured: dict[str, object] = {}

    class FakeCompletions:
        def create(self, **kwargs):
            captured["completion"] = kwargs
            return SimpleNamespace(
                choices=[SimpleNamespace(message=SimpleNamespace(content="도슨트 스크립트"))]
            )

    class FakeOpenAI:
        def __init__(self, **kwargs):
            self.chat = SimpleNamespace(completions=FakeCompletions())

    fake_openai = types.ModuleType("openai")
    fake_openai.OpenAI = FakeOpenAI
    monkeypatch.setitem(sys.modules, "openai", fake_openai)
    monkeypatch.setattr(
        ai_service,
        "get_settings",
        lambda: SimpleNamespace(
            enable_live_ai=True,
            openai_api_key="test-openai-key",  # pragma: allowlist secret
            openai_base_url="https://api.openai.com/v1",
            openai_docent_model="docent-mini-model",
        ),
    )

    request = DocentScriptRequest(
        place_id="place-1",
        place_name="화성행궁",
        category="attraction",
        language="ko",
        mode="brief",
    )

    ai_service.generate_docent_script_text(request)

    assert captured["completion"]["model"] == "docent-mini-model"


def test_rerank_ai_enabled_resolves_docent_qa_role(monkeypatch):
    """rerank_ai_enabled resolves docent_qa role with valid configuration."""
    monkeypatch.setattr(
        ai_service,
        "get_settings",
        lambda: SimpleNamespace(
            enable_live_ai=True,
            openai_api_key="test-openai-key",  # pragma: allowlist secret
            openai_base_url="https://api.openai.com/v1",
            openai_docent_model="gpt-5.4-mini",
        ),
    )

    assert ai_service.rerank_ai_enabled() is True


def test_rerank_ai_enabled_requires_explicit_flag(monkeypatch):
    """rerank_ai_enabled requires enable_live_ai flag."""
    monkeypatch.setattr(
        ai_service,
        "get_settings",
        lambda: SimpleNamespace(
            enable_live_ai=False,
            openai_api_key="test-openai-key",  # pragma: allowlist secret
            openai_base_url="https://api.openai.com/v1",
            openai_docent_model="gpt-5.4-mini",
        ),
    )

    assert ai_service.rerank_ai_enabled() is False


def test_rerank_ai_enabled_requires_api_key(monkeypatch):
    """rerank_ai_enabled requires OpenAI API key."""
    monkeypatch.setattr(
        ai_service,
        "get_settings",
        lambda: SimpleNamespace(
            enable_live_ai=True,
            openai_api_key="",  # Empty key
            openai_base_url="https://api.openai.com/v1",
            openai_docent_model="gpt-5.4-mini",
        ),
    )

    assert ai_service.rerank_ai_enabled() is False


def test_rerank_ai_enabled_rejects_azure_openai_host(monkeypatch):
    """rerank_ai_enabled rejects Azure OpenAI base URLs."""
    monkeypatch.setattr(
        ai_service,
        "get_settings",
        lambda: SimpleNamespace(
            enable_live_ai=True,
            openai_api_key="test-openai-key",  # pragma: allowlist secret
            openai_base_url="https://test.openai.azure.com/v1",
            openai_docent_model="gpt-5.4-mini",
        ),
    )

    assert ai_service.rerank_ai_enabled() is False


def test_rerank_ai_enabled_rejects_invalid_base_url(monkeypatch):
    """rerank_ai_enabled rejects invalid base URL."""
    monkeypatch.setattr(
        ai_service,
        "get_settings",
        lambda: SimpleNamespace(
            enable_live_ai=True,
            openai_api_key="test-openai-key",  # pragma: allowlist secret
            openai_base_url="not-a-valid-url",
            openai_docent_model="gpt-5.4-mini",
        ),
    )

    assert ai_service.rerank_ai_enabled() is False


def test_rerank_ai_enabled_accepts_custom_settings(monkeypatch):
    """rerank_ai_enabled accepts custom settings for testing."""
    custom_settings = SimpleNamespace(
        enable_live_ai=True,
        openai_api_key="custom-test-key",  # pragma: allowlist secret
        openai_base_url="https://api.openai.com/v1",
        openai_docent_model="gpt-5.4-mini",
    )

    assert ai_service.rerank_ai_enabled(custom_settings) is True

    # Custom settings without flag
    custom_settings.enable_live_ai = False
    assert ai_service.rerank_ai_enabled(custom_settings) is False


def test_rerank_docent_candidates_uses_rerank_gate(monkeypatch):
    """rerank_docent_candidates uses rerank_ai_enabled gate."""
    called: list[str] = []

    def fake_completion(prompt: str) -> str:
        called.append(prompt)
        return '{"reranked_ids": ["id1", "id2", "id3"]}'

    monkeypatch.setattr(
        ai_service,
        "get_settings",
        lambda: SimpleNamespace(
            enable_live_ai=True,
            openai_api_key="test-openai-key",  # pragma: allowlist secret
            openai_base_url="https://api.openai.com/v1",
            openai_docent_model="gpt-5.4-mini",
        ),
    )
    monkeypatch.setattr(ai_service, "rerank_ai_enabled", lambda s: True)

    class FakeCompletions:
        def create(self, **kwargs):
            return SimpleNamespace(
                choices=[
                    SimpleNamespace(
                        message=SimpleNamespace(content='{"reranked_ids": ["id1", "id2", "id3"]}')
                    )
                ]
            )

    class FakeOpenAI:
        def __init__(self, **kwargs):
            self.chat = SimpleNamespace(completions=FakeCompletions())

    fake_openai = types.ModuleType("openai")
    fake_openai.OpenAI = FakeOpenAI
    monkeypatch.setitem(sys.modules, "openai", fake_openai)

    prompt = "Test rerank prompt"
    result = ai_service.rerank_docent_candidates(prompt)

    assert result == '{"reranked_ids": ["id1", "id2", "id3"]}'


def test_rerank_docent_candidates_fails_when_rerank_gate_disabled(monkeypatch):
    """rerank_docent_candidates raises error when rerank_ai_enabled is False."""
    monkeypatch.setattr(
        ai_service,
        "get_settings",
        lambda: SimpleNamespace(
            enable_live_ai=False,
            openai_api_key="test-openai-key",  # pragma: allowlist secret
            openai_base_url="https://api.openai.com/v1",
            openai_docent_model="gpt-5.4-mini",
        ),
    )
    monkeypatch.setattr(ai_service, "rerank_ai_enabled", lambda s: False)

    with pytest.raises(ServiceError) as exc_info:
        ai_service.rerank_docent_candidates("Test prompt")

    assert exc_info.value.code == "AI_NOT_CONFIGURED"
    assert exc_info.value.retryable is False
    assert "reranking is not enabled" in exc_info.value.message.lower()


def test_grounding_context_prompt_appends_english_guard_for_en_language():
    grounding = [
        {
            "source_type": "place_profile",
            "title_ko": "정동문화축제",
            "body_ko": "정동문화축제의 주간 로컬 언급 신호입니다.",
            "body_en": None,
        }
    ]

    prompt_en = ai_service._grounding_context_prompt(grounding, language="en")
    prompt_ko = ai_service._grounding_context_prompt(grounding, language="ko")

    # Why: verified grounding bodies are Korean-only, so an English request must carry an
    # explicit translate-to-English guard or the model flips to Korean mid-script.
    assert "every sentence of the final script must be English only" in prompt_en
    assert "English only" not in prompt_ko
    assert "정동문화축제의 주간 로컬 언급 신호입니다." in prompt_en


def test_grounding_context_prompt_prefers_body_en_for_english_requests():
    grounding = [
        {
            "source_type": "place_profile",
            "title_ko": "삼원가든",
            "body_ko": "장소명은 삼원가든입니다.",
            "body_en": "The place name is Samwon Garden.",
        }
    ]

    prompt_en = ai_service._grounding_context_prompt(grounding, language="en")
    prompt_ko = ai_service._grounding_context_prompt(grounding, language="ko")

    assert "The place name is Samwon Garden." in prompt_en
    assert "장소명은 삼원가든입니다." not in prompt_en
    assert "장소명은 삼원가든입니다." in prompt_ko


def test_generate_docent_script_en_prompt_carries_output_language_guard(monkeypatch):
    captured: dict[str, object] = {}

    class FakeCompletions:
        def create(self, **kwargs):
            captured["messages"] = kwargs["messages"]
            return SimpleNamespace(
                choices=[SimpleNamespace(message=SimpleNamespace(content="English script."))]
            )

    class FakeOpenAI:
        def __init__(self, **kwargs):
            self.chat = SimpleNamespace(completions=FakeCompletions())

    fake_openai = types.ModuleType("openai")
    fake_openai.OpenAI = FakeOpenAI
    monkeypatch.setitem(sys.modules, "openai", fake_openai)
    monkeypatch.setattr(
        ai_service,
        "get_settings",
        lambda: SimpleNamespace(
            enable_live_ai=True,
            openai_api_key="test-openai-key",  # pragma: allowlist secret
            openai_base_url="https://api.openai.com/v1",
            openai_docent_model="gpt-5.4-mini",
        ),
    )

    request = DocentScriptRequest(
        place_id="place-en",
        place_name="Jeongdong Cultural Festival",
        category="event",
        language="en",
        mode="brief",
    )
    grounding = [
        {
            "source_type": "place_profile",
            "title_ko": "정동문화축제",
            "body_ko": "정동문화축제는 중구 정동에서 즐기는 행사입니다.",
            "body_en": None,
        }
    ]

    ai_service.generate_docent_script_text(request, grounding_context=grounding)

    user_prompt = captured["messages"][1]["content"]
    assert "Output language: English." in user_prompt
    assert "no Korean characters" in user_prompt
    assert "must be English only" in user_prompt


def test_generate_docent_script_en_prefers_request_place_name_over_korean_title(monkeypatch):
    captured: dict[str, object] = {}

    class FakeCompletions:
        def create(self, **kwargs):
            captured["messages"] = kwargs["messages"]
            return SimpleNamespace(
                choices=[SimpleNamespace(message=SimpleNamespace(content="English script."))]
            )

    class FakeOpenAI:
        def __init__(self, **kwargs):
            self.chat = SimpleNamespace(completions=FakeCompletions())

    fake_openai = types.ModuleType("openai")
    fake_openai.OpenAI = FakeOpenAI
    monkeypatch.setitem(sys.modules, "openai", fake_openai)
    monkeypatch.setattr(
        ai_service,
        "get_settings",
        lambda: SimpleNamespace(
            enable_live_ai=True,
            openai_api_key="test-openai-key",  # pragma: allowlist secret
            openai_base_url="https://api.openai.com/v1",
            openai_docent_model="gpt-5.4-mini",
        ),
    )

    grounding = [
        {
            "source_type": "place_profile",
            "title_ko": "도심속 바다축제",
            "body_ko": "도심속 바다축제는 노량진에서 열리는 행사입니다.",
            "body_en": None,
        }
    ]

    # English request: the client-supplied localized name must win over the Korean title
    # so the model does not invent its own romanization.
    request_en = DocentScriptRequest(
        place_id="place-en",
        place_name="City Sea Festival",
        category="event",
        language="en",
        mode="brief",
    )
    ai_service.generate_docent_script_text(request_en, grounding_context=grounding)
    assert "Place: City Sea Festival." in captured["messages"][1]["content"]

    # Korean request: the verified Korean title keeps priority (unchanged behavior).
    request_ko = DocentScriptRequest(
        place_id="place-ko",
        place_name="도심속 바다축제",
        category="event",
        language="ko",
        mode="brief",
    )
    ai_service.generate_docent_script_text(request_ko, grounding_context=grounding)
    assert "Place: 도심속 바다축제." in captured["messages"][1]["content"]


# --- Docent QA defect regressions (F1/F2/N1/N3/N4/N7) ---


def test_counter_only_mention_chunk_is_not_visitor_review_context():
    """F1: a weekly-counter row (source_type place_mention, counter body with
    no review wording) must NOT arm the visitor-quote persona branch."""
    request = DocentScriptRequest(
        place_id="counter-only",
        place_name="한밭교육박물관",
        category="culture_venue",
        language="ko",
        mode="brief",
    )

    prompt = ai_service._docent_system_prompt(
        request,
        place_name="한밭교육박물관",
        grounding_context=[
            {
                "source_type": "place_mention",
                "title_ko": "한밭교육박물관 주간 언급",
                # Counter-shaped body: numbers only, no review voice.
                "body_ko": "지난주 총 언급 14회, 유기적 언급 9회, 감성 점수 0.61.",
            }
        ],
    )

    assert "공간 큐레이터" in prompt
    assert "수석 도슨트" not in prompt


def test_generation_prompt_forbids_fabricated_quotes_and_indoor_claims():
    """F1/N3/N4 guards must be present in the generation prompt itself so the
    model cannot invent visitor voice, metric wording, or indoor character."""
    import inspect

    source = inspect.getsource(ai_service.generate_docent_script_text)
    assert "NEVER fabricate visitor quotes" in source
    assert "weekly mention counters are aggregate statistics" in source
    assert "Do not assert whether the place is indoors or outdoors" in source
    assert "never mention demand dispersion" in source


def test_en_weather_prompt_translates_korean_air_labels():
    """N1: Korean AQI/outdoor labels must not enter an English prompt."""
    request = DocentScriptRequest(
        place_id="en-aqi",
        place_name="Hwaseong Fortress",
        category="attraction",
        language="en",
        mode="brief",
        dust_grade="좋음",
        dust_pm10_grade="보통",
        dust_pm25_grade="좋음",
        weather_outdoor_status="실외",
    )

    prompt = ai_service._weather_context_prompt(request, language="en")

    assert "좋음" not in prompt
    assert "보통" not in prompt
    assert "실외" not in prompt
    assert "overall dust good" in prompt
    assert "PM10 grade moderate" in prompt
    assert "outdoor status outdoor" in prompt


def test_ko_weather_prompt_keeps_korean_air_labels():
    """The KO path is unchanged (byte-compat with the pre-fix prompt)."""
    request = DocentScriptRequest(
        place_id="ko-aqi",
        place_name="수원화성",
        category="attraction",
        language="ko",
        mode="brief",
        dust_grade="좋음",
    )

    prompt = ai_service._weather_context_prompt(request, language="ko")

    assert "overall dust 좋음" in prompt


def test_grounding_prompt_maps_raw_source_ids_to_reader_safe_labels():
    """N7: raw internal ids like tour_api must not be model-visible."""
    prompt = ai_service._grounding_context_prompt(
        [
            {
                "source_type": "tour_api",
                "title_ko": "아시아아시아",
                "body_ko": "검증된 관광지 프로필입니다.",
            }
        ],
        language="en",
    )

    assert "tour_api" not in prompt
    assert "official tourism data" in prompt


def test_en_dust_guard_sentence_translates_korean_grades():
    """N1 residual (Stage-5 canary): docent_service's EN dust sentence emitted
    'PM10 is 좋음' — the second PM-label path #146 missed."""
    from apps.api.app.schemas.docent import DocentScriptRequest
    from apps.api.app.services import docent_service

    request = DocentScriptRequest(
        place_id="x",
        place_name="Test",
        category="attraction",
        language="en",
        mode="brief",
        dust_pm10_grade="좋음",
        dust_pm10="13",
        dust_pm25_grade="보통",
        dust_pm25="13",
    )
    sentence = docent_service._en_dust_split_sentence(request)
    assert "좋음" not in sentence and "보통" not in sentence
    assert "PM10 is good (13)" in sentence
    assert "PM2.5 is moderate (13)" in sentence


def test_en_weather_sentence_translates_korean_grades():
    """Stage-5 batch finding: docent_service._en_weather_sentence (the third
    PM-label path) still emitted 'PM10 좋음 (13) / PM2.5 좋음 (13)'."""
    from apps.api.app.schemas.docent import DocentScriptRequest
    from apps.api.app.services import docent_service

    request = DocentScriptRequest(
        place_id="x",
        place_name="Test",
        category="attraction",
        language="en",
        mode="brief",
        weather_temp="24.0",
        weather_icon="partly-cloudy",
        dust_pm10_grade="좋음",
        dust_pm10="13",
        dust_pm25_grade="좋음",
        dust_pm25="13",
    )
    sentence = docent_service._en_weather_sentence(request)
    assert "좋음" not in sentence
    assert "PM10 good (13)" in sentence and "PM2.5 good (13)" in sentence
