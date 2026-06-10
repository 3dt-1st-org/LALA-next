from __future__ import annotations

import hmac
from typing import Annotated

from fastapi import Header

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ApiError


def require_api_key(x_api_key: Annotated[str | None, Header(alias="X-API-Key")] = None) -> None:
    expected = get_settings().ios_api_key
    if not expected:
        raise ApiError(
            status_code=503,
            code="API_KEY_NOT_CONFIGURED",
            message="Client API key is not configured.",
            retryable=False,
        )
    if not x_api_key or not hmac.compare_digest(x_api_key.strip(), expected):
        raise ApiError(
            status_code=401,
            code="UNAUTHORIZED",
            message="Invalid client API key.",
            retryable=False,
        )

