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

**Region-targeted place window (region-filter fix):** ``--region
<manual-region-id>`` scopes the place query to the region's canonical
``travel.places.region_name_ko`` spellings via
``region_catalog.manual_region_place_names`` (``= ANY(%s)``), with ``--limit``
applying within the region. Unmappable ids fail closed before any network call
or write. Without ``--region`` the place query and ordering are unchanged.

**Bounded resumable continuation (P5A):** ``--after-place-id <cursor>`` resumes
the region-scoped ``ORDER BY place_id`` window strictly AFTER the cursor
(keyset ``place_id > %s``, parameterized — never interpolated). The published
``next_after_place_id`` only ever advances past CONSECUTIVELY COMPLETED
places: a place with any degrading endpoint outcome, or any unattempted place
(budget stop / fatal stop), stops advancement so the next run re-selects it —
an unattempted or partially failed place is never skipped. On apply rollback
or governance recheck failure NO advanced cursor is published. Resume MUST
reuse the same ``--region`` scope (the cursor is only meaningful inside it);
the payload echoes ``cursor_scope`` for that contract.

**Per-run request ceiling (P5A):** ``--max-requests`` bounds actual provider
HTTP attempts (blog + cafearticle = up to 2 per place). ``requests_used``
counts OBSERVED wire attempts (``AcquisitionOutcome.wire_attempted``): HTTP
401/403/429/network/parse failures happen after a request and count, while a
missing-credential stop launches no request and counts zero. The budget
RESERVES both endpoint slots before starting a place (never split mid-place);
the reservation is labeled separately from observed attempts. Acquisition of a
place stops at the FIRST fatal ``auth_missing``/``quota_exceeded`` endpoint —
the second endpoint is not launched and no outcome is fabricated for it — and
the run stops instead of marching through the remaining places. No retries,
no fallback provider.

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
from datetime import UTC, date, datetime, timedelta
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
from apps.api.app.services.region_catalog import (
    manual_region_place_names,
    manual_region_tour_api_area_code,
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

# P5A: acquisition stops immediately on these (no marching through remaining
# places, no retry storm, no provider fallback).
_FATAL_CATEGORIES = frozenset({"auth_missing", "quota_exceeded"})

# P5A: the existing provider boundary is blog + cafearticle — exactly two
# endpoint requests per place. A place is only started when the whole pair
# fits the remaining request budget (never split mid-place).
_ENDPOINTS_PER_PLACE = 2

# P5A: hard validation ceiling for --max-requests. Finite and documented; the
# default (2 x limit) preserves the existing small batch's safe upper bound.
MAX_REQUESTS_HARD_CAP = 500

# P5A: bounded cursor contract. place_id slugs are short printable tokens; a
# cursor containing whitespace, control/non-printable characters (NUL/DEL/ESC)
# or unreasonable length is malformed and fails closed before settings, DB, or
# acquisition. Printable-but-not-ASCII is allowed (matches the existing id
# contract); isprintable() rejects the C0/C1 control planes and DEL.
_CURSOR_MAX_LENGTH = 128


def _is_valid_cursor(value: str) -> bool:
    return (
        bool(value)
        and len(value) <= _CURSOR_MAX_LENGTH
        and value.isprintable()
        and not any(ch.isspace() for ch in value)
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
    # P5A continuation bookkeeping (honest, never fabricated).
    places_attempted: int = 0
    places_completed: int = 0
    places_deferred: int = 0
    places_name_skipped: int = 0
    requests_used: int = 0
    request_cap: int = 0
    next_after_place_id: str | None = None
    stop_reason: str | None = None


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
    parser.add_argument("--confirm", default=None, help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument(
        "--limit", type=int, default=None, help="Max places to process (default 50)."
    )
    parser.add_argument(
        "--region",
        default=None,
        help=(
            "Optional manual-region id (e.g. seoul-seongdong); scopes the place "
            "window to the region's canonical places, with --limit applying "
            "within the region. Unmappable ids fail closed."
        ),
    )
    parser.add_argument(
        "--display", type=int, default=None, help="Results per Naver endpoint (default 5)."
    )
    parser.add_argument(
        "--after-place-id",
        default=None,
        help=(
            "P5A continuation cursor: resume the region-scoped ORDER BY place_id "
            "window strictly AFTER this place_id (keyset, parameterized). Reuse "
            "the SAME --region scope you started with; the payload's "
            "next_after_place_id is only meaningful inside that scope."
        ),
    )
    parser.add_argument(
        "--max-requests",
        type=int,
        default=None,
        help=(
            "P5A per-run ceiling on actual provider endpoint requests "
            "(blog + cafearticle; failed attempts count). Default 2x --limit "
            f"(preserves today's safe upper bound); hard cap {MAX_REQUESTS_HARD_CAP}."
        ),
    )
    parser.add_argument(
        "--connect-timeout", type=int, default=None, help="Connection timeout seconds (default 5)."
    )
    parser.add_argument(
        "--schedule",
        action="store_true",
        help=(
            "P5B offline regional work-plan: classify canonical regions from a "
            "caller-supplied checkpoint snapshot and emit bounded pending-approval "
            "collection argument arrays. Zero settings/DB/provider I/O; never "
            "executes acquisition. Incompatible with --preview/--apply."
        ),
    )
    parser.add_argument(
        "--regions",
        default=None,
        help=(
            "Schedule mode only: comma-separated canonical manual region ids "
            "(deterministic sorted subset). Omit to plan over all mapped catalog "
            "regions. Unknown ids fail closed."
        ),
    )
    parser.add_argument(
        "--checkpoint-snapshot",
        default=None,
        help=(
            "Schedule mode only: explicit local checkpoint snapshot JSON built "
            "from this collector's committed apply payloads "
            "(collector_checkpoint.build_region_checkpoint). Optional — without "
            "it every region is honestly DUE/unknown."
        ),
    )
    parser.add_argument(
        "--refresh-interval-hours",
        type=int,
        default=None,
        help="Schedule mode only: completed sweeps older than this restart (default 168h).",
    )
    parser.add_argument(
        "--max-regions",
        type=int,
        default=None,
        help="Schedule mode only: bounded batch size of scheduled regions (default 3.",
    )
    parser.add_argument(
        "--per-region-requests",
        type=int,
        default=None,
        help=(
            "Schedule mode only: request cap emitted per scheduled region. "
            "Default: --max-requests if given, else 2 x --limit (the collector "
            "default), bounded [2, hard cap]."
        ),
    )
    parser.add_argument(
        "--total-request-ceiling",
        type=int,
        default=None,
        help=(
            "Schedule mode only: TOTAL planned request ceiling across the batch. "
            "Default: --max-regions x per-region-requests. Emitted caps always "
            "sum within it; regions that no longer fit are DEFERRED."
        ),
    )
    parser.add_argument(
        "--export-checkpoint",
        action="store_true",
        help=(
            "P5B offline export: read ONE bounded committed --apply result JSON "
            "(--from-collector-result) and emit a validated versioned checkpoint "
            "snapshot to stdout. Zero settings/DB/provider I/O; never executes "
            "or authorizes collection."
        ),
    )
    parser.add_argument(
        "--from-collector-result",
        default=None,
        help="Export mode only: explicit local collector apply-result JSON file.",
    )
    args = parser.parse_args(argv)

    _SCHEDULE_ONLY = (
        "--regions",
        "--checkpoint-snapshot",
        "--refresh-interval-hours",
        "--max-regions",
        "--per-region-requests",
        "--total-request-ceiling",
    )

    def _explicitly_supplied() -> list[str]:
        supplied = []
        if args.regions is not None:
            supplied.append("--regions")
        if args.checkpoint_snapshot is not None:
            supplied.append("--checkpoint-snapshot")
        if args.refresh_interval_hours is not None:
            supplied.append("--refresh-interval-hours")
        if args.max_regions is not None:
            supplied.append("--max-regions")
        if args.per_region_requests is not None:
            supplied.append("--per-region-requests")
        if args.total_request_ceiling is not None:
            supplied.append("--total-request-ceiling")
        return supplied

    # B1: mutually exclusive offline modes; fixed usage errors before any I/O.
    modes = [args.apply, args.preview, args.schedule, args.export_checkpoint]
    if sum(1 for on in modes if on) > 1:
        _write(
            args,
            {
                "ok": False,
                "mode": "plan",
                "error": (
                    "--apply, --preview, --schedule and --export-checkpoint are mutually exclusive."
                ),
            },
        )
        return 2
    if args.from_collector_result is not None and not args.export_checkpoint:
        _write(
            args,
            {
                "ok": False,
                "mode": "plan",
                "error": (
                    "--from-collector-result requires --export-checkpoint; no file was read."
                ),
            },
        )
        return 2
    if not args.schedule and not args.export_checkpoint and _explicitly_supplied():
        _write(
            args,
            {
                "ok": False,
                "mode": "plan",
                "error": (
                    "schedule-only options require --schedule; no acquisition, "
                    "plan or export was performed."
                ),
            },
        )
        return 2
    if args.schedule and (args.region is not None or args.after_place_id is not None):
        _write(
            args,
            {
                "ok": False,
                "mode": "schedule",
                "error": (
                    "--schedule plans regional batches itself; --region and "
                    "--after-place-id are collection-run options it must not "
                    "silently ignore."
                ),
            },
        )
        return 2
    if args.export_checkpoint:
        incompatible = _explicitly_supplied() + [
            flag
            for flag, value in (
                ("--region", args.region),
                ("--after-place-id", args.after_place_id),
                ("--max-requests", args.max_requests),
                ("--limit", args.limit),
                ("--display", args.display),
                ("--connect-timeout", args.connect_timeout),
            )
            if value is not None
        ]
        if incompatible or args.confirm is not None:
            _write(
                args,
                {
                    "ok": False,
                    "mode": "export",
                    "error": (
                        "--export-checkpoint accepts only --from-collector-result "
                        "(plus output flags); collection/schedule options are "
                        "rejected."
                    ),
                },
            )
            return 2
        return _run_export(args)

    # Normalize sentinel defaults after mode checks (B1 explicit-supply detection).
    if args.limit is None:
        args.limit = 50
    if args.display is None:
        args.display = 5
    if args.connect_timeout is None:
        args.connect_timeout = 5
    if args.max_regions is None:
        args.max_regions = 3
    if args.refresh_interval_hours is None:
        args.refresh_interval_hours = 168

    if args.schedule and (args.apply or args.preview):
        _write(
            args,
            {
                "ok": False,
                "mode": "plan",
                "error": "--schedule cannot combine with --apply or --preview.",
            },
        )
        return 2

    if args.limit <= 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--limit must be positive."})
        return 2
    if args.apply and args.preview:
        _write(args, {"ok": False, "mode": "plan", "error": "Use either --apply or --preview."})
        return 2

    # P5A bounds (validated for EVERY non-export mode, including plain plan). default ceiling preserves the existing small batch's upper
    # bound (limit places x 2 endpoints); explicit values are finitely bounded.
    request_cap = (
        args.max_requests if args.max_requests is not None else _ENDPOINTS_PER_PLACE * args.limit
    )
    if not 1 <= request_cap <= MAX_REQUESTS_HARD_CAP:
        _write(
            args,
            {
                "ok": False,
                "mode": _mode(args),
                "error": (
                    f"--max-requests must be between 1 and {MAX_REQUESTS_HARD_CAP} "
                    f"(default is 2 x --limit)."
                ),
            },
        )
        return 2

    # P5A cursor: malformed values fail closed BEFORE settings, DB, gate, or
    # acquisition — a garbage cursor must never reach a query parameter. The
    # rejection output is a fixed message: the raw (possibly control-bearing)
    # input is never echoed.
    if args.after_place_id is not None and not _is_valid_cursor(args.after_place_id):
        _write(
            args,
            {
                "ok": False,
                "mode": _mode(args),
                "error": (
                    "--after-place-id is malformed (expected 1-128 printable, "
                    "whitespace-free characters); no settings, DB, or acquisition "
                    "was performed."
                ),
            },
        )
        return 2

    # Fail closed on unmappable ids before any connection, gate check, or
    # acquisition: a typo'd region must never degrade into the global place
    # window (which can contain zero places of the target region).
    region_place_names: tuple[str, ...] | None = None
    region_tour_api_area_code: str | None = None
    if args.region is not None:
        region_place_names = manual_region_place_names(args.region)
        region_tour_api_area_code = manual_region_tour_api_area_code(args.region)
        if region_place_names is None or region_tour_api_area_code is None:
            _write(
                args,
                {
                    "ok": False,
                    "mode": _mode(args),
                    "error": (
                        "--region id is unknown or cannot be mapped to canonical "
                        "region names; no acquisition or write was performed."
                    ),
                    "region": args.region,
                    "region_applied": False,
                },
            )
            return 2

    if args.schedule:
        return _run_schedule(args)

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
        return _run_apply(args, dsn, region_place_names, region_tour_api_area_code, request_cap)
    return _run_preview(args, dsn, region_place_names, region_tour_api_area_code, request_cap)


def _read_window(
    cur,
    args: argparse.Namespace,
    region_place_names: tuple[str, ...] | None,
    region_tour_api_area_code: str | None,
) -> list[ReviewMentionPlace]:
    """Read the place window, threading the cursor only when present.

    Without --after-place-id the call is byte-identical to the pre-P5A shape
    (same positional args, same SQL, same params); with it, a parameterized
    keyset ``place_id > %s`` is added inside the same scoped query.
    """
    if args.after_place_id is None:
        return _read_places_on_cursor(
            cur, args.limit, region_place_names, None, region_tour_api_area_code
        )
    return _read_places_on_cursor(
        cur, args.limit, region_place_names, args.after_place_id, region_tour_api_area_code
    )


def _cursor_scope(args: argparse.Namespace) -> str:
    """Human-readable scope the cursor is valid inside (resume contract)."""
    return args.region if args.region is not None else "global"


# --- P5B schedule mode: offline regional work-plan (zero I/O) ---


def _now_utc() -> datetime:
    """Clock seam — tests inject deterministic timezone-aware UTC times."""
    return datetime.now(UTC)


def _run_schedule(args: argparse.Namespace) -> int:
    from pathlib import Path

    from apps.api.app.services import collector_checkpoint as cc

    # Finite bounded schedule arguments, validated before ANY I/O. The
    # per-region cap defaults to the collector's own safe default (2 x limit,
    # or --max-requests when given) and always honors reserve-two.
    per_region = args.per_region_requests
    if per_region is None:
        per_region = (
            args.max_requests
            if args.max_requests is not None
            else _ENDPOINTS_PER_PLACE * args.limit
        )
    if not 2 <= per_region <= MAX_REQUESTS_HARD_CAP:
        _write(
            args,
            {
                "ok": False,
                "mode": "schedule",
                "error": (
                    f"--per-region-requests must be between 2 (reserve-two) and "
                    f"{MAX_REQUESTS_HARD_CAP}."
                ),
            },
        )
        return 2
    if not 1 <= args.max_regions <= cc.SCHEDULE_MAX_REGIONS_LIMIT:
        _write(
            args,
            {
                "ok": False,
                "mode": "schedule",
                "error": (f"--max-regions must be between 1 and {cc.SCHEDULE_MAX_REGIONS_LIMIT}."),
            },
        )
        return 2
    total_ceiling = args.total_request_ceiling
    if total_ceiling is None:
        total_ceiling = per_region * args.max_regions
    if not 2 <= total_ceiling <= cc.SCHEDULE_TOTAL_REQUEST_CEILING_LIMIT:
        _write(
            args,
            {
                "ok": False,
                "mode": "schedule",
                "error": "--total-request-ceiling is outside the bounded range.",
            },
        )
        return 2
    if total_ceiling < per_region:
        # An total below one per-region cap can never honor reserve-two for a
        # single region: fail closed instead of emitting a vacuous plan.
        _write(
            args,
            {
                "ok": False,
                "mode": "schedule",
                "error": "--total-request-ceiling must be >= --per-region-requests.",
            },
        )
        return 2
    if not 1 <= args.refresh_interval_hours <= cc.SCHEDULE_REFRESH_HOURS_LIMIT:
        _write(
            args,
            {"ok": False, "mode": "schedule", "error": "--refresh-interval-hours must be >= 1."},
        )
        return 2

    # Region scope: explicit subset (sorted/deduplicated) or the whole catalog.
    if args.regions is not None:
        requested = [item.strip() for item in args.regions.split(",") if item.strip()]
        unknown = [r for r in requested if r not in cc.canonical_region_ids()]
        if unknown:
            # Fixed message only — the raw list is never echoed.
            _write(
                args,
                {
                    "ok": False,
                    "mode": "schedule",
                    "error": (
                        "--regions contains unknown/non-canonical manual region "
                        "ids; no plan was produced."
                    ),
                },
            )
            return 2
        regions = tuple(sorted(set(requested)))
    else:
        regions = cc.canonical_region_ids()

    # Caller-supplied explicit snapshot only; strict schema; fail closed.
    entries: dict[str, dict] = {}
    if args.checkpoint_snapshot is not None:
        try:
            entries = cc.load_checkpoint_snapshot(Path(args.checkpoint_snapshot))
        except cc.CheckpointSnapshotError as exc:
            _write(args, {"ok": False, "mode": "schedule", "error": str(exc)})
            return 2

    plan = cc.plan_regional_collection(
        regions=regions,
        entries_by_region=entries,
        now=_now_utc(),
        refresh_interval=timedelta(hours=args.refresh_interval_hours),
        per_region_limit=args.limit,
        per_region_requests=per_region,
        total_request_ceiling=total_ceiling,
        max_regions=args.max_regions,
    )
    _write(
        args,
        {
            "ok": True,
            "mode": "schedule",
            "db_mutation": False,
            **plan,
            "refresh_interval_hours": args.refresh_interval_hours,
            "checkpoint_snapshot_supplied": args.checkpoint_snapshot is not None,
            "plan_note": (
                "planned_arguments are PENDING-APPROVAL collection arguments for "
                "this collector (region/after_place_id/limit/max-requests) — "
                "plain data, never executed here, no confirmation or credentials "
                "included. Scheduling/recency only; not source-data freshness or "
                "coverage proof. Snapshot source: committed apply payloads "
                "bridged via collector_checkpoint.build_region_checkpoint "
                "(operational persistence of these entries is a later scoped gap)."
            ),
        },
    )
    return 0


# --- P5B offline export: collector result -> validated checkpoint snapshot ---


def _run_export(args: argparse.Namespace) -> int:
    """Offline bridge consumer: ONE bounded apply result -> snapshot on stdout.

    Zero settings/DB/provider I/O; the ONLY input is the explicitly supplied
    bounded local file, and the ONLY output is the validated versioned
    snapshot. The observation time comes from the result itself (B4) — a
    legacy/missing-time result is rejected, never silently refreshed.
    """
    import json as _json
    from pathlib import Path

    from apps.api.app.services import collector_checkpoint as cc

    if args.from_collector_result is None:
        _write(
            args,
            {
                "ok": False,
                "mode": "export",
                "error": "--export-checkpoint requires --from-collector-result <path>.",
            },
        )
        return 2
    path = Path(args.from_collector_result)
    try:
        with open(path, "rb") as handle:
            raw = handle.read(cc.SNAPSHOT_MAX_BYTES + 1)
    except OSError:
        _write(args, {"ok": False, "mode": "export", "error": "collector result could not be read"})
        return 2
    if len(raw) > cc.SNAPSHOT_MAX_BYTES:
        _write(
            args,
            {
                "ok": False,
                "mode": "export",
                "error": "collector result exceeds the bounded size limit",
            },
        )
        return 2
    try:
        payload = _json.loads(raw)
        entry = cc.build_region_checkpoint(payload)
    except cc.CheckpointSnapshotError as exc:
        # Sanitized fixed bridge message (no raw invalid input echo).
        _write(args, {"ok": False, "mode": "export", "error": str(exc)})
        return 2
    except (UnicodeDecodeError, ValueError, TypeError):
        _write(
            args,
            {
                "ok": False,
                "mode": "export",
                "error": (
                    "collector result was rejected by the bridge (only committed "
                    "region-scoped apply results with their own observation_time "
                    "are accepted)"
                ),
            },
        )
        return 2
    snapshot = {
        "schema_version": cc.SNAPSHOT_SCHEMA_VERSION,
        "source": cc.SNAPSHOT_SOURCE,
        # P5C provenance: this snapshot's cursor/freshness evidence was
        # produced under the province-qualified collector predicate.
        "scope_contract": cc.SNAPSHOT_SCOPE_CONTRACT,
        "entries": [entry],
    }
    if args.json:
        print(_json.dumps(snapshot, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    print("LALA-next collector checkpoint export (offline)")
    print(f"region={entry['region']}")
    print(f"next_after_place_id={entry['next_after_place_id']}")
    print(f"whole_region_complete={str(entry['whole_region_complete']).lower()}")
    print(f"observation_time={entry['observation_time']}")
    print("snapshot_json_follows")
    print(_json.dumps(snapshot, ensure_ascii=False, sort_keys=True))
    return 0


# --- preview: read-only gate + places, then in-memory acquire + classify ---


def _run_preview(
    args: argparse.Namespace,
    dsn: str,
    region_place_names: tuple[str, ...] | None,
    region_tour_api_area_code: str | None,
    request_cap: int,
) -> int:
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
                places = _read_window(cur, args, region_place_names, region_tour_api_area_code)
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

    batch = _acquire_and_classify(
        places=places,
        display=args.display,
        registration=registration,
        after_place_id=args.after_place_id,
        request_cap=request_cap,
    )
    status = _compute_status(batch.failure_tally, 0)
    window_full = batch.places_count >= args.limit
    _write(
        args,
        {
            "ok": True,
            "status": status,
            "mode": "preview",
            "source_name": SOURCE_NAME,
            "region": args.region,
            "region_applied": region_place_names is not None,
            "places": batch.places_count,
            "candidates": batch.candidates,
            "ad_filtered_out": batch.ad_filtered,
            "organic": len(batch.organic_records),
            "failure_tally": batch.failure_tally,
            # P5A continuation (advisory in preview — nothing is written).
            "after_place_id": args.after_place_id,
            "cursor_scope": _cursor_scope(args),
            "next_after_place_id": batch.next_after_place_id,
            "places_attempted": batch.places_attempted,
            "places_completed": batch.places_completed,
            "places_deferred": batch.places_deferred,
            "places_name_skipped": batch.places_name_skipped,
            "requests_used": batch.requests_used,
            "request_cap": batch.request_cap,
            "requests_reserved_per_place": _ENDPOINTS_PER_PLACE,
            "stop_reason": batch.stop_reason,
            # Exhausted = the whole scoped window was selected and every
            # selected place settled (no budget/fatal stop). window_full only
            # says the limit-sized window MAY have more after it.
            "exhausted": _window_exhausted(batch, args.limit),
            "window_full": window_full,
        },
    )
    return 0


# --- apply: preflight gate → acquire (no DB) → atomic write transaction ---


def _run_apply(
    args: argparse.Namespace,
    dsn: str,
    region_place_names: tuple[str, ...] | None,
    region_tour_api_area_code: str | None,
    request_cap: int,
) -> int:
    from apps.api.app.services import collector_checkpoint

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
                    places = _read_window(cur, args, region_place_names, region_tour_api_area_code)
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
                "committed": False,
                # P5A: nothing committed → no advanced cursor is published.
                "next_after_place_id": None,
                "cursor_advanced": False,
            },
        )
        return 2

    # Phase 2: Acquire + classify OUTSIDE any DB transaction.
    # No PostgreSQL connection is open during Naver network I/O — avoids
    # idle-in-transaction timeouts, bloat, and lock contention at scale.
    batch = _acquire_and_classify(
        places=places,
        display=args.display,
        registration=registration,
        after_place_id=args.after_place_id,
        request_cap=request_cap,
    )

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
                "committed": False,
                # P5A: governance recheck failed inside the transaction → the
                # advanced cursor MUST NOT be published (re-run resumes from
                # the original cursor).
                "next_after_place_id": None,
                "cursor_advanced": False,
            },
        )
        return 2
    except Exception as exc:
        error_msg = redact_secret_text(str(exc) or exc.__class__.__name__, (dsn,))
        _best_effort_job_run(args, dsn, started_at, "failed", error_msg)
        _write(
            args,
            {
                "ok": False,
                "mode": "apply",
                "error": error_msg,
                "committed": False,
                # P5A: apply rolled back → no advanced committed cursor.
                "next_after_place_id": None,
                "cursor_advanced": False,
            },
        )
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
            # True ONLY after the atomic receipts+aggregates transaction
            # committed above; every failure path below reports committed=False.
            "committed": True,
            "source_name": SOURCE_NAME,
            "region": args.region,
            "region_applied": region_place_names is not None,
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
            # P5A continuation — published ONLY after the atomic transaction
            # committed above. next_after_place_id never skips an unattempted
            # or partially failed place (see _acquire_and_classify).
            "after_place_id": args.after_place_id,
            "cursor_scope": _cursor_scope(args),
            "next_after_place_id": batch.next_after_place_id,
            "cursor_advanced": batch.next_after_place_id != args.after_place_id,
            "places_attempted": batch.places_attempted,
            "places_completed": batch.places_completed,
            "places_deferred": batch.places_deferred,
            "places_name_skipped": batch.places_name_skipped,
            "requests_used": batch.requests_used,
            "request_cap": batch.request_cap,
            "requests_reserved_per_place": _ENDPOINTS_PER_PLACE,
            "stop_reason": batch.stop_reason,
            "exhausted": _window_exhausted(batch, args.limit),
            "window_full": batch.places_count >= args.limit,
            # B4: this run's own collection/commit observation time. The
            # offline export preserves it verbatim — never re-stamped.
            "observation_time": datetime.now(UTC).isoformat(),
            # P5C provenance: the predicate this result was actually produced
            # under. The bridge/exporter never upgrades a marker-less legacy
            # result to qualified credit.
            "scope_contract": (
                collector_checkpoint.SNAPSHOT_SCOPE_CONTRACT
                if region_place_names is not None
                else "global_unscoped_v1"
            ),
        },
    )
    return 0


# --- connection / DB helpers ---


def _open_connection(dsn: str, connect_timeout: int):
    """Open a psycopg2 connection. Extracted for test injection."""
    import psycopg2

    return psycopg2.connect(dsn, connect_timeout=connect_timeout)


def _read_places_on_cursor(
    cur,
    limit: int,
    region_place_names: tuple[str, ...] | None = None,
    after_place_id: str | None = None,
    region_tour_api_area_code: str | None = None,
) -> list[ReviewMentionPlace]:
    """Read the place window with the P5C province-qualified region predicate.

    The region clause must narrow the window BEFORE LIMIT: the global
    ORDER BY place_id head can otherwise contain zero places of the target
    region (Seongdong: 132 canonical places, 0 in the head-50 window).
    P5C qualification: district aliases alone are ambiguous (29 catalog
    regions share names like 중구 across provinces). The only PROVEN
    province discriminator is TourAPI's areacode namespace
    (travel.places.province_code written by tour_api_ingest with
    primary_source='tour_api'), so a region scope now ALSO requires
    province_code = <area code> AND primary_source = 'tour_api'. Rows in
    other namespaces / NULL province codes are excluded — collection
    eligibility is scoped to qualified canonical rows, NOT proof that every
    administrative place has data (excluded rows stay a coverage gap).
    P5A: the optional keyset cursor narrows the same window with a bound
    parameter (place_id > %s) — input is NEVER interpolated into the SQL.
    Omitted region/cursor keep the query and params byte-identical to the
    pre-P5A contract.
    """
    region_clause = ""
    cursor_clause = ""
    params: list[Any] = []
    if region_place_names is not None:
        # P5C fail-closed: a region scope REQUIRES the proven province
        # discriminator — an alias-only fallback would bleed across the 29
        # alias-colliding regions. Only the global mode stays unqualified.
        if region_tour_api_area_code is None:
            raise ValueError(
                "region scope requires a proven TourAPI province area code; "
                "refusing to fall back to an alias-only predicate"
            )
        region_clause = (
            "  AND region_name_ko = ANY(%s)\n"
            "  AND province_code = %s\n"
            "  AND primary_source = 'tour_api'\n"
        )
        params.append(list(region_place_names))
        params.append(region_tour_api_area_code)
    if after_place_id is not None:
        cursor_clause = "  AND place_id > %s\n"
        params.append(after_place_id)
    sql = f"""
        SELECT place_id, name_ko, category, region_name_ko
        FROM travel.places
        WHERE name_ko IS NOT NULL
{region_clause}{cursor_clause}        ORDER BY place_id
        LIMIT %s
    """
    params.append(limit)
    cur.execute(sql, tuple(params))
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
    after_place_id: str | None = None,
    request_cap: int = _ENDPOINTS_PER_PLACE * 50,
) -> _AcquireResult:
    """Bounded, resumable acquire + classify over the selected window.

    P5A invariants (see the module docstring):
    - ``requests_used`` counts ACTUAL provider endpoint attempts (from the real
      per-endpoint outcomes, failures included) and never exceeds
      ``request_cap``; a place is started only when the whole endpoint pair
      fits the remaining budget (never split mid-place).
    - ``auth_missing``/``quota_exceeded`` stop the run after the current place
      instead of marching through the remaining places. No retries/fallback.
    - ``next_after_place_id`` only advances past CONSECUTIVELY COMPLETED
      places. A place with any degrading outcome, or an unattempted place
      (budget/fatal stop), halts advancement so the next run re-selects it —
      an unattempted or partially failed place is never skipped. Deterministic
      name-length skips settle a place with zero requests and do not block.
    """
    failure_tally: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    candidates = 0
    ad_filtered = 0
    organic_records: list[dict[str, Any]] = []
    sha_lookup: dict[str, _AggregateProvenance] = {}

    requests_used = 0
    attempted = 0
    completed = 0
    deferred = 0
    name_skipped = 0
    stop_reason: str | None = None
    # Cursor advances only while every place so far settled cleanly; the first
    # non-clean place freezes it (its id stays >= next resume point).
    advanced = after_place_id
    cursor_frozen = False

    for index, place in enumerate(places):
        if not place.name_ko or len(place.name_ko) < 2:
            # Deterministic skip (idempotent, zero requests): settles the place
            # without acquisition. It may never leap over an earlier unresolved
            # place — once the cursor is frozen (earlier partial failure or
            # budget deferral) a skip settles but does not advance it.
            name_skipped += 1
            completed += 1
            if not cursor_frozen:
                advanced = place.place_id
            continue

        # Reserve-two semantics: a place is only started when the whole
        # endpoint pair fits the remaining budget (never split mid-place).
        # This is a RESERVATION decision; requests_used below counts only
        # OBSERVED wire attempts (outcome.wire_attempted), which can be fewer
        # (e.g. absent credentials launch no request at all).
        if request_cap - requests_used < _ENDPOINTS_PER_PLACE:
            deferred += 1
            stop_reason = "request_budget_exhausted"
            cursor_frozen = True
            continue

        result = collect_mentions_for_place(
            place_id=place.place_id,
            place_name=place.name_ko,
            region=place.region_name_ko or "",
            category=place.category,
            display=display,
        )
        attempted += 1
        requests_used += sum(1 for o in result.outcomes if o.wire_attempted)
        place_clean = True
        fatal = False
        for outcome in result.outcomes:
            failure_tally[outcome.provider][outcome.category] += 1
            if outcome.category in _DEGRADING_CATEGORIES:
                place_clean = False
                if outcome.category in _FATAL_CATEGORIES:
                    fatal = True

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

        if place_clean:
            completed += 1
            if not cursor_frozen:
                advanced = place.place_id
        else:
            cursor_frozen = True
            if fatal:
                stop_reason = "fatal_provider_failure"
                # Every place after the fatal one stays unattempted/deferred.
                deferred += len(places) - (index + 1)
                break

    return _AcquireResult(
        failure_tally={k: dict(v) for k, v in failure_tally.items()},
        candidates=candidates,
        ad_filtered=ad_filtered,
        organic_records=organic_records,
        sha_lookup=sha_lookup,
        places_count=len(places),
        places_attempted=attempted,
        places_completed=completed,
        places_deferred=deferred,
        places_name_skipped=name_skipped,
        requests_used=requests_used,
        request_cap=request_cap,
        next_after_place_id=advanced,
        stop_reason=stop_reason,
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


def _has_degrading_failures(failure_tally: Mapping[str, Mapping[str, int]]) -> bool:
    """True when any acquisition outcome was a real (unresolved) failure."""
    return any(
        category in _DEGRADING_CATEGORIES
        for tallies in failure_tally.values()
        for category in tallies
    )


def _window_exhausted(batch: _AcquireResult, limit: int) -> bool:
    """Honest exhaustion: the WHOLE scoped window settled cleanly.

    Requires (a) fewer places selected than the limit (a limit-sized window
    may have more after it — that is ``window_full``, not exhaustion),
    (b) every selected place settled (places_completed already includes
    deterministic name-skips — no completed+name_skipped double counting),
    and (c) no unresolved acquisition failure anywhere in the run. An empty
    successfully-selected window is honestly exhausted; a window with any
    degrading endpoint outcome never is.
    """
    return (
        batch.places_count < limit
        and batch.places_completed == batch.places_count
        and not _has_degrading_failures(batch.failure_tally)
    )


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
        # P5A bounded continuation contract (offline documentation only — this
        # plan loads no settings, opens no DB connection, and calls no provider;
        # actual coverage/freshness remain unknown until a governed run).
        "continuation": {
            "cursor_arg": "--after-place-id",
            "cursor_semantics": (
                "keyset place_id > cursor inside the SAME --region scope; "
                "parameterized SQL, never interpolated; malformed cursors and "
                "unknown regions fail closed before settings/DB/acquisition"
            ),
            "resume_contract": (
                "pass back next_after_place_id with the identical --region; "
                "the cursor never skips an unattempted or partially failed "
                "place, and apply failures publish no advanced cursor"
            ),
            "request_cap": (
                "--max-requests bounds actual provider HTTP attempts "
                "(blog + cafearticle = 2 per place); requests_used counts "
                "observed wire attempts only (a fatal first endpoint never "
                "launches the second, absent credentials launch none), while "
                "the budget RESERVES both endpoint slots before starting a "
                "place (requests_reserved_per_place); default 2 x --limit "
                f"preserves the existing safe upper bound; hard cap {MAX_REQUESTS_HARD_CAP}"
            ),
            "stop_behavior": (
                "auth_missing/quota_exceeded stop the run after the current "
                "place; no retry storm, no provider fallback; budget stops "
                "defer whole places (endpoint pair never split)"
            ),
            "counters": (
                "places/attempted/completed/deferred/name_skipped and "
                "requests_used vs request_cap are reported per run; exhausted "
                "means the whole scoped window settled, distinct from an "
                "honest zero-result success"
            ),
            "coverage": "unknown_until_governed_run",
            "schedule_mode": (
                "--schedule produces the OFFLINE regional work-plan from an "
                "explicit checkpoint snapshot (--checkpoint-snapshot) built via "
                "collector_checkpoint.build_region_checkpoint; zero "
                "settings/DB/provider I/O; planned_arguments are pending-approval "
                "argv data, never executed; alias-colliding regions are "
                "BLOCKED_SCOPE until the collector gains a province-aware scope "
                "predicate; operational persistence of checkpoint entries is a "
                "later scoped gap"
            ),
        },
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
        if payload.get("region") is not None:
            print(f"region={payload['region']}")
        if payload.get("governance_code"):
            print(f"governance_code={payload['governance_code']}")
        return
    for key in (
        "region",
        "region_applied",
        "places",
        "candidates",
        "ad_filtered_out",
        "organic",
        "processed",
        "duplicate",
        "quarantined",
        "aggregated",
        "inserted_rows",
        "after_place_id",
        "cursor_scope",
        "next_after_place_id",
        "cursor_advanced",
        "places_attempted",
        "places_completed",
        "places_deferred",
        "places_name_skipped",
        "requests_used",
        "request_cap",
        "stop_reason",
        "exhausted",
        "window_full",
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
    if args.apply:
        return "apply"
    if args.preview:
        return "preview"
    return "plan"


if __name__ == "__main__":
    raise SystemExit(main())
