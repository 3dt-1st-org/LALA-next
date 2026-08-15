"""V6 foreign-visitor UX: API language contract tests.

Contract (docs/planning/v6-foreign-visitor-ux-contract.md §10): the API stays a
two-language surface. ``normalize_language`` keeps returning only ``ko``/``en``;
visitor locales (``ja``/``zh-Hans``/``zh-Hant``) are mapped to ``en`` at the
Flutter backend seam before the request is made. These tests pin both halves:

  * the server-side normalization boundary is unchanged — visitor-locale codes
    sent by a non-conforming client degrade to ``ko`` (the documented
    unknown-value fallback), never error, and never invent a third language;
  * the localized reason composer keeps composing Korean only for ``ko`` and
    English for ``en``, so a visitor-locale client requesting ``en`` can never
    receive Korean server copy.
"""

from __future__ import annotations

import pytest

from apps.api.app.services.normalization import (
    display_language,
    normalize_language,
)


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("ko", "ko"),
        ("KOR", "ko"),
        ("korean", "ko"),
        ("kr", "ko"),
        ("en", "en"),
        ("ENG", "en"),
        ("english", "en"),
    ],
)
def test_language_normalization_boundary_unchanged(raw: str, expected: str) -> None:
    assert normalize_language(raw) == expected


@pytest.mark.parametrize("raw", ["", None, "fr", "ja", "zh-Hans", "zh-Hant", "zh"])
def test_visitor_and_unknown_codes_fall_back_to_ko(raw: str | None) -> None:
    """Visitor locales are NOT API languages; unknown values degrade to ko.

    The Flutter seam maps ja/zh-* to `en` before the request, so a raw visitor
    code reaching the API means a non-conforming client — the documented
    fallback (ko) applies instead of an error or a third language.
    """
    assert normalize_language(raw) == "ko"


@pytest.mark.parametrize(
    "raw,expected",
    [("ko", "Korean"), ("en", "English"), ("ja", "Korean"), ("zh-Hant", "Korean")],
)
def test_display_language_stays_binary(raw: str, expected: str) -> None:
    assert display_language(raw) == expected


def test_places_reason_localization_is_binary(client, auth_headers, monkeypatch):
    """The reason composer must never mix languages within one response.

    This pins the PR #137 contract the V6 seam depends on: `language=en`
    composes English phrases, `language=ko` composes Korean phrases, so a
    visitor-locale client (which requests `en`) never receives Korean copy.
    """
    from apps.api.app.services.places_service import (
        _upstream_source_reason_phrase,
        _weather_band_phrase,
    )

    for upstream in ("tour_api", "kcisa", "kopis"):
        en = _upstream_source_reason_phrase(upstream, language="en")
        ko = _upstream_source_reason_phrase(upstream, language="ko")
        assert en and not any("데이터" in part for part in [en])
        assert ko and ko != en

    weather = {"temp": "30", "outdoor_status": "normal"}
    en_weather = _weather_band_phrase(weather, category="attraction", language="en")
    ko_weather = _weather_band_phrase(weather, category="attraction", language="ko")
    assert en_weather == "Hot weather"
    assert ko_weather == "더운 날씨"


def test_places_endpoint_accepts_en_without_korean_leak(client, auth_headers):
    """End-to-end: `language=en` responses carry no Korean reason fragments."""
    response = client.get(
        "/api/v1/places?lat=37.2636&lng=127.0286&radius_m=50000&language=en",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["query"]["language"] == "en"
    for place in body["data"]["places"]:
        reason = place.get("reason") or ""
        assert "데이터" not in reason, reason
        assert "날씨" not in reason, reason


def test_places_endpoint_still_serves_korean_for_ko(client, auth_headers):
    """ko keeps its existing behavior — the visitor work must not regress it."""
    response = client.get(
        "/api/v1/places?lat=37.2636&lng=127.0286&radius_m=50000&language=ko",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["query"]["language"] == "ko"
    assert body["data"]["count"] >= 0
