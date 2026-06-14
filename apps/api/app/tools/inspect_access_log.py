from __future__ import annotations

import argparse
import json
import sys

from apps.api.app.services.access_log_inspector import inspect_access_log


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Inspect a local LALA-next JSONL access log without printing secrets."
    )
    parser.add_argument("path", help="Path to the local JSONL access log.")
    parser.add_argument("--request-id", default="", help="Filter by request id.")
    parser.add_argument("--route-path", default="", help="Filter by bounded route path.")
    parser.add_argument("--limit", type=int, default=20, help="Maximum records to print.")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    args = parser.parse_args(argv)

    inspection = inspect_access_log(
        args.path,
        request_id=args.request_id,
        route_path=args.route_path,
        limit=args.limit,
    )
    payload = inspection.to_dict()
    _write(args, payload)
    return 0 if payload["ok"] else 2


def _write(args: argparse.Namespace, payload: dict) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next access log inspection")
    print("mode=read-only")
    print("applies_changes=false")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"path={payload.get('path')}")
    print(f"total_lines={payload.get('total_lines')}")
    print(f"invalid_lines={payload.get('invalid_lines')}")
    print(f"matched_count={payload.get('matched_count')}")
    for warning in payload.get("warnings") or []:
        print(f"warning={warning}")
    for record in payload.get("records") or []:
        print(
            "record="
            f"request_id={record['request_id']} "
            f"method={record['method']} "
            f"path={record['path']} "
            f"status_code={record['status_code']} "
            f"duration_ms={record['duration_ms']} "
            f"client_host={record['client_host']}"
        )


if __name__ == "__main__":
    sys.exit(main())
