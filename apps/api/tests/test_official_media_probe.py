"""Rigorous matrix tests for the official media probe contract.

All tests drive a single injected :class:`FakeTransport`. There are no real
network, provider, DB, or device calls. The matrix pins down every requirement:
governance-before-transport, redirect safety, size proof, MIME normalization,
redaction, determinism, and exception handling.
"""

from __future__ import annotations

import pytest

from apps.api.app.services import official_media_probe as probe
from apps.api.app.services.official_media_probe import (
    ImageProbeRequest,
    ImageProbeResponse,
    ProbeMethod,
    ProbeReason,
    ProbeStatus,
)

# The only sources the real registry declares as registered.
REGISTERED_SOURCE = "tour_api"
UNREGISTERED_SOURCE = "definitely_not_a_registered_source"
PUBLIC_URL = "https://images.example.com/poster.jpg"


class FakeTransport:
    """Records every call and returns scripted responses keyed by method."""

    def __init__(self) -> None:
        self.calls: list[ImageProbeRequest] = []
        self.head: ImageProbeResponse | Exception = ImageProbeResponse(status_code=404)
        self.get: ImageProbeResponse | Exception | None = None

    def __call__(self, request: ImageProbeRequest) -> ImageProbeResponse:
        self.calls.append(request)
        scripted = self.head if request.method is ProbeMethod.HEAD else self.get
        if scripted is None:
            # A GET that was never scripted means the probe should not have asked.
            raise AssertionError("GET invoked without a scripted response")
        if isinstance(scripted, Exception):
            raise scripted
        return scripted

    @property
    def head_calls(self) -> int:
        return sum(1 for c in self.calls if c.method is ProbeMethod.HEAD)

    @property
    def get_calls(self) -> int:
        return sum(1 for c in self.calls if c.method is ProbeMethod.GET)


def _ok_head(
    *,
    content_type: str = "image/jpeg",
    content_length: str = "1024",
    final_url: str = PUBLIC_URL,
) -> ImageProbeResponse:
    return ImageProbeResponse(
        status_code=200,
        final_url=final_url,
        content_type=content_type,
        content_length=content_length,
    )


def _ok_get(  # noqa: RUF029  (pure helper used to build fixtures, not async)
    *,
    content_type: str = "image/jpeg",
    content_length: str | None = "1024",
    observed_bytes: int = 1024,
    body_complete: bool = True,
    final_url: str = PUBLIC_URL,
) -> ImageProbeResponse:
    return ImageProbeResponse(
        status_code=200,
        final_url=final_url,
        content_type=content_type,
        content_length=content_length,
        observed_bytes=observed_bytes,
        body_complete=body_complete,
    )


# --- governance before transport: zero calls -------------------------------


@pytest.mark.parametrize("rights", ["not_permitted", "unknown", "pending", ""])
def test_non_verified_rights_make_zero_calls(rights: str) -> None:
    transport = FakeTransport()
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status=rights,  # type: ignore[arg-type]
        transport=transport,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.RIGHTS
    assert transport.calls == []


def test_unregistered_source_makes_zero_calls() -> None:
    transport = FakeTransport()
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=UNREGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.SOURCE
    assert transport.calls == []


@pytest.mark.parametrize(
    "url",
    [
        "http://example.com/x.jpg",  # wrong scheme
        "ftp://example.com/x.jpg",
        "https://user:pass@example.com/x.jpg",  # credentials  # pragma: allowlist secret
        "https://user@example.com/x.jpg",
        "not-a-url",
        "",
    ],
)
def test_unsafe_initial_url_makes_zero_calls(url: str) -> None:
    transport = FakeTransport()
    result = probe.probe_official_image_url(
        url,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.INVALID_URL
    assert transport.calls == []


# --- private/local hosts rejected (literal IP + DNS names) -----------------


@pytest.mark.parametrize(
    "url",
    [
        "https://localhost/x.jpg",
        "https://127.0.0.1/x.jpg",
        "https://127.0.0.1:8080/x.jpg",
        "https://[::1]/x.jpg",
        "https://10.0.0.1/x.jpg",
        "https://192.168.1.1/x.jpg",
        "https://172.16.0.1/x.jpg",
        "https://sub.localhost/x.jpg",
        "https://host.local/x.jpg",
        "https://0.0.0.0/x.jpg",
        "https://local/x.jpg",  # exact hostname 'local' must also be rejected
    ],
)
def test_private_and_local_hosts_rejected(url: str) -> None:
    transport = FakeTransport()
    result = probe.probe_official_image_url(
        url,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.INVALID_URL
    assert transport.calls == []


# --- HEAD happy path -------------------------------------------------------


def test_head_2xx_accepted_with_image_mime_and_proven_size() -> None:
    transport = FakeTransport()
    transport.head = _ok_head(content_type="image/png", content_length="2048")
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.ACCEPTED
    assert result.media_type == "image/png"
    assert result.proven_size == 2048
    assert result.method is ProbeMethod.HEAD
    assert result.http_status == 200
    assert transport.get_calls == 0


def test_boundary_size_accepted() -> None:
    transport = FakeTransport()
    transport.head = _ok_head(content_length=str(10 * 1024 * 1024))
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
        max_bytes=10 * 1024 * 1024,
    )
    assert result.status is ProbeStatus.ACCEPTED
    assert result.proven_size == 10 * 1024 * 1024


# --- HEAD inconclusive -> exactly one bounded GET --------------------------


@pytest.mark.parametrize("head_status", [403, 405, 501])
def test_fallback_status_triggers_one_bounded_get(head_status: int) -> None:
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=head_status)
    transport.get = _ok_get(content_length="512", observed_bytes=512)
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.ACCEPTED
    assert result.method is ProbeMethod.GET
    assert transport.head_calls == 1
    assert transport.get_calls == 1


def test_head_missing_content_length_triggers_one_bounded_get() -> None:
    transport = FakeTransport()
    transport.head = _ok_head(content_length="")  # size missing -> inconclusive
    transport.get = _ok_get(content_length="768", observed_bytes=768)
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.ACCEPTED
    assert result.proven_size == 768
    assert transport.get_calls == 1


def test_head_missing_mime_triggers_one_bounded_get() -> None:
    transport = FakeTransport()
    transport.head = _ok_head(content_type="", content_length="1024")
    transport.get = _ok_get(content_length="1024")
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.ACCEPTED
    assert transport.get_calls == 1


# --- never fall back for these statuses ------------------------------------


@pytest.mark.parametrize("status", [404, 429, 500, 503])
def test_no_get_for_disallowed_statuses(status: int) -> None:
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=status)
    transport.get = _ok_get()  # scripted; must not be used.
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.HTTP_UNAVAILABLE
    assert result.http_status == status
    assert transport.get_calls == 0


# --- size evidence failures ------------------------------------------------


@pytest.mark.parametrize("raw", ["abc", "1.5", "0", "-10", "NaN"])
def test_malformed_or_nonpositive_size_rejected(raw: str) -> None:
    transport = FakeTransport()
    transport.head = _ok_head(content_length=raw)
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    # An invalid (not merely missing) length fails closed immediately.
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.INVALID_SIZE


def test_oversized_size_rejected() -> None:
    transport = FakeTransport()
    transport.head = _ok_head(content_length=str(20 * 1024 * 1024))
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
        max_bytes=10 * 1024 * 1024,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.OVERSIZED


# --- GET size proof rules --------------------------------------------------


def test_get_partial_without_total_proof_rejected() -> None:
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=403)
    transport.get = _ok_get(content_length=None, observed_bytes=0, body_complete=False)
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.MISSING_SIZE


def test_get_complete_body_with_positive_observed_proves_size() -> None:
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=405)
    transport.get = _ok_get(content_length=None, observed_bytes=4096, body_complete=True)
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.ACCEPTED
    assert result.proven_size == 4096
    assert result.method is ProbeMethod.GET


# --- redirect safety -------------------------------------------------------


def test_unsafe_final_redirect_quarantined() -> None:
    transport = FakeTransport()
    transport.head = _ok_head(final_url="https://169.254.169.254/latest/meta-data/")
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.UNSAFE_REDIRECT


def test_unsafe_get_redirect_quarantined() -> None:
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=403)
    transport.get = _ok_get(final_url="https://localhost/evil.jpg")
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.UNSAFE_REDIRECT


# --- MIME normalization & invalid header never echoed ----------------------


def test_invalid_mime_value_is_not_echoed() -> None:
    transport = FakeTransport()
    transport.head = _ok_head(content_type="text/html; charset=utf-8", content_length="1024")
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.MIME
    # The provider header value must not be echoed into the result.
    assert result.media_type is None
    assert "text/html" not in str(result.to_public_dict())


def test_content_type_with_charset_is_normalized() -> None:
    transport = FakeTransport()
    transport.head = _ok_head(content_type="IMAGE/JPEG; charset=binary", content_length="1024")
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.ACCEPTED
    assert result.media_type == "image/jpeg"


# --- exceptions redacted ---------------------------------------------------


def test_head_exception_redacted() -> None:
    transport = FakeTransport()
    transport.head = RuntimeError("secret internal connection string")
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.ERROR
    assert result.reason is ProbeReason.PROBE_ERROR
    assert "secret internal connection string" not in str(result.to_public_dict())


def test_get_exception_redacted() -> None:
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=403)
    transport.get = OSError("https://internal-host:8080/admin token=abc")
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.ERROR
    assert result.reason is ProbeReason.PROBE_ERROR
    assert "internal-host" not in str(result.to_public_dict())


# --- redaction across all surfaces -----------------------------------------


def test_no_raw_url_anywhere_in_result_or_repr() -> None:
    secret_query = "https://example.com/photo.jpg?token=ABC123&user=me"  # pragma: allowlist secret
    transport = FakeTransport()
    transport.head = _ok_head(final_url=secret_query)
    result = probe.probe_official_image_url(
        secret_query,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    blob = repr(result) + repr(result.to_public_dict()) + str(result.to_public_dict())
    assert secret_query not in blob
    assert "token=ABC123" not in blob
    assert "ABC123" not in blob
    # The request snapshot also hides the URL from repr.
    assert "photo.jpg" not in repr(transport.calls[0])


def test_normalized_hostname_is_safe() -> None:
    transport = FakeTransport()
    transport.head = _ok_head()
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.normalized_hostname == "images.example.com"


def test_literal_ip_hostname_is_redacted() -> None:
    url = "https://203.0.113.10/x.jpg"  # TEST-NET-3 (reserved) -> rejected.
    transport = FakeTransport()
    result = probe.probe_official_image_url(
        url,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    # Reserved IP is rejected before transport; hostname marker never leaks IP.
    assert result.reason is ProbeReason.INVALID_URL


# --- GET receives the byte budget ------------------------------------------


def test_get_request_carries_byte_budget() -> None:
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=403)
    transport.get = _ok_get(content_length="100", observed_bytes=100)
    probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
        max_bytes=12345,
    )
    get_request = next(c for c in transport.calls if c.method is ProbeMethod.GET)
    assert get_request.max_bytes == 12345
    assert get_request.url == PUBLIC_URL
    assert get_request.method is ProbeMethod.GET


# --- batch + reconciliation determinism ------------------------------------


def test_batch_aggregation_is_deterministic_and_immutable() -> None:
    urls = (
        "https://images.example.com/a.jpg",
        "https://images.example.com/b.jpg",
        "https://images.example.com/c.jpg",
    )
    transport = FakeTransport()
    transport.head = _ok_head(content_length="100")  # default for all HEADs.
    report = probe.batch_probe_official_image_urls(
        urls,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert isinstance(report.results, tuple)
    assert report.total_urls == 3
    assert report.accepted_count == 3
    assert report.quarantined_count == 0
    assert report.error_count == 0
    # Order preserved and deterministic.
    assert [r.url_fingerprint for r in report.results] == [
        probe._fingerprint(u)
        for u in urls  # noqa: SLF001
    ]


def test_batch_empty() -> None:
    report = probe.batch_probe_official_image_urls(
        (),
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=FakeTransport(),
    )
    assert report.total_urls == 0
    assert report.results == ()


def test_reconciliation_is_fingerprint_only_and_immutable() -> None:
    transport_a = FakeTransport()
    transport_a.head = _ok_head(content_length="100")
    previous = probe.batch_probe_official_image_urls(
        ("https://images.example.com/keep.jpg", "https://images.example.com/drop.jpg"),
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport_a,
    )

    transport_b = FakeTransport()
    transport_b.head = _ok_head(content_length="100")
    current = probe.batch_probe_official_image_urls(
        ("https://images.example.com/keep.jpg", "https://images.example.com/add.jpg"),
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport_b,
    )

    changes = probe.reconcile_probe_results(previous.results, current.results)
    assert all(isinstance(v, tuple) for v in changes.values())
    keep_fp = probe._fingerprint("https://images.example.com/keep.jpg")  # noqa: SLF001
    drop_fp = probe._fingerprint("https://images.example.com/drop.jpg")  # noqa: SLF001
    add_fp = probe._fingerprint("https://images.example.com/add.jpg")  # noqa: SLF001
    assert changes["newly_accepted"] == (add_fp,)
    assert changes["no_longer_accepted"] == (drop_fp,)
    assert changes["accepted"] == tuple(sorted((keep_fp, add_fp)))
    # No raw URL ever appears in reconciliation output.
    blob = repr(changes)
    assert "keep.jpg" not in blob and "drop.jpg" not in blob and "add.jpg" not in blob


def test_reconciliation_is_stable_across_runs() -> None:
    transport = FakeTransport()
    transport.head = _ok_head(content_length="100")
    kwargs = {
        "source_name": REGISTERED_SOURCE,
        "image_rights_status": "verified",
        "transport": transport,
    }
    run_a = probe.batch_probe_official_image_urls(("https://images.example.com/x.jpg",), **kwargs)
    run_b = probe.batch_probe_official_image_urls(("https://images.example.com/x.jpg",), **kwargs)
    assert probe.reconcile_probe_results(run_a.results, run_b.results)["newly_accepted"] == ()


# --- case-sensitive URL fingerprinting ----------------------------------------


def test_url_fingerprint_preserves_path_case() -> None:
    """URL paths are case-sensitive: /A.jpg and /a.jpg must produce different fingerprints."""
    transport = FakeTransport()
    transport.head = _ok_head(content_length="100")

    result_upper = probe.probe_official_image_url(
        "https://images.example.com/A.jpg",
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    result_lower = probe.probe_official_image_url(
        "https://images.example.com/a.jpg",
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )

    # Different URLs with different case should produce different fingerprints
    assert result_upper.url_fingerprint != result_lower.url_fingerprint

    # But both should be accepted (same content setup)
    assert result_upper.status is ProbeStatus.ACCEPTED
    assert result_lower.status is ProbeStatus.ACCEPTED

    # Verify redaction is still intact - no raw URLs leak
    assert "A.jpg" not in repr(result_upper) and "A.jpg" not in str(result_upper.to_public_dict())
    assert "a.jpg" not in repr(result_lower) and "a.jpg" not in str(result_lower.to_public_dict())


def test_url_fingerprint_preserves_query_case() -> None:
    """URL query parameters are case-sensitive: ?key=Val and ?key=val must produce different fingerprints."""
    transport = FakeTransport()
    transport.head = _ok_head(content_length="100")

    result_upper = probe.probe_official_image_url(
        "https://images.example.com/img.jpg?Version=123",
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    result_lower = probe.probe_official_image_url(
        "https://images.example.com/img.jpg?version=123",
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )

    # Different case in query param should produce different fingerprints
    assert result_upper.url_fingerprint != result_lower.url_fingerprint

    # Both accepted, and redaction maintained
    assert result_upper.status is ProbeStatus.ACCEPTED
    assert result_lower.status is ProbeStatus.ACCEPTED
    assert "Version" not in repr(result_upper) and "Version" not in str(
        result_upper.to_public_dict()
    )


def test_url_fingerprint_canonicalizes_scheme_and_hostname() -> None:
    """Scheme and hostname are case-insensitive and must be lowercased in fingerprints."""
    transport = FakeTransport()
    transport.head = _ok_head(content_length="100")

    result_upper = probe.probe_official_image_url(
        "HTTPS://IMAGES.EXAMPLE.COM/img.jpg",
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    result_lower = probe.probe_official_image_url(
        "https://images.example.com/img.jpg",
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )

    # Scheme and hostname are case-insensitive, so should produce same fingerprint
    assert result_upper.url_fingerprint == result_lower.url_fingerprint


# --- bounded GET fail-closed size enforcement ---------------------------------


def test_get_with_negative_observed_bytes_rejected() -> None:
    """Bounded GET must reject responses with negative observed_bytes."""
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=403)
    transport.get = _ok_get(content_length="100", observed_bytes=-1, body_complete=True)
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.INVALID_SIZE


def test_get_oversized_observed_bytes_rejected_even_with_small_content_length() -> None:
    """Bounded GET must reject when observed_bytes exceeds max_bytes, even if Content-Length header is small."""
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=403)
    transport.get = _ok_get(
        content_length="100",  # Small Content-Length header
        observed_bytes=20 * 1024 * 1024,  # But observed_bytes says 20 MiB
        body_complete=True,
    )
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
        max_bytes=10 * 1024 * 1024,  # 10 MiB budget
    )
    # Must quarantine due to oversized observed_bytes, ignoring the small Content-Length
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.OVERSIZED


def test_get_403_fallback_with_oversized_observed_bytes_quarantined() -> None:
    """403/405/501 fallback GET with small Content-Length but oversized observed_bytes must be quarantined."""
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=403)  # Fallback status
    transport.get = _ok_get(
        content_length="100",  # Small header
        observed_bytes=15 * 1024 * 1024,  # But observed_bytes is 15 MiB
        body_complete=True,
    )
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
        max_bytes=10 * 1024 * 1024,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.OVERSIZED
    assert result.method is ProbeMethod.GET  # Fallback GET was executed


def test_get_405_fallback_with_oversized_observed_bytes_quarantined() -> None:
    """405 fallback GET with small Content-Length but oversized observed_bytes must be quarantined."""
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=405)  # Fallback status
    transport.get = _ok_get(
        content_length="100",  # Small header
        observed_bytes=15 * 1024 * 1024,  # But observed_bytes is 15 MiB
        body_complete=True,
    )
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
        max_bytes=10 * 1024 * 1024,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.OVERSIZED


def test_get_501_fallback_with_oversized_observed_bytes_quarantined() -> None:
    """501 fallback GET with small Content-Length but oversized observed_bytes must be quarantined."""
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=501)  # Fallback status
    transport.get = _ok_get(
        content_length="100",  # Small header
        observed_bytes=15 * 1024 * 1024,  # But observed_bytes is 15 MiB
        body_complete=True,
    )
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
        max_bytes=10 * 1024 * 1024,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.OVERSIZED


def test_get_with_contradictory_size_evidence_rejected() -> None:
    """Bounded GET must reject when Content-Length header and observed_bytes contradict each other."""
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=403)
    transport.get = _ok_get(
        content_length="100",  # Header says 100 bytes
        observed_bytes=200,  # But observed bytes says 200 bytes
        body_complete=True,
    )
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
        max_bytes=10 * 1024 * 1024,  # 10 MiB budget - both values would fit individually
    )
    # Must quarantine due to contradictory evidence, even though both are under budget
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.INVALID_SIZE


def test_get_with_incomplete_body_and_negative_observed_bytes_rejected() -> None:
    """Incomplete body with negative observed_bytes must be rejected."""
    transport = FakeTransport()
    transport.head = ImageProbeResponse(status_code=403)
    transport.get = _ok_get(
        content_length=None,
        observed_bytes=-1,
        body_complete=False,
    )
    result = probe.probe_official_image_url(
        PUBLIC_URL,
        source_name=REGISTERED_SOURCE,
        image_rights_status="verified",
        transport=transport,
    )
    assert result.status is ProbeStatus.QUARANTINED
    assert result.reason is ProbeReason.INVALID_SIZE
