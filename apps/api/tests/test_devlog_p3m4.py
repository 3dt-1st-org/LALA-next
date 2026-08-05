from __future__ import annotations

from pathlib import Path


def _get_devlog_path() -> Path:
    """Get the path to the P3-M4 devlog."""
    # The test file is in apps/api/tests/, need to go to repo root
    current = Path(__file__).resolve()
    # Go up from apps/api/tests/ to repo root
    repo_root = current.parent.parent.parent.parent
    return repo_root / "docs/devlogs/p3-m4-review-replay.md"


def test_p3m4_devlog_has_no_trailing_whitespace():
    """Test that P3-M4 devlog has no trailing whitespace."""
    devlog_path = _get_devlog_path()
    content = devlog_path.read_text(encoding="utf-8")
    lines = content.split("\n")

    for line_no, line in enumerate(lines, start=1):
        assert line == line.rstrip(), f"Line {line_no} has trailing whitespace: {repr(line)}"


def test_p3m4_devlog_references_only_pr_102():
    """Test that P3-M4 devlog references only PR #102."""
    devlog_path = _get_devlog_path()
    content = devlog_path.read_text(encoding="utf-8")

    # Should contain PR: #102
    assert "#102" in content

    # Should not contain any other PR numbers like #96
    assert "#96" not in content
    assert "#95" not in content
    assert "#94" not in content
    assert "#97" not in content
    assert "#98" not in content
    assert "#99" not in content
    assert "#100" not in content
    assert "#101" not in content
    assert "#103" not in content
