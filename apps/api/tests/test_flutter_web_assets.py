import json

import pytest

from scripts.verify_flutter_web_assets import verify


def complete_build(root):
    for name in (
        "index.html",
        "flutter_bootstrap.js",
        "main.dart.js",
        "manifest.json",
        "auth-callback.html",
    ):
        (root / name).write_text("fixture", encoding="utf-8")
    assets = root / "assets"
    assets.mkdir()
    fonts = []
    for family in (
        "MaterialIcons",
        "packages/cupertino_icons/CupertinoIcons",
        "Pretendard",
        "NotoSansCJK",
    ):
        name = family.replace("/", "_") + ".ttf"
        (assets / name).write_bytes(b"fixture")
        fonts.append({"family": family, "fonts": [{"asset": name}]})
    (assets / "FontManifest.json").write_text(json.dumps(fonts), encoding="utf-8")
    images = assets / "assets/images/onboarding"
    images.mkdir(parents=True)
    for name in (
        "docent-listening",
        "lala-guide-travel-v2",
        "location-soft-route",
        "login-dark-refined",
        "login-light-refined",
        "settings-docent-hanok",
        "settings-location-map",
        "traditional-pattern",
    ):
        (images / f"{name}.png").write_bytes(b"fixture")
    return images


def test_missing_illustration_fails_even_with_complete_fonts(tmp_path):
    images = complete_build(tmp_path)
    verify(tmp_path)
    (images / "docent-listening.png").unlink()
    with pytest.raises(ValueError, match="Missing or empty illustration"):
        verify(tmp_path)


def test_font_cannot_escape_build_directory(tmp_path):
    complete_build(tmp_path)
    manifest = tmp_path / "assets/FontManifest.json"
    fonts = json.loads(manifest.read_text(encoding="utf-8"))
    fonts[0]["fonts"][0]["asset"] = "../../outside.ttf"
    manifest.write_text(json.dumps(fonts), encoding="utf-8")
    with pytest.raises(ValueError, match="Missing or invalid font"):
        verify(tmp_path)
