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
        "qualified_scope": bool,             # produced under the qualified predicate
     }]}

Operational note: entries are produced by the offline export mode of the
collector CLI (``--export-checkpoint``) from committed apply result JSON.
Persistent operational storage of snapshots remains a later scoped gap.
"""

from __future__ import annotations

import contextlib
import json
from collections.abc import Mapping
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from apps.api.app.services.region_catalog import MANUAL_REGION_BY_ID, manual_region_place_names

SNAPSHOT_SCHEMA_VERSION = 1
SNAPSHOT_SOURCE = "naver_review_collect_apply_payloads"
# P5C scope contract: the collector's region predicate is province-qualified
# in the proven TourAPI areacode namespace (province_code + primary_source
# 'tour_api'). Snapshots written under this contract may carry cursor and
# freshness credit; older alias-only snapshots are legacy: their cursor and
# completion evidence predate the qualified predicate and confer NO credit,
# while account-wide auth/quota stop signals are always preserved.
SNAPSHOT_SCOPE_CONTRACT = "tour_api_province_qualified_v1"

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

# Offline catalog fact (P5C-resolved): 29 canonical regions share district
# aliases across provinces. The collector's region predicate is now
# province-qualified in the proven TourAPI areacode namespace, so these
# regions are QUALIFIED for planning (counted, not blocked); the mapping is
# retained for coverage accounting of the alias overlap.
_SCOPE_COLLISIONS: dict[str, tuple[str, ...]] | None = None

# Historical 1aeb6249-era entries lack qualified_scope entirely; a missing
# qualifier is conservatively UNQUALIFIED (never defaulted to True). The
# interim 13920092 shape (top-level scope_contract present, entries without
# the bool) lands in the same conservative bucket via this rule.
# P5D2 bounded lineage: a live chain proof. Historical entries lack these
# keys entirely — absence never grants multi-page chain credit.
SWEEP_MAX_PAGES = 64
_KNOWN_PAGE_KINDS = frozenset({"clean_prefix", "degraded_page", "terminal_clean", "failed_page"})
_ENTRY_KEYS_LINEAGE = frozenset(
    {"sweep_pages", "sweep_chain_started_at", "sweep_clean", "lineage_page_kind"}
)
_ENTRY_KEYS_OPTIONAL = frozenset({"qualified_scope"})
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
    Since P5C the collector's region predicate is province-qualified in the
    proven TourAPI areacode namespace, so these regions ARE safely plannable;
    the mapping is retained for coverage accounting of the alias overlap.
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

    Strict acceptance (B4): mode ``apply``, a True ``committed`` transaction
    flag, ok/status consistency, region_applied true, canonical region whose
    id equals cursor_scope, typed nonnegative counters satisfying the real
    place identity, nonnegative tally values, and a timezone-aware
    ``observation_time`` emitted by the collector itself (never the export
    clock). Successful runs (succeeded/degraded) bridge as observations;
    committed FAILED runs of BOTH kinds bridge as observations with an
    unchanged cursor and no completion credit — auth/quota failures export as
    BLOCKED (the account-wide stop), nonfatal failures stay honest retry
    candidates, and no failure is ever fresh.
    Whole-region freshness additionally requires status ``succeeded`` with
    every selected place settled and a clean sweep — degraded/quarantined or
    partially-settled results never certify recency. Preview / failed-before-
    commit / mismatched / legacy input raises outright.
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
    result_contract = payload.get("scope_contract")
    if result_contract is not None and not isinstance(result_contract, str):
        raise CheckpointSnapshotError("result scope_contract is malformed")
    if result_contract is not None and result_contract != SNAPSHOT_SCOPE_CONTRACT:
        # Fail closed on unknown/future markers (explicitly, not silently).
        raise CheckpointSnapshotError("result scope contract is unknown to this bridge")
    qualified_scope = result_contract == SNAPSHOT_SCOPE_CONTRACT
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
    if failed_run:
        # Controller decision (P5C compatibility): BOTH committed failure kinds
        # are observations — nonfatal failures are recorded WITHOUT freshness
        # or whole-completion credit and with an UNCHANGED cursor; auth/quota
        # failures additionally carry the account-wide stop. No failure is ever
        # fresh, and only auth/quota blocks globally.
        next_cursor = input_cursor
    if not qualified_scope:
        # Legacy alias-only result exported by a NEW binary is never upgraded:
        # cursor/freshness credit is stripped, auth/quota stops survive above.
        next_cursor = input_cursor

    # Sweep semantics (B4): exhausted == end-of-selected-window. Whole-region
    # completion is certified ONLY for a single-page sweep started from a null
    # cursor; a non-null tail page stays conservatively unproven.
    # P5D2 per-page eligibility, derived ONLY here from raw committed facts
    # (status + failure tally) — never inferred later from reduced fields.
    fully_settled = counts["places_completed"] == counts["places"]
    if failed_run:
        lineage_page_kind = "failed_page"
    elif status == "degraded" or not sweep_clean:
        lineage_page_kind = "degraded_page"
    elif exhausted and fully_settled:
        # Full terminal proof: succeeded + clean tally + every selected place
        # settled (no unattempted/deferred) + no stop. A structurally
        # consistent but incomplete exhausted tail is NOT terminal-eligible.
        lineage_page_kind = "terminal_clean"
    elif exhausted:
        lineage_page_kind = "degraded_page"  # incomplete exhausted tail
    else:
        lineage_page_kind = "clean_prefix"

    single_page_sweep = input_cursor is None
    whole_region_complete = bool(
        exhausted
        and single_page_sweep
        and blocked is None
        and not failed_run
        and sweep_clean
        and status == "succeeded"
        and counts["places_completed"] == counts["places"]
        and qualified_scope
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
        "qualified_scope": qualified_scope,
        "lineage_page_kind": lineage_page_kind,
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
    if keys not in (
        {"schema_version", "source", "entries"},
        {"schema_version", "source", "entries", "scope_contract"},
    ):
        raise CheckpointSnapshotError("checkpoint snapshot has an unexpected top-level shape")
    legacy_scope = "scope_contract" not in document
    if not legacy_scope and document["scope_contract"] != SNAPSHOT_SCOPE_CONTRACT:
        raise CheckpointSnapshotError("checkpoint snapshot scope contract mismatch")
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
        allowed = _ENTRY_KEYS | _ENTRY_KEYS_OPTIONAL | _ENTRY_KEYS_LINEAGE
        if not entry_keys >= _ENTRY_KEYS or not entry_keys <= allowed:
            # Exact known shapes only: core required; optional qualifiers and
            # lineage keys allowed individually (a fresh bridge entry carries
            # lineage_page_kind alone; chain proof keys must co-appear below).
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
        qualified_scope = (
            _strict_bool(entry["qualified_scope"], "checkpoint qualified_scope")
            if "qualified_scope" in entry
            else False
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
        if "lineage_page_kind" in entry:
            page_kind = entry["lineage_page_kind"]
            if not isinstance(page_kind, str) or page_kind not in _KNOWN_PAGE_KINDS:
                # Includes an explicitly present null kind — never accepted.
                raise CheckpointSnapshotError("checkpoint lineage_page_kind is unknown")
        if ("sweep_pages" in entry) != ("sweep_chain_started_at" in entry) or (
            ("sweep_clean" in entry) != ("sweep_pages" in entry)
        ):
            # Partial or orphan lineage metadata fails safely (orphan
            # sweep_clean never rides along without the complete proof shape).
            raise CheckpointSnapshotError("checkpoint lineage metadata is partial")
        if "sweep_pages" in entry:
            # Complete new-lineage shape requires its typed evidence: an
            # explicit valid page kind, an explicit chain-cleanliness bool and
            # a qualified scope. Marker-only/incomplete/unqualified proof is
            # rejected, and whole multi-page credit is never accepted with a
            # tainted chain or a nonterminal/failed/degraded page kind.
            if "lineage_page_kind" not in entry:
                raise CheckpointSnapshotError("checkpoint lineage proof lacks typed evidence")
            _strict_bool(entry["sweep_clean"], "checkpoint sweep_clean")
            if not entry.get("qualified_scope"):
                raise CheckpointSnapshotError(
                    "checkpoint lineage proof claims an unqualified scope"
                )
            if entry["whole_region_complete"] and (
                not entry["sweep_clean"] or entry["lineage_page_kind"] != "terminal_clean"
            ):
                raise CheckpointSnapshotError("checkpoint entry is internally inconsistent")
            sweep_pages = entry["sweep_pages"]
            if type(sweep_pages) is not int or not 1 <= sweep_pages <= SWEEP_MAX_PAGES:
                raise CheckpointSnapshotError("checkpoint sweep_pages is malformed")
            chain_started = _parse_timestamp(
                entry["sweep_chain_started_at"], "checkpoint sweep_chain_started_at"
            )
            if chain_started > observed_at:
                raise CheckpointSnapshotError("checkpoint entry is internally inconsistent")
            if whole_complete and input_cursor is not None and "sweep_pages" not in entry:
                raise CheckpointSnapshotError("checkpoint entry is internally inconsistent")
        elif whole_complete and input_cursor is not None:
            # A non-null tail can only carry whole completion WITH lineage proof.
            raise CheckpointSnapshotError("checkpoint entry is internally inconsistent")
        if exhausted and entry["stop_reason"] is not None:
            raise CheckpointSnapshotError("checkpoint entry is internally inconsistent")
        if whole_complete and not exhausted:
            raise CheckpointSnapshotError("checkpoint entry is internally inconsistent")
        if whole_complete and blocked is not None:
            raise CheckpointSnapshotError("checkpoint entry is internally inconsistent")
        if entry["empty_scope"] == "region" and input_cursor is not None:
            raise CheckpointSnapshotError("checkpoint entry is internally inconsistent")
        by_region[region] = {
            **entry,
            "next_after_place_id": next_cursor,
            "input_after_place_id": input_cursor,
            "_observed_at_dt": observed_at,
            "_chain_started_dt": (
                _parse_timestamp(entry["sweep_chain_started_at"], "chain start")
                if "sweep_chain_started_at" in entry
                else observed_at
            ),
            # Snapshot-level legacy OR per-entry unqualified result provenance:
            # either way the entry carries no cursor/freshness credit, while
            # account-wide auth/quota stops always survive.
            "_legacy_scope": legacy_scope or not qualified_scope,
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
        # Account-wide stop signals survive every scope-contract change.
        return STATUS_AUTH_QUOTA_BLOCKED
    if entry.get("_legacy_scope"):
        # Alias-only evidence predates the qualified predicate: no cursor or
        # freshness credit may transfer; conservatively DUE (fresh sweep).
        return STATUS_DUE
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
    age = now - entry.get("_chain_started_dt", observed_at)
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
    Selection order is deterministic; alias-colliding regions are qualified
    and counted under the province-qualified predicate (unknown/non-canonical
    --regions ids fail closed earlier); emitted per-region caps sum
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
        "scope_contract": SNAPSHOT_SCOPE_CONTRACT,
        "regions_alias_qualified": len(region_alias_collisions()),
        "collector_scope_gap": (
            "the collector's region predicate is province-qualified in the "
            "proven TourAPI areacode namespace (province_code + "
            "primary_source='tour_api'); district aliases alone no longer "
            "block canonical regions, but rows outside that namespace (other "
            "providers' codes, NULL province) are excluded — a coverage gap, "
            "not empty-region proof. Unknown/non-canonical --regions ids fail "
            "closed before any I/O."
        ),
        "semantics": "collection_scheduling_recency_only",
    }


# --- P5D1: bounded offline local checkpoint state store ---------------------------


class CheckpointStateError(ValueError):
    """Local state-file update failed — prior bytes stay unchanged."""


def _canonical_entry(entry: Mapping) -> dict:
    """Serialize ONLY the validated bounded entry fields (no privates).

    Historical tolerance: entries loaded from genuine old state files may lack
    ``qualified_scope`` entirely, and a legacy TOP-LEVEL marker must demote
    even a stored ``qualified_scope: true`` (it predates the qualified
    predicate). Both normalize to an explicit False in the new-format store —
    never relabeled current, never a KeyError on real old bytes.
    """
    canonical = {
        key: entry[key]
        for key in (
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
        )
    }
    canonical["qualified_scope"] = bool(entry.get("qualified_scope")) and not entry.get(
        "_legacy_scope"
    )
    if "lineage_page_kind" in entry and not entry.get("_legacy_scope"):
        canonical["lineage_page_kind"] = entry["lineage_page_kind"]
    if "sweep_pages" in entry and not entry.get("_legacy_scope"):
        # Bounded chain proof survives reserialization; legacy stores never
        # gain it (absent metadata grants no new chain credit).
        canonical["sweep_pages"] = entry["sweep_pages"]
        canonical["sweep_chain_started_at"] = entry["sweep_chain_started_at"]
        canonical["sweep_clean"] = entry["sweep_clean"]
    return canonical


def _entry_observation_time(entry: Mapping) -> datetime:
    return _parse_timestamp(entry["observation_time"], "entry observation_time")


def _apply_sweep_lineage(stored: dict | None, incoming: dict) -> dict:
    """Attach bounded multi-page chain proof to an incoming canonical entry.

    Per-page eligibility comes ONLY from ``lineage_page_kind`` derived by the
    bridge from raw committed result facts. A chain starts ONLY from a
    qualified CLEAN null-input page; extension requires the SAME region with
    an input cursor exactly equal to the stored head's committed next cursor
    and a strictly newer observation. Clean pages advance with their ACTUAL
    committed cursor; an ADVANCING degraded/quarantined page TAINTS the chain
    (``sweep_clean=False``): the cursor is preserved for resumption but no
    later terminal page can ever grant whole-region credit — only a genuinely
    new clean null-start requalifies. Failed unchanged-cursor retries keep
    the proven prefix (head unchanged, no increment). A valid auth/quota stop
    takes precedence over zero-progress/page-cap rejection: the stop is
    recorded without collection credit and with the prior proof preserved.
    Same-time exact page replays (advancing, terminal, null-start) re-derive
    the identical lineage before any cursor/hole check, keeping persisted
    bytes idempotent; equal-time conflicting facts still reject. Overflow
    past SWEEP_MAX_PAGES fails closed. Unqualified tails never attach (or
    poison) chain proof.
    """
    kind = incoming.get("lineage_page_kind")
    if not incoming["qualified_scope"]:
        # Unqualified tail: no chain attach — and never poisons the stored
        # proof so a later ordinary valid merge still succeeds.
        return incoming
    if incoming["input_after_place_id"] is None:
        if kind in ("clean_prefix", "terminal_clean"):
            incoming["sweep_pages"] = 1
            incoming["sweep_chain_started_at"] = incoming["observation_time"]
            incoming["sweep_clean"] = True
        return incoming

    if stored is None or "sweep_pages" not in stored or not stored["qualified_scope"]:
        return incoming  # non-null tail without a live chain head: no credit

    prior_time = _entry_observation_time(stored)
    incoming_time = _entry_observation_time(incoming)
    if incoming_time == prior_time:
        # Same-time exact replay of the STORED page (before any cursor/hole
        # check): page facts only — whole/empty are chain-derived state.
        page_keys = (
            "region",
            "next_after_place_id",
            "input_after_place_id",
            "exhausted",
            "stop_reason",
            "blocked",
            "requests_used",
            "observation_time",
            "qualified_scope",
            "lineage_page_kind",
        )
        if all(stored.get(k) == incoming.get(k) for k in page_keys):
            incoming["sweep_pages"] = stored["sweep_pages"]
            incoming["sweep_chain_started_at"] = stored["sweep_chain_started_at"]
            incoming["sweep_clean"] = stored["sweep_clean"]
            incoming["whole_region_complete"] = stored["whole_region_complete"]
            incoming["empty_scope"] = stored["empty_scope"]
        return incoming
    if incoming_time < prior_time:
        return incoming  # older page: handled by the monotonic rules

    if incoming["blocked"] == "auth_quota":
        # Sticky valid stop PRIORITY over zero-progress/page-cap rejection:
        # record the stop without collection credit, preserve prior proof,
        # cursors and other regions (the global stickiness rule in the store
        # then blocks further non-reset updates).
        incoming["sweep_pages"] = stored["sweep_pages"]
        incoming["sweep_chain_started_at"] = stored["sweep_chain_started_at"]
        incoming["sweep_clean"] = stored["sweep_clean"]
        incoming["whole_region_complete"] = False
        return incoming

    head_cursor = stored["next_after_place_id"]
    if incoming["input_after_place_id"] != head_cursor:
        return incoming  # hole / unrelated restart: lineage never mends itself

    if kind == "failed_page":
        # Unchanged-cursor retry of the head page: keep the proven prefix,
        # no page increment, actual page facts preserved.
        incoming["sweep_pages"] = stored["sweep_pages"]
        incoming["sweep_chain_started_at"] = stored["sweep_chain_started_at"]
        incoming["sweep_clean"] = stored["sweep_clean"]
        incoming["whole_region_complete"] = False
        return incoming

    if (
        incoming["next_after_place_id"] == incoming["input_after_place_id"]
        and not incoming["exhausted"]
    ):
        raise CheckpointStateError("zero-progress nonterminal page; rejected")

    pages = stored["sweep_pages"] + 1
    if pages > SWEEP_MAX_PAGES:
        raise CheckpointStateError(
            "sweep lineage exceeds the bounded page count; no credit granted"
        )
    incoming["sweep_pages"] = pages
    incoming["sweep_chain_started_at"] = stored["sweep_chain_started_at"]

    if kind == "terminal_clean":
        # Whole-sweep credit ONLY for a fully clean chain: an advancing
        # degraded/quarantined contribution taints it permanently.
        incoming["sweep_clean"] = stored["sweep_clean"]
        if stored["sweep_clean"]:
            incoming["whole_region_complete"] = True
            incoming["empty_scope"] = (
                "window" if incoming["next_after_place_id"] == head_cursor else None
            )
        else:
            incoming["whole_region_complete"] = False
        return incoming
    # clean_prefix advances preserving cleanliness; degraded_page (incl.
    # incomplete exhausted tails) advances with credit invalidated.
    incoming["sweep_clean"] = stored["sweep_clean"] and kind == "clean_prefix"
    incoming["whole_region_complete"] = False
    return incoming


def update_checkpoint_state(state_path: Path, entry: Mapping) -> dict[str, Any]:
    """Atomically merge ONE validated entry into a bounded local state file.

    Cooperating-writer safety (NOT a distributed guarantee): a portable
    exclusive lock ``<state>.lock`` is acquired (O_CREAT|O_EXCL) BEFORE any
    read; a busy/stale lock fails with a sanitized error (no retry storm, no
    stealing, never removing someone else's lock/temp/file). Publication is a
    same-directory temp file + os.replace with restrictive permissions; any
    permission/parse/validation/replace failure leaves the prior bytes
    untouched (owned temp cleaned up in finally).

    Merge policy: other regions are always preserved. Same region: older
    NONBLOCKING evidence is rejected; identical same-time replay is
    idempotent; conflicting same-time evidence fails closed. An auth/quota
    stop is sticky — a recorded stop survives any newer success, older
    evidence, subset selection, or scope/version transition, and newly
    observed valid blocked evidence is never dropped as stale. No auto reset,
    age expiry, or reset flag: clearing a stop is an explicit later operator
    decision. Historical shapes load under the strict legacy rules and are
    normalized to an explicit unqualified bool in the new-format store — never
    relabeled current. The final encoded document is revalidated (bounded
    size/count, strict markers/types) before publication.
    """
    import os
    import tempfile

    if not str(state_path) or str(state_path) in (".", ".."):
        raise CheckpointStateError("state path is empty or invalid")
    state_path = state_path.absolute()
    parent = state_path.parent
    if not parent.is_dir():
        raise CheckpointStateError("state parent directory must already exist")
    if state_path.exists() and not state_path.is_file():
        raise CheckpointStateError("state target is not a regular file")
    if state_path.is_symlink():
        raise CheckpointStateError("state target is a symlink; refusing to overwrite")

    lock_path = state_path.with_name(state_path.name + ".lock")
    try:
        lock_fd = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as exc:
        raise CheckpointStateError(
            "state lock is busy (another cooperating writer holds it); no retry attempted"
        ) from exc
    except OSError as exc:
        raise CheckpointStateError("state lock could not be created") from exc

    temp_path: Path | None = None
    try:
        with os.fdopen(lock_fd, "w"):
            pass  # hold the lock via the file's existence; fd closed cleanly

        prior: dict[str, dict] = {}
        try:
            if state_path.exists():
                prior = load_checkpoint_snapshot(state_path)
        except CheckpointSnapshotError as exc:
            raise CheckpointStateError(f"prior state is invalid: {exc}") from exc
        except OSError as exc:
            raise CheckpointStateError("prior state could not be read") from exc

        incoming = _canonical_entry(entry)
        incoming_region = incoming["region"]
        merged: dict[str, dict] = {
            region: _canonical_entry(stored) for region, stored in prior.items()
        }
        # Guard precedence (controller-approved): a recorded auth/quota stop
        # refuses any NON-blocked incoming update BEFORE lineage evaluation, so
        # page-cap/zero-progress raises can never defeat the sticky stop.
        if incoming["blocked"] != "auth_quota" and any(
            stored.get("blocked") == "auth_quota" for stored in merged.values()
        ):
            raise CheckpointStateError(
                "an auth/quota stop is recorded in this state; it is sticky "
                "until an explicit operator reset — no update applied"
            )
        incoming = _apply_sweep_lineage(merged.get(incoming_region), incoming)

        existing = merged.get(incoming_region)
        if existing is not None:
            prior_time = _entry_observation_time(existing)
            incoming_time = _entry_observation_time(incoming)
            if incoming_time == prior_time and existing != incoming:
                raise CheckpointStateError(
                    "conflicting evidence at the same observation time; rejected"
                )
            if incoming["blocked"] == "auth_quota":
                # Valid blocked evidence is never dropped as stale.
                merged[incoming_region] = incoming
            elif existing.get("blocked") == "auth_quota":
                raise CheckpointStateError(
                    "an auth/quota stop is recorded for this region; it is "
                    "sticky until an explicit operator reset — no update applied"
                )
            elif incoming_time < prior_time:
                raise CheckpointStateError(
                    "incoming observation is older than the stored one; rejected"
                )
            else:
                merged[incoming_region] = incoming
        else:
            merged[incoming_region] = incoming

        document = {
            "schema_version": SNAPSHOT_SCHEMA_VERSION,
            "source": SNAPSHOT_SOURCE,
            "scope_contract": SNAPSHOT_SCOPE_CONTRACT,
            "entries": [merged[region] for region in sorted(merged)],
        }
        blob = json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True).encode("utf-8")
        if len(blob) > SNAPSHOT_MAX_BYTES:
            raise CheckpointStateError("merged state exceeds the bounded size limit")
        # Revalidate the FINAL encoded document through the strict loader
        # before any bytes are replaced.
        try:
            with tempfile.NamedTemporaryFile(
                "wb", dir=parent, prefix=".state-", suffix=".tmp", delete=False
            ) as handle:
                temp_path = Path(handle.name)  # owned from open, cleaned in finally
                handle.write(blob)
                handle.flush()
                os.fsync(handle.fileno())
        except OSError as exc:
            raise CheckpointStateError("state serialization failed") from exc
        try:
            os.chmod(temp_path, 0o600)
        except OSError as exc:
            raise CheckpointStateError("state publication could not secure permissions") from exc
        try:
            load_checkpoint_snapshot(temp_path)
            os.replace(temp_path, state_path)
            temp_path = None
        except CheckpointSnapshotError as exc:
            # The final revalidation of the encoded document failed: sanitized,
            # prior bytes unchanged, owned temp cleaned by the finally block.
            raise CheckpointStateError(
                "final state revalidation failed; nothing was published"
            ) from exc
        except OSError as exc:
            raise CheckpointStateError("atomic state publication failed") from exc
        return {
            "state_updated": True,
            "region": incoming_region,
            "entries_total": len(merged),
        }
    finally:
        if temp_path is not None and temp_path.exists():
            with contextlib.suppress(OSError):
                temp_path.unlink()
        with contextlib.suppress(OSError):
            lock_path.unlink()  # release ONLY our own lock
