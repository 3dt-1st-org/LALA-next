"""Naver Search API based review/mention collection.

Uses Naver Search Open API (blog + cafe) to collect place mentions.
No crawling/scraping — only the official Search API.
"""

from __future__ import annotations

import contextlib
import json
import os
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import UTC, datetime


@dataclass(frozen=True)
class NaverSearchResult:
    provider: str
    external_key: str
    title: str | None
    body: str | None
    post_url: str | None
    created_at_source: datetime | None
    keyword: str


def _naver_headers() -> dict[str, str]:
    cid = os.getenv("NAVER_CLIENT_ID", "").strip()
    csec = os.getenv("NAVER_CLIENT_SECRET", "").strip()
    if not cid or not csec:
        raise ValueError("NAVER_CLIENT_ID and NAVER_CLIENT_SECRET must be set")
    return {"X-Naver-Client-Id": cid, "X-Naver-Client-Secret": csec}


def _parse_date(s: str | None) -> datetime | None:
    if not s or len(s) != 8:
        return None
    try:
        return datetime(int(s[:4]), int(s[4:6]), int(s[6:8]), tzinfo=UTC)
    except ValueError:
        return None


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


def _search(endpoint: str, query: str, display: int = 10, timeout: int = 10) -> list[dict]:
    url = f"https://openapi.naver.com/v1/search/{endpoint}.json?query={urllib.parse.quote(query)}&display={display}&sort=sim"
    req = urllib.request.Request(url, headers=_naver_headers())
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8")).get("items", [])


def search_blog(query: str, display: int = 10, timeout: int = 10) -> list[NaverSearchResult]:
    items = _search("blog", query, display, timeout)
    return [
        NaverSearchResult(
            provider="naver_blog",
            external_key=f"naver-blog-{i.get('link', '')}-{i.get('postdate', '')}"[:200],
            title=_clean(i.get("title")),
            body=_clean(i.get("description")),
            post_url=i.get("link") or None,
            created_at_source=_parse_date(i.get("postdate")),
            keyword=query,
        )
        for i in items
    ]


def search_cafe(query: str, display: int = 10, timeout: int = 10) -> list[NaverSearchResult]:
    items = _search("cafearticle", query, display, timeout)
    return [
        NaverSearchResult(
            provider="naver_cafe",
            external_key=f"naver-cafe-{i.get('link', '')}"[:200],
            title=_clean(i.get("title")),
            body=_clean(i.get("description")),
            post_url=i.get("link") or None,
            created_at_source=None,
            keyword=query,
        )
        for i in items
    ]


def collect_mentions_for_place(place_name: str, display: int = 5) -> list[NaverSearchResult]:
    results: list[NaverSearchResult] = []
    with contextlib.suppress(Exception):
        results.extend(search_blog(place_name, display=display))
    with contextlib.suppress(Exception):
        results.extend(search_cafe(place_name, display=display))
    return results
