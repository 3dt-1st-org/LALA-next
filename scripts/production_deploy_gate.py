"""Decide whether completed CI may deploy production; no cloud access."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def should_deploy(event: dict, *, repository: str, current_main_sha: str) -> bool:
    run = event.get("workflow_run") or {}
    head = run.get("head_commit") or {}
    source = run.get("head_repository") or {}
    message = head.get("message") or ""
    return bool(
        repository
        and re.fullmatch(r"[0-9a-f]{40}", current_main_sha)
        and run.get("conclusion") == "success"
        and run.get("event") == "push"
        and run.get("head_branch") == "main"
        and source.get("full_name") == repository
        and run.get("head_sha") == current_main_sha
        and head.get("id") == current_main_sha
        and isinstance(message, str)
        and message.strip()
        and "[skip deploy]" not in message.lower()
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-file", type=Path, required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--main-sha", required=True)
    args = parser.parse_args()
    try:
        permitted = should_deploy(
            json.loads(args.event_file.read_text()),
            repository=args.repository,
            current_main_sha=args.main_sha,
        )
    except (OSError, ValueError, TypeError, AttributeError):
        permitted = False
    print(f"deploy={str(permitted).lower()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
