from __future__ import annotations

import json
import sys
from datetime import date
from types import SimpleNamespace

import pytest

from apps.api.app.services import kopis_ingest
from apps.api.app.tools import run_kopis_ingest


def test_kopis_ingest_plan_uses_kopis_key_without_live_call(capsys):
    exit_code = run_kopis_ingest.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["source_name"] == "kopis"
    assert payload["operation"] == "pblprfr"
    assert payload["target"] == "culture.events"
    assert payload["job_name"] == run_kopis_ingest.JOB_NAME
    assert payload["required_env"] == ["KOPIS_API_KEY"]
    assert payload["signgucode"] == "41"
    assert payload["signgucodes"] == ["41"]
    assert payload["live_api_call"] is False
    assert payload["db_mutation"] is False


def test_kopis_ingest_plan_supports_all_supported_signgucodes(capsys):
    exit_code = run_kopis_ingest.main(["--json", "--all-supported-signgucodes"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["signgucode"] == "multi"
    assert len(payload["signgucodes"]) == 17
    assert payload["signgucodes"][0] == "11"
    assert payload["signgucodes"][-1] == "50"


def test_default_kopis_date_window_is_within_public_api_limit():
    stdate, eddate = kopis_ingest.default_date_window(today=date(2026, 6, 15), days=30)

    assert stdate == "20260615"
    assert eddate == "20260715"


def test_parse_kopis_performance_maps_fields_to_culture_event():
    xml = """
    <dbs>
      <db>
        <mt20id>PF293603</mt20id>
        <prfnm>VERNON X THE 8: V8 LIVE [고양]</prfnm>
        <prfpdfrom>2026.07.11</prfpdfrom>
        <prfpdto>2026.07.12</prfpdto>
        <fcltynm>킨텍스</fcltynm>
        <poster>http://www.kopis.or.kr/upload/pfmPoster/example.gif</poster>
        <area>경기도</area>
        <genrenm>대중음악</genrenm>
        <openrun>N</openrun>
        <prfstate>공연예정</prfstate>
      </db>
    </dbs>
    """

    performances = kopis_ingest.parse_kopis_performances(xml)

    assert len(performances) == 1
    performance = performances[0]
    assert performance.event_id == "kopis-PF293603"
    assert performance.region_name_ko == "고양시"
    assert performance.starts_on and performance.starts_on.isoformat() == "2026-07-11"
    assert performance.ends_on and performance.ends_on.isoformat() == "2026-07-12"
    assert performance.poster_url == "https://www.kopis.or.kr/upload/pfmPoster/example.gif"
    assert performance.to_event_row() == {
        "event_id": "kopis-PF293603",
        "title_ko": "VERNON X THE 8: V8 LIVE [고양]",
        "title_en": None,
        "event_type": "대중음악",
        "venue_name_ko": "킨텍스",
        "venue_place_id": None,
        "region_name_ko": "고양시",
        "starts_on": "2026-07-11",
        "ends_on": "2026-07-12",
        "url": None,
        "primary_source": "kopis",
        "source_record_id": "PF293603",
    }


def test_kopis_region_inference_uses_gyeonggi_venue_name_when_title_has_no_region():
    performance = kopis_ingest.KopisPerformance(
        mt20id="PF1",
        title_ko="정기연주회",
        starts_on=None,
        ends_on=None,
        venue_name_ko="성남아트센터",
        poster_url=None,
        area="경기도",
        genre_name="클래식",
        openrun=None,
        performance_state=None,
    )

    assert performance.region_name_ko == "성남시"


def test_kopis_region_inference_supports_non_capital_province_aliases():
    performance = kopis_ingest.KopisPerformance(
        mt20id="PF2",
        title_ko="여름 바다 축제 [해운대]",
        starts_on=None,
        ends_on=None,
        venue_name_ko="부산문화회관",
        poster_url=None,
        area="부산광역시",
        genre_name="축제",
        openrun=None,
        performance_state=None,
    )

    assert performance.region_name_ko == "해운대구"


def test_fetch_kopis_performances_uses_official_rest_parameters(monkeypatch):
    class Response:
        text = """
        <dbs>
          <db>
            <mt20id>PF1</mt20id>
            <prfnm>공연 [수원]</prfnm>
            <prfpdfrom>2026.06.15</prfpdfrom>
            <prfpdto>2026.06.16</prfpdto>
            <fcltynm>경기아트센터</fcltynm>
            <area>경기도</area>
            <genrenm>연극</genrenm>
          </db>
        </dbs>
        """

        def raise_for_status(self):
            return None

    calls = []

    def get(url, params, timeout):
        calls.append({"url": url, "params": params, "timeout": timeout})
        return Response()

    monkeypatch.setitem(sys.modules, "requests", SimpleNamespace(get=get))

    result = kopis_ingest.fetch_kopis_performances(
        service_key="secret-key",
        stdate="20260615",
        eddate="20260715",
        rows=1,
        page_size=1,
    )

    assert len(calls) == 1
    assert calls[0]["url"].endswith("/pblprfr")
    assert calls[0]["params"]["service"] == "secret-key"
    assert calls[0]["params"]["stdate"] == "20260615"
    assert calls[0]["params"]["eddate"] == "20260715"
    assert calls[0]["params"]["cpage"] == "1"
    assert calls[0]["params"]["rows"] == "1"
    assert calls[0]["params"]["signgucode"] == "41"
    assert result.raw_count == 1
    assert len(result.performances) == 1
    assert result.signgucodes == ("41",)


def test_fetch_result_can_sweep_multiple_signgucodes(monkeypatch):
    def fake_fetch(**kwargs):
        signgucode = kwargs["signgucode"]
        return kopis_ingest.KopisFetchResult(
            performances=(
                kopis_ingest.KopisPerformance(
                    mt20id=f"PF{signgucode}",
                    title_ko=f"공연 [{signgucode}]",
                    starts_on=None,
                    ends_on=None,
                    venue_name_ko="공연장",
                    poster_url=None,
                    area="서울특별시" if signgucode == "11" else "부산광역시",
                    genre_name="연극",
                    openrun=None,
                    performance_state=None,
                ),
            ),
            request_count=1,
            raw_count=1,
            stdate="20260615",
            eddate="20260715",
            signgucode=signgucode,
            signgucodes=(signgucode,),
            signgucodesub=None,
            prfstate=None,
        )

    monkeypatch.setattr(kopis_ingest, "fetch_kopis_performances", fake_fetch)

    result = kopis_ingest.fetch_kopis_performances_for_signgucodes(
        service_key="kopis-secret",
        stdate="20260615",
        eddate="20260715",
        signgucodes=("서울특별시", "26"),
        rows=5,
        page_size=5,
    )

    assert result.signgucode == "multi"
    assert result.signgucodes == ("11", "26")
    assert result.request_count == 2
    assert result.raw_count == 2
    assert len(result.performances) == 2


def test_fetch_kopis_performances_rejects_windows_larger_than_31_days():
    with pytest.raises(ValueError, match="31 days or less"):
        kopis_ingest.fetch_kopis_performances(
            service_key="secret-key",
            stdate="20260615",
            eddate="20260716",
            rows=1,
            page_size=1,
        )


def test_kopis_apply_requires_guard_before_calling_api(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("KOPIS_API_KEY", "kopis-secret")
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.delenv(run_kopis_ingest.ALLOW_ENV, raising=False)

    exit_code = run_kopis_ingest.main(["--apply", "--confirm", run_kopis_ingest.CONFIRM_TEXT])

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_kopis_ingest.ALLOW_ENV in output
    assert dsn not in output
    assert password not in output
    assert "kopis-secret" not in output


def test_kopis_preview_redacts_service_key_on_execution_error(monkeypatch, capsys):
    monkeypatch.setenv("KOPIS_API_KEY", "kopis-secret")

    def fail(**kwargs):
        raise RuntimeError("bad service key kopis-secret")

    monkeypatch.setattr(run_kopis_ingest, "fetch_kopis_performances", fail)

    exit_code = run_kopis_ingest.main(["--preview"])

    output = capsys.readouterr().out
    assert exit_code == 2
    assert "[redacted]" in output
    assert "kopis-secret" not in output


def test_kopis_apply_records_succeeded_job_run(monkeypatch, capsys):
    monkeypatch.setenv("KOPIS_API_KEY", "kopis-secret")
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(run_kopis_ingest.ALLOW_ENV, "1")
    recorded_runs = []

    result = kopis_ingest.KopisFetchResult(
        performances=(),
        request_count=1,
        raw_count=0,
        stdate="20260615",
        eddate="20260715",
        signgucode="41",
        signgucodes=("41",),
        signgucodesub=None,
        prfstate=None,
    )

    monkeypatch.setattr(run_kopis_ingest, "fetch_kopis_performances", lambda **kwargs: result)
    monkeypatch.setattr(
        run_kopis_ingest,
        "upsert_kopis_performances",
        lambda **kwargs: {"upserted_rows": 0},
    )
    monkeypatch.setattr(
        run_kopis_ingest,
        "record_job_run",
        lambda **kwargs: recorded_runs.append(kwargs),
    )

    exit_code = run_kopis_ingest.main(
        ["--apply", "--confirm", run_kopis_ingest.CONFIRM_TEXT, "--json"]
    )

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["job_name"] == run_kopis_ingest.JOB_NAME
    assert len(recorded_runs) == 1
    assert recorded_runs[0]["job_name"] == run_kopis_ingest.JOB_NAME
    assert recorded_runs[0]["status"] == "succeeded"
    assert recorded_runs[0]["error_message"] is None


def test_kopis_apply_failure_records_redacted_job_run(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("KOPIS_API_KEY", "kopis-secret")
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.setenv(run_kopis_ingest.ALLOW_ENV, "1")
    recorded_runs = []

    def fail(**kwargs):
        raise RuntimeError(f"bad service key kopis-secret dsn={dsn} password={password}")

    monkeypatch.setattr(run_kopis_ingest, "fetch_kopis_performances", fail)
    monkeypatch.setattr(
        run_kopis_ingest,
        "record_job_run",
        lambda **kwargs: recorded_runs.append(kwargs),
    )

    exit_code = run_kopis_ingest.main(
        ["--apply", "--confirm", run_kopis_ingest.CONFIRM_TEXT, "--json"]
    )

    output = capsys.readouterr().out
    payload = json.loads(output)
    assert exit_code == 2
    assert "[redacted]" in payload["error"]
    assert "kopis-secret" not in output
    assert dsn not in output
    assert password not in output
    assert len(recorded_runs) == 1
    assert recorded_runs[0]["job_name"] == run_kopis_ingest.JOB_NAME
    assert recorded_runs[0]["status"] == "failed"
    assert "[redacted]" in recorded_runs[0]["error_message"]
    assert "kopis-secret" not in recorded_runs[0]["error_message"]
    assert dsn not in recorded_runs[0]["error_message"]
    assert password not in recorded_runs[0]["error_message"]


def test_upsert_kopis_performances_targets_source_files_and_culture_events(monkeypatch):
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
    result = kopis_ingest.KopisFetchResult(
        performances=(
            kopis_ingest.KopisPerformance(
                mt20id="PF1",
                title_ko="공연 [수원]",
                starts_on=None,
                ends_on=None,
                venue_name_ko="경기아트센터",
                poster_url=None,
                area="경기도",
                genre_name="연극",
                openrun=None,
                performance_state="공연예정",
            ),
        ),
        request_count=1,
        raw_count=1,
        stdate="20260615",
        eddate="20260715",
        signgucode="41",
        signgucodes=("41",),
        signgucodesub=None,
        prfstate=None,
    )

    payload = kopis_ingest.upsert_kopis_performances(
        dsn="postgresql://redacted",
        result=result,
        connect_timeout=7,
    )

    assert payload["upserted_rows"] == 1
    assert "INSERT INTO ingest.source_files" in executed[1][0]
    assert "INSERT INTO culture.events" in executed[2][0]
    assert executed[-1] == ("commit", None)
