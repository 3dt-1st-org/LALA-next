"""Focused tests for replay-safe official-source receipts + partial-run checks."""

from __future__ import annotations

from apps.api.app.services import official_source_receipts as receipts


# Each cursor() call shares one ordered fetchone queue on the connection.
class _FakeConn:
    def __init__(self, fetchone_results):
        self.executed: list[tuple] = []
        self.fetchone_results = list(fetchone_results)

    def cursor(self):
        return _FakeCursor(self)


class _FakeCursor:
    def __init__(self, conn: _FakeConn) -> None:
        self._conn = conn

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return None

    def execute(self, sql, params=None):
        self._conn.executed.append((sql, params))

    def fetchone(self):
        if not self._conn.fetchone_results:
            return None
        return self._conn.fetchone_results.pop(0)


def test_first_pull_inserts_receipt_and_is_not_replay():
    conn = _FakeConn([None, ("new-id-0001",)])
    result = receipts.record_official_source_receipt(
        conn=conn,
        source_name="tour_api",
        dataset_name="한국관광공사_국문 관광정보 서비스_GW",
        file_name="tour_api::2026-07-26",
        file_sha256="a" * 64,
    )
    assert result.replayed is False
    assert result.source_file_id == "new-id-0001"
    # Advisory lock, then duplicate-check SELECT, then the INSERT.
    assert "pg_advisory_xact_lock" in conn.executed[0][0]
    assert "SELECT id" in conn.executed[1][0]
    assert "INSERT INTO ingest.source_files" in conn.executed[2][0]


def test_replay_with_same_sha_reuses_id_and_skips_insert():
    conn = _FakeConn([("existing-id-9999",)])
    result = receipts.record_official_source_receipt(
        conn=conn,
        source_name="kopis",
        dataset_name="공연예술통합전수망",
        file_name="kopis::2026-07-26",
        file_sha256="b" * 64,
    )
    assert result.replayed is True
    assert result.source_file_id == "existing-id-9999"
    # Advisory lock then duplicate-check SELECT; no INSERT on replay.
    assert len(conn.executed) == 2
    assert "pg_advisory_xact_lock" in conn.executed[0][0]
    assert "SELECT id" in conn.executed[1][0]
    assert not any("INSERT INTO ingest.source_files" in sql for sql, _ in conn.executed)


def test_changed_sha_inserts_a_new_receipt():
    conn = _FakeConn([None, ("new-id-0002",)])
    result = receipts.record_official_source_receipt(
        conn=conn,
        source_name="kopis",
        dataset_name="공연예술통합전수망",
        file_name="kopis::2026-07-27",
        file_sha256="c" * 64,  # different content -> not a replay
    )
    assert result.replayed is False
    assert result.source_file_id == "new-id-0002"


def test_missing_sha_always_inserts_and_is_not_replay():
    conn = _FakeConn([("id-no-sha",)])
    result = receipts.record_official_source_receipt(
        conn=conn,
        source_name="franchise_reference",
        dataset_name="공정위 가맹점",
        file_name="franchise::2026",
        file_sha256="",
    )
    assert result.replayed is False
    assert result.source_file_id == "id-no-sha"
    # No duplicate SELECT and no advisory lock when there is no sha to dedup on.
    assert len(conn.executed) == 1
    assert "INSERT INTO ingest.source_files" in conn.executed[0][0]
    assert not any("pg_advisory_xact_lock" in sql for sql, _ in conn.executed)


def test_reconcile_partial_run_flags_shortfall():
    report = receipts.reconcile_partial_run(total=100, collected=80)
    assert report.partial_run is True
    assert report.total == 100 and report.collected == 80
    assert report.to_public_dict() == {
        "total_count": 100,
        "collected_count": 80,
        "partial_run": True,
    }


def test_reconcile_partial_run_clean_when_total_reached():
    assert receipts.reconcile_partial_run(total=100, collected=100).partial_run is False
    assert receipts.reconcile_partial_run(total=100, collected=120).partial_run is False


def test_reconcile_partial_run_honest_when_total_unknown():
    # Unknown total -> cannot prove a shortfall -> partial_run False (not "complete").
    for total in (None, 0):
        report = receipts.reconcile_partial_run(total=total, collected=50)
        assert report.partial_run is False
        assert report.total in (None, 0)


def test_hashed_receipt_takes_advisory_lock_before_duplicate_lookup():
    # Until canonical 063 applies a unique index, the SELECT-then-INSERT must be
    # guarded by a transaction-scoped advisory lock so two concurrent pulls of
    # the same fingerprint cannot each insert a receipt.
    conn = _FakeConn([None, ("locked-new-id",)])
    result = receipts.record_official_source_receipt(
        conn=conn,
        source_name="tour_api",
        dataset_name="한국관광공사_국문 관광정보 서비스_GW",
        file_name="tour_api::2026-07-26",
        file_sha256="d" * 64,
    )
    assert result.replayed is False
    sqls = [sql for sql, _ in conn.executed]
    lock_idx = next(i for i, sql in enumerate(sqls) if "pg_advisory_xact_lock" in sql)
    dup_idx = next(i for i, sql in enumerate(sqls) if "SELECT id" in sql)
    assert lock_idx < dup_idx


def test_no_hash_receipt_does_not_take_advisory_lock():
    conn = _FakeConn([("id-no-sha-2",)])
    result = receipts.record_official_source_receipt(
        conn=conn,
        source_name="franchise_reference",
        dataset_name="공정위 가맹점",
        file_name="franchise::2026",
        file_sha256="",
    )
    assert result.replayed is False
    sqls = [sql for sql, _ in conn.executed]
    assert not any("pg_advisory_xact_lock" in sql for sql in sqls)
    assert len(sqls) == 1
    assert "INSERT INTO ingest.source_files" in sqls[0]
