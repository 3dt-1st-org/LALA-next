from __future__ import annotations

from urllib.parse import urlsplit, urlunsplit

# The official-source image hosts the lane is allowed to store and forward.
# This is the single source of truth; the scheme-upgrade set is the same set.
OFFICIAL_IMAGE_HOST_ALLOWLIST = frozenset(
    {
        "www.culture.go.kr",
        "www.kopis.or.kr",
        "tong.visitkorea.or.kr",
    }
)

HTTPS_UPGRADE_IMAGE_HOSTS = OFFICIAL_IMAGE_HOST_ALLOWLIST


def official_image_url_or_none(raw_url: object) -> str | None:
    """Forward-only, allowlisted official image URL for ingest storage.

    Stores/forwards allowlisted official-source image URLs only. Drops
    non-http(s) schemes (``data:``, ``javascript:`` ...), non-allowlisted hosts,
    and the null/empty cases. Upgrades ``http`` -> ``https`` for allowlisted
    hosts. Never downloads or generates images.
    """
    if raw_url is None:
        return None
    image_url = str(raw_url).strip()
    if not image_url:
        return None
    try:
        parts = urlsplit(image_url)
    except ValueError:
        return None
    if parts.scheme not in {"http", "https"}:
        return None
    host = (parts.hostname or "").lower()
    if not host or host not in OFFICIAL_IMAGE_HOST_ALLOWLIST:
        return None
    if parts.scheme == "http":
        return urlunsplit(("https", parts.netloc, parts.path, parts.query, parts.fragment))
    return image_url


def normalize_official_image_url(raw_url: object) -> str | None:
    """Read-path normalizer for image URLs already persisted to the DB.

    Kept lenient (scheme upgrade only) so legacy rows still render in public
    display paths. Ingest callers must use :func:`official_image_url_or_none`,
    which enforces the host allowlist at write time.
    """
    if raw_url is None:
        return None
    image_url = str(raw_url).strip()
    if not image_url:
        return None
    try:
        parts = urlsplit(image_url)
    except ValueError:
        return image_url
    host = parts.hostname or ""
    if parts.scheme == "http" and host.lower() in HTTPS_UPGRADE_IMAGE_HOSTS:
        return urlunsplit(("https", parts.netloc, parts.path, parts.query, parts.fragment))
    return image_url
