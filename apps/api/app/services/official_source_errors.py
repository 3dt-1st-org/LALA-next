"""Bounded failure contract for official static/source ingests.

Upstream official APIs (TourAPI, KCISA, KOPIS, 공정위) sometimes embed arbitrary
text -- including service-key-bearing auth messages -- in their error responses.
Those raw blobs must never reach operator-facing payloads: ``redact_secret_text``
only scrubs known secret *values*, not arbitrary upstream message content. This
module is the single chokepoint that converts an upstream failure into a typed,
fixed-reason error so no raw upstream text is echoed.
"""

from __future__ import annotations

import re
from typing import Final, Literal

OfficialSourceErrorCategory = Literal[
    "auth",
    "http_status",
    "malformed_response",
    "empty",
    "window_too_wide",
    "unavailable",
]

REASON_BY_CATEGORY: Final[dict[OfficialSourceErrorCategory, str]] = {
    "auth": "upstream rejected the service key or credentials",
    "http_status": "upstream returned an unsuccessful HTTP status",
    "malformed_response": "upstream response was malformed and could not be parsed",
    "empty": "upstream returned no rows for the requested window",
    "window_too_wide": "requested date window exceeds the upstream limit",
    "unavailable": "upstream was unavailable or timed out",
}

# Substrings that signal an auth/credential failure. Used only to *classify* the
# failure category; the raw upstream text is never echoed into the raised message.
_AUTH_SIGNALS: Final[tuple[str, ...]] = (
    "service_key",
    "service key",
    "servicekey",
    "apikey",
    "api key",
    "unauthorized",
    "authentication",
    "authent",
)

# A bounded operator token (HTTP status, result code) -- never free upstream text.
_BOUNDED_CODE_RE: Final[re.Pattern[str]] = re.compile(r"^[A-Za-z0-9._:-]{1,32}$")


class OfficialSourceError(Exception):
    """A typed, fixed-reason failure for an official-source ingest.

    The string form is ``"{source}: {fixed reason}"`` plus an optional bounded
    code token. It deliberately never contains the raw upstream ``resultMsg``.
    """

    category: OfficialSourceErrorCategory
    source: str

    def __init__(
        self,
        *,
        category: OfficialSourceErrorCategory,
        source: str,
        bounded_code: object = None,
    ) -> None:
        self.category = category
        self.source = source
        message = f"{source}: {REASON_BY_CATEGORY[category]}"
        code_text = "" if bounded_code is None else str(bounded_code)
        if code_text and _BOUNDED_CODE_RE.match(code_text):
            message = f"{message} (code={code_text})"
        super().__init__(message)


def _classify_result_code(
    *,
    result_code: object,
    result_message: object,
) -> OfficialSourceErrorCategory:
    """Classify a non-zero upstream result code without leaking the message text."""
    text = f"{result_code} {result_message or ''}".lower()
    if any(signal in text for signal in _AUTH_SIGNALS):
        return "auth"
    return "malformed_response"


def raise_for_official_result_code(
    *,
    source: str,
    result_code: object,
    result_message: object,
) -> None:
    """Raise ``OfficialSourceError`` when the upstream result code is non-zero.

    ``result_message`` is inspected only to pick the category (auth vs malformed);
    it is never placed on the exception. Only a **missing** result code (``None``
    or empty) is treated as "nothing to validate" and returns ``None`` -- an
    explicit ``"0"`` is a real per-source failure code (e.g. every call site here
    already decides its own success set, such as ``"00"``/``"0000"``, before
    calling this helper) and must always raise, never be swallowed as a silent
    success shorthand (F4).
    """
    code_text = "" if result_code is None else str(result_code).strip()
    if not code_text:
        return
    category = _classify_result_code(result_code=result_code, result_message=result_message)
    raise OfficialSourceError(
        category=category,
        source=source,
        bounded_code=code_text,
    )


def raise_for_official_http_status(
    *,
    source: str,
    status_code: int | None,
) -> None:
    """Raise ``OfficialSourceError`` for an unsuccessful HTTP status code."""
    if status_code is None or 200 <= status_code < 300:
        return
    if status_code in (401, 403):
        category: OfficialSourceErrorCategory = "auth"
    elif 400 <= status_code < 500:
        category = "malformed_response"
    elif status_code >= 500:
        category = "unavailable"
    else:
        category = "http_status"
    raise OfficialSourceError(
        category=category,
        source=source,
        bounded_code=status_code,
    )
