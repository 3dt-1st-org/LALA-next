from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from apps.api.app.main import create_app
from apps.api.app.services.flutter_client_contract import check_flutter_client_contract


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Check the reference Flutter client against the current OpenAPI contract."
    )
    parser.add_argument(
        "--client-path",
        default="clients/flutter/lib/lala_api_client.dart",
        help="Path to the Dart client file.",
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    args = parser.parse_args(argv)

    report = check_flutter_client_contract(
        openapi_schema=create_app().openapi(),
        client_path=Path(args.client_path).resolve(),
    )
    payload = report.to_dict()
    _write(args, payload)
    return 0 if report.ok else 2


def _write(args: argparse.Namespace, payload: dict) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next Flutter client contract check")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"client_path={payload.get('client_path', '')}")
    print(f"checked_route_count={len(payload.get('checked_routes') or [])}")
    for finding in payload.get("findings") or []:
        print(f"finding={finding}")


if __name__ == "__main__":
    sys.exit(main())
