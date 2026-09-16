from __future__ import annotations

import time
from collections.abc import Callable
from typing import Any

from apps.api.app.services.ai_completion import (
    DEFAULT_JSON_GENERATION_PARAMS,
    ChatCompletionGenerationParams,
)


def create_chat_completion_with_retry(
    *,
    client: Any,
    model: str,
    messages: list[dict[str, str]],
    retry_attempts: int,
    retry_delay_sec: float,
    generation: ChatCompletionGenerationParams = DEFAULT_JSON_GENERATION_PARAMS,
    sleep: Callable[[float], None] = time.sleep,
    is_retryable: Callable[[Exception], bool] | None = None,
) -> Any:
    retryable = is_retryable or is_retryable_ai_error
    attempts = max(1, retry_attempts)
    delay = max(0.0, retry_delay_sec)
    last_exc: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            return client.chat.completions.create(
                model=model,
                messages=messages,
                **generation.to_request_kwargs(),
            )
        except Exception as exc:
            last_exc = exc
            if attempt >= attempts or not retryable(exc):
                raise
            sleep(delay * attempt)
    if last_exc:
        raise last_exc
    raise RuntimeError("OpenAI completion failed before a request was attempted.")


def is_retryable_ai_error(exc: Exception) -> bool:
    status_code = getattr(exc, "status_code", None)
    if status_code in {408, 409, 429, 500, 502, 503, 504}:
        return True
    text = str(exc).lower()
    return any(
        marker in text
        for marker in (
            "too many requests",
            "rate limit",
            "timeout",
            "temporarily unavailable",
            "service unavailable",
        )
    )
