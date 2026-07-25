"""Image URL policy tests: strict ingest allowlist + lenient read-path normalizer."""

from __future__ import annotations

from apps.api.app.services import official_media as media

# --- strict ingest path: official_image_url_or_none ---------------------------


def test_allowlisted_http_host_upgraded_and_returned():
    url = media.official_image_url_or_none("http://tong.visitkorea.or.kr/cms/resource/image.jpg")
    assert url == "https://tong.visitkorea.or.kr/cms/resource/image.jpg"


def test_allowlisted_https_host_returned_unchanged():
    url = media.official_image_url_or_none("https://www.kopis.or.kr/upload/pfmPoster/a.gif")
    assert url == "https://www.kopis.or.kr/upload/pfmPoster/a.gif"


def test_non_allowlisted_host_is_dropped():
    # An arbitrary/non-official host must never be stored -- forward allowlisted only.
    assert media.official_image_url_or_none("https://evil.example.com/exfil?token=secret") is None
    assert media.official_image_url_or_none("http://blog.naver.com/image.jpg") is None


def test_non_http_scheme_is_dropped():
    assert media.official_image_url_or_none("data:image/png;base64,AAAA") is None
    assert media.official_image_url_or_none("javascript:alert(1)") is None
    assert media.official_image_url_or_none("//www.kopis.or.kr/x.gif") is None  # scheme-relative


def test_empty_and_none_are_dropped():
    assert media.official_image_url_or_none(None) is None
    assert media.official_image_url_or_none("") is None
    assert media.official_image_url_or_none("   ") is None


# --- lenient read path: normalize_official_image_url --------------------------


def test_read_path_normalizer_upgrades_allowlisted_http():
    url = media.normalize_official_image_url("http://www.culture.go.kr/upload/rdf/thumb.jpg")
    assert url == "https://www.culture.go.kr/upload/rdf/thumb.jpg"


def test_read_path_normalizer_passes_through_legacy_hosts_for_display():
    # Legacy DB rows with non-official hosts still render on the public read path.
    url = media.normalize_official_image_url("http://legacy.example.com/old.jpg")
    assert url == "http://legacy.example.com/old.jpg"
