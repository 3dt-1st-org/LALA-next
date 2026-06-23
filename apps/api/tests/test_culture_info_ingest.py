from __future__ import annotations

import json
import sys
from types import SimpleNamespace

from apps.api.app.services import culture_info_ingest
from apps.api.app.tools import run_culture_info_ingest


def test_culture_info_ingest_plan_uses_public_data_key_without_live_call(capsys):
    exit_code = run_culture_info_ingest.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["source_name"] == "kcisa"
    assert payload["operation"] == "area2"
    assert payload["target"] == "culture.events"
    assert payload["job_name"] == run_culture_info_ingest.JOB_NAME
    assert payload["required_env"] == ["PUBLIC_DATA_SERVICE_KEY"]
    assert payload["live_api_call"] is False
    assert payload["db_mutation"] is False


def test_parse_culture_info_event_maps_fields_to_data_dictionary_names():
    xml = """
    <response>
      <header><resultCode>00</resultCode><resultMsg>정상입니다.</resultMsg></header>
      <body>
        <totalCount>1</totalCount>
        <items>
          <item>
            <serviceName>전시</serviceName>
            <seq>345071</seq>
            <title>미디어&amp;amp;middot;아트 융합 전시 DREAM LIGHT</title>
            <startDate>20250926</startDate>
            <endDate>20261231</endDate>
            <place>수원시미디어센터</place>
            <realmName>전시</realmName>
            <area>경기</area>
            <sigungu>수원시</sigungu>
            <thumbnail>http://www.culture.go.kr/upload/rdf/thumb.jpg</thumbnail>
            <gpsX>127.025</gpsX>
            <gpsY>37.263</gpsY>
          </item>
        </items>
      </body>
    </response>
    """

    events, total_count = culture_info_ingest.parse_culture_info_events(xml)

    assert total_count == 1
    assert len(events) == 1
    event = events[0]
    assert event.event_id == "kcisa-culture-info-345071"
    assert event.title_ko == "미디어·아트 융합 전시 DREAM LIGHT"
    assert event.event_type == "전시"
    assert event.venue_name_ko == "수원시미디어센터"
    assert event.area == "경기도"
    assert event.region_name_ko == "수원시"
    assert event.starts_on and event.starts_on.isoformat() == "2025-09-26"
    assert event.ends_on and event.ends_on.isoformat() == "2026-12-31"
    assert event.thumbnail_url == "https://www.culture.go.kr/upload/rdf/thumb.jpg"
    assert event.to_event_row() == {
        "event_id": "kcisa-culture-info-345071",
        "title_ko": "미디어·아트 융합 전시 DREAM LIGHT",
        "title_en": None,
        "event_type": "전시",
        "venue_name_ko": "수원시미디어센터",
        "venue_place_id": None,
        "region_name_ko": "수원시",
        "starts_on": "2025-09-26",
        "ends_on": "2026-12-31",
        "url": None,
        "primary_source": "kcisa",
        "source_record_id": "345071",
    }


def test_fetch_culture_info_events_uses_num_ofrows_param(monkeypatch):
    class Response:
        text = """
        <response>
          <header><resultCode>00</resultCode><resultMsg>정상입니다.</resultMsg></header>
          <body>
            <totalCount>1</totalCount>
            <items>
              <item>
                <seq>1</seq>
                <title>행사</title>
                <startDate>20260601</startDate>
                <endDate>20260630</endDate>
                <place>장소</place>
                <realmName>공연</realmName>
                <area>경기</area>
                <sigungu>수원시</sigungu>
              </item>
            </items>
          </body>
        </response>
        """

        def raise_for_status(self):
            return None

    calls = []

    def get(url, params, timeout):
        calls.append({"url": url, "params": params, "timeout": timeout})
        return Response()

    monkeypatch.setitem(sys.modules, "requests", SimpleNamespace(get=get))

    result = culture_info_ingest.fetch_culture_info_events(
        service_key="secret-key",
        rows=1,
        page_size=1,
    )

    assert len(calls) == 1
    assert calls[0]["url"].endswith("/area2")
    assert calls[0]["params"]["serviceKey"] == "secret-key"
    assert calls[0]["params"]["sido"] == "경기"
    assert calls[0]["params"]["sigungu"] == "수원시"
    assert calls[0]["params"]["numOfrows"] == "1"
    assert result.raw_count == 1
    assert len(result.events) == 1


def test_apply_requires_guard_before_calling_api(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("PUBLIC_DATA_SERVICE_KEY", "public-data-secret")
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.delenv(run_culture_info_ingest.ALLOW_ENV, raising=False)

    exit_code = run_culture_info_ingest.main(
        ["--apply", "--confirm", run_culture_info_ingest.CONFIRM_TEXT]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_culture_info_ingest.ALLOW_ENV in output
    assert dsn not in output
    assert password not in output
    assert "public-data-secret" not in output


def test_preview_redacts_service_key_on_execution_error(monkeypatch, capsys):
    monkeypatch.setenv("PUBLIC_DATA_SERVICE_KEY", "public-data-secret")

    def fail(**kwargs):
        raise RuntimeError("bad service key public-data-secret")

    monkeypatch.setattr(run_culture_info_ingest, "fetch_culture_info_events", fail)

    exit_code = run_culture_info_ingest.main(["--preview"])

    output = capsys.readouterr().out
    assert exit_code == 2
    assert "[redacted]" in output
    assert "public-data-secret" not in output


def test_apply_records_succeeded_job_run(monkeypatch, capsys):
    monkeypatch.setenv("PUBLIC_DATA_SERVICE_KEY", "public-data-secret")
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(run_culture_info_ingest.ALLOW_ENV, "1")
    recorded_runs = []

    result = culture_info_ingest.CultureInfoFetchResult(
        events=(),
        request_count=1,
        raw_count=0,
        total_count=0,
        operation="area2",
        sido="경기",
        sigungu="수원시",
    )

    monkeypatch.setattr(
        run_culture_info_ingest,
        "fetch_culture_info_events",
        lambda **kwargs: result,
    )
    monkeypatch.setattr(
        run_culture_info_ingest,
        "upsert_culture_info_events",
        lambda **kwargs: {"upserted_rows": 0},
    )
    monkeypatch.setattr(
        run_culture_info_ingest,
        "record_job_run",
        lambda **kwargs: recorded_runs.append(kwargs),
    )

    exit_code = run_culture_info_ingest.main(
        ["--apply", "--confirm", run_culture_info_ingest.CONFIRM_TEXT, "--json"]
    )

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["job_name"] == run_culture_info_ingest.JOB_NAME
    assert len(recorded_runs) == 1
    assert recorded_runs[0]["job_name"] == run_culture_info_ingest.JOB_NAME
    assert recorded_runs[0]["status"] == "succeeded"
    assert recorded_runs[0]["error_message"] is None


def test_apply_failure_records_redacted_job_run(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("PUBLIC_DATA_SERVICE_KEY", "public-data-secret")
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.setenv(run_culture_info_ingest.ALLOW_ENV, "1")
    recorded_runs = []

    def fail(**kwargs):
        raise RuntimeError(f"bad service key public-data-secret dsn={dsn} password={password}")

    monkeypatch.setattr(run_culture_info_ingest, "fetch_culture_info_events", fail)
    monkeypatch.setattr(
        run_culture_info_ingest,
        "record_job_run",
        lambda **kwargs: recorded_runs.append(kwargs),
    )

    exit_code = run_culture_info_ingest.main(
        ["--apply", "--confirm", run_culture_info_ingest.CONFIRM_TEXT, "--json"]
    )

    output = capsys.readouterr().out
    payload = json.loads(output)
    assert exit_code == 2
    assert "[redacted]" in payload["error"]
    assert "public-data-secret" not in output
    assert dsn not in output
    assert password not in output
    assert len(recorded_runs) == 1
    assert recorded_runs[0]["job_name"] == run_culture_info_ingest.JOB_NAME
    assert recorded_runs[0]["status"] == "failed"
    assert "[redacted]" in recorded_runs[0]["error_message"]
    assert "public-data-secret" not in recorded_runs[0]["error_message"]
    assert dsn not in recorded_runs[0]["error_message"]
    assert password not in recorded_runs[0]["error_message"]


def test_upsert_culture_info_events_targets_source_files_and_events(monkeypatch):
    executed = []

    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))
            self.rowcount = 1

        def fetchone(self):
            return ("source-file-id",)

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
    result = culture_info_ingest.CultureInfoFetchResult(
        events=(
            culture_info_ingest.CultureInfoEvent(
                seq="1",
                title_ko="행사",
                event_type="공연",
                venue_name_ko="장소",
                area="경기도",
                sigungu="수원시",
                starts_on=None,
                ends_on=None,
                url=None,
                thumbnail_url=None,
                gps_x=None,
                gps_y=None,
            ),
        ),
        request_count=1,
        raw_count=1,
        total_count=1,
        operation="area2",
        sido="경기",
        sigungu="수원시",
    )

    payload = culture_info_ingest.upsert_culture_info_events(
        dsn="postgresql://redacted",
        result=result,
        connect_timeout=7,
    )

    assert payload["upserted_rows"] == 1
    assert "INSERT INTO ingest.source_files" in executed[1][0]
    assert "INSERT INTO culture.events" in executed[2][0]
    assert executed[-1] == ("commit", None)
