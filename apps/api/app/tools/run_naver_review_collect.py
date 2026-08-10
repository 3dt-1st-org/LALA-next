"""Naver Search Open API review/mention collection tool (governed, aggregate-only).

Mirrors run_review_mention_ingest.py's structure: --preview/--apply,
--confirm APPLY_NAVER_REVIEW_COLLECT, ALLOW_NAVER_REVIEW_COLLECT_APPLY=1, JSON
stdout, DSN via the app settings loader.

DG-1 gate is checked BEFORE any network call. The gate refuses acquisition until
an operator registers ingest.review_sources with source_name='naver_search',
provider='naver', terms_version='naver-search-openapi-terms-v1', an allowed
license_class, and source_status='active'.

Raw provider text (title/body/url) is NEVER persisted, logged, or written to
community.posts. Only content_sha256 + opaque external_key + provenance reach the
governance boundary; only aggregate counts reach community.place_mentions_weekly.

Counts come from the governance boundary's rowcount-backed ReviewIngestResult,
never from len(results).
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.naver_search_service import (
    EXPECTED_PROVIDER,
    EXPECTED_TERMS_VERSION,
    SOURCE_NAME,
    TransientNaverPost,
    collect_mentions_for_place,
)
from apps.api.app.services.review_ingest_governance import (
    ReviewGovernanceError,
    ReviewSourceRegistration,
    load_active_review_source,
    persist_review_ingest_run,
)
from apps.api.app.services.review_mention_ingest import (
    PROMPT_VERSION,
    ReviewMentionDecision,
    ReviewMentionPlace,
    ReviewMentionPost,
    ReviewMentionWeeklyAggregate,
    _week_start,
    classify_post,
    insert_review_mention_aggregates,
    record_job_run,
)

CONFIRM_TEXT = "APPLY_NAVER_REVIEW_COLLECT"
ALLOW_ENV = "ALLOW_NAVER_REVIEW_COLLECT_APPLY"
JOB_NAME = "naver-review-collect"


@dataclass(frozen=True)
class _AggregateProvenance:
    """Maps a content_sha256 to the place/provider used for aggregate rebuild."""

    place_id: str
    place_name_ko: str
    sub_provider: str
    category: str
    week_start: date


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Collect place mentions from Naver Search Open API (governed)."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument(
        "--preview", action="store_true", help="Acquire + classify, counts only, no DB writes."
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Govern through review_ingest_governance + upsert place_mentions_weekly.",
    )
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument("--limit", type=int, default=50, help="Max places to process.")
    parser.add_argument("--display", type=int, default=5, help="Results per Naver endpoint.")
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

    if args.apply:
        guard_error = _apply_guard_error(args)
        if guard_error:
            _write(args, {"ok": False, "mode": "apply", "error": guard_error})
            return 2

    settings = get_settings()
    dsn = os.getenv("DB_DSN") or settings.db_dsn
    if not dsn:
        _write(args, {"ok": False, "mode": _mode(args), "error": "DB_DSN is not configured."})
        return 2

    # DG-1 gate (fail-closed, read-only). No acquisition until this passes.
    try:
        registration = _check_gate(dsn=dsn, connect_timeout=args.connect_timeout)
    except ReviewGovernanceError as exc:
        _write(
            args,
            {
                "ok": False,
                "mode": _mode(args),
                "error": exc.message,
                "governance_code": exc.code,
            },
        )
        return 2

    places = _read_places(dsn=dsn, limit=args.limit, connect_timeout=args.connect_timeout)

    # Acquire + classify in memory (no DB writes in this block).
    failure_tally: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    candidates = 0
    ad_filtered = 0
    organic_records: list[dict[str, Any]] = []
    aggregate_lookup: dict[str, _AggregateProvenance] = {}

    for place in places:
        if not place.name_ko or len(place.name_ko) < 2:
            continue
        result = collect_mentions_for_place(
            place_id=place.place_id,
            place_name=place.name_ko,
            region=place.region_name_ko or "",
            category=place.category,
            display=args.display,
        )
        for outcome in result.outcomes:
            failure_tally[outcome.provider][outcome.category] += 1
        candidates += len(result.posts)

        for post in result.posts:
            rm_post = _to_review_mention_post(post)
            decision = classify_post(post=rm_post, places=[place])
            if decision.is_ad:
                ad_filtered += 1
            if decision.retained:
                record = _build_governed_record(
                    post=post, decision=decision, registration=registration
                )
                organic_records.append(record)
                aggregate_lookup[_aggregate_key(record["content_sha256"])] = _AggregateProvenance(
                    place_id=place.place_id,
                    place_name_ko=place.name_ko,
                    sub_provider=post.provider,
                    category=place.category,
                    week_start=decision.week_start,
                )

    summary: dict[str, Any] = {
        "ok": True,
        "mode": _mode(args),
        "source_name": SOURCE_NAME,
        "expected_provider": EXPECTED_PROVIDER,
        "expected_terms_version": EXPECTED_TERMS_VERSION,
        "places": len(places),
        "candidates": candidates,
        "ad_filtered_out": ad_filtered,
        "organic": len(organic_records),
        "failure_tally": {k: dict(v) for k, v in failure_tally.items()},
    }

    if args.preview:
        # Preview is fully non-mutating: counts only, no DB writes.
        _write(args, summary)
        return 0

    # --- Apply: govern + aggregate (single governance transaction) ---
    window_start = _week_start(datetime.now(UTC))
    started_at = datetime.now(UTC)
    try:
        ingest_result = persist_review_ingest_run(
            dsn=dsn,
            source_name=SOURCE_NAME,
            expected_provider=EXPECTED_PROVIDER,
            expected_terms_version=EXPECTED_TERMS_VERSION,
            records=organic_records,
            window_start=window_start,
            connect_timeout=args.connect_timeout,
        )
        aggregates = _build_weekly_aggregates(
            accepted=ingest_result.accepted,
            aggregate_lookup=aggregate_lookup,
        )
        inserted_rows = insert_review_mention_aggregates(
            dsn=dsn,
            aggregates=aggregates,
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
        finished_at = datetime.now(UTC)
        with contextlib.suppress(Exception):
            record_job_run(
                dsn=dsn,
                status="failed",
                started_at=started_at,
                finished_at=finished_at,
                duration_ms=_duration_ms(started_at, finished_at),
                error_message=redact_secret_text(str(exc) or exc.__class__.__name__, (dsn,)),
                connect_timeout=args.connect_timeout,
            )
        _write(
            args,
            {
                "ok": False,
                "mode": "apply",
                "error": redact_secret_text(str(exc) or exc.__class__.__name__, (dsn,)),
            },
        )
        return 2

    summary["processed"] = ingest_result.run.processed_count
    summary["duplicate"] = ingest_result.run.duplicate_count
    summary["quarantined"] = ingest_result.run.quarantined_count
    summary["aggregated"] = len(aggregates)
    summary["inserted_rows"] = inserted_rows
    summary["window_start"] = window_start.isoformat()
    _write(args, summary)
    return 0


# --- DB helpers (read-only gate + place list; write helpers delegate to services) ---


def _check_gate(*, dsn: str, connect_timeout: int) -> ReviewSourceRegistration:
    """DG-1 fail-closed source gate. Opens a read-only connection; writes nothing."""
    import psycopg2

    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            return load_active_review_source(
                cur,
                source_name=SOURCE_NAME,
                expected_provider=EXPECTED_PROVIDER,
                expected_terms_version=EXPECTED_TERMS_VERSION,
            )


def _read_places(*, dsn: str, limit: int, connect_timeout: int) -> list[ReviewMentionPlace]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    sql = """
        SELECT place_id, name_ko, category, region_name_ko
        FROM travel.places
        WHERE name_ko IS NOT NULL
        ORDER BY place_id
        LIMIT %s
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, (limit,))
            rows = cur.fetchall()
    return [
        ReviewMentionPlace(
            place_id=str(row["place_id"]),
            name_ko=str(row["name_ko"]),
            category=str(row["category"] or "attraction"),
            region_name_ko=row.get("region_name_ko"),
        )
        for row in rows
    ]


# --- in-memory record + aggregate builders (no raw text) ---


def _to_review_mention_post(post: TransientNaverPost) -> ReviewMentionPost:
    """Build the filter's input post. post_url is None — URL never leaves memory."""
    return ReviewMentionPost(
        provider=post.provider,
        external_key=post.external_key,
        keyword=post.keyword,
        region_slug=post.region,
        title=post.title,
        body=post.description,
        post_url=None,
        created_at_source=post.created_at_source,
        collected_at=datetime.now(UTC),
    )


def _build_governed_record(
    *,
    post: TransientNaverPost,
    decision: ReviewMentionDecision,
    registration: ReviewSourceRegistration,
) -> dict[str, Any]:
    """Build a no-raw-text record dict for the governance boundary.

    Only content_sha256 + opaque external_key + provenance + registration-bound
    identity. No body/title/url fields — ReviewSourceRecord.extra='forbid'
    rejects them if accidentally added.
    """
    return {
        "source_name": registration.source_name,
        "provider": registration.provider,
        "external_key": post.external_key,
        "license_class": registration.license_class,
        "terms_version": registration.terms_version,
        "content_sha256": post.content_sha256,
        "received_at": datetime.now(UTC),
        "category": post.category,
        "match_confidence": decision.match_confidence,
        "is_organic": True,
    }


def _aggregate_key(content_sha256: str) -> str:
    """Mirror ApprovedReviewAggregate.aggregate_key for reverse mapping."""
    return f"sha256:{content_sha256[:16]}"


def _build_weekly_aggregates(
    *,
    accepted: tuple,
    aggregate_lookup: dict[str, _AggregateProvenance],
) -> list[ReviewMentionWeeklyAggregate]:
    """Map accepted governance aggregates back to places and group by week.

    mention_count = organic accepted count per (week_start, place, provider,
    category). Raw text never appears — only counts and provenance.
    """
    grouped: dict[tuple[Any, ...], int] = defaultdict(int)
    for agg in accepted:
        prov = aggregate_lookup.get(agg.aggregate_key)
        if prov is None:
            continue
        key = (
            prov.week_start,
            prov.place_id,
            prov.place_name_ko,
            prov.sub_provider,
            prov.category,
        )
        grouped[key] += 1

    aggregates: list[ReviewMentionWeeklyAggregate] = []
    for key, count in sorted(grouped.items()):
        week_start, place_id, place_name_ko, sub_provider, category = key
        aggregates.append(
            ReviewMentionWeeklyAggregate(
                week_start=week_start,
                place_id=place_id,
                place_name_ko=place_name_ko,
                provider=sub_provider,
                category=category,
                mention_count=count,
                organic_mention_count=count,
                sentiment_score=None,
                attributes={
                    "prompt_version": PROMPT_VERSION,
                    "source": SOURCE_NAME,
                    "collection_method": "naver_search_openapi",
                    "organic_review_count": count,
                },
            )
        )
    return aggregates


# --- output / guards ---


def _plan_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "plan",
        "db_mutation": False,
        "source_name": SOURCE_NAME,
        "expected_provider": EXPECTED_PROVIDER,
        "expected_terms_version": EXPECTED_TERMS_VERSION,
        "target": "community.place_mentions_weekly",
        "acquisition": "Naver Search Open API (blog + cafearticle) — no scraping",
        "apply_required_env": [
            "DB_DSN",
            ALLOW_ENV,
            "NAVER_CLIENT_ID",
            "NAVER_CLIENT_SECRET",
        ],
        "dg1_gate": (
            "Requires ingest.review_sources row: "
            f"source_name='{SOURCE_NAME}', provider='{EXPECTED_PROVIDER}', "
            f"terms_version='{EXPECTED_TERMS_VERSION}', "
            "license_class IN (licensed|public_processed|approved_export), "
            "source_status='active'."
        ),
        "review_rules": [
            "dg1_gate_fail_closed",
            "official_api_only_no_scraping_no_daangn",
            "advertising_filtered",
            "aggregate_only_no_raw_text",
            "opaque_digest_identity",
            "accurate_rowcount_counts",
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

    mode = payload.get("mode", "plan")
    print("LALA-next Naver review/mention collection (governed)")
    print(f"mode={mode}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"source_name={SOURCE_NAME}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        if payload.get("governance_code"):
            print(f"governance_code={payload['governance_code']}")
        return
    for key in (
        "places",
        "candidates",
        "ad_filtered_out",
        "organic",
        "processed",
        "duplicate",
        "quarantined",
        "aggregated",
        "inserted_rows",
    ):
        if key in payload:
            print(f"{key}={payload[key]}")
    if payload.get("failure_tally"):
        for provider, tallies in sorted(payload["failure_tally"].items()):
            for cat, count in sorted(tallies.items()):
                print(f"failure_tally.{provider}.{cat}={count}")


def _duration_ms(started_at: datetime, finished_at: datetime) -> int:
    return int((finished_at - started_at).total_seconds() * 1000)


def _mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "preview"


if __name__ == "__main__":
    raise SystemExit(main())
