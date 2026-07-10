from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "deploy" / "vercel" / "flutter-static.vercel.json"
DEFAULT_SOURCE = ROOT / "apps" / "flutter_app" / "build" / "web"
DEFAULT_OUTPUT = ROOT / "static-output"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Stage Flutter web assets with the isolated Vercel static config."
    )
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    source = args.source.resolve()
    output = args.output.resolve()
    _validate_paths(parser, source=source, output=output)
    template = _load_static_template()

    if output.exists():
        shutil.rmtree(output)
    shutil.copytree(source, output)
    (output / "vercel.json").write_text(
        json.dumps(template, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Staged Flutter Vercel output: {output}")
    return 0


def _validate_paths(
    parser: argparse.ArgumentParser,
    *,
    source: Path,
    output: Path,
) -> None:
    if not (source / "index.html").is_file():
        parser.error(f"Flutter web build is missing index.html: {source}")
    if output == ROOT or output == source or source in output.parents or output in source.parents:
        parser.error("Output must be separate from the repository root and source build.")


def _load_static_template() -> dict:
    template = json.loads(TEMPLATE.read_text(encoding="utf-8"))
    if "/api/index.py" in json.dumps(template):
        raise RuntimeError("Flutter Vercel template must not contain the Python API rewrite.")
    return template


if __name__ == "__main__":
    raise SystemExit(main())
