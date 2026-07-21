from __future__ import annotations

import argparse
import json
import os
from datetime import UTC, datetime
from typing import Any

from dotenv import load_dotenv

from apps.api.app.core.key_vault import get_secret_if_configured
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.weather_observation_refresh import (
    WeatherRefreshResult,
    fetch_weather_observations,
    fetch_weather_targets,
    insert_weather_observations,
    record_job_run,
)

CONFIRM_TEXT = "APPLY_WEATHER_OBSERVATION_REFRESH"
ALLOW_ENV = "ALLOW_WEATHER_OBSERVATION_REFRESH_APPLY"
JOB_NAME = "weather-refresh"

load_dotenv()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply public-data weather observations."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Read DB targets and call KMA/AirKorea without mutating DB.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Insert travel.weather_observations rows and record ops.job_runs.",
    )
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument("--limit", type=int, default=20, help="Region target count.")
    parser.add_argument("--connect-timeout", type=int, default=5)
    args = parser.parse_args(argv)

    if args.limit <= 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--limit must be positive."})
        return 2
    if args.apply and args.preview:
        _write(args, {"ok": False, "mode": "plan", "error": "Use either --apply or --preview."})
        return 2

    if not args.apply and not args.preview:
        _write(args, _plan_payload(args))
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
    os.environ.setdefault("PUBLIC_DATA_SERVICE_KEY", service_key)

    dsn = _env_or_secret("DB_DSN", "db-dsn")
    if not dsn:
        _write(args, {"ok": False, "mode": _mode(args), "error": "DB_DSN is not configured."})
        return 2
    os.environ.setdefault("DB_DSN", dsn)

    if args.apply:
        guard_error = _apply_guard_error(args)
        if guard_error:
            _write(args, {"ok": False, "mode": "apply", "error": guard_error})
            return 2

    started_at = datetime.now(UTC)
    try:
        targets = fetch_weather_targets(
            dsn=dsn,
            limit=args.limit,
            connect_timeout=args.connect_timeout,
        )
        observations = fetch_weather_observations(targets)
        inserted_rows = 0
        job_run_recorded = False
        job_run_warning: str | None = None
        if args.apply:
            inserted_rows = insert_weather_observations(
                dsn=dsn,
                observations=observations,
                connect_timeout=args.connect_timeout,
            )
            finished_at = datetime.now(UTC)
            try:
                record_job_run(
                    dsn=dsn,
                    job_name=JOB_NAME,
                    status="succeeded",
                    started_at=started_at,
                    finished_at=finished_at,
                    duration_ms=_duration_ms(started_at, finished_at),
                    error_message=None,
                    connect_timeout=args.connect_timeout,
                )
                job_run_recorded = True
            except Exception as exc:
                job_run_warning = redact_secret_text(
                    str(exc) or exc.__class__.__name__,
                    (service_key, dsn),
                )
        result = WeatherRefreshResult(
            target_count=len(targets),
            observation_count=len(observations),
            inserted_rows=inserted_rows,
            observations=observations,
        )
    except Exception as exc:
        finished_at = datetime.now(UTC)
        if args.apply:
            _record_failed_job_run(
                dsn=dsn,
                started_at=started_at,
                finished_at=finished_at,
                error_message=redact_secret_text(
                    str(exc) or exc.__class__.__name__,
                    (service_key, dsn),
                ),
                connect_timeout=args.connect_timeout,
            )
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

    payload: dict[str, Any] = {
        "ok": True,
        "mode": _mode(args),
        "live_api_call": True,
        "db_mutation": bool(args.apply),
        "target": "travel.weather_observations",
        "job_name": JOB_NAME,
        "result": result.to_public_dict(),
    }
    if args.apply:
        payload["job_run_recorded"] = job_run_recorded
    if job_run_warning:
        payload["warning"] = f"job_run_not_recorded: {job_run_warning}"
    _write(args, payload)
    return 0


def _plan_payload(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "live_api_call": False,
        "db_mutation": False,
        "source_name": "public_data_weather",
        "source_apis": [
            "KMA Ultra Short Nowcast",
            "AirKorea realtime sido air quality",
        ],
        "target": "travel.weather_observations",
        "job_name": JOB_NAME,
        "target_limit": args.limit,
        "required_env": ["PUBLIC_DATA_SERVICE_KEY"],
        "apply_required_env": ["DB_DSN"],
    }


def _apply_guard_error(args: argparse.Namespace) -> str:
    if args.confirm != CONFIRM_TEXT:
        return f"--apply requires --confirm {CONFIRM_TEXT}."
    if os.getenv(ALLOW_ENV) != "1":
        return f"--apply requires {ALLOW_ENV}=1 in the process environment."
    return ""


def _record_failed_job_run(
    *,
    dsn: str,
    started_at: datetime,
    finished_at: datetime,
    error_message: str,
    connect_timeout: int,
) -> None:
    try:
        record_job_run(
            dsn=dsn,
            job_name=JOB_NAME,
            status="failed",
            started_at=started_at,
            finished_at=finished_at,
            duration_ms=_duration_ms(started_at, finished_at),
            error_message=error_message,
            connect_timeout=connect_timeout,
        )
    except Exception:
        return


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
    print(f"job_name={payload.get('job_name', JOB_NAME)}")
    if "live_api_call" in payload:
        print(f"live_api_call={str(payload.get('live_api_call')).lower()}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if "job_run_recorded" in payload:
        print(f"job_run_recorded={str(payload.get('job_run_recorded')).lower()}")
    if payload.get("warning"):
        print(f"warning={payload['warning']}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return

    result = payload.get("result") or {}
    for key in ("target_count", "observation_count", "inserted_rows"):
        if key in result:
            print(f"{key}={result[key]}")
    for api in payload.get("source_apis") or []:
        print(f"source_api={api}")
    for env_name in payload.get("required_env") or []:
        print(f"required_env={env_name}")
    for env_name in payload.get("apply_required_env") or []:
        print(f"apply_required_env={env_name}")
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
                    "source_summary": item.get("source_summary"),
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )


def _mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "preview"


def _duration_ms(started_at: datetime, finished_at: datetime) -> int:
    return int((finished_at - started_at).total_seconds() * 1000)


if __name__ == "__main__":
    raise SystemExit(main())
