from __future__ import annotations

import argparse
import json
from pathlib import Path

from apps.api.app.main import create_app


def export_openapi_schema(output_path: Path) -> dict:
    app = create_app()
    schema = app.openapi()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(schema, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return schema


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Export the LALA-next OpenAPI schema without starting a server."
    )
    parser.add_argument(
        "--output",
        default="artifacts/openapi/lala-next-openapi.json",
        help="Path to write the OpenAPI JSON file.",
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable status.")
    args = parser.parse_args(argv)

    output_path = Path(args.output).resolve()
    schema = export_openapi_schema(output_path)
    payload = {
        "ok": True,
        "output_path": str(output_path),
        "title": schema.get("info", {}).get("title", ""),
        "version": schema.get("info", {}).get("version", ""),
        "path_count": len(schema.get("paths", {})),
    }
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(f"OpenAPI schema written to {output_path}")
        print(f"path_count={payload['path_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
