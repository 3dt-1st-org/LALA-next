from __future__ import annotations

import urllib.parse

from apps.api.app.core.redaction import redact_secret_text


def test_redact_secret_text_masks_dsn_credentials():
    password = "example" + "-password"  # pragma: allowlist secret
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    assert password not in redact_secret_text(dsn)
    assert "user" not in redact_secret_text(dsn)


def test_redact_secret_text_masks_password_query_param():
    password = "example" + "-password"  # pragma: allowlist secret
    text = "connection failed: password=" + password + ";host=db"
    result = redact_secret_text(text)
    assert password not in result
    assert "password=***" in result


def test_redact_secret_text_masks_service_key_query_param():
    # F2: requests.HTTPError embeds the full request URL (including
    # serviceKey=...) in its message; this is the defense-in-depth mask so any
    # such text is scrubbed regardless of how it reaches redact_secret_text.
    text = "https://apis.data.go.kr/x?serviceKey=my-super-secret-key&pageNo=1"
    result = redact_secret_text(text)
    assert "my-super-secret-key" not in result
    assert "serviceKey=***" in result


def test_redact_secret_text_masks_percent_encoded_service_key():
    # requests percent-encodes query values; a raw-literal-only redaction
    # would miss an encoded key containing +, /, or = characters.
    key = "abc+DEF/ghi=="
    encoded = urllib.parse.quote(key, safe="")
    text = f"https://apis.data.go.kr/x?serviceKey={encoded}&pageNo=1"
    result = redact_secret_text(text)
    assert encoded not in result
    assert key not in result
    assert "serviceKey=***" in result


def test_redact_secret_text_masks_service_key_variants_case_insensitively():
    for variant in ("ServiceKey", "SERVICE_KEY", "service-key", "servicekey"):
        text = f"error: {variant}=abc123 rejected"
        result = redact_secret_text(text)
        assert "abc123" not in result


def test_redact_secret_text_still_applies_explicit_values():
    result = redact_secret_text("token=abc123", ("abc123",))
    assert "abc123" not in result
    assert "[redacted]" in result
