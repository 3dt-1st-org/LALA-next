from __future__ import annotations

import os
import shutil
import subprocess
from functools import lru_cache
from pathlib import Path

import pytest


@lru_cache(maxsize=1)
def usable_bash() -> str:
    candidates: list[str] = []
    if os.name == "nt":
        for root in (
            os.environ.get("ProgramFiles"),
            os.environ.get("ProgramW6432"),
            os.environ.get("ProgramFiles(x86)"),
        ):
            if not root:
                continue
            candidates.extend(
                [
                    str(Path(root) / "Git" / "bin" / "bash.exe"),
                    str(Path(root) / "Git" / "usr" / "bin" / "bash.exe"),
                ]
            )
    path_bash = shutil.which("bash")
    if path_bash:
        candidates.append(path_bash)

    seen: set[str] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        try:
            result = subprocess.run(
                [candidate, "-lc", "printf ok"],
                text=True,
                capture_output=True,
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode == 0 and result.stdout == "ok":
            return candidate

    pytest.skip("usable bash is not available")
