from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

from dotenv import load_dotenv

from apps.api.app.core.key_vault import get_secret_if_configured
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.card_spending_ingest import (
    DEFAULT_SOURCE_NAME,
    DEFAULT_VISITOR_TYPE,
    DETAIL_DATASET_NAME,
    load_region_code_map,
    parse_card_spending_file,
    insert_card_spending_result,
)

CONFIRM_TEXT = "APPLY_CARD_SPENDING_FILE_INGEST"
ALLOW_ENV = "ALLOW_CARD_SPENDING_FILE_INGEST_APPLY"

load_dotenv()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply public card spending file ingestion."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--preview", action="store_true", help="Parse a local CSV/XLSX file without DB writes.")
    parser.add_argument("--apply", action="store_true", help="Insert parsed aggregates into DB.")
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument("--file-path", default="", help="Local CSV/XLSX source file path.")
    parser.add_argument("--csv-path", default="", help="Deprecated alias for --file-path.")
    parser.add_argument("--region-map", default="", help="Optional CSV/XLSX code-to-name mapping file.")
    parser.add_argument("--source-name", default=DEFAULT_SOURCE_NAME)
    parser.add_argument("--dataset-name", default=DETAIL_DATASET_NAME)
    parser.add_argument("--visitor-type", default=DEFAULT_VISITOR_TYPE)
    parser.add_argument("--row-limit", type=int, default=0)
    parser.add_argument(
        "--skip-demographics",
        action="store_true",
        help="Parse and insert only area-month aggregates needed by local-value scoring.",
    )
    parser.add_argument("--connect-timeout", type=int, default=5)
    args = parser.parse_args(argv)

    if args.apply and args.preview:
        _write(args, {"ok": False, "mode": "plan", "error": "Use either --apply or --preview."})
        return 2
    if args.row_limit < 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--row-limit cannot be negative."})
        return 2
    if not args.apply and not args.preview:
        _write(args, _plan_payload(args))
        return 0

    file_path = args.file_path or args.csv_path
    if not file_path:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--file-path is required."})
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
        region_code_map = load_region_code_map(args.region_map) if args.region_map else None
        result = parse_card_spending_file(
            path=Path(file_path),
            source_name=args.source_name,
            dataset_name=args.dataset_name,
            visitor_type=args.visitor_type,
            region_code_map=region_code_map,
            row_limit=args.row_limit or None,
            include_demographics=not args.skip_demographics,
        )
        apply_result: dict[str, Any] | None = None
        if args.apply:
            apply_result = insert_card_spending_result(
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
                "error": redact_secret_text(str(exc) or exc.__class__.__name__, (dsn,)),
            },
        )
        return 2

    payload = {
        "ok": True,
        "mode": _mode(args),
        "live_api_call": False,
        "db_mutation": bool(args.apply),
        "target": [
            "economy.card_spending_area_monthly",
            "economy.card_spending_demographics",
        ],
        "result": result.to_public_dict(),
    }
    if apply_result is not None:
        payload["apply_result"] = apply_result
    _write(args, payload)
    return 0


def _plan_payload(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "live_api_call": False,
        "db_mutation": False,
        "source_name": args.source_name,
        "dataset_name": args.dataset_name,
        "supported_file_types": ["csv", "xlsx", "zip"],
        "source_urls": [
            "https://www.data.go.kr/data/15128475/fileData.do",
            "https://www.data.go.kr/data/15151646/fileData.do",
        ],
        "target": [
            "economy.card_spending_area_monthly",
            "economy.card_spending_demographics",
        ],
        "required_env": [],
        "apply_required_env": ["DB_DSN"],
        "options": {
            "skip_demographics": "Area-month aggregates only; useful for the first local-value score rollout.",
        },
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

    print("LALA-next card spending file ingest")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target')}")
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
        print(f"dataset_name={result.get('dataset_name')}")
        print(f"file_name={result.get('file_name')}")
        print(f"input_row_count={result.get('input_row_count')}")
        print(f"parsed_row_count={result.get('parsed_row_count')}")
        print(f"skipped_row_count={result.get('skipped_row_count')}")
        print(f"area_monthly_row_count={result.get('area_monthly_row_count')}")
        print(f"demographic_row_count={result.get('demographic_row_count')}")
        for item in (result.get("preview") or {}).get("area_monthly") or []:
            print(
                "preview_area="
                + json.dumps(
                    {
                        "month": item.get("month"),
                        "region_name_ko": item.get("region_name_ko"),
                        "industry_code": item.get("industry_code"),
                        "spend_amount": item.get("spend_amount"),
                    },
                    ensure_ascii=False,
                    sort_keys=True,
                )
            )
    apply_result = payload.get("apply_result") or {}
    if apply_result:
        print(f"skipped_duplicate={str(apply_result.get('skipped_duplicate')).lower()}")
        print(f"inserted_area_monthly_rows={apply_result.get('inserted_area_monthly_rows')}")
        print(f"inserted_demographic_rows={apply_result.get('inserted_demographic_rows')}")


def _mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "preview"


if __name__ == "__main__":
    raise SystemExit(main())
