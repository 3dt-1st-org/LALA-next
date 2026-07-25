"""Focused tests for the official-source bounded failure contract."""

from __future__ import annotations

import pytest

from apps.api.app.services import official_source_errors as errors


def test_every_category_has_a_fixed_reason():
    for category in (
        "auth",
        "http_status",
        "malformed_response",
        "empty",
        "window_too_wide",
        "unavailable",
    ):
        assert category in errors.REASON_BY_CATEGORY
        assert errors.REASON_BY_CATEGORY[category]


def test_error_message_uses_fixed_reason_and_source():
    exc = errors.OfficialSourceError(
        category="malformed_response",
        source="tour_api",
        bounded_code="ERR010",
    )
    message = str(exc)
    assert "tour_api" in message
    assert errors.REASON_BY_CATEGORY["malformed_response"] in message
    assert "code=ERR010" in message
    assert exc.category == "malformed_response"
    assert exc.source == "tour_api"


def test_error_does_not_embed_unbounded_code_tokens():
    # A free-text "code" must not be appended (only short bounded tokens are).
    exc = errors.OfficialSourceError(
        category="auth",
        source="kopis",
        bounded_code="a raw upstream sentence with spaces and punctuation!",
    )
    assert "raw upstream sentence" not in str(exc)


@pytest.mark.parametrize("code", [None, "", "0"])
def test_zero_or_missing_result_code_does_not_raise(code):
    errors.raise_for_official_result_code(
        source="tour_api",
        result_code=code,
        result_message="anything",
    )


def test_nonzero_result_code_classifies_auth_without_leaking_message():
    raw_message = "ServiceKey is invalid (echoed-token-do-not-leak)"
    with pytest.raises(errors.OfficialSourceError) as info:
        errors.raise_for_official_result_code(
            source="kopis",
            result_code="020",
            result_message=raw_message,
        )
    assert info.value.category == "auth"
    message = str(info.value)
    # The raw upstream message -- which can carry key-shaped text -- is never echoed.
    assert "echoed-token-do-not-leak" not in message
    assert "ServiceKey" not in message
    assert "code=020" in message


def test_nonzero_result_code_without_auth_signal_is_malformed():
    with pytest.raises(errors.OfficialSourceError) as info:
        errors.raise_for_official_result_code(
            source="kcisa",
            result_code="500",
            result_message="some internal upstream detail",
        )
    assert info.value.category == "malformed_response"
    assert "internal upstream detail" not in str(info.value)


@pytest.mark.parametrize("status", [None, 200, 201, 204, 299])
def test_success_http_status_does_not_raise(status):
    errors.raise_for_official_http_status(source="tour_api", status_code=status)


@pytest.mark.parametrize(
    "status,category",
    [
        (401, "auth"),
        (403, "auth"),
        (400, "malformed_response"),
        (404, "malformed_response"),
        (500, "unavailable"),
        (503, "unavailable"),
    ],
)
def test_http_status_maps_to_bounded_category(status, category):
    with pytest.raises(errors.OfficialSourceError) as info:
        errors.raise_for_official_http_status(source="tour_api", status_code=status)
    assert info.value.category == category
    assert f"code={status}" in str(info.value)


def test_other_http_status_falls_back_to_http_status_category():
    with pytest.raises(errors.OfficialSourceError) as info:
        errors.raise_for_official_http_status(source="tour_api", status_code=399)
    assert info.value.category == "http_status"
