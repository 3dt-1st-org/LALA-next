from __future__ import annotations

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.schemas.docent import DocentScriptRequest
from apps.api.app.services.normalization import display_language


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
    language = display_language(request.language)
    place_name = request.place_name or request.place_id
    prompt = (
        f"Write a {request.mode} mobile docent script in {language}. "
        f"Category: {request.category}. Place: {place_name}. "
        "Ground the script in official tourism/culture data, local spending context, "
        "and nearby walking experience. Avoid generic marketing copy. "
        "Keep it concise, friendly, and suitable for a walking travel app."
    )
    try:
        completion = client.chat.completions.create(
            model=settings.azure_openai_deployment,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are LALA, a location-aware Korean travel docent. "
                        "You connect official culture/tourism data with local economic context."
                    ),
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
