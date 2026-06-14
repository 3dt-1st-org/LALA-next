from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from apps.workers.app.contracts import (
    WorkerExecutionError,
    evaluate_worker_live_preflight,
    list_worker_jobs,
    run_worker_job,
)
from apps.workers.app.rollout_plan import (
    DEFAULT_BASE_URL,
    DEFAULT_EVENT_HUB_NAME,
    DEFAULT_EVENT_HUB_NAMESPACE,
    DEFAULT_FUNCTION_APP_NAME,
    DEFAULT_KEY_VAULT_NAME,
    DEFAULT_LOCATION,
    DEFAULT_RESOURCE_GROUP,
    DEFAULT_STORAGE_ACCOUNT_NAME,
    DEFAULT_SUBSCRIPTION_ID,
    build_worker_rollout_plan,
)


def _write_json(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="lala-next-workers",
        description="LALA-next worker boundary CLI. Wave 1 supports dry-run contracts only.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="List worker job contracts.")
    list_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")

    run_parser = subparsers.add_parser("run", help="Run a worker job contract.")
    run_parser.add_argument("job_id", help="Worker job id.")
    run_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    mode_group = run_parser.add_mutually_exclusive_group()
    mode_group.add_argument(
        "--dry-run",
        action="store_true",
        help="Evaluate the job contract without external reads or writes. This is the default.",
    )
    mode_group.add_argument(
        "--execute",
        action="store_true",
        help="Attempt live execution. Blocked in Wave 1 unless an explicit later implementation exists.",
    )

    preflight_parser = subparsers.add_parser(
        "preflight",
        help="Evaluate live worker rollout prerequisites without external reads or writes.",
    )
    preflight_parser.add_argument("--job-id", default="", help="Limit preflight to one worker job.")
    preflight_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")

    rollout_parser = subparsers.add_parser(
        "plan-rollout",
        help="Plan worker live rollout gates without creating resources or enabling mutation.",
    )
    rollout_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    rollout_parser.add_argument("--subscription-id", default=DEFAULT_SUBSCRIPTION_ID)
    rollout_parser.add_argument("--resource-group", default=DEFAULT_RESOURCE_GROUP)
    rollout_parser.add_argument("--location", default=DEFAULT_LOCATION)
    rollout_parser.add_argument("--key-vault-name", default=DEFAULT_KEY_VAULT_NAME)
    rollout_parser.add_argument("--function-app-name", default=DEFAULT_FUNCTION_APP_NAME)
    rollout_parser.add_argument("--storage-account-name", default=DEFAULT_STORAGE_ACCOUNT_NAME)
    rollout_parser.add_argument("--event-hub-namespace", default=DEFAULT_EVENT_HUB_NAMESPACE)
    rollout_parser.add_argument("--event-hub-name", default=DEFAULT_EVENT_HUB_NAME)
    rollout_parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.command == "list":
        jobs = list_worker_jobs()
        payload = {
            "ok": True,
            "jobs": jobs,
            "meta": {"count": len(jobs)},
        }
        if args.json:
            _write_json(payload)
        else:
            for job in jobs:
                print(f"{job['job_id']}: {job['description']}")
        return 0

    if args.command == "run":
        dry_run = not args.execute
        try:
            result = run_worker_job(args.job_id, dry_run=dry_run)
        except WorkerExecutionError as exc:
            payload = {
                "ok": False,
                "error": {"code": exc.code, "message": exc.message},
                "meta": {"job_id": args.job_id},
            }
            if args.json:
                _write_json(payload)
            else:
                print(f"{exc.code}: {exc.message}", file=sys.stderr)
            return 2

        if args.json:
            _write_json(result)
        else:
            print(f"{result['job']['job_id']} {result['mode']} completed.")
        return 0

    if args.command == "preflight":
        try:
            result = evaluate_worker_live_preflight(job_id=args.job_id or None)
        except WorkerExecutionError as exc:
            payload = {
                "ok": False,
                "error": {"code": exc.code, "message": exc.message},
                "meta": {"job_id": args.job_id},
            }
            if args.json:
                _write_json(payload)
            else:
                print(f"{exc.code}: {exc.message}", file=sys.stderr)
            return 2

        if args.json:
            _write_json(result)
        else:
            print(f"worker_live_ready={str(result['ready']).lower()}")
            for check in result["global_checks"]:
                print(f"check={check['name']} status={check['status']}")
            for job in result["jobs"]:
                print(f"job={job['job_id']} ready={str(job['ready']).lower()}")
        return 0

    if args.command == "plan-rollout":
        plan = build_worker_rollout_plan(
            subscription_id=args.subscription_id,
            resource_group=args.resource_group,
            location=args.location,
            key_vault_name=args.key_vault_name,
            function_app_name=args.function_app_name,
            storage_account_name=args.storage_account_name,
            event_hub_namespace=args.event_hub_namespace,
            event_hub_name=args.event_hub_name,
            base_url=args.base_url,
        )
        payload = plan.to_dict()
        if args.json:
            _write_json(payload)
        else:
            print("LALA-next worker rollout plan")
            print("mode=plan")
            print(f"applies_changes={str(payload['applies_changes']).lower()}")
            print(f"status={'ok' if payload.get('ok') else 'degraded'}")
            print(f"key_vault={payload.get('key_vault_name')}")
            print(f"function_app={payload.get('function_app_name')}")
            print(f"storage_account={payload.get('storage_account_name')}")
            print(f"event_hub_namespace={payload.get('event_hub_namespace')}")
            print(f"worker_job_count={len(payload.get('worker_jobs') or [])}")
            for warning in payload.get("warnings") or []:
                print(f"warning={warning}")
            for step in payload.get("steps") or []:
                print(
                    f"step={step['order']} approval_required="
                    f"{str(step['approval_required']).lower()} {step['title']}"
                )
                print(f"command={step['command']}")
        return 0 if plan.ok else 2

    parser.error("unknown command")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
