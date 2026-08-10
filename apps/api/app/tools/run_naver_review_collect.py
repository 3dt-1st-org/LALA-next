"""Naver Search Open API review/mention collection tool (governed, aggregate-only).

Mirrors run_review_mention_ingest.py's structure: --preview/--apply,
--confirm APPLY_NAVER_REVIEW_COLLECT, ALLOW_NAVER_REVIEW_COLLECT_APPLY=1, JSON
stdout, DSN via the app settings loader.

**Atomicity (P1a fix):** apply runs receipts + weekly aggregates in ONE
``with conn:`` transaction via ``govern_review_ingest_on_cursor`` +
``insert_review_mention_aggregates_on_cursor``. If the aggregate upsert fails,
receipts roll back together — a clean re-run re-accepts and re-aggregates.

**Place-aware full digests (P1b/P2 fix):** ``content_sha256`` and
``external_key`` are place-aware (include ``place_id``) and use the full 64-hex
sha256. Accepted records are mapped by full ``content_sha256``, not the
truncated ``aggregate_key``, so the same post for two places yields two
distinct, non-colliding signals.

**Partial-failure degradation (P-add):** if any provider returns
auth_missing/quota_exceeded/network_error/parse_error or governance quarantines
records, the top-level status is ``degraded``. If all providers fail, ``failed``.

Raw provider text (title/body/url) is NEVER persisted, logged, or written to
community.posts. Only content_sha256 + opaque external_key + provenance reach
the governance boundary; only aggregate counts reach community.place_mentions_weekly.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
from collections import defaultdict
from collections.abc import Mapping
from dataclasses import dataclass, field
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
    govern_review_ingest_on_cursor,
    load_active_review_source,
)
from apps.api.app.services.review_mention_ingest import (
    PROMPT_VERSION,
    ReviewMentionDecision,
    ReviewMentionPlace,
    ReviewMentionPost,
    ReviewMentionWeeklyAggregate,
    _week_start,
    classify_post,
    insert_review_mention_aggregates_on_cursor,
    record_job_run,
)

CONFIRM_TEXT = "APPLY_NAVER_REVIEW_COLLECT"
ALLOW_ENV = "ALLOW_NAVER_REVIEW_COLLECT_APPLY"
JOB_NAME = "naver-review-collect"

# Categories that degrade (but don't necessarily fail) a run. "empty" is an
# honest zero-result success, NOT a failure.
_DEGRADING_CATEGORIES = frozenset(
    {"auth_missing", "quota_exceeded", "network_error", "parse_error"}
)


@dataclass(frozen=True)
class _AggregateProvenance:
    """Maps a full content_sha256 to the place/provider for aggregate rebuild."""

    place_id: str
    place_name_ko: str
    sub_provider: str
    category: str
    week_start: date


@dataclass(frozen=True)
class _AcquireResult:
    """Structured result of acquire + classify across all places."""

    failure_tally: dict[str, dict[str, int]]
    candidates: int
    ad_filtered: int
    organic_records: list[dict[str, Any]] = field(default_factory=list)
    sha_lookup: dict[str, _AggregateProvenance] = field(default_factory=dict)
    places_count: int = 0


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
        help="Govern + upsert place_mentions_weekly in ONE atomic transaction.",
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

    if args.apply:
        return _run_apply(args, dsn)
    return _run_preview(args, dsn)


# --- preview: read-only gate + places, then in-memory acquire + classify ---


def _run_preview(args: argparse.Namespace, dsn: str) -> int:
    conn = _open_connection(dsn, args.connect_timeout)
    try:
        with conn:
            with conn.cursor() as cur:
                registration = load_active_review_source(
                    cur,
                    source_name=SOURCE_NAME,
                    expected_provider=EXPECTED_PROVIDER,
                    expected_terms_version=EXPECTED_TERMS_VERSION,
                )
                places = _read_places_on_cursor(cur, args.limit)
    except ReviewGovernanceError as exc:
        _write(
            args,
            {
                "ok": False,
                "mode": "preview",
                "error": exc.message,
                "governance_code": exc.code,
            },
        )
        return 2
    finally:
        conn.close()

    batch = _acquire_and_classify(places=places, display=args.display, registration=registration)
    status = _compute_status(batch.failure_tally, 0)
    _write(
        args,
        {
            "ok": True,
            "status": status,
            "mode": "preview",
            "source_name": SOURCE_NAME,
            "places": batch.places_count,
            "candidates": batch.candidates,
            "ad_filtered_out": batch.ad_filtered,
            "organic": len(batch.organic_records),
            "failure_tally": batch.failure_tally,
        },
    )
    return 0


# --- apply: preflight gate → acquire (no DB) → atomic write transaction ---


def _run_apply(args: argparse.Namespace, dsn: str) -> int:
    started_at = datetime.now(UTC)
    window_start = _week_start(started_at)

    # Phase 1: Preflight gate + read places (short-lived, NO held transaction).
    # Fail-fast before any Naver API call: if the source isn't registered/active,
    # don't waste network calls. The connection is CLOSED before Phase 2.
    registration: ReviewSourceRegistration | None = None
    places: list[ReviewMentionPlace] = []
    try:
        preflight_conn = _open_connection(dsn, args.connect_timeout)
        try:
            with preflight_conn:
                with preflight_conn.cursor() as cur:
                    registration = load_active_review_source(
                        cur,
                        source_name=SOURCE_NAME,
                        expected_provider=EXPECTED_PROVIDER,
                        expected_terms_version=EXPECTED_TERMS_VERSION,
                    )
                    places = _read_places_on_cursor(cur, args.limit)
        finally:
            preflight_conn.close()
    except ReviewGovernanceError as exc:
        _best_effort_job_run(args, dsn, started_at, "failed", exc.message)
        _write(
            args,
            {
                "ok": False,
                "mode": "apply",
                "error": exc.message,
                "governance_code": exc.code,
            },
        )
        return 2

    # Phase 2: Acquire + classify OUTSIDE any DB transaction.
    # No PostgreSQL connection is open during Naver network I/O — avoids
    # idle-in-transaction timeouts, bloat, and lock contention at scale.
    batch = _acquire_and_classify(places=places, display=args.display, registration=registration)

    # Phase 3: Atomic write transaction (ONE connection, ONE ``with conn:``).
    # govern_review_ingest_on_cursor RE-CHECKS the DG-1 gate inside this
    # transaction (authoritative fail-closed). Receipts + aggregates commit or
    # roll back TOGETHER (P1a fix). If the aggregate upsert fails, the rollback
    # undoes every receipt so a clean re-run fully recovers.
    conn = _open_connection(dsn, args.connect_timeout)
    ingest_result = None
    aggregates: list[ReviewMentionWeeklyAggregate] = []
    inserted_rows = 0
    try:
        with conn:
            with conn.cursor() as cur:
                ingest_result = govern_review_ingest_on_cursor(
                    cur,
                    source_name=SOURCE_NAME,
                    expected_provider=EXPECTED_PROVIDER,
                    expected_terms_version=EXPECTED_TERMS_VERSION,
                    records=batch.organic_records,
                    window_start=window_start,
                )
                aggregates = _build_weekly_aggregates(
                    accepted_records=ingest_result.accepted_records,
                    sha_lookup=batch.sha_lookup,
                )
                inserted_rows = insert_review_mention_aggregates_on_cursor(cur, aggregates)
    except ReviewGovernanceError as exc:
        _best_effort_job_run(args, dsn, started_at, "failed", exc.message)
        _write(
            args,
            {
                "ok": False,
                "mode": "apply",
                "error": exc.message,
                "governance_code": exc.code,
            },
        )
        return 2
    except Exception as exc:
        error_msg = redact_secret_text(str(exc) or exc.__class__.__name__, (dsn,))
        _best_effort_job_run(args, dsn, started_at, "failed", error_msg)
        _write(args, {"ok": False, "mode": "apply", "error": error_msg})
        return 2
    finally:
        conn.close()

    status = _compute_status(batch.failure_tally, ingest_result.run.quarantined_count)
    _best_effort_job_run(args, dsn, started_at, status, None)

    _write(
        args,
        {
            "ok": status != "failed",
            "status": status,
            "mode": "apply",
            "source_name": SOURCE_NAME,
            "places": batch.places_count,
            "candidates": batch.candidates,
            "ad_filtered_out": batch.ad_filtered,
            "organic": len(batch.organic_records),
            "processed": ingest_result.run.processed_count,
            "duplicate": ingest_result.run.duplicate_count,
            "quarantined": ingest_result.run.quarantined_count,
            "aggregated": len(aggregates),
            "inserted_rows": inserted_rows,
            "window_start": window_start.isoformat(),
            "failure_tally": batch.failure_tally,
        },
    )
    return 0


# --- connection / DB helpers ---


def _open_connection(dsn: str, connect_timeout: int):
    """Open a psycopg2 connection. Extracted for test injection."""
    import psycopg2

    return psycopg2.connect(dsn, connect_timeout=connect_timeout)


def _read_places_on_cursor(cur, limit: int) -> list[ReviewMentionPlace]:
    sql = """
        SELECT place_id, name_ko, category, region_name_ko
        FROM travel.places
        WHERE name_ko IS NOT NULL
        ORDER BY place_id
        LIMIT %s
    """
    cur.execute(sql, (limit,))
    return [
        ReviewMentionPlace(
            place_id=str(row[0]),
            name_ko=str(row[1]),
            category=str(row[2] or "attraction"),
            region_name_ko=row[3],
        )
        for row in cur.fetchall()
    ]


# --- in-memory acquire + classify (shared by preview and apply) ---


def _acquire_and_classify(
    *,
    places: list[ReviewMentionPlace],
    display: int,
    registration: ReviewSourceRegistration,
) -> _AcquireResult:
    failure_tally: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    candidates = 0
    ad_filtered = 0
    organic_records: list[dict[str, Any]] = []
    sha_lookup: dict[str, _AggregateProvenance] = {}

    for place in places:
        if not place.name_ko or len(place.name_ko) < 2:
            continue
        result = collect_mentions_for_place(
            place_id=place.place_id,
            place_name=place.name_ko,
            region=place.region_name_ko or "",
            category=place.category,
            display=display,
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
                # Key by FULL content_sha256 — no truncation (P1b/P2 fix).
                sha_lookup[record["content_sha256"]] = _AggregateProvenance(
                    place_id=place.place_id,
                    place_name_ko=place.name_ko,
                    sub_provider=post.provider,
                    category=place.category,
                    week_start=decision.week_start,
                )

    return _AcquireResult(
        failure_tally={k: dict(v) for k, v in failure_tally.items()},
        candidates=candidates,
        ad_filtered=ad_filtered,
        organic_records=organic_records,
        sha_lookup=sha_lookup,
        places_count=len(places),
    )


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
    """Build a no-raw-text record dict for the governance boundary."""
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


def _build_weekly_aggregates(
    *,
    accepted_records: tuple,
    sha_lookup: dict[str, _AggregateProvenance],
) -> list[ReviewMentionWeeklyAggregate]:
    """Map accepted records to places by FULL content_sha256 and group by week.

    No truncation — each accepted record's full 64-hex content_sha256 is looked
    up directly in sha_lookup (P1b/P2 fix). Raw text never appears.
    """
    grouped: dict[tuple[Any, ...], int] = defaultdict(int)
    for record in accepted_records:
        prov = sha_lookup.get(record.content_sha256)
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


# --- status / output / guards ---


def _compute_status(failure_tally: Mapping[str, Mapping[str, int]], quarantined_count: int) -> str:
    """succeeded / degraded / failed based on acquisition + quarantine health."""
    total_calls = 0
    failure_calls = 0
    for tallies in failure_tally.values():
        for cat, count in tallies.items():
            total_calls += count
            if cat in _DEGRADING_CATEGORIES:
                failure_calls += count
    if total_calls > 0 and failure_calls == total_calls:
        return "failed"
    if failure_calls > 0 or quarantined_count > 0:
        return "degraded"
    return "succeeded"


def _best_effort_job_run(
    args: argparse.Namespace,
    dsn: str,
    started_at: datetime,
    status: str,
    error_message: str | None,
) -> None:
    finished_at = datetime.now(UTC)
    with contextlib.suppress(Exception):
        record_job_run(
            dsn=dsn,
            status=status,
            started_at=started_at,
            finished_at=finished_at,
            duration_ms=_duration_ms(started_at, finished_at),
            error_message=error_message,
            connect_timeout=args.connect_timeout,
        )


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
            "place_aware_full_digest_identity",
            "accurate_rowcount_counts",
            "one_transaction_atomic_receipts_aggregates",
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
    print(f"ok={str(payload.get('ok', False)).lower()}")
    if payload.get("status"):
        print(f"status={payload['status']}")
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
