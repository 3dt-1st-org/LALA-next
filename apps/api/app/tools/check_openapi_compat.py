from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from apps.api.app.main import create_app
from apps.api.app.services.openapi_compat import compare_openapi_compatibility


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Check whether the current OpenAPI schema is backward-compatible with a baseline snapshot."
    )
    parser.add_argument("baseline", help="Path to a baseline OpenAPI JSON snapshot.")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    args = parser.parse_args(argv)

    baseline_path = Path(args.baseline).resolve()
    try:
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    except Exception as exc:
        _write(args, {"ok": False, "error": f"Could not read baseline OpenAPI JSON: {exc}"})
        return 2

    current = create_app().openapi()
    report = compare_openapi_compatibility(baseline=baseline, current=current)
    payload = report.to_dict() | {"baseline": str(baseline_path)}
    _write(args, payload)
    return 0 if report.ok else 2


def _write(args: argparse.Namespace, payload: dict) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next OpenAPI compatibility check")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"baseline_path_count={payload.get('baseline_path_count', 0)}")
    print(f"current_path_count={payload.get('current_path_count', 0)}")
    if payload.get("error"):
        print(f"error={payload['error']}")
    for finding in payload.get("findings") or []:
        print(f"finding={finding}")


if __name__ == "__main__":
    sys.exit(main())
