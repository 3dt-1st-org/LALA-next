"""Scope-bound collector checkpoint snapshot + offline regional work-plan (P5B).

Honesty contract (P5B):
- A receipt timestamp with an opaque key is NOT per-place/per-region coverage
  proof. The ONLY evidence accepted here is an explicit, caller-supplied,
  versioned, secret-free checkpoint snapshot whose entries are built from THIS
  collector's own result fields (region, next_after_place_id, exhausted,
  stop_reason, blocked category, empty_observed, observed_at).
- This module computes collection SCHEDULING/RECENCY only. It never proves
  source-data freshness, nationwide coverage, or place availability — catalog
  inclusion is not data availability.
- Missing/unknown/malformed/future/inconsistent evidence classifies as
  UNKNOWN/DUE (or fails closed at load time), never as fresh/complete.
- No DB, no provider, no settings access. Pure functions over explicit inputs.

Snapshot schema (strict, v1) — exact keys only, unexpected fields rejected:

    {
      "schema_version": 1,
      "source": "naver_review_collect_apply_payloads",
      "entries": [
        {
          "region": "<canonical manual region id>",
          "next_after_place_id": "<printable cursor>" | null,
          "exhausted": true|false,
          "stop_reason": null|"request_budget_exhausted"|"fatal_provider_failure",
          "blocked": null|"auth_quota",
          "empty_observed": true|false,
          "observed_at": "<ISO-8601 UTC timestamp>"
        },
        ...
      ]
    }

Operational note: the collector does not yet persist these entries anywhere —
an operator (or a later scoped persistence task) assembles the snapshot from
the collector's apply JSON payloads via :func:`build_region_checkpoint`.
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

# Strict bounded snapshot limits: reject unbounded blobs rather than loading them.
SNAPSHOT_MAX_BYTES = 64 * 1024
SNAPSHOT_MAX_ENTRIES = 64
_CURSOR_MAX_LENGTH = 128
_KNOWN_STOP_REASONS = frozenset({"request_budget_exhausted", "fatal_provider_failure"})

# Region plan statuses (bounded, public vocabulary).
STATUS_DUE = "DUE"  # no/unknown evidence for the region
STATUS_DUE_REFRESH = "DUE_REFRESH"  # completed sweep older than the refresh interval
STATUS_RECENTLY_COLLECTED = "RECENTLY_COLLECTED"  # completed sweep inside the interval
STATUS_RESUME_PARTIAL = "RESUME_PARTIAL"  # unfinished window; retry/resume candidate
STATUS_EMPTY_OBSERVED = "EMPTY_OBSERVED"  # completed sweep observed empty (still fresh)
STATUS_AUTH_QUOTA_BLOCKED = "AUTH_QUOTA_BLOCKED"  # needs an explicit reset decision
STATUS_SCHEDULED = "SCHEDULED"  # selected for this plan's bounded batch
STATUS_DEFERRED = "DEFERRED"  # wanted, but max-regions/request budget ran out
STATUS_BLOCKED_SCOPE = "BLOCKED_SCOPE"  # alias collision: collector predicate is ambiguous

# Known offline catalog fact: the collector's place-window predicate filters
# ONLY region_name_ko = ANY(<region aliases>). Distinct canonical regions can
# share district aliases across provinces (e.g. 중구 in six cities), so those
# regions are NOT safely scoped by the existing predicate. Planning must not
# emit collection argv for them; the collector needs a province-aware scope
# predicate first (bounded later correction — no guessed mapping here).
_SCOPE_COLLISIONS: dict[str, tuple[str, ...]] | None = None


def region_alias_collisions() -> dict[str, tuple[str, ...]]:
    """Canonical regions whose alias names collide with another region's.

    Offline deterministic catalog computation: {region_id: (other_region_ids
    sharing at least one place-name alias)}. A region in this map cannot be
    safely planned with the collector's current region_name_ko = ANY(...)
    predicate — its scope would bleed into the colliding regions.
    """
    global _SCOPE_COLLISIONS
    if _SCOPE_COLLISIONS is None:
        name_to_regions: dict[str, list[str]] = {}
        for region_id in canonical_region_ids():
            for name in manual_region_place_names(region_id) or ():
                name_to_regions.setdefault(name, []).append(region_id)
        collisions: dict[str, tuple[str, ...]] = {}
        for owners in name_to_regions.values():
            if len(owners) > 1:
                for region_id in owners:
                    others = collisions.setdefault(region_id, set())
                    others.update(other for other in owners if other != region_id)
        _SCOPE_COLLISIONS = {
            rid: tuple(sorted(others)) for rid, others in sorted(collisions.items())
        }
    return _SCOPE_COLLISIONS


_ENTRY_KEYS = frozenset(
    {
        "region",
        "next_after_place_id",
        "exhausted",
        "stop_reason",
        "blocked",
        "empty_observed",
        "observed_at",
    }
)


class CheckpointSnapshotError(ValueError):
    """Malformed snapshot — the caller must fail closed (rc 2), never plan on it."""


def canonical_region_ids() -> tuple[str, ...]:
    """All canonical manual region ids, deterministically sorted."""
    return tuple(sorted(MANUAL_REGION_BY_ID))


def _validate_cursor(value: object) -> str | None:
    if value is None:
        return None
    if (
        not isinstance(value, str)
        or not value
        or len(value) > _CURSOR_MAX_LENGTH
        or not value.isprintable()
        or any(ch.isspace() for ch in value)
    ):
        raise CheckpointSnapshotError("checkpoint entry has a malformed cursor")
    return value


def _parse_observed_at(value: object) -> datetime:
    if not isinstance(value, str) or not value:
        raise CheckpointSnapshotError("checkpoint entry is missing observed_at")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise CheckpointSnapshotError("checkpoint entry has a malformed observed_at") from exc
    if parsed.tzinfo is None:
        raise CheckpointSnapshotError("checkpoint observed_at must be timezone-aware")
    return parsed.astimezone(UTC)


def build_region_checkpoint(collector_payload: Mapping, *, observed_at: datetime) -> dict:
    """Bridge THIS collector's result payload into one validated snapshot entry.

    ``collector_payload`` is the JSON payload of a successful (committed) apply
    run for exactly one ``--region`` scope. The bounded result fields are
    projected verbatim — nothing about coverage/freshness is invented: the entry
    states only what that run observed. ``observed_at`` must be timezone-aware
    UTC (the commit time supplied by the caller).
    """
    region = collector_payload.get("region")
    if not isinstance(region, str) or region not in MANUAL_REGION_BY_ID:
        raise CheckpointSnapshotError("payload region is not a canonical manual region id")
    failure_tally = collector_payload.get("failure_tally") or {}
    blocked = None
    for tallies in failure_tally.values():
        if "auth_missing" in tallies or "quota_exceeded" in tallies:
            blocked = "auth_quota"
            break
    return {
        "region": region,
        "next_after_place_id": _validate_cursor(collector_payload.get("next_after_place_id")),
        "exhausted": bool(collector_payload.get("exhausted")),
        "stop_reason": collector_payload.get("stop_reason"),
        "blocked": blocked,
        "empty_observed": bool(collector_payload.get("places") == 0),
        "observed_at": observed_at.astimezone(UTC).isoformat(),
    }


def load_checkpoint_snapshot(path: Path) -> dict[str, dict]:
    """Strictly load + validate a caller-supplied snapshot file.

    Returns {region: entry}. Fails closed (raises) on: missing file, oversize
    blob, invalid JSON, wrong schema_version/source, unexpected keys anywhere,
    unknown regions, malformed cursors/times/stop reasons, duplicate entries,
    or too many entries. Never loads raw reviews/credentials by construction —
    only the bounded v1 entry shape above is accepted.
    """
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise CheckpointSnapshotError("checkpoint snapshot could not be read") from exc
    if len(raw) > SNAPSHOT_MAX_BYTES:
        raise CheckpointSnapshotError("checkpoint snapshot exceeds the bounded size limit")
    try:
        document = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise CheckpointSnapshotError("checkpoint snapshot is not valid JSON") from exc
    if not isinstance(document, dict) or set(document) != {
        "schema_version",
        "source",
        "entries",
    }:
        raise CheckpointSnapshotError("checkpoint snapshot has an unexpected top-level shape")
    if (
        document["schema_version"] != SNAPSHOT_SCHEMA_VERSION
        or document["source"] != SNAPSHOT_SOURCE
    ):
        raise CheckpointSnapshotError("checkpoint snapshot version/source mismatch")
    entries = document["entries"]
    if not isinstance(entries, list) or len(entries) > SNAPSHOT_MAX_ENTRIES:
        raise CheckpointSnapshotError("checkpoint snapshot entries exceed the bounded count")

    by_region: dict[str, dict] = {}
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != _ENTRY_KEYS:
            raise CheckpointSnapshotError("checkpoint entry has unexpected fields")
        region = entry["region"]
        if not isinstance(region, str) or region not in MANUAL_REGION_BY_ID:
            raise CheckpointSnapshotError("checkpoint entry has an unknown region id")
        if region in by_region:
            raise CheckpointSnapshotError("checkpoint snapshot has duplicate region entries")
        if not isinstance(entry["exhausted"], bool) or not isinstance(
            entry["empty_observed"], bool
        ):
            raise CheckpointSnapshotError("checkpoint entry has malformed booleans")
        if entry["stop_reason"] is not None and entry["stop_reason"] not in _KNOWN_STOP_REASONS:
            raise CheckpointSnapshotError("checkpoint entry has an unknown stop_reason")
        if entry["blocked"] not in (None, "auth_quota"):
            raise CheckpointSnapshotError("checkpoint entry has an unknown blocked category")
        observed_at = _parse_observed_at(entry["observed_at"])
        _validate_cursor(entry["next_after_place_id"])
        if entry["exhausted"] and entry["stop_reason"] is not None:
            raise CheckpointSnapshotError("checkpoint entry is internally inconsistent")
        by_region[region] = {**entry, "_observed_at_dt": observed_at}
    return by_region


def classify_region(
    entry: dict | None,
    *,
    now: datetime,
    refresh_interval: timedelta,
) -> str:
    """Classify one region's recency state from its (optional) checkpoint entry.

    Malformed-at-load entries never reach here; a FUTURE observed_at (clock
    skew / inconsistent metadata) classifies as DUE (unknown), never fresh.
    """
    if entry is None:
        return STATUS_DUE
    if entry.get("blocked") == "auth_quota":
        return STATUS_AUTH_QUOTA_BLOCKED
    observed_at: datetime = entry["_observed_at_dt"]
    if observed_at > now:
        return STATUS_DUE
    if not entry["exhausted"]:
        return STATUS_RESUME_PARTIAL
    age = now - observed_at
    if age > refresh_interval:
        return STATUS_DUE_REFRESH
    if entry["empty_observed"]:
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

    Selection order is deterministic (sorted region ids). Candidates are the
    regions needing work (DUE, DUE_REFRESH, RESUME_PARTIAL); a global
    auth/quota block anywhere in the evidence stops recommendation of further
    acquisition without an explicit reset decision (the plan then only reports
    statuses). Emitted per-region caps always sum within the TOTAL ceiling and
    honor the reserve-two minimum; regions that no longer fit are DEFERRED.
    """
    statuses: dict[str, str] = {}
    planned: list[dict[str, Any]] = []
    deferred: list[str] = []
    scope_blocked: list[str] = []
    remaining_budget = total_request_ceiling
    scheduled_count = 0
    global_block = any(
        entries_by_region.get(region, {}).get("blocked") == "auth_quota" for region in regions
    )

    region_states: dict[str, str] = {}
    for region in regions:
        status = classify_region(
            entries_by_region.get(region), now=now, refresh_interval=refresh_interval
        )
        region_states[region] = status
        needs_work = status in (STATUS_DUE, STATUS_DUE_REFRESH, STATUS_RESUME_PARTIAL)
        if not needs_work:
            statuses[region] = status
            continue
        if region in region_alias_collisions():
            # Alias collision: the collector's current region predicate cannot
            # scope this region safely. Never emit argv for it; keep it in
            # coverage accounting as BLOCKED_SCOPE pending a province-aware
            # collector predicate (recorded gap, not guessed around).
            statuses[region] = STATUS_BLOCKED_SCOPE
            scope_blocked.append(region)
            continue
        if global_block:
            # Auth/quota is account-level: never march through more regions
            # until an operator resets and supplies refreshed evidence.
            statuses[region] = status
            continue
        if scheduled_count >= max_regions or remaining_budget < per_region_requests:
            statuses[region] = STATUS_DEFERRED
            deferred.append(region)
            continue
        entry = entries_by_region.get(region)
        cursor = None
        if status == STATUS_RESUME_PARTIAL and entry is not None:
            # Same-region cursor preserved: unfinished windows resume without
            # skipping; completed sweeps restart from the beginning.
            cursor = entry.get("next_after_place_id")
        statuses[region] = STATUS_SCHEDULED
        scheduled_count += 1
        remaining_budget -= per_region_requests
        # Argument ARRAY for the real collector — plain data, never a shell
        # command, never executed, no confirmation/credentials inside.
        planned.append(
            {
                "region": region,
                "after_place_id": cursor,
                "limit": per_region_limit,
                "max_requests": per_region_requests,
            }
        )

    return {
        "regions_total": len(regions),
        "regions_scheduled": scheduled_count,
        "regions_deferred": len(deferred),
        "regions_scope_blocked": len(scope_blocked),
        "collector_scope_gap": (
            "regions with BLOCKED_SCOPE share district-name aliases across "
            "provinces; the collector's region_name_ko = ANY(...) predicate "
            "cannot scope them safely. A province-aware place-window predicate "
            "is a bounded later correction — no collection argv is emitted for "
            "them until then."
        ),
        "planned_arguments": planned,
        "statuses": statuses,
        "region_states": region_states,
        "auth_quota_blocked": global_block,
        "requires_reset_decision": global_block,
        "request_budget_total": total_request_ceiling,
        "request_budget_remaining": remaining_budget,
        "per_region_requests": per_region_requests,
        # Scheduling/recency semantics only — NOT source-data freshness or
        # coverage proof (catalog inclusion is not data availability).
        "semantics": "collection_scheduling_recency_only",
    }
