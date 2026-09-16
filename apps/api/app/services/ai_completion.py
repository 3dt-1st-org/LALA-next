from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from types import MappingProxyType
from typing import Any


@dataclass(frozen=True)
class ChatCompletionGenerationParams:
    temperature: float = 0.1
    max_completion_tokens: int = 4000
    response_format: Mapping[str, str] | None = None

    def to_request_kwargs(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "temperature": self.temperature,
            "max_completion_tokens": self.max_completion_tokens,
        }
        if self.response_format is not None:
            payload["response_format"] = dict(self.response_format)
        return payload


DEFAULT_JSON_GENERATION_PARAMS = ChatCompletionGenerationParams(
    response_format=MappingProxyType({"type": "json_object"}),
)
