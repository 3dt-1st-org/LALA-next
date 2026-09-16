from __future__ import annotations

import argparse
import json
from typing import Any

from apps.api.app.core.runtime_secrets import load_runtime_environment
from apps.api.app.services import region_catalog
from apps.api.app.services.job_runs import record_job_run
from apps.api.app.services.kopis_ingest import (
    DEFAULT_DATASET_NAME,
    DEFAULT_SIGNGUCODE,
    KOPIS_BASE_URL,
    KOPIS_OPERATION,
    default_date_window,
    fetch_kopis_performances,
    fetch_kopis_performances_for_signgucodes,
    upsert_kopis_performances,
)
from apps.api.app.tools.batch_helpers import (
    apply_guard_error,
    cli_mode,
    cli_start,
    env_or_secret,
    mutually_exclusive_mode_error,
    record_apply_job_failure,
    record_apply_job_success,
    redact_cli_error,
)

CONFIRM_TEXT = "APPLY_KOPIS_INGEST"
ALLOW_ENV = "ALLOW_KOPIS_INGEST_APPLY"
JOB_NAME = "kopis-ingest"

load_runtime_environment()


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
    parser.add_argument(
        "--eddate", default=default_eddate, help="End date YYYYMMDD. KOPIS supports up to 31 days."
    )
    parser.add_argument(
        "--signgucode", default=DEFAULT_SIGNGUCODE, help="KOPIS 시도 code. Default 41=경기도."
    )
    parser.add_argument(
        "--all-supported-signgucodes",
        action="store_true",
        help="Sweep every KOPIS signgucode known to the shared region catalog.",
    )
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
    if mutually_exclusive_mode_error(args):
        _write(args, {"ok": False, "mode": "plan", "error": "Use either --apply or --preview."})
        return 2

    if args.all_supported_signgucodes:
        signgucodes = region_catalog.kopis_signgucodes()
    else:
        signgucodes = region_catalog.kopis_signgucodes(province_names=(args.signgucode,)) or (
            args.signgucode.strip(),
        )
    signgucodesub = args.signgucodesub.strip() or None
    prfstate = args.prfstate.strip() or None
    if not args.apply and not args.preview:
        _write(args, _plan_payload(args, signgucodes, signgucodesub, prfstate))
        return 0

    service_key = _env_or_secret("KOPIS_API_KEY", "kopis-api-key")
    if not service_key:
        _write(
            args, {"ok": False, "mode": _mode(args), "error": "KOPIS_API_KEY is not configured."}
        )
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

    run_context = cli_start(args)
    try:
        if len(signgucodes) == 1:
            result = fetch_kopis_performances(
                service_key=service_key,
                stdate=args.stdate,
                eddate=args.eddate,
                signgucode=signgucodes[0],
                signgucodesub=signgucodesub,
                prfstate=prfstate,
                rows=args.rows,
                page_size=args.page_size,
                timeout=args.timeout,
            )
        else:
            result = fetch_kopis_performances_for_signgucodes(
                service_key=service_key,
                stdate=args.stdate,
                eddate=args.eddate,
                signgucodes=signgucodes,
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
            record_apply_job_success(
                dsn=dsn,
                job_name=JOB_NAME,
                started_at=run_context.started_at,
                connect_timeout=args.connect_timeout,
                record_job_run=record_job_run,
            )
    except Exception as exc:
        error_message = redact_cli_error(exc, service_key, dsn)
        record_apply_job_failure(
            args=args,
            dsn=dsn,
            job_name=JOB_NAME,
            started_at=run_context.started_at,
            error_message=error_message,
            connect_timeout=args.connect_timeout,
            record_job_run=record_job_run,
        )
        _write(
            args,
            {
                "ok": False,
                "mode": _mode(args),
                "error": error_message,
            },
        )
        return 2

    payload = {
        "ok": True,
        "mode": _mode(args),
        "live_api_call": True,
        "db_mutation": bool(args.apply),
        "target": "culture.events",
        "job_name": JOB_NAME,
        "result": result.to_public_dict(),
    }
    if apply_result is not None:
        payload["apply_result"] = apply_result
    _write(args, payload)
    return 0


def _plan_payload(
    args: argparse.Namespace,
    signgucodes: tuple[str, ...],
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
        "job_name": JOB_NAME,
        "stdate": args.stdate,
        "eddate": args.eddate,
        "signgucode": signgucodes[0] if len(signgucodes) == 1 else "multi",
        "signgucodes": list(signgucodes),
        "signgucodesub": signgucodesub,
        "prfstate": prfstate,
        "target": "culture.events",
        "required_env": ["KOPIS_API_KEY"],
    }


def _apply_guard_error(args: argparse.Namespace) -> str:
    return apply_guard_error(args, confirm_text=CONFIRM_TEXT, allow_env=ALLOW_ENV)


def _env_or_secret(env_name: str, secret_name: str) -> str:
    return env_or_secret(env_name, secret_name)


def _write(args: argparse.Namespace, payload: dict[str, Any]) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next KOPIS ingest")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target', 'culture.events')}")
    if payload.get("job_name"):
        print(f"job_name={payload['job_name']}")
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
        if result.get("signgucodes"):
            print(f"signgucodes={result.get('signgucodes')}")
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
    return cli_mode(args)


if __name__ == "__main__":
    raise SystemExit(main())
