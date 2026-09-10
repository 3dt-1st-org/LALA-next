from __future__ import annotations

import hashlib
import json
from typing import Any

from apps.api.app.core.errors import ApiError

IDEMPOTENCY_KEY_MAX_LENGTH = 200


def canonical_request_hash(payload: dict[str, Any]) -> str:
    """Deterministic sha256 over the canonical JSON of a request payload.

    Key-sorted, separator-normalized JSON makes the hash independent of
    client-side field ordering, so a retried request with the same semantic
    payload always hashes identically.
    """

    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def validate_idempotency_key(value: str | None) -> str | None:
    """Validate an optional ``Idempotency-Key`` header value.

    ``None``/absent passes through (no idempotency requested). Present values
    must be 1-200 chars with no control characters; anything else is a
    deterministic 400 so clients learn about malformed keys instead of
    silently losing deduplication.
    """

    if value is None:
        return None
    key = value.strip()
    if not key or len(key) > IDEMPOTENCY_KEY_MAX_LENGTH:
        raise _invalid()
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in key):
        raise _invalid()
    return key


def _invalid() -> ApiError:
    return ApiError(
        status_code=400,
        code="IDEMPOTENCY_KEY_INVALID",
        message=("The Idempotency-Key header must be 1-200 printable characters when present."),
        retryable=False,
    )
