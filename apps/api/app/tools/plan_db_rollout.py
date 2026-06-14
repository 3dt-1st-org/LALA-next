from __future__ import annotations

import argparse
import json
import sys

from apps.api.app.services.db_rollout_plan import (
    DEFAULT_ADMIN_USER,
    DEFAULT_DATABASE_NAME,
    DEFAULT_KEY_VAULT_NAME,
    DEFAULT_LOCATION,
    DEFAULT_POSTGRES_SERVER_NAME,
    DEFAULT_RESOURCE_GROUP,
    DEFAULT_SKU_NAME,
    DEFAULT_STORAGE_SIZE_GB,
    DEFAULT_SUBSCRIPTION_ID,
    DEFAULT_TIER,
    build_db_rollout_plan,
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan an approved LALA-next PostgreSQL rollout without creating resources."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--subscription-id", default=DEFAULT_SUBSCRIPTION_ID)
    parser.add_argument("--resource-group", default=DEFAULT_RESOURCE_GROUP)
    parser.add_argument("--location", default=DEFAULT_LOCATION)
    parser.add_argument("--key-vault-name", default=DEFAULT_KEY_VAULT_NAME)
    parser.add_argument("--postgres-server-name", default=DEFAULT_POSTGRES_SERVER_NAME)
    parser.add_argument("--database-name", default=DEFAULT_DATABASE_NAME)
    parser.add_argument("--admin-user", default=DEFAULT_ADMIN_USER)
    parser.add_argument("--sku-name", default=DEFAULT_SKU_NAME)
    parser.add_argument("--tier", default=DEFAULT_TIER)
    parser.add_argument("--storage-size-gb", type=int, default=DEFAULT_STORAGE_SIZE_GB)
    parser.add_argument(
        "--public-access",
        default="None",
        help="Azure public-access value for the plan. Default creates no broad firewall rule.",
    )
    args = parser.parse_args(argv)

    plan = build_db_rollout_plan(
        subscription_id=args.subscription_id,
        resource_group=args.resource_group,
        location=args.location,
        key_vault_name=args.key_vault_name,
        postgres_server_name=args.postgres_server_name,
        database_name=args.database_name,
        admin_user=args.admin_user,
        sku_name=args.sku_name,
        tier=args.tier,
        storage_size_gb=args.storage_size_gb,
        public_access=args.public_access,
    )
    payload = plan.to_dict()
    _write(args, payload)
    return 0 if plan.ok else 2


def _write(args: argparse.Namespace, payload: dict) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next DB rollout plan")
    print("mode=plan")
    print("applies_changes=false")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"resource_group={payload.get('resource_group')}")
    print(f"location={payload.get('location')}")
    print(f"key_vault={payload.get('key_vault_name')}")
    print(f"postgres_server={payload.get('postgres_server_name')}")
    print(f"database={payload.get('database_name')}")
    print(f"canonical_sql_files={payload.get('canonical_sql', {}).get('file_count', 0)}")
    for warning in payload.get("warnings") or []:
        print(f"warning={warning}")
    for step in payload.get("steps") or []:
        print(f"step={step['order']} approval_required={str(step['approval_required']).lower()} {step['title']}")
        print(f"command={step['command']}")


if __name__ == "__main__":
    sys.exit(main())
