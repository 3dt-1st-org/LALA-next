from __future__ import annotations

import json
import math
import sys
from types import SimpleNamespace

import pytest

from apps.api.app.services import franchise_reference_ingest
from apps.api.app.services.franchise_reference_ingest import parse_brand_stats_items
from apps.api.app.services.official_source_errors import OfficialSourceError
from apps.api.app.tools import run_franchise_reference_ingest


def test_parse_brand_stats_items_normalizes_public_api_rows():
    records, skipped = parse_brand_stats_items(
        [
            {
                "yr": "2025",
                "indutyLclasNm": "외식",
                "indutyMlsfcNm": "한식",
                "corpNm": "(주)라라푸드",
                "brandNm": "라라버거 수원역점",
                "frcsCnt": "42",
                "avrgSlsAmt": "123000",
            },
            {"brandNm": ""},
        ],
        year=2025,
    )

    assert skipped == 1
    assert len(records) == 1
    record = records[0]
    assert record.brand_name_ko == "라라버거 수원역점"
    assert record.normalized_brand_name == "라라버거"
    assert record.headquarters_name_ko == "(주)라라푸드"
    assert record.business_category == "외식 / 한식"
    assert record.franchise_store_count == 42
    assert record.average_sales_amount == 123000
    assert record.primary_source == "fair_trade_commission"
    assert record.source_record_id == "2025:라라푸드:라라버거"


def test_franchise_reference_ingest_plan_has_no_api_call_or_mutation(capsys):
    exit_code = run_franchise_reference_ingest.main(["--json"])

    assert exit_code == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["mode"] == "plan"
    assert payload["live_api_call"] is False
    assert payload["db_mutation"] is False
    assert payload["target"] == "economy.franchise_brands"
    assert "analytics.place_business_identity" in payload["downstream"]


def test_fetch_franchise_brand_references_deduplicates_api_rows(monkeypatch):
    from apps.api.app.services import franchise_reference_ingest

    calls = {"count": 0}

    def fake_fetch_page(**kwargs):
        calls["count"] += 1
        return {
            "totalCount": 2,
            "items": [
                {"yr": "2025", "corpNm": "라라푸드", "brandNm": "라라버거", "frcsCnt": 3},
                {"yr": "2025", "corpNm": "라라푸드", "brandNm": "라라버거", "frcsCnt": 5},
            ],
        }

    monkeypatch.setattr(franchise_reference_ingest, "_fetch_page", fake_fetch_page)

    result = franchise_reference_ingest.fetch_franchise_brand_references(
        api_key="dummy",
        year=2025,
        rows=0,
        page_size=1000,
        timeout=1,
    )

    assert calls["count"] == 1
    assert result.parsed_row_count == 1
    assert result.skipped_row_count == 1
    assert result.brands[0].franchise_store_count == 5


def test_franchise_reference_ingest_apply_requires_guard(monkeypatch, capsys):
    monkeypatch.setenv("PUBLIC_DATA_SERVICE_KEY", "dummy")
    monkeypatch.setenv("DB_DSN", "postgresql://example")
    monkeypatch.delenv(run_franchise_reference_ingest.ALLOW_ENV, raising=False)

    exit_code = run_franchise_reference_ingest.main(
        ["--apply", "--confirm", run_franchise_reference_ingest.CONFIRM_TEXT, "--json"]
    )

    assert exit_code == 2
    payload = json.loads(capsys.readouterr().out)
    assert run_franchise_reference_ingest.ALLOW_ENV in payload["error"]


# ---------------------------------------------------------------------------
# Reliability boundary tests: replay receipt, bounded errors, decision-input
# ---------------------------------------------------------------------------


def _brand_record():
    return franchise_reference_ingest.FranchiseBrandReference(
        brand_id="2025:hq:brand",
        brand_name_ko="브랜드",
        normalized_brand_name="브랜드",
        headquarters_name_ko="hq",
        business_category="외식 / 한식",
        main_product=None,
        franchise_store_count=10,
        average_sales_amount=1000.0,
        chain_scale_score=franchise_reference_ingest._chain_scale_score(10),
        primary_source="fair_trade_commission",
        source_record_id="2025:hq:brand",
    )


def _ingest_result():
    return franchise_reference_ingest.FranchiseReferenceIngestResult(
        source_name="fair_trade_commission",
        dataset_name="공정위 가맹",
        source_url="https://example.invalid/api",
        year=2025,
        requested_rows=1,
        total_count=1,
        parsed_row_count=1,
        skipped_row_count=0,
        brands=(_brand_record(),),
    )


def test_brands_fingerprint_reflects_row_content_not_only_counters():
    # F1: a corrected franchise_store_count (row content) with identical
    # counters (parsed_row_count, total_count, ...) must change the
    # fingerprint. The old counters-only hash would have been identical here.
    original = _ingest_result()
    corrected_brand = franchise_reference_ingest.FranchiseBrandReference(
        brand_id="2025:hq:brand",
        brand_name_ko="브랜드",
        normalized_brand_name="브랜드",
        headquarters_name_ko="hq",
        business_category="외식 / 한식",
        main_product=None,
        franchise_store_count=99,  # corrected upstream value
        average_sales_amount=1000.0,
        chain_scale_score=franchise_reference_ingest._chain_scale_score(99),
        primary_source="fair_trade_commission",
        source_record_id="2025:hq:brand",
    )

    original_hash = franchise_reference_ingest._brands_fingerprint(original.brands)
    corrected_hash = franchise_reference_ingest._brands_fingerprint((corrected_brand,))

    assert original_hash != corrected_hash


def _install_fake_psycopg2(monkeypatch, fetchone_results):
    executed: list = []

    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))

        def fetchone(self):
            return fetchone_results.pop(0) if fetchone_results else None

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self):
            return Cursor()

        def commit(self):
            executed.append(("commit", None))

    def connect(dsn, connect_timeout):
        executed.append(("connect", {"dsn": dsn, "connect_timeout": connect_timeout}))
        return Connection()

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))
    monkeypatch.setitem(
        sys.modules,
        "psycopg2.extras",
        SimpleNamespace(
            execute_values=lambda cur, sql, values, page_size=500: executed.append(
                ("execute_values", len(values))
            )
        ),
    )
    return executed


def test_insert_franchise_brand_references_writes_receipt_then_upserts(monkeypatch):
    executed = _install_fake_psycopg2(monkeypatch, [None, ("source-file-id",)])
    payload = franchise_reference_ingest.insert_franchise_brand_references(
        dsn="postgresql://redacted",
        result=_ingest_result(),
        connect_timeout=7,
    )
    assert payload["replayed"] is False
    assert payload["source_file_id"] == "source-file-id"
    assert payload["inserted_or_updated_rows"] == 1
    assert any("SELECT id" in sql and "ingest.source_files" in sql for sql, _ in executed)
    assert any("INSERT INTO ingest.source_files" in sql for sql, _ in executed)
    assert any(sql == "execute_values" for sql, _ in executed)


def test_insert_franchise_brand_references_upsert_runs_even_when_replayed(monkeypatch):
    # F1: replayed is provenance metadata only -- it must never gate the
    # actual, idempotent ON CONFLICT upsert. An existing receipt row must not
    # stop a content-only upstream correction (e.g. a corrected store count)
    # from being persisted.
    executed = _install_fake_psycopg2(monkeypatch, [("existing-source-id",)])
    payload = franchise_reference_ingest.insert_franchise_brand_references(
        dsn="postgresql://redacted",
        result=_ingest_result(),
        connect_timeout=7,
    )
    assert payload["replayed"] is True
    assert payload["source_file_id"] == "existing-source-id"
    assert payload["inserted_or_updated_rows"] == 1
    # No NEW source_files INSERT (existing receipt reused)...
    assert not any("INSERT INTO ingest.source_files" in sql for sql, _ in executed)
    # ...but the brand upsert always runs regardless of replay.
    assert any(sql == "execute_values" for sql, _ in executed)


def test_fetch_page_raises_bounded_error_without_raw_upstream_text(monkeypatch):
    import urllib.request

    raw_body = json.dumps(
        {"resultCode": "30", "resultMsg": "ServiceKey echo-do-not-leak detail"}
    ).encode("utf-8")

    class _Response:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def read(self):
            return raw_body

    monkeypatch.setattr(urllib.request, "urlopen", lambda *a, **k: _Response())

    with pytest.raises(OfficialSourceError) as info:
        franchise_reference_ingest._fetch_page(
            api_url="https://example.invalid/api",
            api_key="dummy",
            year=2025,
            page_no=1,
            page_size=10,
            timeout=1,
        )
    message = str(info.value)
    assert "echo-do-not-leak" not in message
    assert "ServiceKey" not in message
    assert info.value.category == "auth"


def test_fetch_page_raises_on_explicit_zero_result_code(monkeypatch):
    # F4: resultCode="0" is a real failure for this source (only "00" means
    # success) -- it must raise, not be silently swallowed as a success shorthand.
    import urllib.request

    raw_body = json.dumps({"resultCode": "0", "resultMsg": "no detail"}).encode("utf-8")

    class _Response:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def read(self):
            return raw_body

    monkeypatch.setattr(urllib.request, "urlopen", lambda *a, **k: _Response())

    with pytest.raises(OfficialSourceError):
        franchise_reference_ingest._fetch_page(
            api_url="https://example.invalid/api",
            api_key="dummy",
            year=2025,
            page_no=1,
            page_size=10,
            timeout=1,
        )


def test_fetch_franchise_brand_references_flags_partial_run_when_capped(monkeypatch):
    def fake_fetch_page(**kwargs):
        return {
            "totalCount": 50,
            "items": [
                {"yr": "2025", "corpNm": "hq", "brandNm": f"brand{n}", "frcsCnt": 2}
                for n in range(2)
            ],
        }

    monkeypatch.setattr(franchise_reference_ingest, "_fetch_page", fake_fetch_page)
    result = franchise_reference_ingest.fetch_franchise_brand_references(
        api_key="dummy",
        year=2025,
        rows=2,  # operator cap well below the upstream total of 50
        page_size=10,
        timeout=1,
    )
    assert result.total_count == 50
    assert result.collected_count == 2
    assert result.partial_run is True


def test_franchise_reference_does_not_fabricate_main_product_or_signals():
    # Decision-input/provenance only: main_product stays None (never invented),
    # chain_scale_score is a deterministic transform of the upstream store count.
    records, _ = parse_brand_stats_items(
        [{"yr": "2025", "corpNm": "hq", "brandNm": "brand", "frcsCnt": "1000"}],
        year=2025,
    )
    assert len(records) == 1
    assert records[0].main_product is None
    assert records[0].chain_scale_score == round(min(1.0, math.log10(1000) / 3.0), 4)
