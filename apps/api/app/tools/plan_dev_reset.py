from __future__ import annotations

import argparse
import json
import os
import sys

from apps.api.app.core.config import get_settings
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.dev_reset_sql import execute_dev_reset_sql, load_dev_reset_sql_plan

CONFIRM_TEXT = "APPLY_DEV_RESET_SQL"
ALLOW_ENV = "ALLOW_DEV_RESET_APPLY"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan or locally apply LALA-next dev seed/reset SQL."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument(
        "--apply", action="store_true", help="Apply dev reset SQL to a local DB_DSN."
    )
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument("--connect-timeout", type=int, default=5)
    args = parser.parse_args(argv)

    plan = load_dev_reset_sql_plan()
    if not plan.ok:
        _write(args, {"ok": False, "mode": "plan", "plan": plan.to_dict()})
        return 2

    if not args.apply:
        _write(args, {"ok": True, "mode": "plan", "plan": plan.to_dict()})
        return 0

    guard_error = _apply_guard_error(args)
    if guard_error:
        _write(args, {"ok": False, "mode": "apply", "error": guard_error, "plan": plan.to_dict()})
        return 2

    dsn = os.getenv("DB_DSN") or get_settings().db_dsn
    if not dsn:
        _write(
            args,
            {
                "ok": False,
                "mode": "apply",
                "error": "DB_DSN is not configured.",
                "plan": plan.to_dict(),
            },
        )
        return 2

    try:
        result = execute_dev_reset_sql(dsn=dsn, plan=plan, connect_timeout=args.connect_timeout)
    except Exception as exc:
        _write(
            args,
            {
                "ok": False,
                "mode": "apply",
                "error": redact_secret_text(str(exc) or exc.__class__.__name__, (dsn,)),
                "plan": plan.to_dict(),
            },
        )
        return 2

    _write(args, {"ok": True, "mode": "apply", "result": result, "plan": plan.to_dict()})
    return 0


def _apply_guard_error(args: argparse.Namespace) -> str:
    if args.confirm != CONFIRM_TEXT:
        return f"--apply requires --confirm {CONFIRM_TEXT}."
    if os.getenv(ALLOW_ENV) != "1":
        return f"--apply requires {ALLOW_ENV}=1 in the process environment."
    return ""


def _write(args: argparse.Namespace, payload: dict) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    plan = payload.get("plan") or {}
    print("LALA-next dev seed/reset SQL")
    print(f"mode={payload.get('mode')}")
    print("local_only=true")
    print("apply_supported=true")
    print(f"apply_scope={plan.get('apply_scope', 'local_only_guarded')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return
    print(f"file_count={plan.get('file_count', 0)}")
    print(f"statement_count={plan.get('statement_count', 0)}")
    for item in plan.get("files") or []:
        print(
            f"file={item['path']} sha256={item['sha256']} "
            f"statements={item['statement_count']} destructive_findings={len(item['destructive_findings'])}"
        )
    for finding in plan.get("safety_findings") or []:
        print(f"finding={finding}")
    result = payload.get("result") or {}
    for name in result.get("applied_files", []):
        print(f"applied={name}")


if __name__ == "__main__":
    sys.exit(main())
