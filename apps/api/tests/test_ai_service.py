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
