from __future__ import annotations

import json
import sys
from types import SimpleNamespace

from openpyxl import Workbook

from apps.api.app.services import card_spending_ingest
from apps.api.app.tools import run_card_spending_file_ingest


def test_card_spending_ingest_plan_is_file_based_without_live_call(capsys):
    exit_code = run_card_spending_file_ingest.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["live_api_call"] is False
    assert payload["db_mutation"] is False
    assert payload["supported_file_types"] == ["csv", "xlsx"]
    assert payload["target"] == [
        "economy.card_spending_area_monthly",
        "economy.card_spending_demographics",
    ]
    assert payload["apply_required_env"] == ["DB_DSN"]


def test_parse_detail_csv_maps_card_columns_to_data_dictionary(tmp_path):
    source = tmp_path / "detail.csv"
    source.write_text(
        "\n".join(
            [
                "기준년월일,시군구코드,카드사 업종분류코드,카드사 업종중분류명,성별,연령별,매출금액,매출건수",
                "20250806,41110,FD01,음식점,F,20,1000,2",
                "20250807,41110,FD01,음식점,M,30,2500,3",
            ]
        ),
        encoding="utf-8",
    )

    result = card_spending_ingest.parse_card_spending_file(path=source)

    assert result.input_row_count == 2
    assert result.parsed_row_count == 2
    assert result.skipped_row_count == 0
    assert len(result.area_monthly_rows) == 1
    area = result.area_monthly_rows[0]
    assert area.month.isoformat() == "2025-08-01"
    assert area.region_name_ko == "수원시"
    assert area.industry_code == "FD01"
    assert area.industry_name_ko == "음식점"
    assert str(area.spend_amount) == "3500"
    assert area.transaction_count == 5
    assert area.visitor_type == "domestic"
    assert len(result.demographic_rows) == 2
    assert {row.gender for row in result.demographic_rows} == {"female", "male"}
    assert {row.age_group for row in result.demographic_rows} == {"20s", "30s"}


def test_parse_aggregate_csv_splits_gender_age_code(tmp_path):
    source = tmp_path / "aggregate.csv"
    source.write_text(
        "\n".join(
            [
                "기준년월,시군구코드,성연령코드,중분류업종코드,매출금액",
                "202509,41210,F20,CT01,12000",
                "202509,41210,M30,CT01,8000",
            ]
        ),
        encoding="utf-8",
    )

    result = card_spending_ingest.parse_card_spending_file(
        path=source,
        dataset_name=card_spending_ingest.AGGREGATE_DATASET_NAME,
    )

    assert len(result.area_monthly_rows) == 1
    area = result.area_monthly_rows[0]
    assert area.month.isoformat() == "2025-09-01"
    assert area.region_name_ko == "광명시"
    assert area.industry_code == "CT01"
    assert str(area.spend_amount) == "20000"
    assert area.transaction_count is None
    assert len(result.demographic_rows) == 2
    assert result.demographic_rows[0].gender == "female"
    assert result.demographic_rows[0].age_group == "20s"


def test_parse_xlsx_uses_same_column_mapping(tmp_path):
    source = tmp_path / "card.xlsx"
    workbook = Workbook()
    worksheet = workbook.active
    worksheet.append(["기준년월", "시군구코드", "성연령코드", "중분류업종코드", "매출금액"])
    worksheet.append(["202510", "41590", "F40", "TR01", 15000])
    workbook.save(source)

    result = card_spending_ingest.parse_card_spending_file(path=source)

    assert len(result.area_monthly_rows) == 1
    assert result.area_monthly_rows[0].region_name_ko == "화성시"
    assert result.demographic_rows[0].gender == "female"
    assert result.demographic_rows[0].age_group == "40s"


def test_apply_requires_guard_before_parsing_file(monkeypatch, tmp_path, capsys):
    source = tmp_path / "detail.csv"
    source.write_text("기준년월,시군구명,매출금액\n202508,수원시,1000\n", encoding="utf-8")
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.delenv(run_card_spending_file_ingest.ALLOW_ENV, raising=False)

    exit_code = run_card_spending_file_ingest.main(
        [
            "--apply",
            "--confirm",
            run_card_spending_file_ingest.CONFIRM_TEXT,
            "--file-path",
            str(source),
        ]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_card_spending_file_ingest.ALLOW_ENV in output
    assert dsn not in output
    assert password not in output


def test_insert_card_spending_result_targets_source_and_economy_tables(monkeypatch, tmp_path):
    source = tmp_path / "detail.csv"
    source.write_text("기준년월,시군구명,매출금액,매출건수\n202508,수원시,1000,2\n", encoding="utf-8")
    result = card_spending_ingest.parse_card_spending_file(path=source)
    executed = []
    fetches = [None, ("source-file-id",)]

    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))
            self.rowcount = 1

        def fetchone(self):
            return fetches.pop(0)

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

    payload = card_spending_ingest.insert_card_spending_result(
        dsn="postgresql://redacted",
        result=result,
        connect_timeout=7,
    )

    assert payload["inserted_area_monthly_rows"] == 1
    assert payload["inserted_demographic_rows"] == 0
    assert "SELECT id" in executed[1][0]
    assert "INSERT INTO ingest.source_files" in executed[2][0]
    assert "INSERT INTO economy.card_spending_area_monthly" in executed[3][0]
    assert executed[-1] == ("commit", None)
