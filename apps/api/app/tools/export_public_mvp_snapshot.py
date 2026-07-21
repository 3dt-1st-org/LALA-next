from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services import public_mvp_snapshot

CONFIRM_TEXT = "WRITE_PUBLIC_MVP_SNAPSHOT"
ALLOW_ENV = "ALLOW_PUBLIC_MVP_SNAPSHOT_WRITE"
DEFAULT_LAT = 37.2636
DEFAULT_LNG = 127.0286
DEFAULT_RADIUS_M = 50000
DEFAULT_LIMIT = 20


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Export the bundled public MVP recommendation snapshot from the canonical DB."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument(
        "--preview", action="store_true", help="Read DB rows and preview snapshot metadata."
    )
    parser.add_argument(
        "--write", action="store_true", help="Write the exported snapshot JSON file."
    )
    parser.add_argument("--confirm", default="", help=f"Required with --write: {CONFIRM_TEXT}")
    parser.add_argument("--output", default=public_mvp_snapshot.DEFAULT_OUTPUT_PATH)
    parser.add_argument("--lat", type=float, default=DEFAULT_LAT)
    parser.add_argument("--lng", type=float, default=DEFAULT_LNG)
    parser.add_argument("--radius-m", type=int, default=DEFAULT_RADIUS_M)
    parser.add_argument(
        "--category",
        choices=["all", "attraction", "restaurant", "event", "culture_venue"],
        default="all",
    )
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT)
    parser.add_argument("--snapshot-id", default="")
    parser.add_argument("--connect-timeout", type=int, default=5)
    args = parser.parse_args(argv)

    validation_error = _validation_error(args)
    if validation_error:
        _write(args, {"ok": False, "mode": _mode(args), "error": validation_error})
        return 2

    if not args.preview and not args.write:
        _write(args, _plan_payload(args))
        return 0

    if args.write:
        guard_error = _write_guard_error(args)
        if guard_error:
            _write(args, {"ok": False, "mode": "write", "error": guard_error})
            return 2

    settings = get_settings()
    dsn = os.getenv("DB_DSN") or settings.db_dsn
    if not dsn:
        _write(args, {"ok": False, "mode": _mode(args), "error": "DB_DSN is not configured."})
        return 2

    try:
        places = public_mvp_snapshot.fetch_snapshot_places(
            dsn=dsn,
            lat=args.lat,
            lng=args.lng,
            radius_m=args.radius_m,
            category=args.category,
            limit=args.limit,
            connect_timeout=args.connect_timeout,
        )
        payload = public_mvp_snapshot.build_snapshot_payload(
            places,
            snapshot_id=args.snapshot_id or "public-mvp-db-export",
            lat=args.lat,
            lng=args.lng,
            radius_m=args.radius_m,
            category=args.category,
        )
        if args.write:
            output_path = Path(args.output)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(public_mvp_snapshot.payload_to_json(payload), encoding="utf-8")
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
            "db_mutation": False,
            "file_write": bool(args.write),
            "output": args.output,
            "snapshot_id": payload["snapshot_id"],
            "place_count": len(payload["places"]),
            "query": payload["query"],
            "preview": _preview_places(payload["places"]),
        },
    )
    return 0


def _validation_error(args: argparse.Namespace) -> str:
    if args.preview and args.write:
        return "Use either --preview or --write."
    if args.limit <= 0:
        return "--limit must be positive."
    if args.radius_m <= 0 or args.radius_m > 50000:
        return "--radius-m must be between 1 and 50000."
    return ""


def _write_guard_error(args: argparse.Namespace) -> str:
    if args.confirm != CONFIRM_TEXT:
        return f"--write requires --confirm {CONFIRM_TEXT}."
    if os.getenv(ALLOW_ENV) != "1":
        return f"--write requires {ALLOW_ENV}=1 in the process environment."
    return ""


def _plan_payload(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "db_mutation": False,
        "file_write": False,
        "output": args.output,
        "default_query": {
            "lat": args.lat,
            "lng": args.lng,
            "radius_m": args.radius_m,
            "category": args.category,
            "limit": args.limit,
        },
        "input_relations": [
            "travel.public_places",
            "analytics.place_score_snapshots",
        ],
        "write_guard": {
            "env": ALLOW_ENV,
            "confirm": CONFIRM_TEXT,
        },
    }


def _write(args: argparse.Namespace, payload: dict[str, Any]) -> None:
    if args.json:
        print(public_mvp_snapshot.payload_to_json(payload), end="")
        return

    print("LALA-next public MVP snapshot export")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"output={payload.get('output', args.output)}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if "file_write" in payload:
        print(f"file_write={str(payload.get('file_write')).lower()}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return
    if "place_count" in payload:
        print(f"place_count={payload['place_count']}")
    for relation in payload.get("input_relations") or []:
        print(f"input_relation={relation}")
    for item in payload.get("preview") or []:
        print(
            "preview="
            + json.dumps(
                {
                    "place_id": item.get("place_id"),
                    "category": item.get("category"),
                    "final_score": item.get("final_score"),
                    "upstream_source": item.get("upstream_source"),
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )


def _preview_places(places: list[dict[str, Any]]) -> list[dict[str, Any]]:
    preview: list[dict[str, Any]] = []
    for place in places[:5]:
        score = place.get("score") or {}
        preview.append(
            {
                "place_id": place.get("place_id"),
                "category": place.get("category"),
                "final_score": score.get("final_score"),
                "upstream_source": place.get("upstream_source"),
            }
        )
    return preview


def _mode(args: argparse.Namespace) -> str:
    if args.write:
        return "write"
    if args.preview:
        return "preview"
    return "plan"


if __name__ == "__main__":
    raise SystemExit(main())
