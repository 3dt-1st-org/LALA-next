from __future__ import annotations

import sys
import types
from types import SimpleNamespace

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
                choices=[SimpleNamespace(message=SimpleNamespace(content="검증된 도슨트 문장입니다."))]
            )

    class FakeAzureOpenAI:
        def __init__(self, **kwargs):
            captured["client"] = kwargs
            self.chat = SimpleNamespace(completions=FakeCompletions())

    fake_openai = types.ModuleType("openai")
    fake_openai.AzureOpenAI = FakeAzureOpenAI
    monkeypatch.setitem(sys.modules, "openai", fake_openai)
    monkeypatch.setattr(
        ai_service,
        "get_settings",
        lambda: SimpleNamespace(
            enable_live_ai=True,
            azure_openai_endpoint="https://example.openai.azure.com",
            azure_openai_key="secret",
            azure_openai_deployment="deployment",
            azure_openai_api_version="2024-02-15-preview",
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
    assert captured["completion"]["model"] == "deployment"
