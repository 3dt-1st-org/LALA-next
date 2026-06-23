from __future__ import annotations

import argparse
import json
import os
from datetime import UTC, datetime
from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.job_runs import duration_ms, record_job_run
from apps.api.app.services.place_score_batch import (
    compute_score_snapshots,
    fetch_place_signals,
    insert_score_snapshots,
)
from apps.api.app.services.recommendation_scoring import (
    COMPONENT_WEIGHTS,
    FORMULA_VERSION,
)

CONFIRM_TEXT = "APPLY_PLACE_SCORE_BATCH"
ALLOW_ENV = "ALLOW_PLACE_SCORE_BATCH_APPLY"
JOB_NAME = "place-score-batch"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply local-value place score snapshots."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--preview", action="store_true", help="Read DB signals and preview scores.")
    parser.add_argument("--apply", action="store_true", help="Insert analytics.place_score_snapshots rows.")
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument(
        "--category",
        choices=["all", "attraction", "restaurant", "event", "culture_venue"],
        default="all",
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

    started_at = datetime.now(UTC)
    try:
        signals = fetch_place_signals(
            dsn=dsn,
            category=args.category,
            limit=args.limit,
            connect_timeout=args.connect_timeout,
        )
        snapshots = compute_score_snapshots(signals)
        inserted_rows = 0
        if args.apply:
            inserted_rows = insert_score_snapshots(
                dsn=dsn,
                snapshots=snapshots,
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
                        (dsn,),
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
            "target": "analytics.place_score_snapshots",
            "job_name": JOB_NAME,
            "formula_version": FORMULA_VERSION,
            "signal_count": len(signals),
            "snapshot_count": len(snapshots),
            "inserted_rows": inserted_rows,
            "preview": [item.to_public_dict() for item in snapshots[:5]],
        },
    )
    return 0


def _plan_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "db_mutation": False,
        "target": "analytics.place_score_snapshots",
        "job_name": JOB_NAME,
        "formula_version": FORMULA_VERSION,
        "component_weights": COMPONENT_WEIGHTS,
        "input_relations": [
            "travel.places",
            "economy.card_spending_area_monthly",
            "culture.events",
            "travel.place_events",
            "analytics.place_business_identity",
            "travel.weather_observations",
            "community.place_mentions_weekly",
        ],
        "review_signal": "community.place_mentions_weekly.attributes.review_quality.score",
        "business_identity_signal": "analytics.place_business_identity.small_merchant_fit_score",
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

    print("LALA-next place score batch")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target', 'analytics.place_score_snapshots')}")
    print(f"formula_version={payload.get('formula_version', FORMULA_VERSION)}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return
    for key in ("signal_count", "snapshot_count", "inserted_rows"):
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
                    "final_score": item.get("final_score"),
                    "formula_version": item.get("formula_version"),
                    "features": {
                        "region_name_ko": item.get("features", {}).get("region_name_ko"),
                        "card_month": item.get("features", {}).get("card_month"),
                        "missing_signals": item.get("features", {}).get("missing_signals"),
                    },
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )


def _mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "preview"


if __name__ == "__main__":
    raise SystemExit(main())
