from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "deploy" / "vercel" / "flutter-static.vercel.json"
DEFAULT_SOURCE = ROOT / "apps" / "flutter_app" / "build" / "web"
DEFAULT_OUTPUT = ROOT / "static-output"
REQUIRED_BUILD_ARTIFACTS = (
    Path("index.html"),
    Path("flutter_bootstrap.js"),
    Path("main.dart.js"),
    Path("assets/AssetManifest.bin.json"),
    Path("auth-callback.html"),
)
VERCEL_ID_PATTERN = re.compile(r"[A-Za-z0-9_-]{3,128}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Stage Flutter web assets with the isolated Vercel static config."
    )
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument(
        "--verify-project-binding",
        action="store_true",
        help="Validate the staged config and project binding without modifying output.",
    )
    args = parser.parse_args(argv)

    output = DEFAULT_OUTPUT
    try:
        _validate_output_boundary(output)
        project_binding = _load_project_binding()
        template = _load_static_template()
        if args.verify_project_binding:
            _verify_staged_contract(
                output=output,
                template=template,
                project_binding=project_binding,
            )
            print(f"Verified Flutter Vercel staging contract: {output}")
            return 0
        source = _validate_source(source=args.source, output=output)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        parser.error(str(exc))

    if output.exists():
        shutil.rmtree(output)
    shutil.copytree(source, output)
    _write_json(output / "vercel.json", template)
    project_directory = output / ".vercel"
    if project_directory.exists():
        shutil.rmtree(project_directory)
    project_directory.mkdir()
    _write_json(project_directory / "project.json", project_binding)
    _verify_staged_contract(
        output=output,
        template=template,
        project_binding=project_binding,
    )
    print(f"Staged Flutter Vercel output: {output}")
    return 0


def _validate_output_boundary(output: Path) -> None:
    root = ROOT.resolve()
    expected_output = root / "static-output"
    lexical_output = output.absolute()
    if lexical_output != expected_output or output != DEFAULT_OUTPUT:
        raise ValueError("Output must be the repository static-output directory.")
    if output.is_symlink():
        raise ValueError("Output must not be a symlink.")
    if output.exists() and not output.is_dir():
        raise ValueError("Output must be a directory when it already exists.")
    resolved_output = output.resolve()
    if resolved_output != expected_output or root not in resolved_output.parents:
        raise ValueError("Output resolves outside the repository staging boundary.")


def _validate_source(*, source: Path, output: Path) -> Path:
    source_metadata = source.lstat()
    if stat.S_ISLNK(source_metadata.st_mode):
        raise ValueError("Flutter web build source must not be a symlink.")
    if not stat.S_ISDIR(source_metadata.st_mode):
        raise ValueError("Flutter web build source must be a directory.")

    resolved_source = source.resolve()
    resolved_output = output.resolve()
    if (
        resolved_output == resolved_source
        or resolved_source in resolved_output.parents
        or resolved_output in resolved_source.parents
    ):
        raise ValueError("Output must be separate from the source build.")
    _reject_source_tree_symlinks(resolved_source)
    _validate_required_artifacts(resolved_source, "Flutter web build")
    return resolved_source


def _reject_source_tree_symlinks(directory: Path) -> None:
    with os.scandir(directory) as entries:
        for entry in entries:
            metadata = entry.stat(follow_symlinks=False)
            if stat.S_ISLNK(metadata.st_mode):
                raise ValueError(f"Flutter web build must not contain symlinks: {entry.path}")
            if stat.S_ISDIR(metadata.st_mode):
                _reject_source_tree_symlinks(Path(entry.path))


def _validate_required_artifacts(directory: Path, label: str) -> None:
    invalid = [
        str(relative_path)
        for relative_path in REQUIRED_BUILD_ARTIFACTS
        if not _is_regular_file(directory / relative_path)
    ]
    if invalid:
        raise ValueError(f"{label} artifact must be a non-symlink regular file: {invalid[0]}")


def _is_regular_file(path: Path) -> bool:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return False
    return stat.S_ISREG(metadata.st_mode)


def _load_project_binding() -> dict[str, str]:
    binding: dict[str, str] = {}
    for environment_name, json_name in (
        ("VERCEL_ORG_ID", "orgId"),
        ("VERCEL_PROJECT_ID", "projectId"),
    ):
        value = os.environ.get(environment_name, "")
        if not VERCEL_ID_PATTERN.fullmatch(value):
            raise ValueError(f"{environment_name} must be set to a valid Vercel identifier.")
        binding[json_name] = value
    return binding


def _verify_staged_contract(
    *,
    output: Path,
    template: dict,
    project_binding: dict[str, str],
) -> None:
    _validate_output_boundary(output)
    if not output.is_dir():
        raise ValueError("Flutter Vercel staging output does not exist.")
    _validate_required_artifacts(output, "Staged Flutter output")
    effective_config = _read_json_object(output / "vercel.json", "Vercel config")
    if effective_config != template:
        raise ValueError("Staged Vercel config does not match the Flutter template.")
    effective_binding = _read_json_object(
        output / ".vercel" / "project.json",
        "Vercel project binding",
    )
    if effective_binding != project_binding:
        raise ValueError("Staged Vercel project binding does not match the environment.")


def _read_json_object(path: Path, label: str) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"{label} must be a JSON object.")
    return payload


def _write_json(path: Path, payload: dict) -> None:
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _load_static_template() -> dict:
    template = json.loads(TEMPLATE.read_text(encoding="utf-8"))
    if "/api/index.py" in json.dumps(template):
        raise RuntimeError("Flutter Vercel template must not contain the Python API rewrite.")
    return template


if __name__ == "__main__":
    raise SystemExit(main())
