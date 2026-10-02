"""Fail a preview handoff when Flutter's generated static assets are missing."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def verify(root: Path) -> None:
    root = root.resolve()
    required = [
        "index.html",
        "flutter_bootstrap.js",
        "main.dart.js",
        "manifest.json",
        "auth-callback.html",
        "assets/FontManifest.json",
    ]
    for name in required:
        path = root / name
        if not path.is_file() or not path.stat().st_size:
            raise ValueError(f"Missing or empty web asset: {name}")
    manifest = json.loads((root / "assets/FontManifest.json").read_text(encoding="utf-8"))
    families = {entry["family"] for entry in manifest}
    for family in (
        "MaterialIcons",
        "packages/cupertino_icons/CupertinoIcons",
        "Pretendard",
        "NotoSansCJK",
    ):
        if family not in families:
            raise ValueError(f"Missing font family: {family}")
    count = 0
    for entry in manifest:
        for font in entry["fonts"]:
            path = (root / "assets" / font["asset"]).resolve()
            if not path.is_relative_to(root) or not path.is_file() or not path.stat().st_size:
                raise ValueError(f"Missing or invalid font file for {entry['family']}")
            count += 1
    # These are the explicit UI illustrations, not remote place photography.
    illustrations = (
        "docent-listening",
        "lala-guide-travel-v2",
        "location-soft-route",
        "login-dark-refined",
        "login-light-refined",
        "settings-docent-hanok",
        "settings-location-map",
        "traditional-pattern",
    )
    for name in illustrations:
        path = root / "assets/assets/images/onboarding" / f"{name}.png"
        if not path.is_file() or not path.stat().st_size:
            raise ValueError(f"Missing or empty illustration: {name}")
    print(f"Web entrypoints, {count} fonts and {len(illustrations)} illustrations verified.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build_directory", type=Path)
    try:
        verify(parser.parse_args().build_directory)
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(1, f"Web asset validation failed: {error}\n")
