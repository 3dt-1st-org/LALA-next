from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from apps.workers.app.contracts import (
    WorkerExecutionError,
    list_worker_jobs,
    run_worker_job,
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

    parser.error("unknown command")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
