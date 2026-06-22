from __future__ import annotations

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.schemas.docent import DocentScriptRequest
from apps.api.app.services.normalization import display_language, format_celsius_label


def live_ai_enabled() -> bool:
    settings = get_settings()
    return bool(
        settings.enable_live_ai
        and settings.azure_openai_endpoint
        and settings.azure_openai_key
        and settings.azure_openai_deployment
        and settings.azure_openai_api_version
    )


_REVIEW_SOURCE_HINTS = (
    "review",
    "visitor",
    "blog",
    "naver",
    "mention",
    "community",
)
_REVIEW_TEXT_HINTS_KO = (
    "방문객",
    "리뷰",
    "후기",
    "키워드",
    "분위기",
    "팁",
)
_ATTRACTION_NOISE_GUARD_KO = (
    "명소나 문화공간을 식당/카페 리뷰처럼 쓰지 마세요. 음식, 카페, 맛집은 "
    "주변 동선 팁으로만 다루고, 장소 자체의 매력이나 근거로 둔갑시키지 마세요."
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
        timeout=8.0,
    )
    language = display_language(request.language)
    grounding_context = grounding_context or []
    place_name = (
        _canonical_grounding_title(grounding_context)
        or request.place_name
        or request.place_id
    )
    context = _docent_context_prompt(
        request,
        grounding_context=grounding_context,
    )
    system_prompt = _docent_system_prompt(
        request,
        place_name=place_name,
        grounding_context=grounding_context,
    )
    prompt = (
        f"Output language: {language}.\n"
        f"Mode: {request.mode}.\n"
        f"Category: {request.category}.\n"
        f"Place: {place_name}.\n"
        f"{context}\n"
        "Ground the script in verified tourism/culture data, local spending context, "
        "and nearby walking experience. Avoid generic marketing copy. "
        "If visitor-review context is provided, turn it into a natural insight, "
        "not a raw review summary. If only official/place-profile context is "
        "provided, stay closer to spatial curation and practical visiting value. "
        "If distance, weather, PM10, PM2.5, small-merchant, or local-spending "
        "context is provided, mention those signals naturally without exposing "
        "private numeric recommendation scores. Include one practical route action "
        "for what to do before or after this stop. "
        "Do not infer sunny, clear, rainy, snowy, or sky conditions unless a "
        "weather condition/icon is provided; when it is provided, use only that "
        "condition. "
        "Use recommendation scores only as private reasoning: do not quote numeric "
        "scores, score labels, internal table names, cache names, or raw source codes "
        "in the user-facing docent script. "
        "Keep it concise, friendly, and suitable for a walking travel app."
    )
    try:
        completion = client.chat.completions.create(
            model=settings.azure_openai_deployment,
            messages=[
                {
                    "role": "system",
                    "content": system_prompt,
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


def _docent_system_prompt(
    request: DocentScriptRequest,
    *,
    place_name: str,
    grounding_context: list[dict] | None = None,
) -> str:
    language_name = display_language(request.language)
    sentence_rule = "3-4" if request.mode == "brief" else "6-8"
    has_review_data = _has_visitor_review_context(grounding_context or [])
    category = request.category

    if category in {"attraction", "culture_venue"}:
        guard = f"\n[가드레일] {_ATTRACTION_NOISE_GUARD_KO}"
        if has_review_data:
            return (
                "당신은 'LALA'의 활기차고 센스 있는 수석 도슨트입니다.\n"
                "[미션] 방문객의 실제 리뷰와 검증된 장소 데이터를 바탕으로 이 장소의 "
                "'살아있는 매력'을 짧고 강렬하게 소개하세요.\n"
                "[가이드라인]\n"
                f"1. 첫인상: 가능하면 '{place_name}에 오신 것을 환영합니다!'처럼 "
                "장소의 분위기를 먼저 잡아 주세요.\n"
                "2. 공감대: '많은 분들이 이곳의 ~한 점을 좋아하시더라고요'처럼 "
                "방문객의 목소리를 자연스럽게 녹이되, 원문을 과장하지 마세요.\n"
                "3. 현장감: 이어폰으로 듣는 상황을 고려해 리듬감 있는 구어체를 사용하세요.\n"
                f"4. 분량: {sentence_rule}문장. 언어: {language_name}. 없는 사실을 지어내지 마세요."
                f"{guard}"
            )
        return (
            "당신은 장소의 가치를 전달하는 '공간 큐레이터'입니다.\n"
            "[미션] 공식 설명 데이터와 운영 DB의 장소 프로필을 바탕으로 장소의 특징을 "
            f"{sentence_rule}문장, {language_name}로 품격 있게 소개하세요.\n"
            "실용적인 방문 팁과 주변 동선 가치를 포함하고, 없는 사실을 지어내지 마세요."
            f"{guard}"
        )

    if category == "restaurant":
        return (
            "당신은 'LALA AI Guide'입니다.\n"
            "[대본 작성 원칙]\n"
            "1. 구성: 분위기와 메뉴 특성에 따라 자연스럽게 storytelling 하세요.\n"
            "2. 데이터 기반: 키워드와 리뷰 인사이트를 문장에 녹여내 생생함을 더하세요.\n"
            "3. 말투: 이어폰으로 듣는 상황을 고려해 리듬감 있는 구어체를 사용하세요.\n"
            f"4. 분량: {sentence_rule}문장. 언어: {language_name}. 없는 사실을 지어내지 마세요."
        )

    return (
        "You are LALA's docent writer for a location-based mobile travel app. "
        f"Write {sentence_rule} conversational sentences in {language_name}. "
        "Mention practical tips and local context, connect the event to nearby "
        "culture or small-merchant routes when provided, and do not invent unavailable facts."
    )


def _has_visitor_review_context(grounding_context: list[dict]) -> bool:
    for item in grounding_context:
        source_type = str(item.get("source_type") or "").strip().lower()
        if any(hint in source_type for hint in _REVIEW_SOURCE_HINTS):
            return True
        body = " ".join(
            str(item.get(key) or "")
            for key in ("title_ko", "body_ko", "body_en")
        )
        if any(hint in body for hint in _REVIEW_TEXT_HINTS_KO):
            return True
    return False


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
    weather_context = _weather_context_prompt(request)
    if weather_context:
        parts.append(weather_context)
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


def _weather_context_prompt(request: DocentScriptRequest) -> str:
    weather_parts: list[str] = []
    if temperature := format_celsius_label(request.weather_temp):
        weather_parts.append(f"temperature {temperature}")
    if condition := _weather_condition_label(request.weather_icon):
        weather_parts.append(
            f"weather condition {condition} (icon {request.weather_icon})"
        )
    if request.weather_outdoor_status:
        weather_parts.append(f"outdoor status {request.weather_outdoor_status}")
    if request.dust_grade:
        weather_parts.append(f"overall dust {request.dust_grade}")
    if request.dust_pm10:
        weather_parts.append(f"PM10 value {request.dust_pm10}")
    if request.dust_pm25:
        weather_parts.append(f"PM2.5 value {request.dust_pm25}")
    if request.dust_pm10_grade:
        weather_parts.append(f"PM10 grade {request.dust_pm10_grade}")
    if request.dust_pm25_grade:
        weather_parts.append(f"PM2.5 grade {request.dust_pm25_grade}")
    if not weather_parts:
        return ""
    return "Current weather and air quality: " + "; ".join(weather_parts) + "."


def _weather_condition_label(icon: str | None) -> str | None:
    return {
        "partly-cloudy": "partly cloudy",
        "partly_cloudy": "partly cloudy",
        "partly cloudy": "partly cloudy",
        "cloudy": "cloudy",
        "clear": "clear",
        "sunny": "sunny",
        "rain": "rainy",
        "sleet": "mixed rain and snow",
        "snow": "snowy",
    }.get((icon or "").strip().lower())


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
        "Grounding snippets from LALA verified place context. Use them when relevant, "
        "and do not invent facts beyond them:\n" + "\n".join(snippets)
    )


def _canonical_grounding_title(grounding_context: list[dict]) -> str | None:
    for item in grounding_context:
        if str(item.get("source_type") or "").strip() != "place_profile":
            continue
        title = str(item.get("title_ko") or "").strip()
        if title:
            return title
    for item in grounding_context:
        title = str(item.get("title_ko") or "").strip()
        if title:
            return title
    return None
