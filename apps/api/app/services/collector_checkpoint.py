"""Scope-bound collector checkpoint snapshot + offline regional work-plan (P5B, corrected).

Honesty contract (P5B/B4):
- Only committed, scope-matched ``--apply`` RESULT metadata may become an
  accepted observation, via :func:`build_region_checkpoint` (strict field/
  mode/status/region checks). Preview/failed/mismatched input is rejected.
- The observation time is the collector's OWN emitted ``observation_time``
  (collection/commit time it actually observed). Export never stamps an old
  result fresh; legacy/missing-time input is rejected. Collection time is NOT
  source-data freshness — provenance stays caller-supplied, unverified.
- ``exhausted`` means end-of-selected-window. A whole-region completion is
  certified only for a single-page full sweep (null input cursor, all work
  completed). Multi-page tails without validated prior-checkpoint continuity
  are UNKNOWN_COMPLETION and conservatively restart from the beginning — no
  invented history, no boolean promoted into proven coverage.
- An empty FINAL page after populated pages is an empty window, not an empty
  region; only a null-cursor empty sweep records region-scoped emptiness.
- A receipt timestamp with an opaque key is NOT coverage proof. This module
  computes collection SCHEDULING/RECENCY only, never data availability.

No DB, no provider, no settings access. Pure functions over explicit inputs.

Snapshot schema (strict, v1) — exact keys only, unexpected fields rejected:

    {"schema_version": 1, "source": "naver_review_collect_apply_payloads",
     "entries": [{
        "region": str,                      # canonical manual region id
        "next_after_place_id": str | null,   # committed continuation cursor
        "input_after_place_id": str | null,  # the run's input cursor
        "exhausted": bool,                  # end-of-selected-window
        "whole_region_complete": bool,      # single-page null-cursor sweep only
        "empty_scope": null | "region" | "window",
        "stop_reason": null | "request_budget_exhausted" | "fatal_provider_failure",
        "blocked": null | "auth_quota",
        "requests_used": int,
        "observation_time": str,             # ISO-8601 UTC, from the result itself
     }]}

Operational note: entries are produced by the offline export mode of the
collector CLI (``--export-checkpoint``) from committed apply result JSON.
Persistent operational storage of snapshots remains a later scoped gap.
"""

from __future__ import annotations

import json
from collections.abc import Mapping
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from apps.api.app.services.region_catalog import MANUAL_REGION_BY_ID, manual_region_place_names

SNAPSHOT_SCHEMA_VERSION = 1
SNAPSHOT_SOURCE = "naver_review_collect_apply_payloads"

# Strict bounded snapshot limits (independent constants; B3).
# Independently bounded ceiling chosen to hold the supported full-catalog state
# (229 entries, two 128-char cursors each, exporter's indent=2 formatting) with
# margin, while staying a finite explicit bound. Reads stay MAX+1 bounded.
SNAPSHOT_MAX_BYTES = 1024 * 1024
SNAPSHOT_MAX_ENTRIES = 256
_REGION_ID_MAX_LENGTH = 64
_CURSOR_MAX_LENGTH = 128
_TIMESTAMP_MAX_LENGTH = 64
_KNOWN_STOP_REASONS = frozenset({"request_budget_exhausted", "fatal_provider_failure"})
_KNOWN_FAILURE_CATEGORIES = frozenset(
    {"ok", "empty", "auth_missing", "quota_exceeded", "network_error", "parse_error"}
)
_KNOWN_APPLY_STATUSES = frozenset({"succeeded", "degraded"})
_REQUESTS_USED_MAX = 10_000

# Independent bounded CLI argument ceilings (B3): no upper limit is derived
# solely from the same unbounded user argument.
SCHEDULE_MAX_REGIONS_LIMIT = 64
SCHEDULE_TOTAL_REQUEST_CEILING_LIMIT = 10_000
SCHEDULE_REFRESH_HOURS_LIMIT = 8760  # one year of hours; conservative default stays 168

# Region plan statuses (bounded, public vocabulary).
STATUS_DUE = "DUE"
STATUS_DUE_REFRESH = "DUE_REFRESH"
STATUS_RECENTLY_COLLECTED = "RECENTLY_COLLECTED"
STATUS_RESUME_PARTIAL = "RESUME_PARTIAL"
STATUS_EMPTY_OBSERVED = "EMPTY_OBSERVED"
STATUS_UNKNOWN_COMPLETION = "UNKNOWN_COMPLETION"
STATUS_AUTH_QUOTA_BLOCKED = "AUTH_QUOTA_BLOCKED"
STATUS_SCHEDULED = "SCHEDULED"
STATUS_DEFERRED = "DEFERRED"
STATUS_BLOCKED_SCOPE = "BLOCKED_SCOPE"

# B6: offline catalog fact — the collector's place-window predicate filters
# ONLY region_name_ko = ANY(<aliases>); regions sharing district aliases across
# provinces cannot be safely scoped. Planning never emits argv for them; a
# province-aware collector predicate is the bounded P5C correction.
_SCOPE_COLLISIONS: dict[str, tuple[str, ...]] | None = None

_ENTRY_KEYS = frozenset(
    {
        "region",
        "next_after_place_id",
        "input_after_place_id",
        "exhausted",
        "whole_region_complete",
        "empty_scope",
        "stop_reason",
        "blocked",
        "requests_used",
        "observation_time",
    }
)


class CheckpointSnapshotError(ValueError):
    """Malformed snapshot/result — the caller must fail closed (rc 2)."""


def canonical_region_ids() -> tuple[str, ...]:
    """All canonical manual region ids, deterministically sorted."""
    return tuple(sorted(MANUAL_REGION_BY_ID))


def region_alias_collisions() -> dict[str, tuple[str, ...]]:
    """Canonical regions whose alias names collide with another region's.

    Offline deterministic catalog computation: {region_id: (colliding ids)}.
    A region in this map cannot be safely planned with the collector's
    current region_name_ko = ANY(...) predicate.
    """
    global _SCOPE_COLLISIONS
    if _SCOPE_COLLISIONS is None:
        name_to_regions: dict[str, list[str]] = {}
        for region_id in canonical_region_ids():
            for alias in manual_region_place_names(region_id) or ():
                name_to_regions.setdefault(alias, []).append(region_id)
        collisions: dict[str, set[str]] = {}
        for owners in name_to_regions.values():
            if len(owners) > 1:
                for region_id in owners:
                    collisions.setdefault(region_id, set()).update(
                        other for other in owners if other != region_id
                    )
        _SCOPE_COLLISIONS = {
            rid: tuple(sorted(others)) for rid, others in sorted(collisions.items())
        }
    return _SCOPE_COLLISIONS


def _strict_bool(value: object, label: str) -> bool:
    # type-is-bool: reject bool-as-integer (True is an int in Python).
    if type(value) is not bool:
        raise CheckpointSnapshotError(f"{label} must be a boolean")
    return value


def _validate_cursor(value: object, label: str) -> str | None:
    if value is None:
        return None
    if (
        not isinstance(value, str)
        or not value
        or len(value) > _CURSOR_MAX_LENGTH
        or not value.isprintable()
        or any(ch.isspace() for ch in value)
    ):
        raise CheckpointSnapshotError(f"{label} is malformed")
    return value


def _parse_timestamp(value: object, label: str) -> datetime:
    if not isinstance(value, str) or not value or len(value) > _TIMESTAMP_MAX_LENGTH:
        raise CheckpointSnapshotError(f"{label} is missing or oversized")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (ValueError, OverflowError) as exc:
        raise CheckpointSnapshotError(f"{label} is malformed") from exc
    if parsed.tzinfo is None:
        # Naive timestamps are never assumed-local (that would silently shift
        # the observation); they must carry their own offset.
        raise CheckpointSnapshotError(f"{label} must be timezone-aware")
    try:
        return parsed.astimezone(UTC)
    except (OverflowError, OSError, ValueError) as exc:
        raise CheckpointSnapshotError(f"{label} is malformed") from exc


def _failure_signal(payload: Mapping) -> tuple[str | None, bool]:
    """(blocked_category, sweep_was_clean) from the result's failure tally.

    blocked is set for account-level auth/quota evidence. sweep_was_clean is
    True only when every tallied category is ok/empty — any degrading failure
    (network/parse/auth/quota) means the sweep is not a clean completion, so it
    can never certify fresh whole-region recency.
    """
    tally = payload.get("failure_tally")
    if not isinstance(tally, dict):
        raise CheckpointSnapshotError("result failure_tally is malformed")
    blocked: str | None = None
    clean = True
    for provider, tallies in tally.items():
        if not isinstance(provider, str) or not isinstance(tallies, dict):
            raise CheckpointSnapshotError("result failure_tally is malformed")
        for category, count in tallies.items():
            if category not in _KNOWN_FAILURE_CATEGORIES:
                raise CheckpointSnapshotError("result failure_tally has an unknown category")
            if type(count) is not int or count < 0:
                raise CheckpointSnapshotError("result failure_tally has a malformed count")
            if category in ("auth_missing", "quota_exceeded"):
                blocked = "auth_quota"
            if category not in ("ok", "empty"):
                clean = False
    return blocked, clean


def build_region_checkpoint(payload: Mapping) -> dict:
    """Bridge ONE committed, scope-matched collector apply RESULT into an entry.

    Strict acceptance (B4): mode ``apply``, ``ok`` true, status
    succeeded/degraded, region_applied true, canonical region whose id equals
    cursor_scope, typed booleans/counts, and a timezone-aware
    ``observation_time`` emitted by the collector itself (never the export
    clock). Preview/failed/mismatched/legacy input raises — it is never
    silently classified as recent completion.
    """
    if not isinstance(payload, Mapping):
        raise CheckpointSnapshotError("result payload is not an object")
    if payload.get("mode") != "apply":
        raise CheckpointSnapshotError("only committed --apply results may become observations")
    if payload.get("committed") is not True:
        # Failed-before-commit / governance-rejected / rollback / legacy
        # payloads carry no proof of an atomic commit: rejected outright.
        raise CheckpointSnapshotError("result carries no committed-transaction proof")
    status = payload.get("status")
    if status not in _KNOWN_APPLY_STATUSES and status != "failed":
        raise CheckpointSnapshotError("result status is not an accepted apply status")
    ok = payload.get("ok")
    if type(ok) is not bool or ok != (status != "failed"):
        raise CheckpointSnapshotError("result ok/status are inconsistent")
    failed_run = status == "failed"
    region = payload.get("region")
    if not isinstance(region, str) or region not in MANUAL_REGION_BY_ID:
        raise CheckpointSnapshotError("result region is not a canonical manual region id")
    if len(region) > _REGION_ID_MAX_LENGTH:
        raise CheckpointSnapshotError("result region id is oversized")
    if payload.get("region_applied") is not True:
        raise CheckpointSnapshotError("result was not region-scoped")
    if payload.get("cursor_scope") != region:
        raise CheckpointSnapshotError("result cursor_scope does not match its region")
    exhausted = _strict_bool(payload.get("exhausted"), "result exhausted")
    places = payload.get("places")
    if type(places) is not int or places < 0:
        raise CheckpointSnapshotError("result places count is malformed")
    requests_used = payload.get("requests_used")
    if type(requests_used) is not int or not 0 <= requests_used <= _REQUESTS_USED_MAX:
        raise CheckpointSnapshotError("result requests_used is malformed")
    counts = {}
    for field in (
        "places",
        "places_attempted",
        "places_completed",
        "places_deferred",
        "places_name_skipped",
    ):
        value = payload.get(field)
        if type(value) is not int or value < 0:
            raise CheckpointSnapshotError(f"result {field} is malformed")
        counts[field] = value
    # completed already includes deterministic name-skips (never double-counted);
    # every selected place is exactly one of attempted / deferred / name-skipped,
    # and the clean share of attempts is what completed adds beyond the skips.
    settled_clean = counts["places_completed"] - counts["places_name_skipped"]
    if settled_clean < 0 or settled_clean > counts["places_attempted"]:
        raise CheckpointSnapshotError("result place counts are inconsistent")
    if (
        counts["places_attempted"] + counts["places_deferred"] + counts["places_name_skipped"]
        != counts["places"]
    ):
        raise CheckpointSnapshotError("result place counts are inconsistent")
    stop_reason = payload.get("stop_reason")
    if stop_reason is not None and stop_reason not in _KNOWN_STOP_REASONS:
        raise CheckpointSnapshotError("result stop_reason is unknown")
    if exhausted and stop_reason is not None:
        raise CheckpointSnapshotError("result is internally inconsistent")
    observation_time = _parse_timestamp(payload.get("observation_time"), "result observation_time")
    blocked, sweep_clean = _failure_signal(payload)
    next_cursor = _validate_cursor(payload.get("next_after_place_id"), "result cursor")
    input_cursor = _validate_cursor(payload.get("after_place_id"), "result input cursor")

    # Sweep semantics (B4): exhausted == end-of-selected-window. Whole-region
    # completion is certified ONLY for a single-page sweep started from a null
    # cursor; a non-null tail page stays conservatively unproven.
    single_page_sweep = input_cursor is None
    whole_region_complete = bool(
        exhausted and single_page_sweep and blocked is None and not failed_run and sweep_clean
    )
    empty_scope = (
        ("region" if single_page_sweep else "window")
        if places == 0 and not failed_run and sweep_clean
        else None
    )
    return {
        "region": region,
        "next_after_place_id": next_cursor,
        "input_after_place_id": input_cursor,
        "exhausted": exhausted,
        "whole_region_complete": whole_region_complete,
        "empty_scope": empty_scope,
        "stop_reason": stop_reason,
        "blocked": blocked,
        "requests_used": requests_used,
        "observation_time": observation_time.isoformat(),
    }


def load_checkpoint_snapshot(path: Path) -> dict[str, dict]:
    """Strictly load + validate a caller-supplied snapshot file (bounded read).

    Reads at most SNAPSHOT_MAX_BYTES+1 bytes (oversize fails closed without
    loading the blob). Rejects invalid encoding/JSON, unsupported versions,
    unexpected keys anywhere, non-dict entries, bool-as-integer counts,
    malformed cursors/times/states, duplicates and over-count — always with a
    fixed sanitized message (no traceback, no raw invalid input echo).
    """
    try:
        with open(path, "rb") as handle:
            raw = handle.read(SNAPSHOT_MAX_BYTES + 1)
    except OSError as exc:
        raise CheckpointSnapshotError("checkpoint snapshot could not be read") from exc
    if len(raw) > SNAPSHOT_MAX_BYTES:
        raise CheckpointSnapshotError("checkpoint snapshot exceeds the bounded size limit")
    try:
        document = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        raise CheckpointSnapshotError("checkpoint snapshot is not valid JSON") from exc
    if not isinstance(document, dict):
        raise CheckpointSnapshotError("checkpoint snapshot has an unexpected top-level shape")
    try:
        keys = set(document)
    except TypeError as exc:
        raise CheckpointSnapshotError(
            "checkpoint snapshot has an unexpected top-level shape"
        ) from exc
    if keys != {"schema_version", "source", "entries"}:
        raise CheckpointSnapshotError("checkpoint snapshot has an unexpected top-level shape")
    if (
        type(document["schema_version"]) is not int
        or document["schema_version"] != SNAPSHOT_SCHEMA_VERSION
        or not isinstance(document["source"], str)
        or document["source"] != SNAPSHOT_SOURCE
    ):
        raise CheckpointSnapshotError("checkpoint snapshot version/source mismatch")
    entries = document["entries"]
    if not isinstance(entries, list) or len(entries) > SNAPSHOT_MAX_ENTRIES:
        raise CheckpointSnapshotError("checkpoint snapshot entries exceed the bounded count")

    by_region: dict[str, dict] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise CheckpointSnapshotError("checkpoint entry is not an object")
        try:
            entry_keys = set(entry)
        except TypeError as exc:
            raise CheckpointSnapshotError("checkpoint entry has unexpected fields") from exc
        if entry_keys != _ENTRY_KEYS:
            raise CheckpointSnapshotError("checkpoint entry has unexpected fields")
        region = entry["region"]
        if (
            not isinstance(region, str)
            or not region
            or len(region) > _REGION_ID_MAX_LENGTH
            or region not in MANUAL_REGION_BY_ID
        ):
            raise CheckpointSnapshotError("checkpoint entry has an unknown region id")
        if region in by_region:
            raise CheckpointSnapshotError("checkpoint snapshot has duplicate region entries")
        exhausted = _strict_bool(entry["exhausted"], "checkpoint exhausted")
        whole_complete = _strict_bool(
            entry["whole_region_complete"], "checkpoint whole_region_complete"
        )
        requests_used = entry["requests_used"]
        if type(requests_used) is not int or not 0 <= requests_used <= _REQUESTS_USED_MAX:
            raise CheckpointSnapshotError("checkpoint requests_used is malformed")
        stop_reason = entry["stop_reason"]
        if stop_reason is not None and (
            not isinstance(stop_reason, str) or stop_reason not in _KNOWN_STOP_REASONS
        ):
            raise CheckpointSnapshotError("checkpoint entry has an unknown stop_reason")
        blocked = entry["blocked"]
        if blocked is not None and (not isinstance(blocked, str) or blocked != "auth_quota"):
            raise CheckpointSnapshotError("checkpoint entry has an unknown blocked category")
        empty_scope = entry["empty_scope"]
        if empty_scope is not None and (
            not isinstance(empty_scope, str) or empty_scope not in ("region", "window")
        ):
            raise CheckpointSnapshotError("checkpoint entry has an unknown empty_scope")
        next_cursor = _validate_cursor(entry["next_after_place_id"], "checkpoint cursor")
        input_cursor = _validate_cursor(entry["input_after_place_id"], "checkpoint input cursor")
        observed_at = _parse_timestamp(entry["observation_time"], "checkpoint observation_time")
        if exhausted and entry["stop_reason"] is not None:
            raise CheckpointSnapshotError("checkpoint entry is internally inconsistent")
        if whole_complete and not (exhausted and input_cursor is None):
            raise CheckpointSnapshotError("checkpoint entry is internally inconsistent")
        if entry["empty_scope"] == "region" and input_cursor is not None:
            raise CheckpointSnapshotError("checkpoint entry is internally inconsistent")
        by_region[region] = {
            **entry,
            "next_after_place_id": next_cursor,
            "input_after_place_id": input_cursor,
            "_observed_at_dt": observed_at,
        }
    return by_region


def classify_region(
    entry: dict | None,
    *,
    now: datetime,
    refresh_interval: timedelta,
) -> str:
    """Classify one region's recency state from its (optional) entry.

    Blocked evidence never expires and never resets by age/filter (B2).
    Future observation times classify DUE (unknown), never fresh.
    """
    if entry is None:
        return STATUS_DUE
    if entry.get("blocked") == "auth_quota":
        return STATUS_AUTH_QUOTA_BLOCKED
    observed_at: datetime = entry["_observed_at_dt"]
    if observed_at > now:
        return STATUS_DUE
    if not entry["whole_region_complete"]:
        # End-of-window without proven whole-region completion: a partial
        # window resumes from its committed cursor; an unproven multi-page
        # tail is UNKNOWN_COMPLETION and conservatively restarts (no holes,
        # dedup absorbs re-collection). Never marked recently collected.
        if entry["exhausted"] and entry["input_after_place_id"] is not None:
            return STATUS_UNKNOWN_COMPLETION
        return STATUS_RESUME_PARTIAL
    age = now - observed_at
    if age > refresh_interval:
        return STATUS_DUE_REFRESH
    if entry["empty_scope"] == "region":
        return STATUS_EMPTY_OBSERVED
    return STATUS_RECENTLY_COLLECTED


def plan_regional_collection(
    *,
    regions: tuple[str, ...],
    entries_by_region: dict[str, dict],
    now: datetime,
    refresh_interval: timedelta,
    per_region_limit: int,
    per_region_requests: int,
    total_request_ceiling: int,
    max_regions: int,
) -> dict[str, Any]:
    """Compute the bounded offline regional work-plan (pure; no I/O).

    B2: the auth/quota stop inspects ALL loaded evidence, not only the
    requested subset — any valid blocked entry anywhere prevents new
    acquisition argv until an operator reset supplies refreshed evidence.
    Selection order is deterministic; ambiguous-scope regions are BLOCKED_SCOPE
    with no argv, retained in coverage accounting; emitted per-region caps sum
    within the TOTAL ceiling honoring reserve-two; regions that no longer fit
    are DEFERRED.
    """
    statuses: dict[str, str] = {}
    region_states: dict[str, str] = {}
    planned: list[dict[str, Any]] = []
    planned_argv: list[list[str]] = []
    deferred: list[str] = []
    scope_blocked: list[str] = []
    remaining_budget = total_request_ceiling
    scheduled_count = 0
    global_block = any(entry.get("blocked") == "auth_quota" for entry in entries_by_region.values())

    for region in regions:
        status = classify_region(
            entries_by_region.get(region), now=now, refresh_interval=refresh_interval
        )
        region_states[region] = status
        if region in region_alias_collisions():
            # B6: an ambiguous predicate taints even "fresh" evidence — the
            # sweep scope bled across provinces. Always BLOCKED_SCOPE, kept in
            # coverage accounting, until the P5C province-aware predicate.
            statuses[region] = STATUS_BLOCKED_SCOPE
            scope_blocked.append(region)
            continue
        needs_work = status in (
            STATUS_DUE,
            STATUS_DUE_REFRESH,
            STATUS_RESUME_PARTIAL,
            STATUS_UNKNOWN_COMPLETION,
        )
        if status == STATUS_AUTH_QUOTA_BLOCKED or not needs_work:
            statuses[region] = status
            continue
        if global_block:
            statuses[region] = status
            continue
        if scheduled_count >= max_regions or remaining_budget < per_region_requests:
            statuses[region] = STATUS_DEFERRED
            deferred.append(region)
            continue
        entry = entries_by_region.get(region)
        cursor = None
        if status == STATUS_RESUME_PARTIAL and entry is not None:
            cursor = entry.get("next_after_place_id")
        # UNKNOWN_COMPLETION / DUE / DUE_REFRESH restart from the beginning.
        statuses[region] = STATUS_SCHEDULED
        scheduled_count += 1
        remaining_budget -= per_region_requests
        planned.append(
            {
                "region": region,
                "after_place_id": cursor,
                "limit": per_region_limit,
                "max_requests": per_region_requests,
            }
        )
        # Parseable real-collector argv ARRAY (equals-form option encoding so a
        # cursor beginning with '-' can never be read as an option). Pending
        # approval only — never executed, no credentials or confirm tokens.
        argv = [
            f"--region={region}",
            f"--limit={per_region_limit}",
            f"--max-requests={per_region_requests}",
        ]
        if cursor is not None:
            argv.insert(1, f"--after-place-id={cursor}")
        planned_argv.append(argv)

    return {
        "regions_total": len(regions),
        "regions_scheduled": scheduled_count,
        "regions_deferred": len(deferred),
        "regions_scope_blocked": len(scope_blocked),
        "planned_arguments": planned,
        "planned_argv": planned_argv,
        "statuses": statuses,
        "region_states": region_states,
        "auth_quota_blocked": global_block,
        "requires_reset_decision": global_block,
        "request_budget_total": total_request_ceiling,
        "request_budget_remaining": remaining_budget,
        "per_region_requests": per_region_requests,
        "collector_scope_gap": (
            "regions with BLOCKED_SCOPE share district-name aliases across "
            "provinces; the collector's region_name_ko = ANY(...) predicate "
            "cannot scope them safely. A province-aware place-window predicate "
            "is the bounded P5C correction — no collection argv is emitted for "
            "them until then."
        ),
        "semantics": "collection_scheduling_recency_only",
    }
