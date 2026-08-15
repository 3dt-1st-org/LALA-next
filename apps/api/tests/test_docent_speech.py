from __future__ import annotations

from apps.api.app.services.speech_service import strip_markdown_for_tts


def test_tts_sanitizer_strips_emphasis_and_links():
    """F2: markdown symbols must never reach the TTS input."""
    script = (
        "# Heading\n"
        "**Suwon Hwaseong** is a *fortress* with __walls__.\n"
        "- bullet one\n"
        "1. ordered item\n"
        "See [the guide](https://example.invalid/guide) for details.\n"
        "```\ncode fence\n```\n"
        "`inline` code ends."
    )

    spoken = strip_markdown_for_tts(script)

    assert "**" not in spoken
    assert "*" not in spoken
    assert "__" not in spoken
    assert "#" not in spoken
    assert "[" not in spoken and "]" not in spoken
    assert "https://" not in spoken
    assert "```" not in spoken
    assert "`" not in spoken
    # The words survive; only the markup is removed.
    assert "Suwon Hwaseong" in spoken
    assert "fortress" in spoken
    assert "the guide" in spoken
    assert "bullet one" in spoken


def test_tts_sanitizer_leaves_plain_text_untouched():
    plain = "수원화성은 조선 후기에 건축된 성곽입니다. 동문을 먼저 보세요."
    assert strip_markdown_for_tts(plain) == plain


def test_tts_sanitizer_collapses_blank_lines_left_by_block_markers():
    cleaned = strip_markdown_for_tts("# A\n\n\n\nB")
    assert cleaned == "A\n\nB"
