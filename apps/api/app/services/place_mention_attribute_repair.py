"""Redaction repair for legacy URL-shaped values in place_mentions_weekly.attributes.

S2 companion to the S1 ingest-side redaction (review_mention_ingest). Existing
production rows written before S1 still carry raw URL-shaped ``external_key``
values inside ``attributes.preprocess.retained_external_keys`` /
``filtered_external_keys``. The ingest ON CONFLICT upsert preserves legacy
``review_attributes``/``review_quality`` but overwrites the rest only on the
next apply, so re-running ingest does NOT clean the backlog — only this repair
path can zero it.

- Detection walks the JSONB **recursively** (objects and arrays) and classifies
  each *string value* by URL form (scheme/host/path/query heuristics) — not by
  key allowlist, so an unsafe value hidden under any key at any depth is found.
- Repair action per value (evidence: review_attribute_batch.py joins
  ``preprocess.retained_external_keys`` back to ``community.posts`` via the
  pgcrypto digest of ``provider|external_key``, so the reference must SURVIVE
  as the same S1 digest — removing it would gut the AI enrichment lane):
  in-bound values become the provider-scoped sha256 digest; over-bound values
  are dropped (fail-closed, matching the S1 4096-char bound — never
  truncate-hashed, because two keys sharing a 4096-char prefix must never
  collide into one digest and one join).
- A count-only field records drops, mirroring the S1
  ``retained_external_key_bounded_count`` convention.

No unsafe value ever leaves this module: reports carry counts, field paths,
and sha256 digests only.
"""

from __future__ import annotations

import hashlib
import json
import re
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Any

# Why: value-form detection, not key allowlist — the production defect class is
# "URL-shaped string wherever it ended up", which a key allowlist would miss.
_URL_SHAPED = re.compile(
    r"^(?:https?|ftp)://[^\s]+",  # scheme://... with no whitespace
    re.IGNORECASE,
)
# Why: bare authority/path forms (e.g. "www.host/x") are the same leak class
# even without a scheme; www. is the production-observed prefix form.
_URL_AUTHORITY_SHAPED = re.compile(
    r"^(?:www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?:/[^\s]*)?$",
    re.IGNORECASE,
)

# Same fail-closed bound as review_mention_ingest._EXTERNAL_KEY_HASH_INPUT_MAX;
# kept as a local constant so the repair contract is explicit about it.
_HASH_INPUT_MAX = 4096

# Sentinel marking an over-bound unsafe value that must be dropped from its
# container (list slot removed / dict key removed) — never written anywhere.
_DROPPED = object()


def is_url_shaped(value: Any) -> bool:
    """Return True when a string value is URL-shaped by form (any depth-safe check)."""
    if not isinstance(value, str) or not value:
        return False
    if _URL_SHAPED.match(value):
        return True
    return bool(_URL_AUTHORITY_SHAPED.match(value))


def safe_digest(provider: str, value: str) -> str | None:
    """Provider-scoped sha256 of an unsafe value; None when over the bound.

    Mirrors review_mention_ingest.external_key_sha256 exactly (same scoping,
    same 4096-char bound, same fail-closed exclusion — never truncate-hash).
    """
    material = f"{provider}|{value}"
    if len(material) > _HASH_INPUT_MAX:
        return None
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class Finding:
    """One unsafe value occurrence: location only, never the value."""

    path: tuple[str, ...]  # e.g. ("preprocess", "retained_external_keys", "0")
    digest: str | None  # sha256 replacement (None when over-bound -> drop)


@dataclass(frozen=True)
class RowPlan:
    """Repair plan for one place_mentions_weekly row. No unsafe values."""

    mention_id: str
    place_id: str | None
    week_start: str
    provider: str
    before_sha256: str  # checksum of the full original JSONB
    after_sha256: str  # checksum of the repaired JSONB
    findings: tuple[Finding, ...] = field(default_factory=tuple)

    @property
    def unsafe_value_count(self) -> int:
        return len(self.findings)

    @property
    def replace_count(self) -> int:
        return sum(1 for item in self.findings if item.digest is not None)

    @property
    def drop_count(self) -> int:
        return sum(1 for item in self.findings if item.digest is None)


def attributes_sha256(value: Any) -> str:
    """Stable checksum of a full attributes JSONB (sorted, no spaces)."""
    material = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def find_unsafe_values(
    attributes: Any,
    *,
    provider: str,
    path: tuple[str, ...] = (),
) -> list[Finding]:
    """Recursively locate URL-shaped string values anywhere in the JSONB."""
    findings: list[Finding] = []
    if isinstance(attributes, dict):
        for key in sorted(attributes):
            findings.extend(
                find_unsafe_values(attributes[key], provider=provider, path=(*path, str(key)))
            )
    elif isinstance(attributes, list):
        for index, item in enumerate(attributes):
            findings.extend(find_unsafe_values(item, provider=provider, path=(*path, str(index))))
    elif is_url_shaped(attributes):
        findings.append(Finding(path=path, digest=safe_digest(provider, attributes)))
    return findings


def redact_unsafe_values(
    attributes: Any,
    *,
    provider: str,
) -> tuple[Any, bool]:
    """Return ``(repaired, changed)``: unsafe strings -> digests; over-bound -> dropped.

    Containers emptied by a drop are pruned only when the drop emptied them —
    a container that was already empty before repair is preserved untouched, so
    the repair never rewrites unrelated shape. Idempotent because a sha256
    digest is never URL-shaped.
    """
    if isinstance(attributes, dict):
        repaired: dict[str, Any] = {}
        changed = False
        for key, value in attributes.items():
            new_value, value_changed = redact_unsafe_values(value, provider=provider)
            changed = changed or value_changed
            if value_changed and new_value is _DROPPED:
                # A dict value (not a list slot) that was over-bound -> drop key.
                continue
            if value_changed and new_value in ([], {}):
                # This container emptied *because of a drop* -> prune the key.
                continue
            repaired[key] = new_value
        return (repaired, changed) if changed else (attributes, False)
    if isinstance(attributes, list):
        repaired_list: list[Any] = []
        changed = False
        for item in attributes:
            new_item, item_changed = redact_unsafe_values(item, provider=provider)
            changed = changed or item_changed
            if item_changed and new_item is _DROPPED:
                # This slot was an over-bound unsafe value -> remove the slot.
                continue
            repaired_list.append(new_item)
        return (repaired_list, changed) if changed else (attributes, False)
    if is_url_shaped(attributes):
        digest = safe_digest(provider, attributes)
        if digest is None:
            # Over-bound: fail closed — drop the value entirely, never a
            # truncated hash that could collide with a shorter key's digest.
            return (_DROPPED, True)
        return (digest, True)
    return (attributes, False)


def plan_row_repair(
    *,
    mention_id: str,
    place_id: str | None,
    week_start: Any,
    provider: str,
    attributes: Any,
) -> RowPlan | None:
    """Build a RowPlan for one row, or None when the row has nothing unsafe."""
    findings = find_unsafe_values(attributes, provider=provider)
    if not findings:
        return None
    before = attributes_sha256(attributes)
    repaired, _changed = redact_unsafe_values(attributes, provider=provider)
    after = attributes_sha256(repaired)
    return RowPlan(
        mention_id=str(mention_id),
        place_id=str(place_id) if place_id is not None else None,
        week_start=str(week_start),
        provider=str(provider),
        before_sha256=before,
        after_sha256=after,
        findings=tuple(findings),
    )


def summarize_row_plans(
    plans: list[RowPlan],
    *,
    scanned_row_count: int = 0,
) -> dict[str, Any]:
    """Aggregate-safe summary: counts, paths, digests only — never values."""
    field_counts: dict[str, int] = defaultdict(int)
    for plan in plans:
        for finding in plan.findings:
            # Root field of the path (e.g. "preprocess" for preprocess.retained_external_keys.0)
            field_counts[finding.path[0] if finding.path else "<root>"] += 1
    return {
        "scanned_row_count": scanned_row_count,
        "affected_row_count": len(plans),
        "unsafe_value_count": sum(plan.unsafe_value_count for plan in plans),
        "replace_action_count": sum(plan.replace_count for plan in plans),
        "drop_action_count": sum(plan.drop_count for plan in plans),
        "field_breakdown": dict(sorted(field_counts.items())),
    }
