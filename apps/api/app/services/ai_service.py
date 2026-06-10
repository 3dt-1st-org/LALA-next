from __future__ import annotations

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.schemas.docent import DocentScriptRequest


def live_ai_enabled() -> bool:
    settings = get_settings()
    return bool(
        settings.enable_live_ai
        and settings.azure_openai_endpoint
        and settings.azure_openai_key
        and settings.azure_openai_deployment
        and settings.azure_openai_api_version
    )


def generate_docent_script_text(request: DocentScriptRequest) -> str:
    settings = get_settings()
    if not live_ai_enabled():
        raise ServiceError(
            status_code=503,
            code="AI_NOT_CONFIGURED",
            message="Azure OpenAI live generation is not enabled.",
            retryable=False,
        )
    try:
        from openai import AzureOpenAI
    except Exception as exc:
        raise ServiceError(
            status_code=503,
            code="AI_CLIENT_UNAVAILABLE",
            message="Azure OpenAI client dependency is unavailable.",
            retryable=False,
        ) from exc

    client = AzureOpenAI(
        azure_endpoint=settings.azure_openai_endpoint,
        api_key=settings.azure_openai_key,
        api_version=settings.azure_openai_api_version,
    )
    language = "Korean" if request.language == "ko" else "English"
    prompt = (
        f"Write a {request.mode} mobile docent script in {language}. "
        f"Category: {request.category}. Place id: {request.place_id}. "
        "Keep it concise, friendly, and suitable for a walking travel app."
    )
    try:
        completion = client.chat.completions.create(
            model=settings.azure_openai_deployment,
            messages=[
                {
                    "role": "system",
                    "content": "You are LALA, a location-aware travel docent for Gyeonggi-do.",
                },
                {"role": "user", "content": prompt},
            ],
            temperature=0.4,
            max_tokens=500,
        )
        text = completion.choices[0].message.content or ""
    except Exception as exc:
        raise ServiceError(
            status_code=502,
            code="AI_GENERATION_FAILED",
            message="Azure OpenAI generation failed.",
            retryable=True,
        ) from exc
    text = text.strip()
    if not text:
        raise ServiceError(
            status_code=502,
            code="AI_EMPTY_RESPONSE",
            message="Azure OpenAI returned an empty response.",
            retryable=True,
        )
    return text
