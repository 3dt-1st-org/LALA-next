"""Naver Search Open API review/mention acquisition (governed, aggregate-only).

Official Naver Search Open API only (blog + cafearticle via openapi.naver.com).
No scraping, no crawling, no Daangn. Raw provider text (title/description/link)
lives only in process memory long enough to (a) compute content_sha256 and (b)
hand to the deterministic filter; it is never persisted, logged, or written to
any DB column (DG-11/G-TRUST). Acquisition is keyed on a concrete travel.places
row and every emitted record carries place_id/region/category provenance.

Failures are typed via AcquisitionOutcome (auth_missing / quota_exceeded /
network_error / parse_error / empty) — never swallowed, never resembling honest
zero-result success. external_key is an opaque, place-aware digest token
(naver_<provider>_sha256:<hex64>) using the full sha256, never the raw post URL.
"""

from __future__ import annotations

import hashlib
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Literal

from apps.api.app.services.review_mention_ingest import clean_review_text

# DG-1 gate identity. The tool refuses to acquire until an operator registers
# ingest.review_sources with source_name=SOURCE_NAME, provider=EXPECTED_PROVIDER,
# terms_version=EXPECTED_TERMS_VERSION, an allowed license_class, and
# source_status='active'. This is the explicit legal/access decision point.
SOURCE_NAME = "naver_search"
EXPECTED_PROVIDER = "naver"
EXPECTED_TERMS_VERSION = "naver-search-openapi-terms-v1"

NAVER_API_BASE = "https://openapi.naver.com/v1/search"

AcquisitionCategory = Literal[
    "ok",
    "auth_missing",
    "quota_exceeded",
    "network_error",
    "parse_error",
    "empty",
]


@dataclass(frozen=True)
class AcquisitionOutcome:
    """Typed per-provider acquisition result — carries NO raw payload.

    A network/auth/quota failure is reported with its real category, never as an
    honest zero-result ok/empty. ``attempted_count`` is the number of candidate
    items returned before filtering; it is 0 for every non-ok category because no
    items are trusted from a failed call.
    """

    provider: str
    category: AcquisitionCategory
    retryable: bool
    http_status: int | None
    attempted_count: int


@dataclass(frozen=True)
class TransientNaverPost:
    """In-memory-only raw post, retained transiently for hashing + filtering.

    DG-11/G-TRUST: title/description/link NEVER reach a DB column, log line, or
    governed record. The orchestrator reads them to run the deterministic filter
    (classify_post), then builds a no-raw-text record dict carrying only
    content_sha256 + the opaque external_key + provenance.
    """

    provider: str
    external_key: str
    keyword: str
    place_id: str
    region: str
    category: str
    title: str
    description: str
    link: str
    postdate: str
    created_at_source: datetime | None
    content_sha256: str


@dataclass(frozen=True)
class PlaceCollectionResult:
    """Aggregated acquisition result for one place (blog + cafe providers)."""

    place_id: str
    place_name: str
    region: str
    category: str
    keyword: str
    outcomes: tuple[AcquisitionOutcome, ...]
    posts: tuple[TransientNaverPost, ...]


# --- text/date helpers (retained from the original module for compatibility) ---


def _clean(s: str | None) -> str | None:
    if not s:
        return None
    return (
        s.replace("<b>", "")
        .replace("</b>", "")
        .replace("&quot;", '"')
        .replace("&amp;", "&")
        .strip()
    )


def _parse_date(s: str | None) -> datetime | None:
    if not s or len(s) != 8:
        return None
    try:
        return datetime(int(s[:4]), int(s[4:6]), int(s[6:8]), tzinfo=UTC)
    except ValueError:
        return None


# --- opaque identity helpers (never persist the raw URL) ---


def _opaque_external_key(*, provider: str, link: str, postdate: str, place_id: str) -> str:
    """Place-aware opaque token: naver_<provider>_sha256:<full hex64>.

    Full 64-hex sha256 over (provider + link + postdate + place_id). The raw URL
    is hashed and never appears. Place-awareness means the same post for two
    distinct places yields two distinct keys (P1b fix). Full digest means no
    preventable 64-bit collision domain at place×post scale (P2 fix).
    """
    material = f"{provider}|{link}|{postdate}|{place_id}"
    digest = hashlib.sha256(material.encode("utf-8")).hexdigest()
    return f"naver_{provider}_sha256:{digest}"


def _content_sha256(
    *,
    provider: str,
    link: str,
    postdate: str,
    place_id: str,
    title: str | None,
    description: str | None,
) -> str:
    """Place-aware full 64-hex content digest — the only retained content identity.

    sha256 over (provider + link + postdate + place_id + cleaned-title-hash +
    cleaned-desc-hash). Raw text is hashed in memory and discarded; only the
    64-char hex digest escapes. Place-aware: same post for two places yields two
    distinct digests so both get independent receipts/aggregates (P1b fix).
    """
    cleaned_title = clean_review_text(title or "")
    cleaned_desc = clean_review_text(description or "")
    title_hash = hashlib.sha256(cleaned_title.encode("utf-8")).hexdigest()
    desc_hash = hashlib.sha256(cleaned_desc.encode("utf-8")).hexdigest()
    material = f"{provider}|{link}|{postdate}|{place_id}|{title_hash}|{desc_hash}"
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def _naver_credentials() -> tuple[str, str]:
    return (
        os.getenv("NAVER_CLIENT_ID", "").strip(),
        os.getenv("NAVER_CLIENT_SECRET", "").strip(),
    )


# --- low-level fetch (raises; classified by the caller) ---


def _fetch_items(
    endpoint: str,
    query: str,
    display: int,
    timeout: int,
    cid: str,
    csec: str,
) -> list[dict]:
    """Call one Naver Search Open API endpoint and return raw items (or raise)."""
    url = (
        f"{NAVER_API_BASE}/{endpoint}.json"
        f"?query={urllib.parse.quote(query)}&display={display}&sort=sim"
    )
    req = urllib.request.Request(
        url,
        headers={"X-Naver-Client-Id": cid, "X-Naver-Client-Secret": csec},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8")).get("items", [])


def _build_transient_post(
    item: dict,
    *,
    provider: str,
    keyword: str,
    place_id: str,
    region: str,
    category: str,
) -> TransientNaverPost:
    link = str(item.get("link") or "")
    postdate = str(item.get("postdate") or "")
    title = _clean(item.get("title")) or ""
    description = _clean(item.get("description")) or ""
    return TransientNaverPost(
        provider=provider,
        external_key=_opaque_external_key(
            provider=provider, link=link, postdate=postdate, place_id=place_id
        ),
        keyword=keyword,
        place_id=place_id,
        region=region,
        category=category,
        title=title,
        description=description,
        link=link,
        postdate=postdate,
        created_at_source=_parse_date(item.get("postdate")),
        content_sha256=_content_sha256(
            provider=provider,
            link=link,
            postdate=postdate,
            place_id=place_id,
            title=title,
            description=description,
        ),
    )


def acquire_provider(
    *,
    endpoint: str,
    provider: str,
    query: str,
    place_id: str,
    region: str,
    category: str,
    display: int = 5,
    timeout: int = 10,
) -> tuple[AcquisitionOutcome, list[TransientNaverPost]]:
    """Acquire from one Naver Search endpoint with typed failure classification.

    Returns ``(outcome, posts)``. On any typed failure the outcome carries the
    real category and posts is empty. Unexpected errors propagate (never
    swallowed). Missing credentials are auth_missing, not a silent skip.
    """
    cid, csec = _naver_credentials()
    if not cid or not csec:
        return (
            AcquisitionOutcome(
                provider=provider,
                category="auth_missing",
                retryable=False,
                http_status=None,
                attempted_count=0,
            ),
            [],
        )
    try:
        items = _fetch_items(endpoint, query, display, timeout, cid, csec)
    except urllib.error.HTTPError as exc:
        status = int(exc.code)
        if status in (401, 403):
            cat: AcquisitionCategory = "auth_missing"
            retryable = False
        elif status == 429:
            cat = "quota_exceeded"
            retryable = True
        else:
            # Other HTTP errors (5xx, 400, etc.) are upstream server failures
            # best classified as network_error within the bounded category set.
            cat = "network_error"
            retryable = True
        return (
            AcquisitionOutcome(
                provider=provider,
                category=cat,
                retryable=retryable,
                http_status=status,
                attempted_count=0,
            ),
            [],
        )
    except (urllib.error.URLError, TimeoutError, OSError):
        return (
            AcquisitionOutcome(
                provider=provider,
                category="network_error",
                retryable=True,
                http_status=None,
                attempted_count=0,
            ),
            [],
        )
    except json.JSONDecodeError:
        return (
            AcquisitionOutcome(
                provider=provider,
                category="parse_error",
                retryable=False,
                http_status=None,
                attempted_count=0,
            ),
            [],
        )

    if not items:
        return (
            AcquisitionOutcome(
                provider=provider,
                category="empty",
                retryable=False,
                http_status=None,
                attempted_count=0,
            ),
            [],
        )

    posts = [
        _build_transient_post(
            item,
            provider=provider,
            keyword=query,
            place_id=place_id,
            region=region,
            category=category,
        )
        for item in items
    ]
    return (
        AcquisitionOutcome(
            provider=provider,
            category="ok",
            retryable=False,
            http_status=None,
            attempted_count=len(posts),
        ),
        posts,
    )


def collect_mentions_for_place(
    *,
    place_id: str,
    place_name: str,
    region: str,
    category: str,
    display: int = 5,
    timeout: int = 10,
) -> PlaceCollectionResult:
    """Acquire blog + cafe mentions for one concrete travel.places row.

    Every emitted post carries place_id/region/category provenance. Raw text
    lives in TransientNaverPost (in-memory only); the orchestrator builds the
    no-raw-text governed record from content_sha256 + external_key.
    """
    outcomes: list[AcquisitionOutcome] = []
    all_posts: list[TransientNaverPost] = []
    for endpoint, provider in (("blog", "naver_blog"), ("cafearticle", "naver_cafe")):
        outcome, posts = acquire_provider(
            endpoint=endpoint,
            provider=provider,
            query=place_name,
            place_id=place_id,
            region=region,
            category=category,
            display=display,
            timeout=timeout,
        )
        outcomes.append(outcome)
        all_posts.extend(posts)
    return PlaceCollectionResult(
        place_id=place_id,
        place_name=place_name,
        region=region,
        category=category,
        keyword=place_name,
        outcomes=tuple(outcomes),
        posts=tuple(all_posts),
    )
