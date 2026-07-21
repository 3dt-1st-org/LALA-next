from __future__ import annotations

import argparse
import json
import os
from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.franchise_identity import (
    compute_place_business_identities,
    fetch_business_identity_inputs,
    upsert_place_business_identities,
)

CONFIRM_TEXT = "APPLY_FRANCHISE_IDENTITY_BATCH"
ALLOW_ENV = "ALLOW_FRANCHISE_IDENTITY_BATCH_APPLY"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply franchise business identity matching."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument(
        "--preview", action="store_true", help="Read DB franchise refs and preview matches."
    )
    parser.add_argument(
        "--apply", action="store_true", help="Upsert analytics.place_business_identity rows."
    )
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument(
        "--category",
        choices=["all", "attraction", "restaurant", "event", "culture_venue"],
        default="restaurant",
    )
    parser.add_argument("--limit", type=int, default=500)
    parser.add_argument("--connect-timeout", type=int, default=5)
    args = parser.parse_args(argv)

    if args.limit <= 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--limit must be positive."})
        return 2
    if args.apply and args.preview:
        _write(args, {"ok": False, "mode": "plan", "error": "Use either --apply or --preview."})
        return 2
    if not args.apply and not args.preview:
        _write(args, _plan_payload())
        return 0

    settings = get_settings()
    dsn = os.getenv("DB_DSN") or settings.db_dsn
    if not dsn:
        _write(args, {"ok": False, "mode": _mode(args), "error": "DB_DSN is not configured."})
        return 2

    if args.apply:
        guard_error = _apply_guard_error(args)
        if guard_error:
            _write(args, {"ok": False, "mode": "apply", "error": guard_error})
            return 2

    try:
        places, brands, locations = fetch_business_identity_inputs(
            dsn=dsn,
            category=args.category,
            limit=args.limit,
            connect_timeout=args.connect_timeout,
        )
        identities = compute_place_business_identities(
            places,
            brands=brands,
            locations=locations,
        )
        upserted_rows = 0
        if args.apply:
            upserted_rows = upsert_place_business_identities(
                dsn=dsn,
                identities=identities,
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

    _write(
        args,
        {
            "ok": True,
            "mode": _mode(args),
            "db_mutation": bool(args.apply),
            "target": "analytics.place_business_identity",
            "place_count": len(places),
            "brand_reference_count": len(brands),
            "location_reference_count": len(locations),
            "identity_count": len(identities),
            "upserted_rows": upserted_rows,
            "preview": [identity.to_public_dict() for identity in identities[:5]],
        },
    )
    return 0


def _plan_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "db_mutation": False,
        "target": "analytics.place_business_identity",
        "input_relations": [
            "travel.places",
            "economy.franchise_brands",
            "economy.franchise_locations",
        ],
        "output_relation": "analytics.place_business_identity",
        "matching_rules": [
            "normalize names and strip branch suffixes",
            "prefer franchise location coordinate match within 100m",
            "use location store-name match when branch coordinates are unavailable",
            "fallback to exact/prefix/contains brand name match",
            "mark unmatched restaurants as independent local only when franchise references are loaded",
            "separate national franchise, franchise store, local small chain, independent local, and unknown",
        ],
    }


def _apply_guard_error(args: argparse.Namespace) -> str:
    if args.confirm != CONFIRM_TEXT:
        return f"--apply requires --confirm {CONFIRM_TEXT}."
    if os.getenv(ALLOW_ENV) != "1":
        return f"--apply requires {ALLOW_ENV}=1 in the process environment."
    return ""


def _write(args: argparse.Namespace, payload: dict[str, Any]) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next franchise identity batch")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target', 'analytics.place_business_identity')}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return
    for key in (
        "place_count",
        "brand_reference_count",
        "location_reference_count",
        "identity_count",
        "upserted_rows",
    ):
        if key in payload:
            print(f"{key}={payload[key]}")
    for relation in payload.get("input_relations") or []:
        print(f"input_relation={relation}")
    for item in payload.get("preview") or []:
        print(
            "preview="
            + json.dumps(
                {
                    "place_id": item.get("place_id"),
                    "business_identity_type": item.get("business_identity_type"),
                    "is_franchise": item.get("is_franchise"),
                    "franchise_brand_name": item.get("franchise_brand_name"),
                    "franchise_match_confidence": item.get("franchise_match_confidence"),
                    "small_merchant_fit_score": item.get("small_merchant_fit_score"),
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )


def _mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "preview"


if __name__ == "__main__":
    raise SystemExit(main())
