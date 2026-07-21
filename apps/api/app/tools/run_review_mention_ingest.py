from __future__ import annotations

import argparse
import contextlib
import json
import os
from datetime import UTC, datetime
from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.review_mention_ingest import (
    JOB_NAME,
    PROMPT_VERSION,
    build_review_mention_result,
    fetch_review_mention_inputs,
    insert_review_mention_aggregates,
    record_job_run,
)

CONFIRM_TEXT = "APPLY_REVIEW_MENTION_INGEST"
ALLOW_ENV = "ALLOW_REVIEW_MENTION_INGEST_APPLY"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply approved review/mention preprocessing."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Read approved community posts and preview weekly mention aggregates.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Upsert community.place_mentions_weekly rows.",
    )
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument("--provider", default="all")
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
        posts, places = fetch_review_mention_inputs(
            dsn=dsn,
            limit=args.limit,
            provider=args.provider,
            connect_timeout=args.connect_timeout,
        )
        result = build_review_mention_result(posts=posts, places=places, limit=args.limit)
        inserted_rows = 0
        if args.apply:
            inserted_rows = insert_review_mention_aggregates(
                dsn=dsn,
                aggregates=result.aggregates,
                connect_timeout=args.connect_timeout,
            )
            finished_at = datetime.now(UTC)
            record_job_run(
                dsn=dsn,
                status="succeeded",
                started_at=started_at,
                finished_at=finished_at,
                duration_ms=_duration_ms(started_at, finished_at),
                error_message=None,
                connect_timeout=args.connect_timeout,
            )
    except Exception as exc:
        if args.apply:
            finished_at = datetime.now(UTC)
            with contextlib.suppress(Exception):
                record_job_run(
                    dsn=dsn,
                    status="failed",
                    started_at=started_at,
                    finished_at=finished_at,
                    duration_ms=_duration_ms(started_at, finished_at),
                    error_message=redact_secret_text(
                        str(exc) or exc.__class__.__name__,
                        (dsn,),
                    ),
                    connect_timeout=args.connect_timeout,
                )
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
            "target": "community.place_mentions_weekly",
            "job_name": JOB_NAME,
            "prompt_version": PROMPT_VERSION,
            "input_relations": ["community.posts", "travel.places"],
            "provider": args.provider,
            "inserted_rows": inserted_rows,
            "result": result.to_public_dict(),
        },
    )
    return 0


def _plan_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "db_mutation": False,
        "target": "community.place_mentions_weekly",
        "job_name": JOB_NAME,
        "prompt_version": PROMPT_VERSION,
        "input_relations": ["community.posts", "travel.places"],
        "apply_required_env": ["DB_DSN", ALLOW_ENV],
        "review_rules": [
            "advertising_filtered",
            "attraction_food_only_review_rejected",
            "restaurant_food_terms_retained",
            "ambiguous_match",
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

    print("LALA-next review/mention preprocessing")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target', 'community.place_mentions_weekly')}")
    print(f"prompt_version={payload.get('prompt_version', PROMPT_VERSION)}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return
    result = payload.get("result") or {}
    if result:
        for key in (
            "post_count",
            "decision_count",
            "retained_count",
            "ad_filtered_count",
            "irrelevant_count",
            "unmatched_count",
            "ambiguous_count",
            "aggregate_count",
        ):
            print(f"{key}={result.get(key)}")
    if "inserted_rows" in payload:
        print(f"inserted_rows={payload['inserted_rows']}")
    for relation in payload.get("input_relations") or []:
        print(f"input_relation={relation}")
    for aggregate in (result.get("preview") or {}).get("aggregates") or []:
        print(
            "preview_aggregate="
            + json.dumps(
                {
                    "week_start": aggregate.get("week_start"),
                    "place_id": aggregate.get("place_id"),
                    "place_name_ko": aggregate.get("place_name_ko"),
                    "organic_mention_count": aggregate.get("organic_mention_count"),
                    "category_policy": (aggregate.get("attributes") or {}).get("category_policy"),
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )


def _duration_ms(started_at: datetime, finished_at: datetime) -> int:
    return int((finished_at - started_at).total_seconds() * 1000)


def _mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "preview"


if __name__ == "__main__":
    raise SystemExit(main())
