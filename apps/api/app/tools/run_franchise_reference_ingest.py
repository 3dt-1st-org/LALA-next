from __future__ import annotations

import argparse
import json
import os
from datetime import date
from typing import Any

from dotenv import load_dotenv

from apps.api.app.core.key_vault import get_secret_if_configured
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.franchise_reference_ingest import (
    DEFAULT_API_URL,
    DEFAULT_DATASET_NAME,
    DEFAULT_SOURCE_NAME,
    fetch_franchise_brand_references,
    insert_franchise_brand_references,
)

CONFIRM_TEXT = "APPLY_FRANCHISE_REFERENCE_INGEST"
ALLOW_ENV = "ALLOW_FRANCHISE_REFERENCE_INGEST_APPLY"

load_dotenv()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply Fair Trade franchise brand reference ingestion."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--preview", action="store_true", help="Call API and preview brand rows.")
    parser.add_argument(
        "--apply", action="store_true", help="Upsert economy.franchise_brands rows."
    )
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument("--year", type=int, default=date.today().year - 1)
    parser.add_argument(
        "--rows",
        type=int,
        default=500,
        help="Rows to fetch. Use 0 to fetch all rows reported by the API.",
    )
    parser.add_argument("--page-size", type=int, default=1000)
    parser.add_argument("--connect-timeout", type=int, default=10)
    parser.add_argument("--api-url", default=DEFAULT_API_URL)
    parser.add_argument("--source-name", default=DEFAULT_SOURCE_NAME)
    parser.add_argument("--dataset-name", default=DEFAULT_DATASET_NAME)
    args = parser.parse_args(argv)

    if args.apply and args.preview:
        _write(args, {"ok": False, "mode": "plan", "error": "Use either --apply or --preview."})
        return 2
    if not args.apply and not args.preview:
        _write(args, _plan_payload(args))
        return 0
    if args.rows < 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--rows cannot be negative."})
        return 2

    api_key = _env_or_secret("PUBLIC_DATA_SERVICE_KEY", "public-data-service-key")
    if not api_key:
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

    try:
        result = fetch_franchise_brand_references(
            api_key=api_key,
            year=args.year,
            rows=args.rows,
            page_size=args.page_size,
            timeout=args.connect_timeout,
            api_url=args.api_url,
            source_name=args.source_name,
            dataset_name=args.dataset_name,
        )
        apply_result: dict[str, Any] | None = None
        if args.apply:
            apply_result = insert_franchise_brand_references(
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
                "error": redact_secret_text(str(exc) or exc.__class__.__name__, (api_key, dsn)),
            },
        )
        return 2

    payload = {
        "ok": True,
        "mode": _mode(args),
        "live_api_call": True,
        "db_mutation": bool(args.apply),
        "target": "economy.franchise_brands",
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
        "source_url": args.api_url,
        "year": args.year,
        "target": "economy.franchise_brands",
        "downstream": [
            "analytics.place_business_identity",
            "analytics.place_score_snapshots",
            "rag.knowledge_chunks",
        ],
        "required_env": ["PUBLIC_DATA_SERVICE_KEY"],
        "apply_required_env": ["DB_DSN"],
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

    print("LALA-next franchise reference ingest")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target', 'economy.franchise_brands')}")
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
        print(f"year={result.get('year')}")
        print(f"total_count={result.get('total_count')}")
        print(f"parsed_row_count={result.get('parsed_row_count')}")
        print(f"skipped_row_count={result.get('skipped_row_count')}")
        for item in result.get("preview") or []:
            print(
                "preview_brand="
                + json.dumps(
                    {
                        "brand_name_ko": item.get("brand_name_ko"),
                        "headquarters_name_ko": item.get("headquarters_name_ko"),
                        "business_category": item.get("business_category"),
                        "franchise_store_count": item.get("franchise_store_count"),
                        "chain_scale_score": item.get("chain_scale_score"),
                    },
                    ensure_ascii=False,
                    sort_keys=True,
                )
            )
    apply_result = payload.get("apply_result") or {}
    if apply_result:
        print(f"inserted_or_updated_rows={apply_result.get('inserted_or_updated_rows')}")


def _mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "preview"


if __name__ == "__main__":
    raise SystemExit(main())
