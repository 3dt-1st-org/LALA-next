from __future__ import annotations

import argparse
import json
import sys

from apps.api.app.services.identity_rollout_plan import (
    DEFAULT_API_APP_ID_URI,
    DEFAULT_API_APP_NAME,
    DEFAULT_BASE_URL,
    DEFAULT_FLUTTER_APP_NAME,
    DEFAULT_KEY_VAULT_NAME,
    DEFAULT_REQUIRED_SCOPES,
    build_identity_rollout_plan,
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan LALA-next OAuth/Entra identity rollout without applying changes."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--key-vault-name", default=DEFAULT_KEY_VAULT_NAME)
    parser.add_argument("--api-app-name", default=DEFAULT_API_APP_NAME)
    parser.add_argument("--flutter-app-name", default=DEFAULT_FLUTTER_APP_NAME)
    parser.add_argument("--api-app-id-uri", default=DEFAULT_API_APP_ID_URI)
    parser.add_argument(
        "--required-scope",
        action="append",
        default=None,
        help="Delegated scope name to include. Repeat for multiple scopes.",
    )
    args = parser.parse_args(argv)

    plan = build_identity_rollout_plan(
        key_vault_name=args.key_vault_name,
        api_app_name=args.api_app_name,
        flutter_app_name=args.flutter_app_name,
        api_app_id_uri=args.api_app_id_uri,
        required_scopes=tuple(args.required_scope or DEFAULT_REQUIRED_SCOPES),
        base_url=args.base_url,
    )
    payload = plan.to_dict()
    _write(args, payload)
    return 0 if plan.ok else 2


def _write(args: argparse.Namespace, payload: dict) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next identity rollout plan")
    print("mode=plan")
    print("applies_changes=false")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"key_vault={payload.get('key_vault_name')}")
    print(f"api_app_name={payload.get('api_app_name')}")
    print(f"flutter_app_name={payload.get('flutter_app_name')}")
    print(f"api_app_id_uri={payload.get('api_app_id_uri')}")
    print(f"required_scope_count={len(payload.get('required_scopes') or [])}")
    print(f"readiness_check_count={len(payload.get('readiness_checks') or [])}")
    for warning in payload.get("warnings") or []:
        print(f"warning={warning}")
    for step in payload.get("steps") or []:
        print(f"step={step['order']} approval_required={str(step['approval_required']).lower()} {step['title']}")
        print(f"command={step['command']}")


if __name__ == "__main__":
    sys.exit(main())
