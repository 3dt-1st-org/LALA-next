from __future__ import annotations

import argparse
import json
import os
from datetime import date
from typing import Any

from dotenv import load_dotenv

from apps.api.app.core.key_vault import get_secret_if_configured
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.review_mention_ingest import (
    DEFAULT_PROVIDER,
    NAVER_BLOG_SEARCH_URL,
    PROMPT_VERSION,
    SUPPORTED_CATEGORIES,
    build_review_mention_result,
    fetch_naver_blog_items,
    fetch_review_mention_targets,
    upsert_review_mention_result,
)

CONFIRM_TEXT = "APPLY_REVIEW_MENTION_INGEST"
ALLOW_ENV = "ALLOW_REVIEW_MENTION_INGEST_APPLY"

load_dotenv()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply review and local mention preprocessing."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument("--preview", action="store_true", help="Call source APIs and preview aggregates.")
    parser.add_argument("--apply", action="store_true", help="Persist organic mentions and weekly aggregates.")
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument(
        "--category",
        choices=sorted(SUPPORTED_CATEGORIES),
        default="all",
    )
    parser.add_argument("--limit", type=int, default=10, help="Place target limit.")
    parser.add_argument("--items-per-place", type=int, default=10)
    parser.add_argument("--provider", default=DEFAULT_PROVIDER)
    parser.add_argument("--week-start", default="", help="Optional YYYY-MM-DD aggregate week start.")
    parser.add_argument("--timeout", type=int, default=10)
    parser.add_argument("--connect-timeout", type=int, default=5)
    args = parser.parse_args(argv)

    if args.limit <= 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--limit must be positive."})
        return 2
    if args.items_per_place <= 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--items-per-place must be positive."})
        return 2
    if args.apply and args.preview:
        _write(args, {"ok": False, "mode": "plan", "error": "Use either --apply or --preview."})
        return 2
    if args.provider != DEFAULT_PROVIDER:
        _write(args, {"ok": False, "mode": _mode(args), "error": f"Unsupported provider: {args.provider}"})
        return 2

    if not args.apply and not args.preview:
        _write(args, _plan_payload(args))
        return 0

    dsn = _env_or_secret("DB_DSN", "db-dsn")
    client_id = _env_or_secret("NAVER_CLIENT_ID", "naver-client-id")
    client_secret = _env_or_secret("NAVER_CLIENT_SECRET", "naver-client-secret")
    secrets = (dsn, client_id, client_secret)
    if not dsn:
        _write(args, {"ok": False, "mode": _mode(args), "error": "DB_DSN is not configured."})
        return 2
    if not client_id or not client_secret:
        _write(
            args,
            {
                "ok": False,
                "mode": _mode(args),
                "error": "NAVER_CLIENT_ID and NAVER_CLIENT_SECRET are not configured.",
            },
        )
        return 2

    if args.apply:
        guard_error = _apply_guard_error(args)
        if guard_error:
            _write(args, {"ok": False, "mode": "apply", "error": guard_error})
            return 2

    try:
        fixed_week_start = _parse_week_start(args.week_start)
        targets = fetch_review_mention_targets(
            dsn=dsn,
            category=args.category,
            limit=args.limit,
            connect_timeout=args.connect_timeout,
        )
        items_by_place_id = {
            target.place_id: fetch_naver_blog_items(
                query=target.search_query,
                client_id=client_id,
                client_secret=client_secret,
                display=args.items_per_place,
                timeout=args.timeout,
            )
            for target in targets
        }
        result = build_review_mention_result(
            targets=targets,
            provider=args.provider,
            items_by_place_id=items_by_place_id,
            week_start=fixed_week_start,
        )
        apply_result: dict[str, Any] | None = None
        if args.apply:
            apply_result = upsert_review_mention_result(
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
                "error": redact_secret_text(str(exc) or exc.__class__.__name__, secrets),
            },
        )
        return 2

    payload = {
        "ok": True,
        "mode": _mode(args),
        "live_api_call": True,
        "db_mutation": bool(args.apply),
        "provider": args.provider,
        "prompt_version": PROMPT_VERSION,
        "target": [
            "community.posts",
            "community.place_mentions_weekly",
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
        "provider": args.provider,
        "prompt_version": PROMPT_VERSION,
        "source_url": NAVER_BLOG_SEARCH_URL,
        "category": args.category,
        "limit": args.limit,
        "items_per_place": args.items_per_place,
        "target": [
            "community.posts",
            "community.place_mentions_weekly",
        ],
        "required_env": ["DB_DSN", "NAVER_CLIENT_ID", "NAVER_CLIENT_SECRET"],
        "filters": [
            "html_cleanup",
            "deduplicate_by_content_hash",
            "deterministic_ad_filter",
            "non_restaurant_food_only_policy",
            "targeted_place_name_match",
        ],
    }


def _apply_guard_error(args: argparse.Namespace) -> str:
    if args.confirm != CONFIRM_TEXT:
        return f"--apply requires --confirm {CONFIRM_TEXT}."
    if os.getenv(ALLOW_ENV) != "1":
        return f"--apply requires {ALLOW_ENV}=1 in the process environment."
    return ""


def _parse_week_start(value: str) -> date | None:
    text = value.strip()
    if not text:
        return None
    parsed = date.fromisoformat(text)
    return parsed


def _env_or_secret(env_name: str, secret_name: str) -> str:
    value = (os.getenv(env_name) or "").strip()
    if value:
        return value
    return get_secret_if_configured((os.getenv("KEY_VAULT_URL") or "").strip(), secret_name)


def _write(args: argparse.Namespace, payload: dict[str, Any]) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next review/mention preprocessing")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"provider={payload.get('provider', DEFAULT_PROVIDER)}")
    print(f"prompt_version={payload.get('prompt_version', PROMPT_VERSION)}")
    print(f"target={payload.get('target')}")
    if "live_api_call" in payload:
        print(f"live_api_call={str(payload.get('live_api_call')).lower()}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return

    for item in payload.get("filters") or []:
        print(f"filter={item}")
    result = payload.get("result") or {}
    for key in (
        "target_count",
        "candidate_count",
        "organic_candidate_count",
        "filtered_ad_count",
        "duplicate_count",
        "aggregate_count",
    ):
        if key in result:
            print(f"{key}={result[key]}")
    for item in result.get("preview_aggregates") or []:
        print(
            "preview_aggregate="
            + json.dumps(
                {
                    "place_id": item.get("place_id"),
                    "place_name_ko": item.get("place_name_ko"),
                    "week_start": item.get("week_start"),
                    "mention_count": item.get("mention_count"),
                    "organic_mention_count": item.get("organic_mention_count"),
                    "top_terms": (item.get("attributes") or {}).get("top_terms"),
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )
    apply_result = payload.get("apply_result") or {}
    if apply_result:
        print(f"inserted_posts={apply_result.get('inserted_posts')}")
        print(f"upserted_aggregates={apply_result.get('upserted_aggregates')}")


def _mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "preview"


if __name__ == "__main__":
    raise SystemExit(main())
