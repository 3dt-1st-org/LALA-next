"""Replay-safe ``ingest.source_files`` receipts + partial-run reconciliation.

The official-source lane writes one ``ingest.source_files`` row per pull as a
provenance receipt. ``ingest.source_files`` has **no** unique constraint today, so
dedup is a pre-flight SELECT by ``(source_name, dataset_name, file_sha256)``
guarded by a transaction-scoped advisory lock. Until a separately approved
operator migration adds a uniqueness constraint, that lock -- not the SELECT
alone -- is what stops two concurrent pulls of the same fingerprint from each
inserting a receipt.
Re-running the same pull against unchanged upstream data must reuse the
existing receipt row instead of appending a duplicate.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Any, Final

_DUPLICATE_SQL: Final[str] = """
    SELECT id
    FROM ingest.source_files
    WHERE source_name = %s
      AND dataset_name = %s
      AND file_sha256 = %s
    ORDER BY downloaded_at DESC
    LIMIT 1
"""

_INSERT_SQL: Final[str] = """
    INSERT INTO ingest.source_files (
        source_name,
        dataset_name,
        file_name,
        file_sha256,
        local_path
    )
    VALUES (%s, %s, %s, %s, %s)
    RETURNING id
"""

# Transaction-scoped advisory lock taken before the duplicate lookup. The lock
# is held only until the caller's transaction commits/rolls back, so it cannot
# leak across runs.
_LOCK_SQL: Final[str] = "SELECT pg_advisory_xact_lock(%s)"


def _receipt_lock_key(source_name: str, dataset_name: str, file_sha256: str) -> int:
    """Derive a stable 63-bit advisory-lock key from the receipt identity.

    Different fingerprints map to different keys; a hash collision can serialize
    two unrelated receipts but cannot merge them, since each still runs its own
    SELECT + INSERT and writes its own row.
    """
    digest = hashlib.sha256(f"{source_name}\x1f{dataset_name}\x1f{file_sha256}".encode()).digest()
    return int.from_bytes(digest[:8], "big", signed=False) & ((1 << 63) - 1)


@dataclass(frozen=True)
class OfficialSourceReceipt:
    """The receipt row written for one official-source pull."""

    source_file_id: str
    replayed: bool


def record_official_source_receipt(
    *,
    conn: Any,
    source_name: str,
    dataset_name: str,
    file_name: str,
    file_sha256: str | None,
    local_path: str | None = None,
) -> OfficialSourceReceipt:
    """Insert or reuse an ``ingest.source_files`` receipt.

    Opens its own cursor on ``conn`` so callers can keep their transaction shape
    (commit stays with the caller). When ``file_sha256`` matches an existing row
    for this ``(source, dataset)``, the existing id is reused and ``replayed`` is
    ``True`` -- this is the replay guard that prevents duplicate receipts.
    """
    if not file_sha256:
        # No content hash -> cannot dedup deterministically; record a fresh row.
        # No advisory lock: there is no dedup identity to protect, and each
        # no-hash call legitimately creates its own receipt row.
        with conn.cursor() as cur:
            cur.execute(
                _INSERT_SQL,
                (source_name, dataset_name, file_name, file_sha256, local_path),
            )
            row = cur.fetchone()
        return OfficialSourceReceipt(source_file_id=str(row[0]), replayed=False)

    with conn.cursor() as cur:
        # Serialize concurrent pulls of the same fingerprint BEFORE the lookup.
        # Until a separately approved operator migration adds a unique
        # constraint, this is the only thing stopping two parallel SELECTs
        # (both empty) from each inserting.
        cur.execute(_LOCK_SQL, (_receipt_lock_key(source_name, dataset_name, file_sha256),))
        cur.execute(_DUPLICATE_SQL, (source_name, dataset_name, file_sha256))
        existing = cur.fetchone()
        if existing:
            return OfficialSourceReceipt(source_file_id=str(existing[0]), replayed=True)
        cur.execute(
            _INSERT_SQL,
            (source_name, dataset_name, file_name, file_sha256, local_path),
        )
        row = cur.fetchone()
    return OfficialSourceReceipt(source_file_id=str(row[0]), replayed=False)


@dataclass(frozen=True)
class PartialRunReport:
    """Reconciles an upstream-reported total against what was actually collected."""

    total: int | None
    collected: int
    partial_run: bool

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "total_count": self.total,
            "collected_count": self.collected,
            "partial_run": self.partial_run,
        }


def reconcile_partial_run(
    *,
    total: int | None,
    collected: int,
) -> PartialRunReport:
    """Flag a partial run when the upstream reported a total we did not reach.

    A ``None`` or zero total means the upstream did not report one, so a partial
    run cannot be proven and the flag is ``False`` (honest: unknown, not partial).
    """
    partial = bool(total and total > 0 and collected < total)
    return PartialRunReport(total=total, collected=collected, partial_run=partial)
