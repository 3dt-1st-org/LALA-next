from __future__ import annotations

import argparse
import json
from typing import Any

from apps.api.app.core.runtime_secrets import load_runtime_environment
from apps.api.app.services import region_catalog
from apps.api.app.services.culture_info_ingest import (
    CULTURE_INFO_BASE_URL,
    DEFAULT_DATASET_NAME,
    DEFAULT_OPERATION,
    DEFAULT_SIDO,
    DEFAULT_SIGUNGU,
    fetch_culture_info_events,
    fetch_culture_info_events_for_sidos,
    upsert_culture_info_events,
)
from apps.api.app.services.job_runs import record_job_run
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

CONFIRM_TEXT = "APPLY_CULTURE_INFO_INGEST"
ALLOW_ENV = "ALLOW_CULTURE_INFO_INGEST_APPLY"
JOB_NAME = "kcisa-culture-info-ingest"

load_runtime_environment()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply KCISA culture information ingestion into culture.events."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument(
        "--preview", action="store_true", help="Call KCISA culture info API and preview rows."
    )
    parser.add_argument(
        "--apply", action="store_true", help="Upsert KCISA culture info rows into DB."
    )
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument("--operation", default=DEFAULT_OPERATION)
    parser.add_argument("--sido", default=DEFAULT_SIDO)
    parser.add_argument(
        "--all-supported-sido",
        action="store_true",
        help="Sweep every KCISA sido known to the shared region catalog.",
    )
    parser.add_argument("--sigungu", default=DEFAULT_SIGUNGU)
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

    sigungu = args.sigungu.strip() or None
    if args.all_supported_sido:
        sidos = region_catalog.kcisa_sido_names()
    else:
        sidos = region_catalog.kcisa_sido_names(province_names=(args.sido,)) or (args.sido,)
    if not args.apply and not args.preview:
        _write(args, _plan_payload(args, sidos, sigungu))
        return 0

    service_key = _env_or_secret("PUBLIC_DATA_SERVICE_KEY", "public-data-service-key")
    if not service_key:
        _write(
            args,
            {
                "ok": False,
                "mode": _mode(args),
                "error": "PUBLIC_DATA_SERVICE_KEY is not configured.",
            },
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
        if len(sidos) == 1:
            result = fetch_culture_info_events(
                service_key=service_key,
                operation=args.operation,
                sido=sidos[0],
                sigungu=sigungu,
                rows=args.rows,
                page_size=args.page_size,
                timeout=args.timeout,
            )
        else:
            result = fetch_culture_info_events_for_sidos(
                service_key=service_key,
                operation=args.operation,
                sidos=sidos,
                sigungu=sigungu,
                rows=args.rows,
                page_size=args.page_size,
                timeout=args.timeout,
            )
        apply_result: dict[str, Any] | None = None
        if args.apply:
            apply_result = upsert_culture_info_events(
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
    sidos: tuple[str, ...],
    sigungu: str | None,
) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "live_api_call": False,
        "db_mutation": False,
        "source_name": "kcisa",
        "dataset_name": DEFAULT_DATASET_NAME,
        "operation": args.operation,
        "base_url": CULTURE_INFO_BASE_URL,
        "job_name": JOB_NAME,
        "sido": sidos[0] if len(sidos) == 1 else "multi",
        "sidos": list(sidos),
        "sigungu": sigungu,
        "target": "culture.events",
        "required_env": ["PUBLIC_DATA_SERVICE_KEY"],
    }


def _apply_guard_error(args: argparse.Namespace) -> str:
    return apply_guard_error(args, confirm_text=CONFIRM_TEXT, allow_env=ALLOW_ENV)


def _env_or_secret(env_name: str, secret_name: str) -> str:
    return env_or_secret(env_name, secret_name)


def _write(args: argparse.Namespace, payload: dict[str, Any]) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next KCISA culture info ingest")
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
        print(f"sido={result.get('sido')}")
        if result.get("sidos"):
            print(f"sidos={result.get('sidos')}")
        print(f"sigungu={result.get('sigungu')}")
        print(f"request_count={result.get('request_count')}")
        print(f"raw_count={result.get('raw_count')}")
        print(f"event_count={result.get('event_count')}")
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
