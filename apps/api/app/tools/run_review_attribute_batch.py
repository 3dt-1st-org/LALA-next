from __future__ import annotations

import argparse
import contextlib
import json
import os
from datetime import UTC, datetime
from typing import Any

from apps.api.app.core.config import get_settings, resolve_openai_base_url_host
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.model_client import resolve
from apps.api.app.services.review_attribute_batch import (
    JOB_NAME,
    PROMPT_VERSION,
    apply_review_attribute_enrichments,
    build_deterministic_enrichments,
    duration_ms,
    fetch_review_attribute_candidates,
    generate_ai_enrichments,
    generate_ai_recheck,
    record_job_run,
    route_low_confidence_enrichments,
    selected_review_batch_model,
    selected_review_recheck_model,
)

CONFIRM_TEXT = "APPLY_REVIEW_ATTRIBUTE_BATCH"
ALLOW_ENV = "ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, dry-run, or apply review attribute scoring."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Read DB candidates and compute deterministic attributes without DB writes.",
    )
    parser.add_argument(
        "--dry-run-ai",
        action="store_true",
        help="Read DB candidates and call standard OpenAI (bulk nano + mini recheck) without DB writes.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Call standard OpenAI (bulk nano + mini recheck) and update DB rows.",
    )
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument(
        "--category",
        choices=["all", "attraction", "restaurant", "event", "culture_venue"],
        default="all",
    )
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--min-organic", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=10)
    parser.add_argument("--retry-attempts", type=int, default=3)
    parser.add_argument("--retry-delay-sec", type=float, default=5.0)
    parser.add_argument("--connect-timeout", type=int, default=5)
    args = parser.parse_args(argv)

    validation_error = _validation_error(args)
    if validation_error:
        _write(args, {"ok": False, "mode": "plan", "error": validation_error})
        return 2

    selected_modes = sum(bool(value) for value in (args.preview, args.dry_run_ai, args.apply))
    if selected_modes > 1:
        _write(
            args,
            {
                "ok": False,
                "mode": "plan",
                "error": "Use only one of --preview, --dry-run-ai, or --apply.",
            },
        )
        return 2
    if selected_modes == 0:
        _write(args, _plan_payload(args))
        return 0

    settings = get_settings()
    dsn = os.getenv("DB_DSN") or settings.db_dsn
    bulk_model = selected_review_batch_model(settings)
    recheck_model = selected_review_recheck_model(settings)
    bulk_role = resolve("review_bulk", settings)
    recheck_role = resolve("review_recheck", settings)
    if args.apply:
        guard_error = _apply_guard_error(args)
        if guard_error:
            _write(args, {"ok": False, "mode": "apply", "error": guard_error})
            return 2
    if args.dry_run_ai and _live_ai_disabled(settings):
        _write(
            args,
            _disabled_payload(
                bulk_role=bulk_role,
                recheck_role=recheck_role,
                reason=_live_ai_disabled_reason(settings),
            ),
        )
        return 0
    if args.apply and _live_ai_disabled(settings):
        _write(
            args,
            {
                **_disabled_payload(
                    bulk_role=bulk_role,
                    recheck_role=recheck_role,
                    reason=_live_ai_disabled_reason(settings),
                ),
                "ok": False,
                "mode": "apply",
                "error": "Live AI is disabled; apply is fail-closed.",
            },
        )
        return 2
    if not dsn:
        _write(args, {"ok": False, "mode": _mode(args), "error": "DB_DSN is not configured."})
        return 2

    started_at = datetime.now(UTC)
    live_lane = bool(args.dry_run_ai or args.apply)
    source_method = "openai" if live_lane else "deterministic"
    recheck_routed_count = 0
    recheck_upgraded_count = 0
    recheck_failed_count = 0
    try:
        openai_base_url_host = resolve_openai_base_url_host(settings.openai_base_url)
    except ValueError as exc:
        _write(args, {"ok": False, "mode": _mode(args), "error": str(exc)})
        return 2
    try:
        candidates = fetch_review_attribute_candidates(
            dsn=dsn,
            category=args.category,
            min_organic=args.min_organic,
            limit=args.limit,
            connect_timeout=args.connect_timeout,
        )
        if args.preview:
            # Preview is deterministic only and must never invoke either live lane.
            enrichments = build_deterministic_enrichments(candidates)
        else:
            # Bulk lane: standard OpenAI gpt-5.4-nano.
            enrichments = generate_ai_enrichments(
                candidates=candidates,
                batch_size=args.batch_size,
                retry_attempts=args.retry_attempts,
                retry_delay_sec=args.retry_delay_sec,
            )
            # Selective recheck: route only low-confidence rows to gpt-5.4-mini.
            # No low-confidence rows => generate_ai_recheck is not invoked.
            routed = route_low_confidence_enrichments(enrichments)
            recheck_routed_count = len(routed)
            if routed:
                recheck_stats: dict[str, int] = {}
                enrichments = generate_ai_recheck(
                    candidates=candidates,
                    enrichments=enrichments,
                    batch_size=args.batch_size,
                    retry_attempts=args.retry_attempts,
                    retry_delay_sec=args.retry_delay_sec,
                    recheck_stats=recheck_stats,
                )
                recheck_failed_count = recheck_stats.get("recheck_failed_count", 0)
                recheck_upgraded_count = sum(
                    1 for item in enrichments if item.source_method == "openai_recheck"
                )
        updated_rows = 0
        if args.apply:
            updated_rows = apply_review_attribute_enrichments(
                dsn=dsn,
                candidates=candidates,
                enrichments=enrichments,
                source_method=source_method,
                connect_timeout=args.connect_timeout,
            )
            finished_at = datetime.now(UTC)
            record_job_run(
                dsn=dsn,
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
            with contextlib.suppress(Exception):
                record_job_run(
                    dsn=dsn,
                    status="failed",
                    started_at=started_at,
                    finished_at=finished_at,
                    duration_ms=duration_ms(started_at, finished_at),
                    error_message=redact_secret_text(
                        str(exc) or exc.__class__.__name__,
                        (dsn, settings.openai_api_key),
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
                    (dsn, settings.openai_api_key),
                ),
            },
        )
        return 2

    _write(
        args,
        {
            "ok": True,
            "mode": _mode(args),
            "live_ai_call": bool(args.dry_run_ai or args.apply),
            "db_mutation": bool(args.apply),
            "target": "community.place_mentions_weekly",
            "job_name": JOB_NAME,
            "prompt_version": PROMPT_VERSION,
            "model_role": "review_bulk",
            "model_roles": {
                "review_bulk": bulk_role.as_metadata(),
                "review_recheck": recheck_role.as_metadata(),
            },
            "bulk_model": bulk_model,
            "recheck_model": recheck_model,
            "recheck_routed_count": recheck_routed_count,
            "recheck_upgraded_count": recheck_upgraded_count,
            "recheck_failed_count": recheck_failed_count,
            "openai_base_url_host": openai_base_url_host,
            "source_method": source_method,
            "candidate_count": len(candidates),
            "generated_count": len(enrichments),
            "updated_rows": updated_rows,
            "preview_candidates": [item.to_public_dict() for item in candidates[:5]],
            "preview": [item.to_public_dict() for item in enrichments[:5]],
        },
    )
    return 0


def _plan_payload(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "live_ai_call": False,
        "db_mutation": False,
        "target": "community.place_mentions_weekly",
        "job_name": JOB_NAME,
        "prompt_version": PROMPT_VERSION,
        "model_role": "review_bulk",
        "model_envs": {
            "review_bulk": "LALA_MODEL_ROLE_REVIEW_BULK (legacy OPENAI_REVIEW_BATCH_MODEL)",
            "review_recheck": "LALA_MODEL_ROLE_REVIEW_RECHECK (legacy OPENAI_REVIEW_RECHECK_MODEL)",
        },
        "live_ai_required_env": ["OPENAI_API_KEY", "LALA_ENABLE_LIVE_AI"],
        "input_relations": [
            "community.place_mentions_weekly",
            "community.posts",
        ],
        "output_attributes": [
            "attributes.review_attributes",
            "attributes.review_quality",
            "sentiment_score",
        ],
        "default_min_organic": args.min_organic,
        "apply_required_env": ["DB_DSN", "OPENAI_API_KEY", "LALA_ENABLE_LIVE_AI", ALLOW_ENV],
    }


def _live_ai_disabled(settings: Any) -> bool:
    return not bool(getattr(settings, "enable_live_ai", False)) or not bool(
        getattr(settings, "openai_api_key", "")
    )


def _live_ai_disabled_reason(settings: Any) -> str:
    missing = []
    if not getattr(settings, "enable_live_ai", False):
        missing.append("LALA_ENABLE_LIVE_AI=true")
    if not getattr(settings, "openai_api_key", ""):
        missing.append("OPENAI_API_KEY")
    return "missing_or_disabled:" + ",".join(missing)


def _disabled_payload(*, bulk_role: Any, recheck_role: Any, reason: str) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "disabled",
        "status": "disabled",
        "reason": reason,
        "live_ai_call": False,
        "db_mutation": False,
        "target": "community.place_mentions_weekly",
        "job_name": JOB_NAME,
        "prompt_version": PROMPT_VERSION,
        "model_role": "review_bulk",
        "model_roles": {
            "review_bulk": bulk_role.as_metadata(),
            "review_recheck": recheck_role.as_metadata(),
        },
        "candidate_count": 0,
        "generated_count": 0,
        "updated_rows": 0,
        "recheck_routed_count": 0,
        "recheck_upgraded_count": 0,
        "recheck_failed_count": 0,
    }


def _validation_error(args: argparse.Namespace) -> str:
    if args.limit <= 0:
        return "--limit must be positive."
    if args.min_organic <= 0:
        return "--min-organic must be positive."
    if args.batch_size <= 0:
        return "--batch-size must be positive."
    if args.retry_attempts <= 0:
        return "--retry-attempts must be positive."
    if args.retry_delay_sec < 0:
        return "--retry-delay-sec must be non-negative."
    return ""


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

    print("LALA-next review attribute batch")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target', 'community.place_mentions_weekly')}")
    print(f"prompt_version={payload.get('prompt_version', PROMPT_VERSION)}")
    if payload.get("model_role"):
        print(f"model_role={payload['model_role']}")
    if "live_ai_call" in payload:
        print(f"live_ai_call={str(payload.get('live_ai_call')).lower()}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if payload.get("source_method"):
        print(f"source_method={payload['source_method']}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return
    for key in (
        "candidate_count",
        "generated_count",
        "updated_rows",
        "recheck_routed_count",
        "recheck_upgraded_count",
    ):
        if key in payload:
            print(f"{key}={payload[key]}")
    for relation in payload.get("input_relations") or []:
        print(f"input_relation={relation}")
    for item in payload.get("output_attributes") or []:
        print(f"output_attribute={item}")
    for item in payload.get("preview") or []:
        print(
            "preview="
            + json.dumps(
                {
                    "mention_id": item.get("mention_id"),
                    "attribute_mean": item.get("attribute_mean"),
                    "sentiment_score": item.get("sentiment_score"),
                    "source_method": item.get("source_method"),
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )


def _mode(args: argparse.Namespace) -> str:
    if args.apply:
        return "apply"
    if args.dry_run_ai:
        return "dry-run-ai"
    return "preview"


if __name__ == "__main__":
    raise SystemExit(main())
