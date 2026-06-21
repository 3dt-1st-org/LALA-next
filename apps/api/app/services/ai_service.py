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


def generate_docent_script_text(
    request: DocentScriptRequest,
    *,
    grounding_context: list[dict] | None = None,
) -> str:
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
    context = _docent_context_prompt(
        request,
        grounding_context=grounding_context or [],
    )
    prompt = (
        f"Write a {request.mode} mobile docent script in {language}. "
        f"Category: {request.category}. Place: {place_name}. "
        f"{context} "
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


def _docent_context_prompt(
    request: DocentScriptRequest,
    *,
    grounding_context: list[dict] | None = None,
) -> str:
    parts: list[str] = []
    if request.address:
        parts.append(f"Address: {request.address}.")
    region = request.region_en or request.region_ko
    if region:
        parts.append(f"Region: {region}.")
    if request.distance_m is not None and request.distance_m > 0:
        parts.append(f"Distance from user: {request.distance_m} meters.")
    source = request.upstream_source or request.source
    if source:
        parts.append(f"Data source: {source}.")
    score_context = _score_context_prompt(request)
    if score_context:
        parts.append(score_context)
    grounding_prompt = _grounding_context_prompt(grounding_context or [])
    if grounding_prompt:
        parts.append(grounding_prompt)
    return " ".join(parts)


def _score_context_prompt(request: DocentScriptRequest) -> str:
    score_parts: list[str] = []
    if request.final_score is not None:
        score_parts.append(f"overall recommendation score {request.final_score:.2f}")
    if request.local_spending_score is not None:
        score_parts.append(
            f"domestic spending score {request.local_spending_score:.2f}"
        )
    if request.small_merchant_fit_score is not None:
        score_parts.append(f"small merchant fit {request.small_merchant_fit_score:.2f}")
    if request.demand_dispersion_score is not None:
        score_parts.append(
            f"tourism demand dispersion {request.demand_dispersion_score:.2f}"
        )
    if request.weather_fit_score is not None:
        score_parts.append(f"weather fit {request.weather_fit_score:.2f}")
    if request.culture_relevance_score is not None:
        score_parts.append(f"culture relevance {request.culture_relevance_score:.2f}")
    if not score_parts:
        return ""
    return "Recommendation evidence: " + "; ".join(score_parts) + "."


def _grounding_context_prompt(grounding_context: list[dict]) -> str:
    snippets: list[str] = []
    for item in grounding_context[:3]:
        source_type = str(item.get("source_type") or "unknown").strip()
        title = str(item.get("title_ko") or "").strip()
        body = str(item.get("body_ko") or item.get("body_en") or "").strip()
        body = " ".join(body.split())
        if not body:
            continue
        if len(body) > 260:
            body = body[:257].rstrip() + "..."
        label = source_type
        if title:
            label += f" / {title}"
        snippets.append(f"- {label}: {body}")
    if not snippets:
        return ""
    return (
        "Grounding snippets from LALA RAG knowledge index. Use them when relevant, "
        "and do not invent facts beyond them:\n" + "\n".join(snippets)
    )
