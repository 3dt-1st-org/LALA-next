from __future__ import annotations

import argparse
import json
import os
from typing import Any

from dotenv import load_dotenv

from apps.api.app.core.key_vault import get_secret_if_configured
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.tour_api_ingest import (
    DEFAULT_AREA_CODE,
    DEFAULT_CONTENT_TYPE_IDS,
    TOUR_API_BASE_URL,
    TOUR_API_OPERATION,
    fetch_tour_api_places,
    upsert_tour_api_places,
)

CONFIRM_TEXT = "APPLY_TOUR_API_INGEST"
ALLOW_ENV = "ALLOW_TOUR_API_INGEST_APPLY"

load_dotenv()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply TourAPI place ingestion into travel.places."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--preview", action="store_true", help="Call TourAPI and preview rows.")
    parser.add_argument("--apply", action="store_true", help="Upsert TourAPI rows into DB.")
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument("--area-code", default=DEFAULT_AREA_CODE)
    parser.add_argument(
        "--content-type-id",
        action="append",
        dest="content_type_ids",
        help="TourAPI contentTypeId. Repeatable. Defaults to attractions, culture venues, events, restaurants.",
    )
    parser.add_argument("--rows", type=int, default=40)
    parser.add_argument("--page-size", type=int, default=20)
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

    content_type_ids = tuple(args.content_type_ids or DEFAULT_CONTENT_TYPE_IDS)
    if not args.apply and not args.preview:
        _write(args, _plan_payload(args.area_code, content_type_ids))
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

    try:
        result = fetch_tour_api_places(
            service_key=service_key,
            area_code=args.area_code,
            content_type_ids=content_type_ids,
            rows=args.rows,
            page_size=args.page_size,
            timeout=args.timeout,
        )
        apply_result: dict[str, Any] | None = None
        if args.apply:
            apply_result = upsert_tour_api_places(
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
        "target": "travel.places",
        "result": result.to_public_dict(),
    }
    if apply_result is not None:
        payload["apply_result"] = apply_result
    _write(args, payload)
    return 0


def _plan_payload(area_code: str, content_type_ids: tuple[str, ...]) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "live_api_call": False,
        "db_mutation": False,
        "source_name": "tour_api",
        "dataset_name": "한국관광공사_국문 관광정보 서비스_GW",
        "operation": TOUR_API_OPERATION,
        "base_url": TOUR_API_BASE_URL,
        "area_code": area_code,
        "content_type_ids": list(content_type_ids),
        "target": "travel.places",
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

    print("LALA-next TourAPI ingest")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target', 'travel.places')}")
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
        print(f"area_code={result.get('area_code')}")
        print(f"request_count={result.get('request_count')}")
        print(f"raw_count={result.get('raw_count')}")
        print(f"place_count={result.get('place_count')}")
        for item in result.get("preview") or []:
            print(
                "preview="
                + json.dumps(
                    {
                        "place_id": item.get("place_id"),
                        "name_ko": item.get("name_ko"),
                        "category": item.get("category"),
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
