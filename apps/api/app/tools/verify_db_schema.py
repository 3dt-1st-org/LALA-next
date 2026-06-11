from __future__ import annotations

import argparse
import json
import os
import re
import sys

from apps.api.app.core.config import get_settings
from apps.api.app.services.db_schema import inspect_canonical_schema


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify the LALA-next canonical DB schema.")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--connect-timeout", type=int, default=5)
    args = parser.parse_args(argv)

    dsn = os.getenv("DB_DSN") or get_settings().db_dsn
    if not dsn:
        _write(args, {"ok": False, "error": "DB_DSN is not configured."})
        return 2

    try:
        report = inspect_canonical_schema(dsn=dsn, connect_timeout=args.connect_timeout)
    except Exception as exc:
        _write(args, {"ok": False, "error": _safe_error(exc, dsn)})
        return 2

    payload = report.to_dict()
    _write(args, payload)
    return 0 if report.ok else 2


def _write(args: argparse.Namespace, payload: dict) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next DB schema verification")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return
    missing = payload.get("missing") or {}
    for group in ("extensions", "schemas", "relations"):
        values = missing.get(group) or []
        if values:
            print(f"missing_{group}={','.join(values)}")
        else:
            print(f"missing_{group}=none")


def _safe_error(exc: Exception, dsn: str) -> str:
    message = str(exc) or exc.__class__.__name__
    if dsn:
        message = message.replace(dsn, "[redacted DB_DSN]")
    message = re.sub(
        r"(postgres(?:ql)?://)([^:\s/@]+):([^@\s]+)@",
        r"\1***:***@",
        message,
        flags=re.IGNORECASE,
    )
    message = re.sub(r"(password=)([^ \t\r\n;]+)", r"\1***", message, flags=re.IGNORECASE)
    return message


if __name__ == "__main__":
    sys.exit(main())
