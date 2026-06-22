from __future__ import annotations

import argparse
import json
import os
from typing import Any

from dotenv import load_dotenv

from apps.api.app.core.key_vault import get_secret_if_configured
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.weather_observation_refresh import (
    default_refresh_targets,
    fetch_region_targets_from_places,
    parse_refresh_target,
    refresh_weather_observations,
    upsert_weather_observations,
)

CONFIRM_TEXT = "APPLY_WEATHER_OBSERVATION_REFRESH"
ALLOW_ENV = "ALLOW_WEATHER_OBSERVATION_REFRESH_APPLY"

load_dotenv()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply public weather observation refresh into travel.weather_observations."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--preview", action="store_true", help="Call public weather APIs without DB writes.")
    parser.add_argument("--apply", action="store_true", help="Insert weather observations into DB.")
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument(
        "--target",
        action="append",
        default=[],
        help="Refresh target as NAME=LAT,LNG. May be passed multiple times.",
    )
    parser.add_argument(
        "--db-regions",
        action="store_true",
        help="Read region targets from travel.public_places. Requires DB_DSN.",
    )
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--connect-timeout", type=int, default=5)
    parser.add_argument("--force", action="store_true", help="Bypass in-process public weather cache.")
    args = parser.parse_args(argv)

    if args.apply and args.preview:
        _write(args, {"ok": False, "mode": "plan", "error": "Use either --apply or --preview."})
        return 2
    if args.limit <= 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--limit must be positive."})
        return 2

    if not args.apply and not args.preview:
        _write(args, _plan_payload(args))
        return 0

    dsn = _env_or_secret("DB_DSN", "db-dsn")
    if args.db_regions and not dsn:
        _write(args, {"ok": False, "mode": _mode(args), "error": "DB_DSN is required with --db-regions."})
        return 2
    if args.apply and not dsn:
        _write(args, {"ok": False, "mode": "apply", "error": "DB_DSN is not configured."})
        return 2
    if args.apply:
        guard_error = _apply_guard_error(args)
        if guard_error:
            _write(args, {"ok": False, "mode": "apply", "error": guard_error})
            return 2

    try:
        targets = _resolve_targets(args, dsn=dsn)
        result = refresh_weather_observations(targets=targets, force=args.force)
        apply_result: dict[str, Any] | None = None
        if args.apply:
            apply_result = upsert_weather_observations(
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
        "live_api_call": True,
        "db_mutation": bool(args.apply),
        "target": "travel.weather_observations",
        "result": result.to_public_dict(),
    }
    if apply_result is not None:
        payload["apply_result"] = apply_result
    _write(args, payload)
    return 0


def _resolve_targets(args: argparse.Namespace, *, dsn: str) -> tuple:
    if args.target:
        return tuple(parse_refresh_target(value) for value in args.target)
    if args.db_regions:
        return fetch_region_targets_from_places(
            dsn=dsn,
            limit=args.limit,
            connect_timeout=args.connect_timeout,
        )
    return default_refresh_targets()


def _plan_payload(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "live_api_call": False,
        "db_mutation": False,
        "source_name": "public_weather",
        "target": "travel.weather_observations",
        "default_targets": [target.to_public_dict() for target in default_refresh_targets()],
        "required_env": ["PUBLIC_DATA_SERVICE_KEY"],
        "apply_required_env": ["DB_DSN"],
        "options": {
            "target": "NAME=LAT,LNG for a bounded manual refresh",
            "db_regions": "Read distinct region targets from travel.public_places",
            "limit": args.limit,
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

    print("LALA-next weather observation refresh")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target', 'travel.weather_observations')}")
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
        print(f"target_count={result.get('target_count')}")
        print(f"observation_count={result.get('observation_count')}")
        print(f"skipped_target_count={result.get('skipped_target_count')}")
        for item in result.get("preview") or []:
            print(
                "preview="
                + json.dumps(
                    {
                        "location_name": item.get("location_name"),
                        "temperature_c": item.get("temperature_c"),
                        "pm10": item.get("pm10"),
                        "pm25": item.get("pm25"),
                        "observed_at": item.get("observed_at"),
                    },
                    ensure_ascii=False,
                    sort_keys=True,
                )
            )
    apply_result = payload.get("apply_result") or {}
    if apply_result:
        print(f"inserted_rows={apply_result.get('inserted_rows')}")
        print(f"skipped_duplicate_rows={apply_result.get('skipped_duplicate_rows')}")


def _mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "preview"


if __name__ == "__main__":
    raise SystemExit(main())
