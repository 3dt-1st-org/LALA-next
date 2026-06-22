from __future__ import annotations

import argparse
import json
import os
from typing import Any

from dotenv import load_dotenv

from apps.api.app.core.key_vault import get_secret_if_configured
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.review_attribute_scoring import (
    PROMPT_VERSION,
    SCHEMA_VERSION,
    SOURCE_METHOD,
    SUPPORTED_CATEGORIES,
    apply_review_attribute_scores,
    build_review_attribute_scores,
    fetch_review_attribute_candidates,
)

CONFIRM_TEXT = "APPLY_REVIEW_ATTRIBUTE_BATCH"
ALLOW_ENV = "ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY"

load_dotenv()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply review sentiment and attribute scoring."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--preview", action="store_true", help="Read DB aggregates and preview scores.")
    parser.add_argument("--apply", action="store_true", help="Persist review attribute scores.")
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument(
        "--category",
        choices=sorted(SUPPORTED_CATEGORIES),
        default="all",
    )
    parser.add_argument("--limit", type=int, default=250)
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

    dsn = _env_or_secret("DB_DSN", "db-dsn")
    if not dsn:
        _write(args, {"ok": False, "mode": _mode(args), "error": "DB_DSN is not configured."})
        return 2

    if args.apply:
        guard_error = _apply_guard_error(args)
        if guard_error:
            _write(args, {"ok": False, "mode": "apply", "error": guard_error})
            return 2

    try:
        aggregates = fetch_review_attribute_candidates(
            dsn=dsn,
            category=args.category,
            limit=args.limit,
            connect_timeout=args.connect_timeout,
        )
        scores = build_review_attribute_scores(aggregates)
        apply_result: dict[str, int] | None = None
        if args.apply:
            apply_result = apply_review_attribute_scores(
                dsn=dsn,
                scores=scores,
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

    payload: dict[str, Any] = {
        "ok": True,
        "mode": _mode(args),
        "db_mutation": bool(args.apply),
        "schema_version": SCHEMA_VERSION,
        "prompt_version": PROMPT_VERSION,
        "source_method": SOURCE_METHOD,
        "source": "community.place_mentions_weekly",
        "target": [
            "community.place_mentions_weekly",
            "travel.place_enrichments",
        ],
        "aggregate_count": len(aggregates),
        "score_count": len(scores),
        "eligible_review_quality_count": sum(
            1 for item in scores if item.review_quality_score is not None
        ),
        "preview": [item.to_public_dict() for item in scores[:5]],
    }
    if apply_result is not None:
        payload["apply_result"] = apply_result
    _write(args, payload)
    return 0


def _plan_payload(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "db_mutation": False,
        "schema_version": SCHEMA_VERSION,
        "prompt_version": PROMPT_VERSION,
        "source_method": SOURCE_METHOD,
        "source": "community.place_mentions_weekly",
        "target": [
            "community.place_mentions_weekly",
            "travel.place_enrichments",
        ],
        "category": args.category,
        "limit": args.limit,
        "required_env": ["DB_DSN"],
        "score_outputs": [
            "sentiment_score",
            "review_attributes",
            "review_quality.score",
        ],
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

    print("LALA-next review attribute scoring")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"source={payload.get('source', 'community.place_mentions_weekly')}")
    print(f"target={payload.get('target')}")
    print(f"schema_version={payload.get('schema_version', SCHEMA_VERSION)}")
    print(f"prompt_version={payload.get('prompt_version', PROMPT_VERSION)}")
    print(f"source_method={payload.get('source_method', SOURCE_METHOD)}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return
    for output in payload.get("score_outputs") or []:
        print(f"score_output={output}")
    for key in ("aggregate_count", "score_count", "eligible_review_quality_count"):
        if key in payload:
            print(f"{key}={payload[key]}")
    if payload.get("apply_result"):
        print("apply_result=" + json.dumps(payload["apply_result"], sort_keys=True))
    for item in payload.get("preview") or []:
        print(
            "preview="
            + json.dumps(
                {
                    "place_id": item.get("place_id"),
                    "category": item.get("category"),
                    "organic_mention_count": item.get("organic_mention_count"),
                    "sentiment_score": item.get("sentiment_score"),
                    "review_quality_score": item.get("review_quality_score"),
                    "insufficient_reason": item.get("insufficient_reason"),
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )


def _mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "preview"


if __name__ == "__main__":
    raise SystemExit(main())
