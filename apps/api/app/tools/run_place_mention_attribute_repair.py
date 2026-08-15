"""Repair legacy URL-shaped values in community.place_mentions_weekly.attributes.

S2 companion to the S1 ingest-side redaction. Production rows written before
S1 still carry raw URL-shaped external_key values inside
``attributes.preprocess.retained_external_keys`` / ``filtered_external_keys``.
The ingest ON CONFLICT upsert preserves legacy review_attributes and only
overwrites the rest on the next ingest apply, so re-running ingest does NOT
clean existing rows — only this repair path can zero the backlog.

Repair action (evidence-based, see place_mention_attribute_repair module doc):
REPLACE with the S1 provider-scoped sha256 digest, not remove.
review_attribute_batch.py joins ``preprocess.retained_external_keys`` back to
``community.posts`` via ``digest(mentions.provider || '|' || posts.external_key,
'sha256')`` — so the same digest keeps the AI enrichment lane working, while
removing the reference would silently drop every candidate row from that join.

Safety contract (S2):
- Default mode is PLAN: no DB connection at all. ``--scan`` performs the
  read-only detection pass and reports COUNTS ONLY (scanned/affected rows,
  unsafe values, replace vs drop breakdown, per-root-field breakdown).
- ``--apply`` is a TWO-MAN RULE requiring ALL of:
  1. env ``REVIEW_ATTRIBUTE_REPAIR_APPLY=I-UNDERSTAND-THIS-MUTATES-PRODUCTION``
  2. ``--confirm-count <N>`` exactly matching the pre-apply scan's unsafe count
  3. ``--backup-ref <s3-or-path>`` recording where the controller's backup of
     the affected rows lives (the tool takes no backup itself)
  Missing any one refuses with exit 2 and zero mutation.
- APPLY re-reads each affected row inside the apply transaction with
  ``SELECT ... FOR UPDATE`` and repairs from that live re-read (never from the
  stale plan), so a concurrent writer is blocked across re-read→UPDATE and any
  committed change is preserved rather than overwritten. Re-runs are idempotent
  (0 changes the second time).
- Post-apply verification re-scans and reports ``unsafe_after``; target 0
  (non-zero exits 1 so CI/operators see the incomplete state).
- ``--report <path>`` writes a sanitized JSON artifact (counts/digests only —
  never a raw value, key, URL, storage path, or internal row id; even the
  backup reference is reduced to a sha256 digest) for the controller's audit
  trail.
- Any error path goes through redact_secret_text with the DSN as explicit
  secret; no unsafe attribute value is ever placed in a log or report shape.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from datetime import UTC, datetime
from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.services.place_mention_attribute_repair import (
    attributes_sha256,
    find_unsafe_values,
    plan_row_repair,
    redact_unsafe_values,
    summarize_row_plans,
)

CONFIRM_ENV = "REVIEW_ATTRIBUTE_REPAIR_APPLY"
CONFIRM_ENV_VALUE = "I-UNDERSTAND-THIS-MUTATES-PRODUCTION"
JOB_NAME = "place-mention-attribute-repair"
TARGET = "community.place_mentions_weekly.attributes"

_RESELECT_SQL = "SELECT attributes FROM community.place_mentions_weekly WHERE id = %s FOR UPDATE"

_SELECT_SQL = """
    SELECT
        id,
        place_id,
        week_start,
        provider,
        attributes
    FROM community.place_mentions_weekly
    ORDER BY week_start DESC, place_name_ko, provider, category
    LIMIT %s
"""

_UPDATE_SQL = """
    UPDATE community.place_mentions_weekly
    SET attributes = %s,
        updated_at = now()
    WHERE id = %s
"""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Detect/repair URL-shaped values in place_mentions_weekly.attributes."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument(
        "--scan",
        action="store_true",
        help="Read-only detection pass; report counts only (no writes).",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Rewrite affected rows with digests (two-man rule required).",
    )
    parser.add_argument(
        "--confirm-count",
        type=int,
        default=None,
        help="Required with --apply: must equal the --scan unsafe_value_count exactly.",
    )
    parser.add_argument(
        "--backup-ref",
        default="",
        help="Required with --apply: s3:// or path reference to the controller's backup.",
    )
    parser.add_argument("--limit", type=int, default=100000, help="Max rows to scan.")
    parser.add_argument("--connect-timeout", type=int, default=5)
    parser.add_argument(
        "--report",
        default="",
        help="Optional path to write a sanitized JSON report artifact (counts/digests only).",
    )
    args = parser.parse_args(argv)

    if args.limit <= 0:
        _write(args, {"ok": False, "mode": _mode(args), "error": "--limit must be positive."})
        return 2
    if args.apply and args.scan:
        _write(args, {"ok": False, "mode": "plan", "error": "Use either --apply or --scan."})
        return 2
    if not args.apply and not args.scan:
        _write(args, _plan_payload())
        return 0

    dsn = os.getenv("DB_DSN") or get_settings().db_dsn
    if not dsn:
        _write(args, {"ok": False, "mode": _mode(args), "error": "DB_DSN is not configured."})
        return 2

    if args.apply:
        # Two-man rule: verify ALL guards BEFORE opening any connection, so a
        # refusal can never touch the database.
        guard_error = _apply_guard_error(args)
        if guard_error:
            _write(args, {"ok": False, "mode": "apply", "error": guard_error})
            return 2
        return _run_apply(args, dsn)
    return _run_scan(args, dsn)


def _run_scan(args: argparse.Namespace, dsn: str) -> int:
    conn = None
    try:
        conn = _open_connection(dsn, args.connect_timeout)
        with conn:
            with conn.cursor() as cur:
                scan = _scan_with_limit(cur, args.limit)
    except Exception as exc:
        _fail(args, dsn, "scan", exc)
        return 2
    finally:
        if conn is not None:
            conn.close()

    summary = summarize_row_plans(scan["plans"], scanned_row_count=scan["scanned_row_count"])
    payload: dict[str, Any] = {
        "ok": True,
        "mode": "scan",
        "db_mutation": False,
        "target": TARGET,
        **summary,
    }
    _write(args, payload)
    _write_report(args, payload)
    return 0


def _run_apply(args: argparse.Namespace, dsn: str) -> int:
    started_at = datetime.now(UTC)
    conn = None
    updated_rows = 0
    before_after: list[dict[str, str]] = []
    try:
        conn = _open_connection(dsn, args.connect_timeout)
        with conn:
            with conn.cursor() as cur:
                scan = _scan_with_limit(cur, args.limit)
                plans = scan["plans"]
                planned_unsafe = sum(plan.unsafe_value_count for plan in plans)
                # The count guard is checked against LIVE state too: if the
                # table changed since the operator ran --scan, the confirmed
                # count no longer matches and the apply must refuse.
                if planned_unsafe != args.confirm_count:
                    _write(
                        args,
                        {
                            "ok": False,
                            "mode": "apply",
                            "error": (
                                "--confirm-count does not match the live unsafe value count "
                                f"({planned_unsafe}); re-run --scan and confirm the new count."
                            ),
                        },
                    )
                    return 2

                # Re-read each affected row's CURRENT attributes inside the same
                # transaction under a row lock (FOR UPDATE), then repair from
                # that live re-read — never from the stale plan. The lock blocks
                # concurrent writers across re-read→UPDATE; a writer that
                # committed before the lock is observed in the re-read and its
                # change is preserved (unsafe values are still repaired, but
                # nothing the writer cleaned is re-written from stale state).
                for plan in plans:
                    cur.execute(_RESELECT_SQL, (plan.mention_id,))
                    row = cur.fetchone()
                    if row is None:
                        continue
                    current = _json_object(row[0])
                    if not find_unsafe_values(current, provider=plan.provider):
                        continue  # already repaired by a concurrent/recent run
                    repaired, _changed = redact_unsafe_values(current, provider=plan.provider)
                    before_after.append(
                        {
                            "row_sha256": row_evidence_sha256(plan.mention_id),
                            "before_sha256": attributes_sha256(current),
                            "after_sha256": attributes_sha256(repaired),
                        }
                    )
                    cur.execute(_UPDATE_SQL, (json.dumps(repaired), plan.mention_id))
                    updated_rows += int(cur.rowcount or 0)

                # Post-apply verification: re-scan the same window and report
                # the remaining unsafe count. Target is 0.
                verify = _scan_with_limit(cur, args.limit)
                unsafe_after = sum(plan.unsafe_value_count for plan in verify["plans"])
    except Exception as exc:
        _fail(args, dsn, "apply", exc)
        _best_effort_job_run(
            args,
            dsn,
            started_at,
            "failed",
            redact_secret_text(str(exc) or exc.__class__.__name__, (dsn,)),
        )
        return 2
    finally:
        if conn is not None:
            conn.close()

    _best_effort_job_run(args, dsn, started_at, "succeeded", None)
    payload: dict[str, Any] = {
        "ok": True,
        "mode": "apply",
        "db_mutation": True,
        "target": TARGET,
        # Evidence is digest-based: the operator's raw --backup-ref and the
        # internal mention row ids never enter stdout, the report, or the
        # job-run record (the raw ref lives only in the controller's ledger).
        "backup_ref_sha256": backup_ref_sha256(args.backup_ref),
        "scanned_row_count": scan["scanned_row_count"],
        "affected_row_count": len(plans),
        "unsafe_value_count": planned_unsafe,
        "updated_row_count": updated_rows,
        "unsafe_after": unsafe_after,
        "updated_row_checksums": before_after,
    }
    _write(args, payload)
    _write_report(args, payload)
    return 0 if unsafe_after == 0 else 1


def _scan_with_limit(cur, limit: int) -> dict[str, Any]:
    """Scan bounded by ``limit`` rows (list of raw rows -> plans)."""
    cur.execute(_SELECT_SQL, (limit,))
    rows = cur.fetchall()
    plans = []
    for row in rows:
        plan = plan_row_repair(
            mention_id=row[0],
            place_id=row[1],
            week_start=row[2],
            provider=row[3],
            attributes=_json_object(row[4]),
        )
        if plan is not None:
            plans.append(plan)
    return {"scanned_row_count": len(rows), "plans": plans}


def _open_connection(dsn: str, connect_timeout: int):
    """Open a psycopg2 connection. Extracted for test injection."""
    import psycopg2

    return psycopg2.connect(dsn, connect_timeout=connect_timeout)


def backup_ref_sha256(backup_ref: str) -> str:
    """Non-reversible evidence for the operator's --backup-ref.

    The raw reference can name internal storage (bucket/path); outputs carry
    this digest so the controller can correlate the run with its ledger entry
    without the report ever echoing the storage path itself.
    """
    return hashlib.sha256(backup_ref.strip().encode("utf-8")).hexdigest()


def row_evidence_sha256(mention_id: Any) -> str:
    """Non-reversible evidence for an internal mention row id."""
    return hashlib.sha256(str(mention_id).encode("utf-8")).hexdigest()


def _json_object(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return {}
        return parsed if isinstance(parsed, dict) else {}
    return {}


def _fail(args: argparse.Namespace, dsn: str, mode: str, exc: Exception) -> None:
    error_msg = redact_secret_text(str(exc) or exc.__class__.__name__, (dsn,))
    _write(args, {"ok": False, "mode": mode, "error": error_msg})


def _write_report(args: argparse.Namespace, payload: dict[str, Any]) -> None:
    """Write the sanitized JSON artifact if --report was given.

    The payload is counts/digests by construction; this is deliberately a
    passthrough so the artifact can never diverge from stdout.
    """
    if not args.report:
        return
    with open(args.report, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def _best_effort_job_run(
    args: argparse.Namespace,
    dsn: str,
    started_at: datetime,
    status: str,
    error_message: str | None,
) -> None:
    import contextlib

    # Generic job-run service with THIS tool's job name — never the ingest
    # module's wrapper, which hardcodes its own JOB_NAME and would misrecord
    # this repair as a review-mention-ingest run.
    from apps.api.app.services.job_runs import record_job_run

    finished_at = datetime.now(UTC)
    with contextlib.suppress(Exception):
        record_job_run(
            dsn=dsn,
            job_name=JOB_NAME,
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
        "target": TARGET,
        "detection": (
            "Recursive JSONB walk; value-form URL heuristics "
            "(scheme://..., bare authority/path) — not key-allowlist."
        ),
        "repair_actions": [
            "replace_value_with_provider_scoped_sha256",
            "drop_value_when_over_4096_material_bound",
        ],
        "apply_required_env": ["DB_DSN", CONFIRM_ENV],
        "apply_required_args": ["--confirm-count <N>", "--backup-ref <s3-or-path>"],
        "apply_guard": (
            f"{CONFIRM_ENV}={CONFIRM_ENV_VALUE} AND --confirm-count matching the "
            "--scan unsafe_value_count AND --backup-ref naming the controller backup"
        ),
        "safety_rules": [
            "scan_reports_counts_only",
            "no_unsafe_value_in_any_output_or_report",
            "rollback_evidence_row_checksums",
            "apply_two_man_rule_env_confirm_count_backup_ref",
            "apply_idempotent_zero_changes_on_rerun",
            "post_apply_rescan_target_unsafe_after_zero",
        ],
        "job_name": JOB_NAME,
    }


def _apply_guard_error(args: argparse.Namespace) -> str:
    if os.getenv(CONFIRM_ENV) != CONFIRM_ENV_VALUE:
        return f"--apply requires {CONFIRM_ENV}={CONFIRM_ENV_VALUE} in the process environment."
    if args.confirm_count is None:
        return "--apply requires --confirm-count <N> equal to the --scan unsafe_value_count."
    if args.confirm_count < 0:
        return "--confirm-count must be non-negative."
    if not args.backup_ref.strip():
        return "--apply requires --backup-ref <s3-or-path> naming the controller's backup."
    return ""


def _write(args: argparse.Namespace, payload: dict[str, Any]) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next place_mentions_weekly attribute redaction repair")
    print(f"mode={payload.get('mode')}")
    print(f"ok={str(payload.get('ok', False)).lower()}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return
    for key in (
        "scanned_row_count",
        "affected_row_count",
        "unsafe_value_count",
        "replace_action_count",
        "drop_action_count",
        "updated_row_count",
        "unsafe_after",
    ):
        if key in payload:
            print(f"{key}={payload[key]}")
    if payload.get("backup_ref_sha256"):
        print(f"backup_ref_sha256={payload['backup_ref_sha256']}")
    for field_name, count in (payload.get("field_breakdown") or {}).items():
        print(f"field.{field_name}={count}")


def _duration_ms(started_at: datetime, finished_at: datetime) -> int:
    return int((finished_at - started_at).total_seconds() * 1000)


def _mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "scan"


if __name__ == "__main__":
    raise SystemExit(main())
