from __future__ import annotations

import argparse
import json
import sys

from apps.api.app.services.legacy_retirement_plan import (
    DEFAULT_BASE_URL,
    DEFAULT_FASTAPI_APP_LABEL,
    DEFAULT_LEGACY_APP_LABEL,
    build_legacy_retirement_plan,
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan legacy Flask replacement or retirement without applying changes."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--legacy-app-label", default=DEFAULT_LEGACY_APP_LABEL)
    parser.add_argument("--fastapi-app-label", default=DEFAULT_FASTAPI_APP_LABEL)
    args = parser.parse_args(argv)

    plan = build_legacy_retirement_plan(
        base_url=args.base_url,
        legacy_app_label=args.legacy_app_label,
        fastapi_app_label=args.fastapi_app_label,
    )
    payload = plan.to_dict()
    _write(args, payload)
    return 0 if plan.ok else 2


def _write(args: argparse.Namespace, payload: dict) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next legacy Flask retirement plan")
    print("mode=plan")
    print(f"applies_changes={str(payload['applies_changes']).lower()}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"legacy_app={payload.get('legacy_app_label')}")
    print(f"fastapi_app={payload.get('fastapi_app_label')}")
    print(f"route_mapping_count={len(payload.get('route_mappings') or [])}")
    for warning in payload.get("warnings") or []:
        print(f"warning={warning}")
    for step in payload.get("steps") or []:
        print(
            f"step={step['order']} approval_required={str(step['approval_required']).lower()} {step['title']}"
        )
        print(f"command={step['command']}")


if __name__ == "__main__":
    sys.exit(main())
