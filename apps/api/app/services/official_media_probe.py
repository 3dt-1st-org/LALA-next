"""Official media probe contract: deterministic, fail-closed image URL verification.

Offline contract only -- it never opens a socket; all I/O flows through a single
injected :class:`ProbeTransport`. It reuses ``validate_image_url`` and the source
registry so URL/governance/image-rights rules match the rest of the inventory.

Security contract: results never carry a raw initial/final URL, query,
credentials, header, body, literal IP, or provider/exception text -- only an
opaque SHA-256 URL fingerprint and a normalized DNS hostname leave the module.
Governance and verified rights are checked **before** any transport call, so
rights/source/URL failures make zero calls. Every transport exception is caught
and collapsed to one generic redacted probe error.
"""

from __future__ import annotations

import hashlib
import ipaddress
import re
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Protocol
from urllib.parse import urlparse

from apps.api.app.services.official_source_inventory import (
    ImageRightsStatus,
    ImageUrlPolicy,
    OfficialSourceInventoryError,
    validate_image_url,
)
from apps.api.app.services.official_source_registry import is_source_registered

DEFAULT_TIMEOUT_MS: int = 5000
DEFAULT_MAX_BYTES: int = 10 * 1024 * 1024  # 10 MiB bounded-download budget.
# HEAD statuses whose semantics ("HEAD not supported") permit exactly one GET.
_FALLBACK_STATUSES: frozenset[int] = frozenset({403, 405, 501})
_MEDIA_TYPE_RE: re.Pattern[str] = re.compile(r"^image/[a-z0-9.+-]+$")
_LOCAL_HOST_SUFFIXES: tuple[str, ...] = (".localhost", ".local")
_LOCAL_HOST_EXACT: tuple[str, ...] = ("localhost", "local")
_REDACTED_IP = "ip-address"


class ProbeStatus(StrEnum):
    """Stable public outcome of a probe."""

    ACCEPTED = "accepted"
    QUARANTINED = "quarantined"  # validation rejection; fail closed.
    ERROR = "error"  # transport/inspection failure.


class ProbeReason(StrEnum):
    """Stable, redacted reason for a non-accepted outcome."""

    INVALID_URL = "invalid_url"
    UNSAFE_REDIRECT = "unsafe_redirect"
    SOURCE = "source"
    RIGHTS = "rights"
    HTTP_UNAVAILABLE = "http_unavailable"
    MIME = "mime"
    INVALID_SIZE = "invalid_size"
    MISSING_SIZE = "missing_size"
    OVERSIZED = "oversized"
    PROBE_ERROR = "probe_error"


class ProbeMethod(StrEnum):
    """HTTP method carried by a probe request."""

    HEAD = "HEAD"
    GET = "GET"


@dataclass(frozen=True, slots=True)
class ImageProbeRequest:
    """One transport request. ``url`` is transport-visible but never printed."""

    method: ProbeMethod
    url: str = field(repr=False)
    timeout_ms: int = DEFAULT_TIMEOUT_MS
    max_bytes: int = DEFAULT_MAX_BYTES


@dataclass(frozen=True, slots=True)
class ImageProbeResponse:
    """Raw transport snapshot. All provider header/URL values are repr-hidden."""

    status_code: int | None
    final_url: str = field(repr=False, default="")
    content_type: str = field(repr=False, default="")
    content_length: str = field(repr=False, default="")
    observed_bytes: int = 0
    body_complete: bool = False


class ProbeTransport(Protocol):
    """Single injected transport: one request in, one snapshot out (or raise)."""

    def __call__(self, request: ImageProbeRequest) -> ImageProbeResponse: ...


@dataclass(frozen=True, slots=True)
class OfficialImageProbeResult:
    """Secret-safe result. No raw URL/IP/header/body/exception text anywhere."""

    url_fingerprint: str
    normalized_hostname: str
    status: ProbeStatus
    reason: ProbeReason | None = None
    media_type: str | None = None
    proven_size: int | None = None
    method: ProbeMethod | None = None
    http_status: int | None = None

    def to_public_dict(self) -> dict[str, object]:
        """Expose only fingerprint/hostname/status fields, never source content."""
        return {
            "url_fingerprint": self.url_fingerprint,
            "normalized_hostname": self.normalized_hostname,
            "status": self.status.value,
            "reason": self.reason.value if self.reason is not None else None,
            "media_type": self.media_type,
            "proven_size": self.proven_size,
            "method": self.method.value if self.method is not None else None,
            "http_status": self.http_status,
        }


@dataclass(frozen=True, slots=True)
class BatchProbeReport:
    """Aggregated batch report (immutable tuple of results)."""

    total_urls: int
    accepted_count: int
    quarantined_count: int
    error_count: int
    results: tuple[OfficialImageProbeResult, ...] = ()

    def to_public_dict(self) -> dict[str, object]:
        return {
            "total_urls": self.total_urls,
            "accepted_count": self.accepted_count,
            "quarantined_count": self.quarantined_count,
            "error_count": self.error_count,
            "results": [r.to_public_dict() for r in self.results],
        }


# --- internal helpers --------------------------------------------------------


def _fingerprint(url: str) -> str:
    """Opaque SHA-256 of the normalized URL (never the URL itself).

    Canonicalization: only scheme and hostname are lowercased (DNS is case-insensitive).
    Path, query, and fragment preserve their original case because they can be
    case-sensitive. Fragment is excluded from fingerprint as it doesn't affect
    the resource content.
    """
    stripped = url.strip()
    try:
        parsed = urlparse(stripped)
        # Reconstruct URL with only scheme and hostname lowercased, fragment excluded
        canonical = (
            f"{parsed.scheme.lower()}://"
            f"{parsed.hostname.lower() if parsed.hostname else ''}"
            + (f":{parsed.port}" if parsed.port else "")
            + (parsed.path or "")
            + (f"?{parsed.query}" if parsed.query else "")
        )
        return hashlib.sha256(canonical.encode()).hexdigest()
    except ValueError:
        # Fallback for malformed URLs: hash the stripped URL
        return hashlib.sha256(stripped.encode()).hexdigest()


def _safe_hostname(url: str) -> str:
    """Return a lowercased DNS hostname, or a redacted marker for literal IPs."""
    try:
        host = (urlparse(url).hostname or "").lower()
    except ValueError:
        return ""
    if not host:
        return ""
    try:
        ipaddress.ip_address(host)
    except ValueError:
        return host
    return _REDACTED_IP


def _url_is_safe(url: str) -> bool:
    """Reuse the inventory URL gate plus localhost/local-name rejection."""
    try:
        validated = validate_image_url(url, ImageUrlPolicy())
    except OfficialSourceInventoryError:
        return False
    host = (urlparse(validated).hostname or "").lower()
    if not host or host in _LOCAL_HOST_EXACT or host.endswith(_LOCAL_HOST_SUFFIXES):
        return False
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        return True  # public DNS name; validate_image_url already bound the scheme.
    # validate_image_url rejected private/loopback/reserved; also fail closed on
    # unspecified/multicast/zero addresses that are not routable image hosts.
    return not (
        address.is_unspecified
        or address.is_loopback
        or address.is_private
        or address.is_reserved
        or address.is_multicast
    )


def _normalize_media_type(raw: str | None) -> str | None:
    """Bound a Content-Type to a lowercase ``image/<subtype>`` or None."""
    if not raw or not raw.strip():
        return None
    media = raw.split(";", 1)[0].strip().lower()
    return media if _MEDIA_TYPE_RE.fullmatch(media) else None


def _classify_size(raw: str | None, max_bytes: int) -> tuple[str, int | None]:
    """Return a ``(state, size)`` pair: missing/invalid/oversized/proven."""
    if raw is None or not str(raw).strip():
        return "missing", None
    try:
        size = int(str(raw).strip())
    except (ValueError, TypeError):
        return "invalid", None
    if size <= 0:
        return "invalid", None
    if size > max_bytes:
        return "oversized", size
    return "proven", size


@dataclass(frozen=True, slots=True)
class _Decision:
    """Internal outcome of validating one response's metadata."""

    outcome: str  # "accept" | "reject" | "needs_get"
    reason: ProbeReason | None = None
    media_type: str | None = None
    proven_size: int | None = None


def _classify_head_response(response: ImageProbeResponse, max_bytes: int) -> _Decision:
    """For a 2xx HEAD: accept only image MIME + proven size, else one bounded GET."""
    media = _normalize_media_type(response.content_type)
    size_state, size = _classify_size(response.content_length, max_bytes)
    if response.content_type.strip() and media is None:
        return _Decision("reject", ProbeReason.MIME)
    if size_state == "invalid":
        return _Decision("reject", ProbeReason.INVALID_SIZE)
    if size_state == "oversized":
        return _Decision("reject", ProbeReason.OVERSIZED)
    if media is not None and size_state == "proven":
        return _Decision("accept", media_type=media, proven_size=size)
    # Missing MIME or missing size is inconclusive -> exactly one bounded GET.
    return _Decision("needs_get")


def _classify_get_response(response: ImageProbeResponse, max_bytes: int) -> _Decision:
    """For a 2xx GET: prove size from a header or a complete positive body."""
    media = _normalize_media_type(response.content_type)
    if media is None:
        return _Decision("reject", ProbeReason.MIME)

    # Fail-closed: never accept merely because Content-Length is small when observed_bytes
    # is negative or exceeds max_bytes. Reject inconsistent size evidence.
    if response.observed_bytes < 0:
        return _Decision("reject", ProbeReason.INVALID_SIZE)
    if response.observed_bytes > max_bytes:
        return _Decision("reject", ProbeReason.OVERSIZED)

    size_state, size = _classify_size(response.content_length, max_bytes)
    if size_state == "invalid":
        return _Decision("reject", ProbeReason.INVALID_SIZE)
    if size_state == "oversized":
        return _Decision("reject", ProbeReason.OVERSIZED)
    if size_state == "proven":
        # Allow only positive Content-Length <= max_bytes with non-contradictory observed bytes
        if response.observed_bytes > 0 and response.observed_bytes != size:
            return _Decision("reject", ProbeReason.INVALID_SIZE)
        return _Decision("accept", media_type=media, proven_size=size)
    # No header proof: a complete body with positive observed bytes proves size.
    if response.body_complete and response.observed_bytes > 0:
        if response.observed_bytes > max_bytes:
            return _Decision("reject", ProbeReason.OVERSIZED)
        return _Decision("accept", media_type=media, proven_size=response.observed_bytes)
    if response.body_complete:  # complete but zero observed bytes.
        return _Decision("reject", ProbeReason.INVALID_SIZE)
    return _Decision("reject", ProbeReason.MISSING_SIZE)


def _result(
    fingerprint: str,
    hostname: str,
    status: ProbeStatus,
    *,
    reason: ProbeReason | None = None,
    media_type: str | None = None,
    proven_size: int | None = None,
    method: ProbeMethod | None = None,
    http_status: int | None = None,
) -> OfficialImageProbeResult:
    return OfficialImageProbeResult(
        url_fingerprint=fingerprint,
        normalized_hostname=hostname,
        status=status,
        reason=reason,
        media_type=media_type,
        proven_size=proven_size,
        method=method,
        http_status=http_status,
    )


def _redirect_is_unsafe(final_url: str) -> bool:
    """A redirect is unsafe only if it actually happened and landed unsafely.

    An empty ``final_url`` means no redirect occurred, so the already-validated
    request URL stands and there is nothing to re-check.
    """
    return bool(final_url) and not _url_is_safe(final_url)


def _run_one_get(
    url: str,
    fingerprint: str,
    hostname: str,
    transport: ProbeTransport,
    timeout_ms: int,
    max_bytes: int,
) -> OfficialImageProbeResult:
    """Execute exactly one bounded GET and classify its snapshot."""
    request = ImageProbeRequest(
        ProbeMethod.GET, url=url, timeout_ms=timeout_ms, max_bytes=max_bytes
    )
    try:
        response = transport(request)
    except Exception:
        return _result(fingerprint, hostname, ProbeStatus.ERROR, reason=ProbeReason.PROBE_ERROR)
    if _redirect_is_unsafe(response.final_url):
        return _result(
            fingerprint,
            hostname,
            ProbeStatus.QUARANTINED,
            reason=ProbeReason.UNSAFE_REDIRECT,
            method=ProbeMethod.GET,
            http_status=response.status_code,
        )
    if response.status_code is not None and 200 <= response.status_code < 300:
        decision = _classify_get_response(response, max_bytes)
        if decision.outcome == "accept":
            return _result(
                fingerprint,
                hostname,
                ProbeStatus.ACCEPTED,
                media_type=decision.media_type,
                proven_size=decision.proven_size,
                method=ProbeMethod.GET,
                http_status=response.status_code,
            )
        assert decision.reason is not None
        return _result(
            fingerprint,
            hostname,
            ProbeStatus.QUARANTINED,
            reason=decision.reason,
            method=ProbeMethod.GET,
            http_status=response.status_code,
        )
    return _result(
        fingerprint,
        hostname,
        ProbeStatus.QUARANTINED,
        reason=ProbeReason.HTTP_UNAVAILABLE,
        http_status=response.status_code,
    )


# --- public API --------------------------------------------------------------


def probe_official_image_url(
    url: str,
    *,
    source_name: str,
    image_rights_status: ImageRightsStatus,
    transport: ProbeTransport,
    timeout_ms: int = DEFAULT_TIMEOUT_MS,
    max_bytes: int = DEFAULT_MAX_BYTES,
) -> OfficialImageProbeResult:
    """Probe one official image URL with HEAD-first validation and one bounded GET.

    Fail-closed policy: governance/rights/URL are checked before transport; a
    HEAD 2xx is accepted only with image MIME and a proven positive size at or
    below ``max_bytes``; otherwise exactly one bounded GET may run (also for
    403/405/501). 404/429/500/503 never fall back. All exceptions become one
    generic redacted probe error. Actual fallback statuses are only 403/405/501
    and incomplete 2xx HEAD metadata; 503 must not fall back.
    """
    fingerprint = _fingerprint(url)
    hostname = _safe_hostname(url)

    # 1. Governance before transport: source, rights, then URL safety.
    if not is_source_registered(source_name):
        return _result(fingerprint, hostname, ProbeStatus.QUARANTINED, reason=ProbeReason.SOURCE)
    if image_rights_status != "verified":
        return _result(fingerprint, hostname, ProbeStatus.QUARANTINED, reason=ProbeReason.RIGHTS)
    if not _url_is_safe(url):
        return _result(
            fingerprint, hostname, ProbeStatus.QUARANTINED, reason=ProbeReason.INVALID_URL
        )

    # 2. HEAD first.
    head_request = ImageProbeRequest(
        ProbeMethod.HEAD, url=url, timeout_ms=timeout_ms, max_bytes=max_bytes
    )
    try:
        head = transport(head_request)
    except Exception:
        return _result(fingerprint, hostname, ProbeStatus.ERROR, reason=ProbeReason.PROBE_ERROR)

    if _redirect_is_unsafe(head.final_url):
        return _result(
            fingerprint,
            hostname,
            ProbeStatus.QUARANTINED,
            reason=ProbeReason.UNSAFE_REDIRECT,
            http_status=head.status_code,
        )

    # 3. Route the HEAD status.
    if head.status_code is not None and 200 <= head.status_code < 300:
        decision = _classify_head_response(head, max_bytes)
        if decision.outcome == "accept":
            return _result(
                fingerprint,
                hostname,
                ProbeStatus.ACCEPTED,
                media_type=decision.media_type,
                proven_size=decision.proven_size,
                method=ProbeMethod.HEAD,
                http_status=head.status_code,
            )
        if decision.outcome == "reject":
            assert decision.reason is not None
            return _result(
                fingerprint,
                hostname,
                ProbeStatus.QUARANTINED,
                reason=decision.reason,
                http_status=head.status_code,
            )
        return _run_one_get(url, fingerprint, hostname, transport, timeout_ms, max_bytes)
    if head.status_code in _FALLBACK_STATUSES:
        return _run_one_get(url, fingerprint, hostname, transport, timeout_ms, max_bytes)
    return _result(
        fingerprint,
        hostname,
        ProbeStatus.QUARANTINED,
        reason=ProbeReason.HTTP_UNAVAILABLE,
        http_status=head.status_code,
    )


def batch_probe_official_image_urls(
    urls: tuple[str, ...],
    *,
    source_name: str,
    image_rights_status: ImageRightsStatus,
    transport: ProbeTransport,
    timeout_ms: int = DEFAULT_TIMEOUT_MS,
    max_bytes: int = DEFAULT_MAX_BYTES,
) -> BatchProbeReport:
    """Probe many URLs deterministically; aggregate counts over an immutable tuple."""
    if not urls:
        return BatchProbeReport(0, 0, 0, 0, ())
    results = tuple(
        probe_official_image_url(
            url,
            source_name=source_name,
            image_rights_status=image_rights_status,
            transport=transport,
            timeout_ms=timeout_ms,
            max_bytes=max_bytes,
        )
        for url in urls
    )
    return BatchProbeReport(
        total_urls=len(results),
        accepted_count=sum(1 for r in results if r.status is ProbeStatus.ACCEPTED),
        quarantined_count=sum(1 for r in results if r.status is ProbeStatus.QUARANTINED),
        error_count=sum(1 for r in results if r.status is ProbeStatus.ERROR),
        results=results,
    )


def reconcile_probe_results(
    previous_results: tuple[OfficialImageProbeResult, ...],
    current_results: tuple[OfficialImageProbeResult, ...],
) -> dict[str, tuple[str, ...]]:
    """Deterministic, fingerprint-only diff of accepted identity between two runs."""
    prev_accepted = {
        r.url_fingerprint for r in previous_results if r.status is ProbeStatus.ACCEPTED
    }
    curr_accepted = {r.url_fingerprint for r in current_results if r.status is ProbeStatus.ACCEPTED}
    return {
        "accepted": tuple(sorted(curr_accepted)),
        "previously_accepted": tuple(sorted(prev_accepted)),
        "newly_accepted": tuple(sorted(curr_accepted - prev_accepted)),
        "no_longer_accepted": tuple(sorted(prev_accepted - curr_accepted)),
    }


__all__ = [
    "DEFAULT_MAX_BYTES",
    "DEFAULT_TIMEOUT_MS",
    "BatchProbeReport",
    "ImageProbeRequest",
    "ImageProbeResponse",
    "OfficialImageProbeResult",
    "ProbeMethod",
    "ProbeReason",
    "ProbeStatus",
    "ProbeTransport",
    "batch_probe_official_image_urls",
    "probe_official_image_url",
    "reconcile_probe_results",
]
