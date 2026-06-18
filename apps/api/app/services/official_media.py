from __future__ import annotations

from urllib.parse import urlsplit, urlunsplit

HTTPS_UPGRADE_IMAGE_HOSTS = frozenset(
    {
        "tong.visitkorea.or.kr",
    }
)


def normalize_official_image_url(raw_url: object) -> str | None:
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
