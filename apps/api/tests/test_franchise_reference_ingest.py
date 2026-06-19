from __future__ import annotations

import json

from apps.api.app.services.franchise_reference_ingest import parse_brand_stats_items
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
