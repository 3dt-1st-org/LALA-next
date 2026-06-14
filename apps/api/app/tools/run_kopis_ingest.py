from __future__ import annotations

import argparse
import json
import os
from typing import Any

from dotenv import load_dotenv

from apps.api.app.core.key_vault import get_secret_if_configured
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.kopis_ingest import (
    DEFAULT_DATASET_NAME,
    DEFAULT_SIGNGUCODE,
    KOPIS_BASE_URL,
    KOPIS_OPERATION,
    default_date_window,
    fetch_kopis_performances,
    upsert_kopis_performances,
)

CONFIRM_TEXT = "APPLY_KOPIS_INGEST"
ALLOW_ENV = "ALLOW_KOPIS_INGEST_APPLY"

load_dotenv()


def main(argv: list[str] | None = None) -> int:
    default_stdate, default_eddate = default_date_window()
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply KOPIS performance ingestion into culture.events."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--preview", action="store_true", help="Call KOPIS and preview rows.")
    parser.add_argument("--apply", action="store_true", help="Upsert KOPIS rows into DB.")
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument("--stdate", default=default_stdate, help="Start date YYYYMMDD.")
    parser.add_argument("--eddate", default=default_eddate, help="End date YYYYMMDD. KOPIS supports up to 31 days.")
    parser.add_argument("--signgucode", default=DEFAULT_SIGNGUCODE, help="KOPIS 시도 code. Default 41=경기도.")
    parser.add_argument("--signgucodesub", default="", help="Optional KOPIS 시군구 code.")
    parser.add_argument("--prfstate", default="", help="Optional KOPIS performance state code.")
    parser.add_argument("--rows", type=int, default=20)
    parser.add_argument("--page-size", type=int, default=10)
    parser.add_argument("--timeout", type=int, default=10)
    parser.add_argument("--connect-timeout", type=int, default=5)
    args = parser.parse_args(argv)

    if args.rows <= 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--rows must be positive."})
        return 2
    if args.page_size <= 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--page-size must be positive."})
        return 2
    if args.apply and args.preview:
        _write(args, {"ok": False, "mode": "plan", "error": "Use either --apply or --preview."})
        return 2

    signgucode = args.signgucode.strip() or None
    signgucodesub = args.signgucodesub.strip() or None
    prfstate = args.prfstate.strip() or None
    if not args.apply and not args.preview:
        _write(args, _plan_payload(args, signgucode, signgucodesub, prfstate))
        return 0

    service_key = _env_or_secret("KOPIS_API_KEY", "kopis-api-key")
    if not service_key:
        _write(args, {"ok": False, "mode": _mode(args), "error": "KOPIS_API_KEY is not configured."})
        return 2

    dsn = _env_or_secret("DB_DSN", "db-dsn")
    if args.apply and not dsn:
        _write(args, {"ok": False, "mode": "apply", "error": "DB_DSN is not configured."})
        return 2

    if args.apply:
        guard_error = _apply_guard_error(args)
        if guard_error:
            _write(args, {"ok": False, "mode": "apply", "error": guard_error})
            return 2

    try:
        result = fetch_kopis_performances(
            service_key=service_key,
            stdate=args.stdate,
            eddate=args.eddate,
            signgucode=signgucode,
            signgucodesub=signgucodesub,
            prfstate=prfstate,
            rows=args.rows,
            page_size=args.page_size,
            timeout=args.timeout,
        )
        apply_result: dict[str, Any] | None = None
        if args.apply:
            apply_result = upsert_kopis_performances(
                dsn=dsn,
                result=result,
                connect_timeout=args.connect_timeout,
            )
    except Exception as exc:
        _write(
            args,
            {
                "ok": False,
                "mode": _mode(args),
                "error": redact_secret_text(
                    str(exc) or exc.__class__.__name__,
                    (service_key, dsn),
                ),
            },
        )
        return 2

    payload = {
        "ok": True,
        "mode": _mode(args),
        "live_api_call": True,
        "db_mutation": bool(args.apply),
        "target": "culture.events",
        "result": result.to_public_dict(),
    }
    if apply_result is not None:
        payload["apply_result"] = apply_result
    _write(args, payload)
    return 0


def _plan_payload(
    args: argparse.Namespace,
    signgucode: str | None,
    signgucodesub: str | None,
    prfstate: str | None,
) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "live_api_call": False,
        "db_mutation": False,
        "source_name": "kopis",
        "dataset_name": DEFAULT_DATASET_NAME,
        "operation": KOPIS_OPERATION,
        "base_url": KOPIS_BASE_URL,
        "stdate": args.stdate,
        "eddate": args.eddate,
        "signgucode": signgucode,
        "signgucodesub": signgucodesub,
        "prfstate": prfstate,
        "target": "culture.events",
        "required_env": ["KOPIS_API_KEY"],
    }


def _apply_guard_error(args: argparse.Namespace) -> str:
    if args.confirm != CONFIRM_TEXT:
        return f"--apply requires --confirm {CONFIRM_TEXT}."
    if os.getenv(ALLOW_ENV) != "1":
        return f"--apply requires {ALLOW_ENV}=1 in the process environment."
    return ""


def _env_or_secret(env_name: str, secret_name: str) -> str:
    value = (os.getenv(env_name) or "").strip()
    if value:
        return value
    return get_secret_if_configured((os.getenv("KEY_VAULT_URL") or "").strip(), secret_name)


def _write(args: argparse.Namespace, payload: dict[str, Any]) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next KOPIS ingest")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target', 'culture.events')}")
    if "live_api_call" in payload:
        print(f"live_api_call={str(payload.get('live_api_call')).lower()}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return

    result = payload.get("result") or {}
    if result:
        print(f"source_name={result.get('source_name')}")
        print(f"operation={result.get('operation')}")
        print(f"stdate={result.get('stdate')}")
        print(f"eddate={result.get('eddate')}")
        print(f"signgucode={result.get('signgucode')}")
        print(f"request_count={result.get('request_count')}")
        print(f"raw_count={result.get('raw_count')}")
        print(f"performance_count={result.get('performance_count')}")
        for item in result.get("preview") or []:
            print(
                "preview="
                + json.dumps(
                    {
                        "event_id": item.get("event_id"),
                        "title_ko": item.get("title_ko"),
                        "event_type": item.get("event_type"),
                        "region_name_ko": item.get("region_name_ko"),
                    },
                    ensure_ascii=False,
                    sort_keys=True,
                )
            )
    apply_result = payload.get("apply_result") or {}
    if apply_result:
        print(f"upserted_rows={apply_result.get('upserted_rows')}")


def _mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "preview"


if __name__ == "__main__":
    raise SystemExit(main())
