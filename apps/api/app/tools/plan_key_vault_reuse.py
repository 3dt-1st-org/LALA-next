from __future__ import annotations

import argparse
import json
import sys

from apps.api.app.services.key_vault_reuse_plan import (
    DEFAULT_SOURCE_VAULT_NAME,
    DEFAULT_TARGET_VAULT_NAME,
    build_key_vault_reuse_plan,
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan safe ONMU Key Vault reuse for LALA-next without applying changes."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--source-vault-name", default=DEFAULT_SOURCE_VAULT_NAME)
    parser.add_argument("--target-vault-name", default=DEFAULT_TARGET_VAULT_NAME)
    args = parser.parse_args(argv)

    plan = build_key_vault_reuse_plan(
        source_vault_name=args.source_vault_name,
        target_vault_name=args.target_vault_name,
    )
    payload = plan.to_dict()
    _write(args, payload)
    return 0 if plan.ok else 2


def _write(args: argparse.Namespace, payload: dict) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next Key Vault reuse plan")
    print("mode=plan")
    print("applies_changes=false")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"source_vault={payload.get('source_vault_name')}")
    print(f"target_vault={payload.get('target_vault_name')}")
    print(f"candidate_count={len(payload.get('candidate_secret_mappings') or [])}")
    print(f"rejected_pattern_count={len(payload.get('rejected_secret_patterns') or [])}")
    for warning in payload.get("warnings") or []:
        print(f"warning={warning}")
    for candidate in payload.get("candidate_secret_mappings") or []:
        print(
            "candidate="
            f"{candidate['source_secret_name']}->{candidate['target_secret_name']} "
            f"action={candidate['action']} "
            f"approval_required={str(candidate['approval_required']).lower()}"
        )
    for pattern in payload.get("rejected_secret_patterns") or []:
        print(f"reject_pattern={pattern['pattern']} reason={pattern['reason']}")
    for command in payload.get("verification_commands") or []:
        print(f"verify={command}")


if __name__ == "__main__":
    sys.exit(main())
