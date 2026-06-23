from __future__ import annotations

import argparse
import json
import os
from datetime import UTC, datetime
from typing import Any

from dotenv import load_dotenv

from apps.api.app.core.key_vault import get_secret_if_configured
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.job_runs import duration_ms, record_job_run
from apps.api.app.services.culture_info_ingest import (
    CULTURE_INFO_BASE_URL,
    DEFAULT_DATASET_NAME,
    DEFAULT_OPERATION,
    DEFAULT_SIDO,
    DEFAULT_SIGUNGU,
    fetch_culture_info_events,
    upsert_culture_info_events,
)

CONFIRM_TEXT = "APPLY_CULTURE_INFO_INGEST"
ALLOW_ENV = "ALLOW_CULTURE_INFO_INGEST_APPLY"
JOB_NAME = "kcisa-culture-info-ingest"

load_dotenv()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply KCISA culture information ingestion into culture.events."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--preview", action="store_true", help="Call KCISA culture info API and preview rows.")
    parser.add_argument("--apply", action="store_true", help="Upsert KCISA culture info rows into DB.")
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument("--operation", default=DEFAULT_OPERATION)
    parser.add_argument("--sido", default=DEFAULT_SIDO)
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
    if args.apply and args.preview:
        _write(args, {"ok": False, "mode": "plan", "error": "Use either --apply or --preview."})
        return 2

    sigungu = args.sigungu.strip() or None
    if not args.apply and not args.preview:
        _write(args, _plan_payload(args, sigungu))
        return 0

    service_key = _env_or_secret("PUBLIC_DATA_SERVICE_KEY", "public-data-service-key")
    if not service_key:
        _write(args, {"ok": False, "mode": _mode(args), "error": "PUBLIC_DATA_SERVICE_KEY is not configured."})
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

    started_at = datetime.now(UTC)
    try:
        result = fetch_culture_info_events(
            service_key=service_key,
            operation=args.operation,
            sido=args.sido,
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
            finished_at = datetime.now(UTC)
            record_job_run(
                dsn=dsn,
                job_name=JOB_NAME,
                status="succeeded",
                started_at=started_at,
                finished_at=finished_at,
                duration_ms=duration_ms(started_at, finished_at),
                error_message=None,
                connect_timeout=args.connect_timeout,
            )
    except Exception as exc:
        if args.apply:
            finished_at = datetime.now(UTC)
            try:
                record_job_run(
                    dsn=dsn,
                    job_name=JOB_NAME,
                    status="failed",
                    started_at=started_at,
                    finished_at=finished_at,
                    duration_ms=duration_ms(started_at, finished_at),
                    error_message=redact_secret_text(
                        str(exc) or exc.__class__.__name__,
                        (service_key, dsn),
                    ),
                    connect_timeout=args.connect_timeout,
                )
            except Exception:
                pass
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
        "job_name": JOB_NAME,
        "result": result.to_public_dict(),
    }
    if apply_result is not None:
        payload["apply_result"] = apply_result
    _write(args, payload)
    return 0


def _plan_payload(args: argparse.Namespace, sigungu: str | None) -> dict[str, Any]:
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
        "sido": args.sido,
        "sigungu": sigungu,
        "target": "culture.events",
        "required_env": ["PUBLIC_DATA_SERVICE_KEY"],
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
    return "apply" if args.apply else "preview"


if __name__ == "__main__":
    raise SystemExit(main())
