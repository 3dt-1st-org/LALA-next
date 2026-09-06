"""P5A bounded resumable continuation tests for the Naver review collector.

Exercises the ACTUAL CLI main -> selection -> acquisition -> apply path with
injected transport/DB fakes (no network, no DB, no credentials). Covers cursor
progression, exact request bounds, scope/argument validation, quota/auth early
stop, partial-failure cursor safety, rollback/no-advanced-cursor, zero-result
honesty, and the offline no-I/O plan.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime

import pytest

from apps.api.app.services import naver_search_service as svc
from apps.api.app.services.naver_search_service import (
    AcquisitionOutcome,
    PlaceCollectionResult,
    TransientNaverPost,
)
from apps.api.app.services.region_catalog import (
    manual_region_place_names,
    manual_region_tour_api_area_code,
)
from apps.api.app.services.review_ingest_governance import (
    ReviewGovernanceError,
    ReviewIngestResult,
    ReviewIngestRunSummary,
    ReviewSourceRegistration,
)
from apps.api.app.services.review_mention_ingest import ReviewMentionPlace
from apps.api.app.tools import run_naver_review_collect as tool

NAVER_LINK = "https://blog.naver.com/post123/456"
PLACE_NAME = "테스트 미술관"


# -- fakes (mirrors test_naver_search_service.py patterns) ----------------------


class _FakeCursor:
    def __init__(self, conn: _FakeConn) -> None:
        self.conn = conn

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class _FakeConn:
    """Models the psycopg2 transaction boundary (commit vs rollback)."""

    def __init__(self) -> None:
        self.committed = False
        self.rolled_back = False

    def cursor(self) -> _FakeCursor:
        return _FakeCursor(self)

    def close(self) -> None:
        pass

    def __enter__(self):
        return self

    def __exit__(self, exc_type, *args):
        if exc_type is None:
            self.committed = True
        else:
            self.rolled_back = True
        return False


class _RecordingCursor:
    """Captures the place query + params, returns canned rows."""

    def __init__(self, rows: list[tuple] | None = None) -> None:
        self.queries: list[tuple[str, tuple]] = []
        self._rows = rows if rows is not None else []

    def execute(self, sql, params):
        self.queries.append((sql, tuple(params)))

    def fetchall(self):
        return list(self._rows)


def _registration() -> ReviewSourceRegistration:
    return ReviewSourceRegistration(
        source_name=svc.SOURCE_NAME,
        provider=svc.EXPECTED_PROVIDER,
        license_class="licensed",
        terms_version=svc.EXPECTED_TERMS_VERSION,
        collection_method="naver_search_openapi",
        retention_policy="aggregate_only_no_raw_text",
        redaction_policy="no_raw_text_no_pii",
    )


def _outcome(provider: str = "naver_blog", category: str = "ok") -> AcquisitionOutcome:
    return AcquisitionOutcome(
        provider=provider,
        category=category,  # type: ignore[arg-type]
        retryable=False,
        http_status=None,
        attempted_count=0,
    )


def _collection(
    place_id: str,
    *,
    blog: str = "ok",
    cafe: str = "ok",
    posts: int = 0,
) -> PlaceCollectionResult:
    outcomes = (
        _outcome("naver_blog", blog),
        _outcome("naver_cafe", cafe),
    )
    items = tuple(
        TransientNaverPost(
            provider="naver_blog",
            external_key=svc._opaque_external_key(
                provider="naver_blog", link=NAVER_LINK, postdate="20260801", place_id=place_id
            ),
            keyword=PLACE_NAME,
            place_id=place_id,
            region="서울",
            category="attraction",
            title="좋은 전시 해설",
            description="전시가 정말 좋았습니다",
            link=NAVER_LINK,
            postdate="20260801",
            created_at_source=datetime(2026, 8, 1, tzinfo=UTC),
            content_sha256=svc._content_sha256(
                provider="naver_blog",
                link=NAVER_LINK,
                postdate="20260801",
                place_id=place_id,
                title="좋은 전시 해설",
                description="전시가 정말 좋았습니다",
            ),
        )
        for _ in range(posts)
    )
    return PlaceCollectionResult(
        place_id=place_id,
        place_name=PLACE_NAME,
        region="서울",
        category="attraction",
        keyword=PLACE_NAME,
        outcomes=outcomes,
        posts=items,
    )


def _place(place_id: str, name_ko: str = PLACE_NAME) -> ReviewMentionPlace:
    return ReviewMentionPlace(
        place_id=place_id, name_ko=name_ko, category="attraction", region_name_ko="성동구"
    )


def _ingest_result() -> ReviewIngestResult:
    run = ReviewIngestRunSummary(
        run_key="naver_search|2026-09-06|review-ingest-governance-v1",
        source_name=svc.SOURCE_NAME,
        provider=svc.EXPECTED_PROVIDER,
        license_class="licensed",
        terms_version=svc.EXPECTED_TERMS_VERSION,
        schema_version="review-ingest-governance-v1",
        received_count=0,
        processed_count=0,
        duplicate_count=0,
        quarantined_count=0,
        failure_category="none",
        status="succeeded",
    )
    return ReviewIngestResult(run=run, accepted=(), accepted_records=(), quarantined=())


def _wire(
    monkeypatch: pytest.MonkeyPatch,
    *,
    places: list[ReviewMentionPlace],
    script: dict[str, PlaceCollectionResult],
) -> dict[str, list]:
    """Wire every external touch of the tool; returns the call ledger."""
    calls: dict[str, list] = {
        "open": [],
        "read": [],
        "acquire": [],
        "govern": [],
        "insert": [],
        "job_run": [],
        "settings": [],
    }
    monkeypatch.setattr(
        tool, "_open_connection", lambda *a, **kw: calls["open"].append(1) or _FakeConn()
    )
    monkeypatch.setattr(tool, "get_settings", lambda: calls["settings"].append(1))

    def fake_read(cur, limit, region_place_names=None, after_place_id=None, tour_api_area=None):
        calls["read"].append((limit, region_place_names, after_place_id))
        return list(places)

    monkeypatch.setattr(tool, "_read_places_on_cursor", fake_read)

    def fake_collect(**kw):
        calls["acquire"].append(kw["place_id"])
        return script[kw["place_id"]]

    monkeypatch.setattr(tool, "collect_mentions_for_place", fake_collect)
    monkeypatch.setattr(
        tool,
        "govern_review_ingest_on_cursor",
        lambda cur, **kw: calls["govern"].append(1) or _ingest_result(),
    )
    monkeypatch.setattr(
        tool,
        "insert_review_mention_aggregates_on_cursor",
        lambda cur, aggs: calls["insert"].append(1) or 0,
    )
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: calls["job_run"].append(1))
    monkeypatch.setattr(tool, "load_active_review_source", lambda *a, **kw: _registration())
    monkeypatch.setenv("DB_DSN", "host=localhost dbname=test")
    return calls


def _out(capsys) -> dict:
    return json.loads(capsys.readouterr().out)


# -- plan: offline, no I/O -------------------------------------------------------


def test_plan_describes_continuation_without_any_io(monkeypatch, capsys):
    def _boom(*a, **kw):  # pragma: no cover - sentinel
        raise AssertionError("plan mode must not touch settings/DB/providers")

    monkeypatch.setattr(tool, "get_settings", _boom)
    monkeypatch.setattr(tool, "_open_connection", _boom)
    monkeypatch.setattr(tool, "collect_mentions_for_place", _boom)

    rc = tool.main(["--json"])

    assert rc == 0
    payload = _out(capsys)
    assert payload["ok"] is True
    assert payload["db_mutation"] is False
    cont = payload["continuation"]
    assert cont["cursor_arg"] == "--after-place-id"
    assert "place_id > cursor" in cont["cursor_semantics"]
    assert "never interpolated" in cont["cursor_semantics"]
    assert cont["coverage"] == "unknown_until_governed_run"
    assert str(tool.MAX_REQUESTS_HARD_CAP) in cont["request_cap"]


# -- argument validation fails closed before settings/DB/acquisition ------------


@pytest.mark.parametrize(
    "cursor",
    ["", " ", "has space", "a" * 129, "line\nbreak", "\x00nul", "\x7fdel", "\x1bescape", "\ttab"],
)
def test_malformed_cursor_fails_closed_before_any_io(cursor, monkeypatch, capsys):
    calls = _wire(monkeypatch, places=[], script={})
    monkeypatch.delenv("DB_DSN", raising=False)

    rc = tool.main(["--preview", "--json", "--after-place-id", cursor])

    assert rc == 2
    payload = _out(capsys)
    assert payload["ok"] is False
    assert "malformed" in payload["error"]

    # The raw (possibly control-bearing) input is never echoed anywhere.
    def _values(node):
        if isinstance(node, dict):
            for v in node.values():
                yield from _values(v)
        elif isinstance(node, str):
            yield node

    assert cursor not in [v for v in _values(payload) if v]
    assert calls == {
        "open": [],
        "read": [],
        "acquire": [],
        "govern": [],
        "insert": [],
        "job_run": [],
        "settings": [],
    }


@pytest.mark.parametrize("bad", ["0", "-1", "501", "10000"])
def test_invalid_max_requests_fails_closed_before_any_io(bad, monkeypatch, capsys):
    calls = _wire(monkeypatch, places=[], script={})
    monkeypatch.delenv("DB_DSN", raising=False)

    rc = tool.main(["--preview", "--json", "--max-requests", bad])

    assert rc == 2
    payload = _out(capsys)
    assert payload["ok"] is False
    assert "--max-requests" in payload["error"]
    assert calls["open"] == [] and calls["acquire"] == [] and calls["settings"] == []


def test_unknown_region_with_cursor_fails_closed(monkeypatch, capsys):
    calls = _wire(monkeypatch, places=[], script={})

    rc = tool.main(["--preview", "--json", "--region", "seoul", "--after-place-id", "p1"])

    assert rc == 2
    payload = _out(capsys)
    assert payload["ok"] is False
    assert "cannot be mapped" in payload["error"]
    assert calls["open"] == [] and calls["acquire"] == []


# -- cursor SQL contract ---------------------------------------------------------


def test_cursor_sql_is_parameterized_keyset_inside_region_scope():
    names = manual_region_place_names("seoul-seongdong")
    cur = _RecordingCursor([("p9", PLACE_NAME, "attraction", "성동구")])

    # P5C: the scoped helper REQUIRES the proven qualifier (Seoul area code 1).
    tool._read_places_on_cursor(cur, 25, names, "p1", "1")

    sql, params = cur.queries[0]
    assert "AND region_name_ko = ANY(%s)" in sql
    assert "AND place_id > %s" in sql
    assert (
        sql.index("ANY(%s)")
        < sql.index("place_id > %s")
        < sql.index("ORDER BY place_id")
        < sql.index("LIMIT %s")
    )
    assert params == (list(names), "1", "p1", 25)


def test_cursor_sql_global_scope_without_region():
    cur = _RecordingCursor()

    tool._read_places_on_cursor(cur, 10, None, "abc")

    sql, params = cur.queries[0]
    assert "ANY" not in sql
    assert "AND place_id > %s" in sql
    assert params == ("abc", 10)


# -- end-to-end continuation through the CLI -------------------------------------


def test_preview_cursor_progression_and_counters(monkeypatch, capsys):
    places = [_place("p1"), _place("p2"), _place("p3")]
    script = {p.place_id: _collection(p.place_id, posts=1) for p in places}
    calls = _wire(monkeypatch, places=places, script=script)

    rc = tool.main(
        [
            "--preview",
            "--json",
            "--after-place-id",
            "p0",
            "--limit",
            "5",
            "--region",
            "seoul-seongdong",
        ]
    )

    assert rc == 0
    assert calls["read"] == [(5, manual_region_place_names("seoul-seongdong"), "p0")]
    payload = _out(capsys)
    assert payload["next_after_place_id"] == "p3"
    assert payload["cursor_scope"] == "seoul-seongdong"
    assert payload["places"] == 3
    assert payload["places_attempted"] == 3
    assert payload["places_completed"] == 3
    assert payload["places_deferred"] == 0
    assert payload["requests_used"] == 6
    assert payload["request_cap"] == 10  # default 2 x limit
    assert payload["exhausted"] is True
    assert payload["window_full"] is False
    assert payload["stop_reason"] is None


def test_apply_publishes_cursor_only_after_commit(monkeypatch, capsys):
    places = [_place("p1"), _place("p2")]
    script = {p.place_id: _collection(p.place_id) for p in places}
    _wire(monkeypatch, places=places, script=script)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")

    rc = tool.main(["--apply", "--json", "--confirm", tool.CONFIRM_TEXT, "--after-place-id", "p0"])

    assert rc == 0
    payload = _out(capsys)
    assert payload["ok"] is True
    assert payload["next_after_place_id"] == "p2"
    assert payload["cursor_advanced"] is True
    assert payload["requests_used"] == 4


@pytest.mark.parametrize("failing", ["govern", "insert"])
def test_apply_failure_publishes_no_advanced_cursor(failing, monkeypatch, capsys):
    places = [_place("p1"), _place("p2")]
    script = {p.place_id: _collection(p.place_id) for p in places}
    _wire(monkeypatch, places=places, script=script)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")
    if failing == "govern":

        def _raise(cur, **kw):
            raise ReviewGovernanceError("REVIEW_SOURCE_INACTIVE", "gate recheck failed")

        monkeypatch.setattr(tool, "govern_review_ingest_on_cursor", _raise)
    else:

        def _boom(cur, aggs):
            raise RuntimeError("aggregate upsert failed")

        monkeypatch.setattr(tool, "insert_review_mention_aggregates_on_cursor", _boom)

    rc = tool.main(["--apply", "--json", "--confirm", tool.CONFIRM_TEXT, "--after-place-id", "p0"])

    assert rc == 2
    payload = _out(capsys)
    assert payload["ok"] is False
    assert payload["next_after_place_id"] is None
    assert payload["cursor_advanced"] is False


def test_preflight_gate_failure_publishes_no_advanced_cursor(monkeypatch, capsys):
    places = [_place("p1")]
    script = {p.place_id: _collection(p.place_id) for p in places}
    _wire(monkeypatch, places=places, script=script)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")

    def _raise(cur, **kw):
        raise ReviewGovernanceError("REVIEW_SOURCE_INACTIVE", "gate failed")

    monkeypatch.setattr(tool, "load_active_review_source", _raise)

    rc = tool.main(["--apply", "--json", "--confirm", tool.CONFIRM_TEXT, "--after-place-id", "p0"])

    assert rc == 2
    payload = _out(capsys)
    assert payload["next_after_place_id"] is None
    assert payload["cursor_advanced"] is False
    assert payload["governance_code"] == "REVIEW_SOURCE_INACTIVE"


# -- exact request bound / no off-by-one ------------------------------------------


def test_budget_exact_boundary_defers_whole_place(monkeypatch, capsys):
    places = [_place("p1"), _place("p2"), _place("p3")]
    script = {p.place_id: _collection(p.place_id) for p in places}
    calls = _wire(monkeypatch, places=places, script=script)

    rc = tool.main(["--preview", "--json", "--max-requests", "4"])

    assert rc == 0
    assert calls["acquire"] == ["p1", "p2"]  # p3 deferred BEFORE any request
    payload = _out(capsys)
    assert payload["requests_used"] == 4
    assert payload["request_cap"] == 4
    assert payload["places_attempted"] == 2
    assert payload["places_completed"] == 2
    assert payload["places_deferred"] == 1
    assert payload["next_after_place_id"] == "p2"
    assert payload["stop_reason"] == "request_budget_exhausted"
    assert payload["exhausted"] is False


def test_odd_budget_never_splits_endpoint_pair(monkeypatch, capsys):
    places = [_place("p1"), _place("p2"), _place("p3")]
    script = {p.place_id: _collection(p.place_id) for p in places}
    calls = _wire(monkeypatch, places=places, script=script)

    rc = tool.main(["--preview", "--json", "--max-requests", "5"])

    assert rc == 0
    assert calls["acquire"] == ["p1", "p2"]
    payload = _out(capsys)
    # 2 places x 2 endpoints = 4 used; 1 remaining cannot start a whole place.
    assert payload["requests_used"] == 4
    assert payload["places_deferred"] == 1


def test_budget_counts_failed_attempts_and_never_exceeds_cap(monkeypatch, capsys):
    places = [_place("p1"), _place("p2")]
    script = {
        "p1": _collection("p1", blog="network_error", cafe="ok"),
        "p2": _collection("p2"),
    }
    calls = _wire(monkeypatch, places=places, script=script)

    rc = tool.main(["--preview", "--json", "--max-requests", "4"])

    assert rc == 0
    assert calls["acquire"] == ["p1", "p2"]
    payload = _out(capsys)
    # Failed endpoint attempts are real requests and count toward the cap.
    assert payload["requests_used"] == 4
    assert payload["requests_used"] <= payload["request_cap"]


# -- fatal (auth/quota) early stop -------------------------------------------------


@pytest.mark.parametrize("fatal", ["auth_missing", "quota_exceeded"])
def test_fatal_provider_failure_stops_instead_of_marching(fatal, monkeypatch, capsys):
    places = [_place("p1"), _place("p2"), _place("p3")]
    script = {
        "p1": _collection("p1"),
        "p2": _collection("p2", blog=fatal, cafe=fatal),
        "p3": _collection("p3"),
    }
    calls = _wire(monkeypatch, places=places, script=script)

    rc = tool.main(["--preview", "--json"])

    assert rc == 0
    # p3 was NOT attempted: no marching through remaining places after a fatal.
    assert calls["acquire"] == ["p1", "p2"]
    payload = _out(capsys)
    assert payload["places_attempted"] == 2
    assert payload["places_completed"] == 1
    assert payload["places_deferred"] == 1
    assert payload["stop_reason"] == "fatal_provider_failure"
    assert payload["status"] == "degraded"
    # p2 is partially failed -> cursor never advances past p1.
    assert payload["next_after_place_id"] == "p1"


# -- partial (non-fatal) failure cursor safety --------------------------------------


def test_partial_failure_freezes_cursor_but_processes_later_places(monkeypatch, capsys):
    places = [_place("p1"), _place("p2"), _place("p3")]
    script = {
        "p1": _collection("p1"),
        "p2": _collection("p2", blog="network_error"),
        "p3": _collection("p3"),
    }
    calls = _wire(monkeypatch, places=places, script=script)

    rc = tool.main(["--preview", "--json", "--after-place-id", "p0"])

    assert rc == 0
    assert calls["acquire"] == ["p1", "p2", "p3"]  # non-fatal: later places still run
    payload = _out(capsys)
    assert payload["places_attempted"] == 3
    assert payload["places_completed"] == 2
    assert payload["places_deferred"] == 0
    # p2 incomplete -> cursor frozen at p1 so the next run re-selects p2.
    assert payload["next_after_place_id"] == "p1"
    assert payload["status"] == "degraded"


def test_name_skipped_place_settles_without_blocking_cursor(monkeypatch, capsys):
    places = [_place("p1"), _place("p2", name_ko="X"), _place("p3")]
    script = {p.place_id: _collection(p.place_id) for p in places if p.name_ko != "X"}
    calls = _wire(monkeypatch, places=places, script=script)

    rc = tool.main(["--preview", "--json"])

    assert rc == 0
    assert calls["acquire"] == ["p1", "p3"]
    payload = _out(capsys)
    assert payload["places_name_skipped"] == 1
    assert payload["requests_used"] == 4
    assert payload["next_after_place_id"] == "p3"


# -- zero-result honesty --------------------------------------------------------------


def test_zero_selected_places_is_honest_success_not_exhaustion_error(monkeypatch, capsys):
    calls = _wire(monkeypatch, places=[], script={})

    rc = tool.main(["--preview", "--json", "--after-place-id", "p0", "--limit", "5"])

    assert rc == 0
    assert calls["acquire"] == []
    payload = _out(capsys)
    assert payload["ok"] is True
    assert payload["status"] == "succeeded"
    assert payload["places"] == 0
    assert payload["exhausted"] is True
    assert payload["window_full"] is False
    # Nothing settled -> cursor unchanged (honest, not advanced).
    assert payload["next_after_place_id"] == "p0"


def test_limit_sized_window_reports_window_full_not_exhausted(monkeypatch, capsys):
    places = [_place(f"p{i}") for i in range(1, 4)]
    script = {p.place_id: _collection(p.place_id) for p in places}
    _wire(monkeypatch, places=places, script=script)

    rc = tool.main(["--preview", "--json", "--limit", "3"])

    assert rc == 0
    payload = _out(capsys)
    assert payload["window_full"] is True
    assert payload["exhausted"] is False


# -- region + cursor scope echo through the CLI ----------------------------------------


def test_cursor_read_threading_global_scope(monkeypatch, capsys):
    places = [_place("p1")]
    script = {p.place_id: _collection(p.place_id) for p in places}
    calls = _wire(monkeypatch, places=places, script=script)

    rc = tool.main(["--preview", "--json", "--after-place-id", "p0"])

    assert rc == 0
    assert calls["read"] == [(50, None, "p0")]
    payload = _out(capsys)
    assert payload["cursor_scope"] == "global"
    assert payload["after_place_id"] == "p0"


def test_no_cursor_call_shape_unchanged(monkeypatch, capsys):
    places = [_place("p1")]
    script = {p.place_id: _collection(p.place_id) for p in places}
    calls = _wire(monkeypatch, places=places, script=script)

    rc = tool.main(["--preview", "--json"])

    assert rc == 0
    # Byte-identical pre-P5A call: (limit, region) with no cursor argument.
    assert calls["read"] == [(50, None, None)]
    payload = _out(capsys)
    assert payload["after_place_id"] is None
    assert payload["next_after_place_id"] == "p1"


# -- P5A correction regressions ----------------------------------------------------


def test_name_skip_never_leaps_over_earlier_unresolved_place(monkeypatch, capsys):
    # p1 ok, p2 network failure (cursor freezes at p1), p3 one-character name:
    # the skip settles p3 but the published cursor MUST remain p1.
    places = [_place("p1"), _place("p2"), _place("p3", name_ko="X")]
    script = {
        "p1": _collection("p1"),
        "p2": _collection("p2", blog="network_error"),
    }
    calls = _wire(monkeypatch, places=places, script=script)

    rc = tool.main(["--preview", "--json", "--after-place-id", "p0"])

    assert rc == 0
    assert calls["acquire"] == ["p1", "p2"]
    payload = _out(capsys)
    assert payload["places_name_skipped"] == 1
    assert payload["places_completed"] == 2  # p1 + deterministic skip (no double count)
    assert payload["next_after_place_id"] == "p1"
    assert payload["exhausted"] is False


def test_name_skip_after_budget_deferral_keeps_cursor(monkeypatch, capsys):
    # Budget defers p2 (freeze); a later name-skip still must not advance.
    places = [_place("p1"), _place("p2"), _place("p3", name_ko="X")]
    script = {"p1": _collection("p1")}
    calls = _wire(monkeypatch, places=places, script=script)

    rc = tool.main(["--preview", "--json", "--max-requests", "2"])

    assert rc == 0
    assert calls["acquire"] == ["p1"]
    payload = _out(capsys)
    assert payload["places_deferred"] == 1
    assert payload["places_name_skipped"] == 1
    assert payload["next_after_place_id"] == "p1"


def test_exhausted_false_with_terminal_failure_preview(monkeypatch, capsys):
    # selected(2) < limit(5), deferred 0 — but p2 failed terminally: the window
    # is NOT exhausted (an unresolved acquisition failure exists).
    places = [_place("p1"), _place("p2")]
    script = {
        "p1": _collection("p1"),
        "p2": _collection("p2", blog="network_error"),
    }
    _wire(monkeypatch, places=places, script=script)

    rc = tool.main(["--preview", "--json", "--limit", "5"])

    assert rc == 0
    payload = _out(capsys)
    assert payload["places"] == 2
    assert payload["places_deferred"] == 0
    assert payload["exhausted"] is False
    assert payload["window_full"] is False


def test_exhausted_true_only_when_every_selected_place_settled_clean(monkeypatch, capsys):
    places = [_place("p1"), _place("p2", name_ko="X"), _place("p3")]
    script = {"p1": _collection("p1"), "p3": _collection("p3")}
    _wire(monkeypatch, places=places, script=script)

    rc = tool.main(["--preview", "--json", "--limit", "5"])

    assert rc == 0
    payload = _out(capsys)
    assert payload["places"] == 3
    assert payload["places_completed"] == 3  # includes the name skip, no double count
    assert payload["exhausted"] is True


def test_apply_json_reports_honest_exhaustion_after_commit(monkeypatch, capsys):
    places = [_place("p1"), _place("p2")]
    script = {
        "p1": _collection("p1"),
        "p2": _collection("p2", cafe="parse_error"),
    }
    _wire(monkeypatch, places=places, script=script)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")

    rc = tool.main(["--apply", "--json", "--confirm", tool.CONFIRM_TEXT, "--limit", "5"])

    assert rc == 0
    payload = _out(capsys)
    assert payload["ok"] is True
    assert payload["status"] == "degraded"
    # Committed apply still reports the terminal failure honestly.
    assert payload["exhausted"] is False
    assert payload["next_after_place_id"] == "p1"


def _wire_real_acquisition(
    monkeypatch: pytest.MonkeyPatch,
    *,
    places: list[ReviewMentionPlace],
) -> list[str]:
    """Wire DB/gate/read fakes but leave the REAL collect_mentions_for_place
    (and its _fetch_items / credential boundary) installed."""
    monkeypatch.setattr(tool, "_open_connection", lambda *a, **kw: _FakeConn())
    monkeypatch.setattr(tool, "load_active_review_source", lambda *a, **kw: _registration())
    monkeypatch.setattr(
        tool,
        "_read_places_on_cursor",
        lambda cur, limit, names=None, cursor=None, area=None: list(places),
    )
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
    monkeypatch.setenv("DB_DSN", "host=localhost dbname=test")
    fetches: list[str] = []
    monkeypatch.setattr(svc, "_fetch_items", lambda *a, **kw: fetches.append(a[0]) or [])
    return fetches


def test_absent_credentials_make_zero_wire_requests(monkeypatch, capsys):
    # Real acquisition boundary, credentials absent: no HTTP request is
    # launched (fetch sentinel must never fire), yet outcomes exist — so
    # requests_used must be 0, not the number of outcome objects.
    monkeypatch.delenv("NAVER_CLIENT_ID", raising=False)
    monkeypatch.delenv("NAVER_CLIENT_SECRET", raising=False)
    fetches = _wire_real_acquisition(monkeypatch, places=[_place("p1")])

    rc = tool.main(["--preview", "--json", "--after-place-id", "p0"])

    assert rc == 0
    assert fetches == []
    payload = _out(capsys)
    assert payload["requests_used"] == 0
    assert payload["requests_reserved_per_place"] == 2
    assert payload["failure_tally"]["naver_blog"]["auth_missing"] == 1
    assert payload["status"] == "failed"
    # Fatal auth stop: second endpoint never launched -> single outcome, and
    # the cursor did not advance.
    assert payload["next_after_place_id"] == "p0"
    assert payload["stop_reason"] == "fatal_provider_failure"


@pytest.mark.parametrize("status_code", [401, 403, 429])
def test_fatal_first_endpoint_never_launches_second_and_counts_one_wire_attempt(
    status_code, monkeypatch, capsys
):
    # Post-request fatal failures (401/403/429) count as observed wire attempts
    # and stop the place at the FIRST endpoint through the real boundary.
    import io as _io
    import urllib.error

    monkeypatch.setenv("NAVER_CLIENT_ID", "test-cid")
    monkeypatch.setenv("NAVER_CLIENT_SECRET", "test-csec")
    fetches = _wire_real_acquisition(monkeypatch, places=[_place("p1"), _place("p2")])

    def fatal_fetch(endpoint, *a, **kw):
        fetches.append(endpoint)
        raise urllib.error.HTTPError("u", status_code, "denied", {}, _io.BytesIO(b""))

    monkeypatch.setattr(svc, "_fetch_items", fatal_fetch)

    rc = tool.main(["--preview", "--json", "--after-place-id", "p0"])

    assert rc == 0
    # Exactly ONE HTTP attempt: the denied blog endpoint; cafe + p2 untouched.
    assert fetches == ["blog"]
    payload = _out(capsys)
    assert payload["requests_used"] == 1
    assert "naver_cafe" not in payload["failure_tally"]
    assert payload["places_attempted"] == 1
    assert payload["places_deferred"] == 1
    assert payload["stop_reason"] == "fatal_provider_failure"
    assert payload["next_after_place_id"] == "p0"
    assert payload["exhausted"] is False


def test_wire_attempts_count_post_request_network_and_parse_failures(monkeypatch, capsys):
    # HTTP 500 (network_error after a request) and JSON parse garbage both
    # occur after a real request and must count toward requests_used.
    import io as _io
    import json as _json
    import urllib.error

    monkeypatch.setenv("NAVER_CLIENT_ID", "test-cid")
    monkeypatch.setenv("NAVER_CLIENT_SECRET", "test-csec")
    fetches = _wire_real_acquisition(monkeypatch, places=[_place("p1")])

    def flaky_fetch(endpoint, *a, **kw):
        fetches.append(endpoint)
        if endpoint == "blog":
            raise urllib.error.HTTPError("u", 500, "boom", {}, _io.BytesIO(b""))
        return _json.loads("not-json")

    monkeypatch.setattr(svc, "_fetch_items", flaky_fetch)

    rc = tool.main(["--preview", "--json"])

    assert rc == 0
    assert fetches == ["blog", "cafearticle"]
    payload = _out(capsys)
    assert payload["requests_used"] == 2
    assert payload["failure_tally"]["naver_blog"]["network_error"] == 1
    assert payload["failure_tally"]["naver_cafe"]["parse_error"] == 1


# == P5B (corrected): offline schedule/export modes =================================


def _no_io_wiring(monkeypatch):
    def _boom(*a, **kw):  # pragma: no cover - sentinel
        raise AssertionError("offline modes must not touch settings/DB/providers")

    monkeypatch.setattr(tool, "get_settings", _boom)
    monkeypatch.setattr(tool, "_open_connection", _boom)
    monkeypatch.setattr(tool, "collect_mentions_for_place", _boom)


def _write_snapshot(path, entries):
    import json as _json

    path.write_text(
        _json.dumps(
            {
                "schema_version": 1,
                "source": "naver_review_collect_apply_payloads",
                "scope_contract": "tour_api_province_qualified_v1",
                "entries": entries,
            }
        )
    )


def _entry(
    region,
    *,
    cursor=None,
    input_cursor=None,
    exhausted=False,
    blocked=None,
    empty_scope=None,
    hours_ago=1,
    stop=None,
    whole_region_complete=False,
    requests_used=4,
):
    from datetime import UTC as _UTC
    from datetime import datetime as _dt
    from datetime import timedelta as _td

    observed = (_dt.now(_UTC) - _td(hours=hours_ago)).isoformat()
    return {
        "region": region,
        "next_after_place_id": cursor,
        "input_after_place_id": input_cursor,
        "exhausted": exhausted,
        "whole_region_complete": whole_region_complete,
        "empty_scope": empty_scope,
        "stop_reason": stop,
        "blocked": blocked,
        "requests_used": requests_used,
        "observation_time": observed,
        "qualified_scope": True,
    }


# --- B1: mode guards and option hygiene -------------------------------------------


def test_b1_schedule_only_options_rejected_without_schedule(monkeypatch, capsys):
    _no_io_wiring(monkeypatch)
    for argv in (
        ["--regions", "seoul-seongdong"],
        ["--checkpoint-snapshot", "cp.json"],
        ["--max-regions", "2"],
        ["--refresh-interval-hours", "24"],
        ["--per-region-requests", "4"],
        ["--total-request-ceiling", "8"],
        ["--preview", "--json", "--regions", "seoul-seongdong"],
        ["--apply", "--json", "--max-regions", "2"],
    ):
        rc = tool.main([*argv, "--json"] if "--json" not in argv else argv)
        assert rc == 2, argv
        assert "schedule-only" in _out(capsys)["error"]


def test_b1_schedule_rejects_singular_scope_and_cursor(monkeypatch, capsys):
    _no_io_wiring(monkeypatch)
    for argv in (
        ["--schedule", "--region", "seoul-seongdong"],
        ["--schedule", "--after-place-id", "p1"],
    ):
        rc = tool.main([*argv, "--json"])
        assert rc == 2, argv
        assert "must not" in _out(capsys)["error"]


def test_b1_modes_mutually_exclusive(monkeypatch, capsys):
    _no_io_wiring(monkeypatch)
    rc = tool.main(["--schedule", "--export-checkpoint", "--json"])
    assert rc == 2
    rc = tool.main(["--preview", "--export-checkpoint", "--json"])
    assert rc == 2


def test_b1_plain_plan_validates_cursor_cap_and_region(monkeypatch, capsys):
    # Zero-I/O plan still rejects invalid options (P5A guards restored for plan).
    _no_io_wiring(monkeypatch)
    assert tool.main(["--json", "--after-place-id", "\x00bad"]) == 2
    capsys.readouterr()
    assert tool.main(["--json", "--max-requests", "501"]) == 2
    capsys.readouterr()
    assert tool.main(["--json", "--limit", "0"]) == 2
    capsys.readouterr()
    rc = tool.main(["--json", "--region", "seoul"])
    assert rc == 2
    assert "cannot be mapped" in _out(capsys)["error"]
    # A fully valid plain plan still works and stays offline.
    assert tool.main(["--json", "--region", "seoul-seongdong"]) == 0
    assert _out(capsys)["mode"] == "plan"


def test_b1_export_rejects_incompatible_options(monkeypatch, capsys):
    _no_io_wiring(monkeypatch)
    for argv in (
        ["--region", "seoul-seongdong"],
        ["--after-place-id", "p1"],
        ["--limit", "5"],
        ["--max-requests", "4"],
        ["--display", "3"],
        ["--confirm", "APPLY_NAVER_REVIEW_COLLECT"],
    ):
        rc = tool.main(["--export-checkpoint", "--json", *argv])
        assert rc == 2, argv
        assert "rejected" in _out(capsys)["error"]
    assert tool.main(["--export-checkpoint", "--json"]) == 2  # missing input


# --- B3: bounded strict snapshot I/O ------------------------------------------------


def test_b3_bounded_read_rejects_oversize_without_loading(monkeypatch, capsys, tmp_path):
    _no_io_wiring(monkeypatch)
    big = tmp_path / "big.json"
    big.write_bytes(b"x" * (1024 * 1024 + 1))
    rc = tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(big)])
    assert rc == 2
    assert "bounded size" in _out(capsys)["error"]


@pytest.mark.parametrize(
    "raw",
    [
        b"\xff\xfe not utf8",
        b'{"schema_version": 1, "source": "naver_review_collect_apply_payloads", "entries": [1,2]}',
        b'{"schema_version": 2, "source": "naver_review_collect_apply_payloads", "entries": []}',
        b'{"schema_version": 1, "source": "other", "entries": []}',
        b'{"schema_version": 1, "source": "naver_review_collect_apply_payloads", "entries": [], "extra": 1}',
        b'["not", "an", "object"]',
    ],
)
def test_b3_malformed_snapshots_fail_sanitized(raw, monkeypatch, capsys, tmp_path):
    _no_io_wiring(monkeypatch)
    bad = tmp_path / "bad.json"
    bad.write_bytes(raw)
    rc = tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(bad)])
    assert rc == 2
    payload = _out(capsys)
    assert payload["ok"] is False
    assert payload["error"].startswith("checkpoint")
    assert "Traceback" not in payload["error"]


def test_b3_bool_as_integer_and_bad_enums_rejected(monkeypatch, capsys, tmp_path):
    import json as _json

    _no_io_wiring(monkeypatch)
    base = {"schema_version": 1, "source": "naver_review_collect_apply_payloads", "entries": []}

    def _with(entry):
        doc = {**base, "entries": [entry]}
        path = tmp_path / "e.json"
        path.write_text(_json.dumps(doc))
        return path

    good = _entry("busan-haeundae")
    assert tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(_with(good))]) == 0
    for mutate in (
        lambda e: {**e, "exhausted": 1},
        lambda e: {**e, "whole_region_complete": 1},
        lambda e: {**e, "requests_used": True},
        lambda e: {**e, "stop_reason": ["not", "a", "string"]},
        lambda e: {**e, "empty_scope": "galaxy"},
        lambda e: {**e, "observation_time": "not-a-time"},
        lambda e: {**e, "observation_time": "2026-09-06T00:00:00"},  # naive
    ):
        rc = tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(_with(mutate(good)))])
        assert rc == 2, mutate


def test_b3_supports_whole_catalog_snapshot(monkeypatch, capsys, tmp_path):
    from apps.api.app.services import collector_checkpoint as cc

    _no_io_wiring(monkeypatch)
    entries = [
        _entry(region, exhausted=True, whole_region_complete=True, input_cursor=None, hours_ago=2)
        for region in cc.canonical_region_ids()
    ]
    snapshot = tmp_path / "all.json"
    _write_snapshot(snapshot, entries)
    rc = tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(snapshot)])
    assert rc == 0
    payload = _out(capsys)
    assert payload["regions_total"] == len(cc.canonical_region_ids())
    # P5C: the province-qualified predicate unblocks alias-colliding regions;
    # they are counted as qualified (scheduled as RECENT evidence allows).
    assert payload["regions_scope_blocked"] == 0
    assert payload["regions_alias_qualified"] == len(cc.region_alias_collisions())
    assert payload["scope_contract"] == "tour_api_province_qualified_v1"


def test_b3_independent_upper_limits(monkeypatch, capsys):
    _no_io_wiring(monkeypatch)
    assert tool.main(["--schedule", "--json", "--max-regions", "65"]) == 2
    assert tool.main(["--schedule", "--json", "--total-request-ceiling", "10001"]) == 2
    assert tool.main(["--schedule", "--json", "--refresh-interval-hours", "8761"]) == 2


# --- B2: global auth/quota stop over ALL loaded evidence ----------------------------


def test_b2_blocked_entry_outside_requested_subset_stops_everything(monkeypatch, capsys, tmp_path):
    _no_io_wiring(monkeypatch)
    snapshot = tmp_path / "cp.json"
    _write_snapshot(
        snapshot,
        [
            _entry("daegu-jung", blocked="auth_quota", stop="fatal_provider_failure"),
            _entry("busan-haeundae", cursor="p9"),
        ],
    )
    # Requested subset excludes the blocked region entirely.
    rc = tool.main(
        [
            "--schedule",
            "--json",
            "--checkpoint-snapshot",
            str(snapshot),
            "--regions",
            "seoul-seongdong,incheon-yeonsu",
        ]
    )
    assert rc == 0
    payload = _out(capsys)
    assert payload["auth_quota_blocked"] is True
    assert payload["requires_reset_decision"] is True
    assert payload["planned_argv"] == []
    assert payload["planned_arguments"] == []


def test_b2_block_never_expires_by_age_or_filter(monkeypatch, capsys, tmp_path):
    from datetime import UTC as _UTC
    from datetime import datetime as _dt

    _no_io_wiring(monkeypatch)
    frozen = _dt(2026, 9, 6, 12, 0, tzinfo=_UTC)
    monkeypatch.setattr(tool, "_now_utc", lambda: frozen)
    snapshot = tmp_path / "cp.json"
    _write_snapshot(snapshot, [_entry("busan-haeundae", blocked="auth_quota", hours_ago=500)])
    rc = tool.main(
        [
            "--schedule",
            "--json",
            "--checkpoint-snapshot",
            str(snapshot),
            "--regions",
            "seoul-seongdong",
        ]
    )
    assert rc == 0
    payload = _out(capsys)
    assert payload["auth_quota_blocked"] is True
    assert payload["planned_argv"] == []


# --- B4: evidence truth --------------------------------------------------------------


def _apply_result(**overrides):
    """REAL committed apply result shape (P5A counters + committed flag)."""
    base = {
        "ok": True,
        "status": "succeeded",
        "mode": "apply",
        "committed": True,
        "region": "busan-haeundae",
        "region_applied": True,
        "cursor_scope": "busan-haeundae",
        "after_place_id": None,
        "next_after_place_id": "place-2",
        "exhausted": True,
        "places": 2,
        "places_attempted": 2,
        "places_completed": 2,
        "places_deferred": 0,
        "places_name_skipped": 0,
        "requests_used": 4,
        "stop_reason": None,
        "failure_tally": {},
        "observation_time": "2026-09-06T11:00:00+00:00",
        "scope_contract": "tour_api_province_qualified_v1",
    }
    return {**base, **overrides}


def test_b4_bridge_rejects_preview_failed_and_mismatched_results():
    from apps.api.app.services import collector_checkpoint as cc

    for bad in (
        _apply_result(mode="preview"),
        _apply_result(ok=False),
        _apply_result(status="failed"),
        _apply_result(region_applied=False),
        _apply_result(cursor_scope="global"),
        _apply_result(region="not-a-region"),
        {**_apply_result(), "observation_time": None},
        _apply_result(exhausted=True, stop_reason="request_budget_exhausted"),
        _apply_result(requests_used="many"),
    ):
        with pytest.raises(cc.CheckpointSnapshotError):
            cc.build_region_checkpoint(bad)


def test_b4_single_page_null_cursor_sweep_certifies_whole_region():
    from apps.api.app.services import collector_checkpoint as cc

    entry = cc.build_region_checkpoint(_apply_result(after_place_id=None, exhausted=True))
    assert entry["whole_region_complete"] is True
    assert entry["empty_scope"] is None


def test_b4_arbitrary_tail_exhausted_is_not_whole_region():
    from apps.api.app.services import collector_checkpoint as cc

    entry = cc.build_region_checkpoint(_apply_result(after_place_id="place-1", exhausted=True))
    assert entry["whole_region_complete"] is False


def test_b4_zero_result_vs_tail_empty_scope(monkeypatch, capsys, tmp_path):
    from datetime import UTC as _UTC
    from datetime import datetime as _dt

    from apps.api.app.services import collector_checkpoint as cc

    _no_io_wiring(monkeypatch)
    frozen = _dt(2026, 9, 6, 12, 0, tzinfo=_UTC)
    monkeypatch.setattr(tool, "_now_utc", lambda: frozen)

    zero_region = cc.build_region_checkpoint(
        _apply_result(
            places=0,
            places_attempted=0,
            places_completed=0,
            places_deferred=0,
            exhausted=True,
            next_after_place_id=None,
        )
    )
    assert zero_region["empty_scope"] == "region"
    tail_empty = cc.build_region_checkpoint(
        _apply_result(
            places=0,
            places_attempted=0,
            places_completed=0,
            places_deferred=0,
            exhausted=True,
            next_after_place_id="p9",
            after_place_id="p1",
        )
    )
    assert tail_empty["empty_scope"] == "window"

    snapshot = tmp_path / "cp.json"
    _write_snapshot(snapshot, [zero_region, tail_empty])

    zero_region_result = cc.build_region_checkpoint(
        _apply_result(
            region="seoul-seongdong",
            cursor_scope="seoul-seongdong",
            places=0,
            places_attempted=0,
            places_completed=0,
            places_deferred=0,
            exhausted=True,
            next_after_place_id=None,
        )
    )
    tail_region = cc.build_region_checkpoint(
        _apply_result(
            region="incheon-yeonsu",
            cursor_scope="incheon-yeonsu",
            places=0,
            places_attempted=0,
            places_completed=0,
            places_deferred=0,
            exhausted=True,
            next_after_place_id="p9",
            after_place_id="p1",
        )
    )
    _write_snapshot(snapshot, [zero_region_result, tail_region])
    rc = tool.main(
        [
            "--schedule",
            "--json",
            "--checkpoint-snapshot",
            str(snapshot),
            "--regions",
            "seoul-seongdong,incheon-yeonsu",
        ]
    )
    assert rc == 0
    payload = _out(capsys)
    # Whole-region empty sweep is fresh; a tail-empty window is unknown
    # completion and conservatively restarts from the beginning.
    assert payload["region_states"]["seoul-seongdong"] == "EMPTY_OBSERVED"
    assert payload["statuses"]["seoul-seongdong"] == "EMPTY_OBSERVED"
    assert payload["region_states"]["incheon-yeonsu"] == "UNKNOWN_COMPLETION"
    planned = {p["region"]: p for p in payload["planned_arguments"]}
    assert planned["incheon-yeonsu"]["after_place_id"] is None


def test_b4_export_preserves_result_time_and_rejects_legacy(monkeypatch, capsys, tmp_path):
    import json as _json

    _no_io_wiring(monkeypatch)
    result_file = tmp_path / "result.json"
    result_file.write_text(_json.dumps(_apply_result()))
    rc = tool.main(["--export-checkpoint", "--json", "--from-collector-result", str(result_file)])
    assert rc == 0
    snapshot = _json.loads(capsys.readouterr().out)
    entry = snapshot["entries"][0]
    assert entry["observation_time"] == "2026-09-06T11:00:00+00:00"  # preserved, not re-stamped

    legacy = tmp_path / "legacy.json"
    payload = _apply_result()
    del payload["observation_time"]
    legacy.write_text(_json.dumps(payload))
    rc = tool.main(["--export-checkpoint", "--json", "--from-collector-result", str(legacy)])
    assert rc == 2
    assert _out(capsys)["error"].startswith("result ")  # specific bridge reason


# --- B5: real CLI round-trip with argv arrays -----------------------------------------


def test_b5_round_trip_export_then_schedule_argv(monkeypatch, capsys, tmp_path):
    import json as _json
    from datetime import UTC as _UTC
    from datetime import datetime as _dt

    # 1) Real mocked committed apply result (P5A fakes) — partial window.
    places = [_place("p1"), _place("p2")]
    script = {p.place_id: _collection(p.place_id) for p in places}
    _wire(monkeypatch, places=places, script=script)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")
    frozen = _dt(2026, 9, 6, 12, 0, tzinfo=_UTC)
    monkeypatch.setattr(tool, "_now_utc", lambda: frozen)
    rc = tool.main(
        [
            "--apply",
            "--json",
            "--confirm",
            tool.CONFIRM_TEXT,
            "--region",
            "busan-haeundae",
            "--after-place-id",
            "p0",
            "--limit",
            "2",
        ]
    )
    assert rc == 0
    apply_payload = _out(capsys)
    assert "observation_time" in apply_payload

    # 2) OFFLINE export main(): result file -> validated snapshot on stdout.
    _no_io_wiring(monkeypatch)
    result_file = tmp_path / "result.json"
    result_file.write_text(_json.dumps(apply_payload))
    rc = tool.main(["--export-checkpoint", "--json", "--from-collector-result", str(result_file)])
    assert rc == 0
    snapshot_doc = _json.loads(capsys.readouterr().out)

    # 3) SCHEDULE main(): snapshot -> planned argv arrays.
    monkeypatch.setattr(tool, "_now_utc", lambda: frozen)
    snapshot_file = tmp_path / "cp.json"
    snapshot_file.write_text(_json.dumps(snapshot_doc))
    rc = tool.main(
        [
            "--schedule",
            "--json",
            "--checkpoint-snapshot",
            str(snapshot_file),
            "--regions",
            "busan-haeundae,seoul-seongdong",
        ]
    )
    assert rc == 0
    payload = _out(capsys)
    argv_arrays = payload["planned_argv"]
    assert argv_arrays and all(isinstance(a, list) for a in argv_arrays)
    assert all(isinstance(item, str) for a in argv_arrays for item in a)
    busan_argv = next(a for a in argv_arrays if "--region=busan-haeundae" in a)
    assert f"--after-place-id={apply_payload['next_after_place_id']}" in busan_argv
    assert "--limit=50" in busan_argv
    # No shell strings, credentials or confirm tokens anywhere.
    joined = _json.dumps(argv_arrays)
    for forbidden in (";", "&&", tool.CONFIRM_TEXT, "NAVER_CLIENT"):
        assert forbidden not in joined
    # 4) The argv is parseable by the real collector main (fixed two-step parse
    #    simulation): every element is an exact equals-form option.
    for element in busan_argv:
        assert element.startswith("--") and "=" in element


def test_b5_argv_encoding_is_dash_safe(monkeypatch, capsys, tmp_path):

    _no_io_wiring(monkeypatch)
    # A legally odd cursor beginning with '-' stays an unambiguous value.
    snapshot = tmp_path / "cp.json"
    _write_snapshot(
        snapshot,
        [
            _entry("busan-haeundae", cursor="-weird-cursor", input_cursor="-older"),
        ],
    )
    rc = tool.main(
        [
            "--schedule",
            "--json",
            "--checkpoint-snapshot",
            str(snapshot),
            "--regions",
            "busan-haeundae",
        ]
    )
    assert rc == 0
    payload = _out(capsys)
    argv = payload["planned_argv"][0]
    assert "--after-place-id=-weird-cursor" in argv
    # Simulate real argv parsing with faked boundaries: argparse reads
    # equals-form values verbatim, so the dash-leading cursor is a value.
    _wire(monkeypatch, places=[], script={})
    parsed = tool.main([*argv, "--preview", "--json"])
    assert parsed == 0


# == P5B final residual corrections (R1/R2/S1-S3 + committed fatal stop) ============


def test_r1_from_collector_result_requires_export(monkeypatch, capsys):
    _no_io_wiring(monkeypatch)
    rc = tool.main(["--json", "--from-collector-result", "result.json"])
    assert rc == 2
    payload = _out(capsys)
    assert "requires --export-checkpoint" in payload["error"]
    # Explicitly empty value is still "supplied" and rejected the same way.
    rc = tool.main(["--json", "--from-collector-result", ""])
    assert rc == 2


def test_r1_export_rejects_explicitly_empty_confirm(monkeypatch, capsys):
    _no_io_wiring(monkeypatch)
    rc = tool.main(
        ["--export-checkpoint", "--json", "--from-collector-result", "r.json", "--confirm", ""]
    )
    assert rc == 2
    assert "rejected" in _out(capsys)["error"]


def test_r2_schema_version_bool_is_rejected(monkeypatch, capsys, tmp_path):
    import json as _json

    _no_io_wiring(monkeypatch)
    doc = tmp_path / "boolver.json"
    doc.write_text(_json.dumps({"schema_version": True, "source": "x", "entries": []}))
    rc = tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(doc)])
    assert rc == 2
    assert "version/source mismatch" in _out(capsys)["error"]


def test_s1_zero_completed_with_network_failure_never_certifies_fresh():
    from apps.api.app.services import collector_checkpoint as cc

    # Committed degraded run: 2 places, 0 completed, network failures only.
    entry = cc.build_region_checkpoint(
        _apply_result(
            status="degraded",
            exhausted=False,
            places=2,
            places_attempted=2,
            places_completed=0,
            failure_tally={"naver_blog": {"network_error": 2}},
        )
    )
    assert entry["whole_region_complete"] is False
    assert entry["empty_scope"] is None
    # Even an "exhausted" clean-shaped window with network failures stays unproven.
    entry2 = cc.build_region_checkpoint(
        _apply_result(
            status="degraded",
            exhausted=True,
            places=2,
            places_attempted=2,
            places_completed=2,
            failure_tally={"naver_blog": {"network_error": 1}},
        )
    )
    assert entry2["whole_region_complete"] is False


def test_s1_legitimate_empty_and_partial_prefixes_preserved():
    from apps.api.app.services import collector_checkpoint as cc

    empty = cc.build_region_checkpoint(
        _apply_result(
            places=0,
            places_attempted=0,
            places_completed=0,
            exhausted=True,
            next_after_place_id=None,
        )
    )
    assert empty["whole_region_complete"] is True
    assert empty["empty_scope"] == "region"
    partial = cc.build_region_checkpoint(
        _apply_result(
            exhausted=False,
            places=3,
            places_attempted=2,
            places_completed=2,
            places_deferred=1,
            stop_reason="request_budget_exhausted",
            next_after_place_id="p2",
        )
    )
    assert partial["whole_region_complete"] is False
    assert partial["next_after_place_id"] == "p2"


@pytest.mark.parametrize("bad_time", ["0001-01-01T00:00:00+14:00", "9999-12-31T23:59:59-14:00"])
def test_s2_timestamp_overflow_is_sanitized_everywhere(bad_time, monkeypatch, capsys, tmp_path):
    import json as _json

    _no_io_wiring(monkeypatch)
    # Export path: overflow inside the result bridge.
    result = tmp_path / "r.json"
    result.write_text(_json.dumps(_apply_result(observation_time=bad_time)))
    rc = tool.main(["--export-checkpoint", "--json", "--from-collector-result", str(result)])
    assert rc == 2
    assert _out(capsys)["error"].startswith("result ")  # specific bridge reason

    # Loader path: overflow inside snapshot entry parsing.
    entry = _entry("busan-haeundae")
    entry["observation_time"] = bad_time
    snap = tmp_path / "cp.json"
    _write_snapshot(snap, [entry])
    rc = tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(snap)])
    assert rc == 2
    err = _out(capsys)["error"]
    assert err.startswith("checkpoint")
    assert bad_time not in err  # no raw input echo


def test_s3_full_catalog_state_fits_bounded_ceiling(monkeypatch, capsys, tmp_path):
    import json as _json

    from apps.api.app.services import collector_checkpoint as cc

    _no_io_wiring(monkeypatch)
    cursor = "-" + "가" * 63 + "x" * 64  # 128 printable non-ASCII dash-leading cursor
    entries = [
        _entry(
            region,
            cursor=cursor,
            input_cursor=cursor,
            exhausted=False,
            requests_used=4,
            hours_ago=1,
        )
        for region in cc.canonical_region_ids()
    ]
    # Serialize with the exporter's actual formatting (indent=2, sort_keys).
    doc = {
        "schema_version": 1,
        "source": "naver_review_collect_apply_payloads",
        "entries": entries,
    }
    blob = _json.dumps(doc, ensure_ascii=False, indent=2, sort_keys=True)
    assert len(blob.encode("utf-8")) <= cc.SNAPSHOT_MAX_BYTES
    snap = tmp_path / "all.json"
    snap.write_text(blob, encoding="utf-8")
    rc = tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(snap)])
    assert rc == 0
    payload = _out(capsys)
    assert payload["regions_total"] == len(cc.canonical_region_ids())
    # P5C: alias-colliding resume candidates are qualified and scheduled now.
    assert payload["regions_scope_blocked"] == 0
    assert payload["regions_alias_qualified"] == len(cc.region_alias_collisions())


def test_committed_auth_quota_failure_round_trip_blocks_other_regions(
    monkeypatch, capsys, tmp_path
):
    import io as _io
    import json as _json
    import urllib.error
    from datetime import UTC as _UTC
    from datetime import datetime as _dt

    # REAL apply path with faked wire boundary: FIRST provider endpoint
    # quota-fails; no second endpoint, no later place.
    places = [_place("p1"), _place("p2")]
    script = {p.place_id: _collection(p.place_id) for p in places}
    _wire(monkeypatch, places=places, script=script)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")
    monkeypatch.setenv("NAVER_CLIENT_ID", "test-cid")
    monkeypatch.setenv("NAVER_CLIENT_SECRET", "test-csec")

    def fatal_fetch(endpoint, *a, **kw):
        raise urllib.error.HTTPError("u", 429, "Too Many", {}, _io.BytesIO(b""))

    from apps.api.app.services import naver_search_service as svc

    monkeypatch.setattr(svc, "_fetch_items", fatal_fetch)
    # Use the REAL acquisition path (fake credentials + fake wire boundary stay
    # installed for the entire test, including this first-request failure).
    monkeypatch.setattr(tool, "collect_mentions_for_place", svc.collect_mentions_for_place)
    frozen = _dt(2026, 9, 6, 12, 0, tzinfo=_UTC)
    monkeypatch.setattr(tool, "_now_utc", lambda: frozen)

    rc = tool.main(
        [
            "--apply",
            "--json",
            "--confirm",
            tool.CONFIRM_TEXT,
            "--region",
            "busan-haeundae",
            "--after-place-id",
            "p0",
        ]
    )
    assert rc == 0
    failed_payload = _out(capsys)
    # Committed empty bookkeeping, but the run failed on the first request.
    assert failed_payload["ok"] is False
    assert failed_payload["status"] == "failed"
    assert failed_payload["committed"] is True
    assert failed_payload["requests_used"] == 1
    assert failed_payload["places_attempted"] == 1
    assert failed_payload["places_deferred"] == 1

    # OFFLINE export: the committed fatal failure becomes a BLOCKED observation.
    _no_io_wiring(monkeypatch)
    result = tmp_path / "r.json"
    result.write_text(_json.dumps(failed_payload))
    rc = tool.main(["--export-checkpoint", "--json", "--from-collector-result", str(result)])
    assert rc == 0
    snapshot_doc = _json.loads(capsys.readouterr().out)
    entry = snapshot_doc["entries"][0]
    assert entry["blocked"] == "auth_quota"
    assert entry["whole_region_complete"] is False
    assert entry["next_after_place_id"] == "p0"  # unchanged cursor, no credit

    # Scheduling ANOTHER region => global block, zero argv.
    snap = tmp_path / "cp.json"
    snap.write_text(_json.dumps(snapshot_doc))
    rc = tool.main(
        [
            "--schedule",
            "--json",
            "--checkpoint-snapshot",
            str(snap),
            "--regions",
            "seoul-seongdong,incheon-yeonsu",
        ]
    )
    assert rc == 0
    payload = _out(capsys)
    assert payload["auth_quota_blocked"] is True
    assert payload["planned_argv"] == []
    assert payload["planned_arguments"] == []


def test_rollback_control_never_exports(monkeypatch, capsys, tmp_path):
    import json as _json

    # Rollback inside the write transaction => committed False => export rejects.
    places = [_place("p1")]
    script = {p.place_id: _collection(p.place_id) for p in places}
    _wire(monkeypatch, places=places, script=script)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")

    def _boom(cur, aggs):
        raise RuntimeError("aggregate upsert failed")

    monkeypatch.setattr(tool, "insert_review_mention_aggregates_on_cursor", _boom)
    rc = tool.main(
        ["--apply", "--json", "--confirm", tool.CONFIRM_TEXT, "--region", "busan-haeundae"]
    )
    assert rc == 2
    rolled = _out(capsys)
    assert rolled["committed"] is False

    _no_io_wiring(monkeypatch)
    result = tmp_path / "r.json"
    result.write_text(_json.dumps(rolled))
    rc = tool.main(["--export-checkpoint", "--json", "--from-collector-result", str(result)])
    assert rc == 2
    assert _out(capsys)["error"].startswith("result ")  # specific bridge reason


def test_audit_unsettled_places_never_certify_freshness():
    from apps.api.app.services import collector_checkpoint as cc

    # Real-shaped otherwise-valid payload: 2 places, 2 attempted, 0 completed,
    # nothing deferred, exhausted=True with a clean tally — internally the
    # consistency identity holds (2 == 2+0+0), but settled != selected, so the
    # region is NOT whole-region complete.
    entry = cc.build_region_checkpoint(
        _apply_result(
            status="degraded",
            exhausted=True,
            places=2,
            places_attempted=2,
            places_completed=0,
            places_deferred=0,
            failure_tally={},  # clean acquisition tally, yet nothing settled
        )
    )
    assert entry["whole_region_complete"] is False
    assert entry["empty_scope"] is None


def test_audit_degraded_by_quarantine_never_certifies_freshness():
    from apps.api.app.services import collector_checkpoint as cc

    # status=degraded caused by governance quarantine keeps a clean acquisition
    # tally; whole-region freshness must still be denied.
    entry = cc.build_region_checkpoint(
        _apply_result(
            status="degraded",
            exhausted=True,
            quarantined=3,
        )
    )
    assert entry["whole_region_complete"] is False


def test_audit_valid_all_name_skipped_sweep_certifies_freshness():
    from apps.api.app.services import collector_checkpoint as cc

    # Deterministic all-skip window: attempted 0, completed == places via
    # name-skips, succeeded + exhausted + null cursor → legitimately fresh.
    entry = cc.build_region_checkpoint(
        _apply_result(
            places=2,
            places_attempted=0,
            places_completed=2,
            places_deferred=0,
            places_name_skipped=2,
            requests_used=0,
            exhausted=True,
            next_after_place_id=None,
        )
    )
    assert entry["whole_region_complete"] is True


# == P5C: province-qualified region predicate =======================================


def test_p5c_qualified_sql_predicate_parameterized_before_limit():
    names = manual_region_place_names("daegu-jung")
    cur = _RecordingCursor([("p9", PLACE_NAME, "attraction", "중구")])

    tool._read_places_on_cursor(cur, 25, names, "p1", "4")

    sql, params = cur.queries[0]
    # Same district (중구) in multiple provinces resolves to DISTINCT proven
    # TourAPI area codes: daegu 4 (not kopis 27, not seoul 1).
    assert manual_region_tour_api_area_code("seoul-jung") == "1"
    assert manual_region_tour_api_area_code("daegu-jung") == "4"
    assert manual_region_tour_api_area_code("busan-jung") == "6"
    assert "region_name_ko = ANY(%s)" in sql
    assert "province_code = %s" in sql
    assert "primary_source = 'tour_api'" in sql
    assert "place_id > %s" in sql
    assert (
        sql.index("ANY(%s)")
        < sql.index("province_code = %s")
        < sql.index("place_id > %s")
        < sql.index("ORDER BY place_id")
        < sql.index("LIMIT %s")
    )
    assert params == (list(names), "4", "p1", 25)


def test_p5c_area_code_none_fails_closed_for_region_scope():
    names = manual_region_place_names("seoul-seongdong")
    cur = _RecordingCursor()
    with pytest.raises(ValueError, match="proven TourAPI province area code"):
        tool._read_places_on_cursor(cur, 25, names, None, None)
    assert cur.queries == []  # nothing executed

    cur2 = _RecordingCursor()
    tool._read_places_on_cursor(cur2, 25, None, None, None)
    sql2, params2 = cur2.queries[0]
    # Global mode stays byte-identical: no region/province/source/cursor parts.
    assert "ANY" not in sql2 and "province_code" not in sql2 and "place_id >" not in sql2
    assert "ORDER BY place_id" in sql2 and "LIMIT %s" in sql2
    assert params2 == (25,)


def test_p5c_helper_fail_closed_and_provenance():
    from apps.api.app.services.region_catalog import (
        _KOPIS_SIGNGUCODES,
        _TOUR_API_AREA_CODES,
        manual_region_scope,
    )

    assert manual_region_tour_api_area_code("not-a-region") is None
    assert manual_region_tour_api_area_code(None) is None
    scope = manual_region_scope("daegu-jung")
    assert scope is not None
    # TourAPI areacode namespace (4): a KOPIS signgucode value never appears,
    # and the code is exactly one of the catalog's TourAPI province codes.
    tour_code = manual_region_tour_api_area_code("daegu-jung")
    assert tour_code == "4"
    assert tour_code not in set(_KOPIS_SIGNGUCODES.values())
    assert tour_code in set(_TOUR_API_AREA_CODES.values())


def test_p5c_preview_and_apply_thread_the_qualified_scope(monkeypatch, capsys):
    reads: list[tuple] = []

    def fake_read(cur, limit, names=None, after=None, area=None):
        reads.append((limit, names, after, area))
        return [_place("p1")]

    monkeypatch.setattr(tool, "_open_connection", lambda *a, **kw: _FakeConn())
    monkeypatch.setattr(tool, "load_active_review_source", lambda *a, **kw: _registration())
    monkeypatch.setattr(tool, "_read_places_on_cursor", fake_read)
    monkeypatch.setattr(
        tool, "collect_mentions_for_place", lambda **kw: _collection(kw["place_id"])
    )
    monkeypatch.setenv("DB_DSN", "host=localhost dbname=test")

    rc = tool.main(["--preview", "--json", "--region", "daegu-jung", "--after-place-id", "p1"])
    assert rc == 0
    monkeypatch.setattr(tool, "govern_review_ingest_on_cursor", lambda cur, **kw: _ingest_result())
    monkeypatch.setattr(tool, "insert_review_mention_aggregates_on_cursor", lambda cur, aggs: 0)
    monkeypatch.setattr(tool, "record_job_run", lambda **kw: None)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")
    rc = tool.main(["--apply", "--json", "--confirm", tool.CONFIRM_TEXT, "--region", "daegu-jung"])
    assert rc == 0

    # Identical qualified scope on both paths: aliases + proven area code 4.
    assert reads[0] == (50, manual_region_place_names("daegu-jung"), "p1", "4")
    assert reads[1] == (50, manual_region_place_names("daegu-jung"), None, "4")


def test_p5c_ambiguous_regions_get_qualified_plans_not_blocks(monkeypatch, capsys):
    from apps.api.app.services import collector_checkpoint as cc

    _no_io_wiring(monkeypatch)
    rc = tool.main(["--schedule", "--json", "--regions", "daegu-jung,seoul-jung,busan-jung"])
    assert rc == 0
    payload = _out(capsys)
    assert payload["regions_scope_blocked"] == 0
    assert payload["regions_alias_qualified"] == len(cc.region_alias_collisions())
    assert {p["region"] for p in payload["planned_arguments"]} == {
        "busan-jung",
        "daegu-jung",
        "seoul-jung",
    }
    # Eligibility is scoped to qualified rows, never whole-region data proof.
    assert "coverage gap" in payload["collector_scope_gap"]


def test_p5c_legacy_snapshot_transfers_no_credit_but_keeps_quota_stop(
    monkeypatch, capsys, tmp_path
):
    import json as _json

    _no_io_wiring(monkeypatch)
    legacy = tmp_path / "legacy.json"
    # Alias-only snapshot (no scope_contract): partial cursor + fresh completion.
    legacy.write_text(
        _json.dumps(
            {
                "schema_version": 1,
                "source": "naver_review_collect_apply_payloads",
                "entries": [
                    _entry("seoul-seongdong", cursor="p5", exhausted=False),
                    _entry("busan-haeundae", exhausted=True, whole_region_complete=True),
                ],
            }
        )
    )
    rc = tool.main(
        [
            "--schedule",
            "--json",
            "--checkpoint-snapshot",
            str(legacy),
            "--regions",
            "seoul-seongdong,busan-haeundae",
        ]
    )
    assert rc == 0
    payload = _out(capsys)
    # No cursor and no freshness credit from legacy evidence...
    assert payload["region_states"]["seoul-seongdong"] == "DUE"
    assert payload["region_states"]["busan-haeundae"] == "DUE"
    planned = {p["region"]: p for p in payload["planned_arguments"]}
    assert planned["seoul-seongdong"]["after_place_id"] is None
    # ...but account-wide stops always survive the contract change.
    blocked = tmp_path / "blocked.json"
    blocked.write_text(
        _json.dumps(
            {
                "schema_version": 1,
                "source": "naver_review_collect_apply_payloads",
                "entries": [_entry("daegu-jung", blocked="auth_quota")],
            }
        )
    )
    rc = tool.main(
        [
            "--schedule",
            "--json",
            "--checkpoint-snapshot",
            str(blocked),
            "--regions",
            "seoul-seongdong",
        ]
    )
    assert rc == 0
    payload = _out(capsys)
    assert payload["auth_quota_blocked"] is True
    assert payload["planned_argv"] == []


def test_p5c_mismatched_scope_contract_fails_closed(monkeypatch, capsys, tmp_path):
    import json as _json

    _no_io_wiring(monkeypatch)
    bad = tmp_path / "bad.json"
    bad.write_text(
        _json.dumps(
            {
                "schema_version": 1,
                "source": "naver_review_collect_apply_payloads",
                "scope_contract": "some-future-contract",
                "entries": [],
            }
        )
    )
    rc = tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(bad)])
    assert rc == 2
    assert "scope contract mismatch" in _out(capsys)["error"]


def test_p5c_round_trip_retains_scope_provenance(monkeypatch, capsys, tmp_path):
    import json as _json

    # Real scoped apply on an AMBIGUOUS district under the qualified predicate.
    places = [_place("p1")]
    script = {p.place_id: _collection(p.place_id) for p in places}
    _wire(monkeypatch, places=places, script=script)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")
    rc = tool.main(
        [
            "--apply",
            "--json",
            "--confirm",
            tool.CONFIRM_TEXT,
            "--region",
            "daegu-jung",
            "--limit",
            "2",
        ]
    )
    assert rc == 0
    apply_payload = _out(capsys)

    _no_io_wiring(monkeypatch)
    result = tmp_path / "r.json"
    result.write_text(_json.dumps(apply_payload))
    rc = tool.main(["--export-checkpoint", "--json", "--from-collector-result", str(result)])
    assert rc == 0
    snapshot_doc = _json.loads(capsys.readouterr().out)
    assert snapshot_doc["scope_contract"] == "tour_api_province_qualified_v1"

    snap = tmp_path / "cp.json"
    snap.write_text(_json.dumps(snapshot_doc))
    rc = tool.main(
        [
            "--schedule",
            "--json",
            "--checkpoint-snapshot",
            str(snap),
            "--regions",
            "daegu-jung,seoul-seongdong",
        ]
    )
    assert rc == 0
    payload = _out(capsys)
    # New-contract evidence carries real credit: daegu-jung resumes/schedules.
    assert payload["region_states"]["daegu-jung"] != "DUE"
    argv_regions = {a[0] for a in payload["planned_argv"]}
    assert "daegu-jung" in argv_regions or payload["region_states"]["daegu-jung"] in {
        "RECENTLY_COLLECTED",
        "EMPTY_OBSERVED",
    }


# == P5C provenance correction: legacy results are never upgraded ====================


def test_p5cc_legacy_succeeded_result_exports_creditless(monkeypatch, capsys, tmp_path):
    import json as _json

    _no_io_wiring(monkeypatch)
    # OLD raw apply result (pre-P5C shape: NO scope_contract) that fully
    # succeeded a null-cursor sweep. The NEW exporter must not upgrade it.
    legacy = _apply_result()
    del legacy["scope_contract"]
    result = tmp_path / "old.json"
    result.write_text(_json.dumps(legacy))

    rc = tool.main(["--export-checkpoint", "--json", "--from-collector-result", str(result)])
    assert rc == 0
    snapshot_doc = _json.loads(capsys.readouterr().out)
    entry = snapshot_doc["entries"][0]
    assert entry["qualified_scope"] is False
    assert entry["whole_region_complete"] is False

    snapshot_doc["scope_contract"] = "tour_api_province_qualified_v1"
    snap = tmp_path / "cp.json"
    snap.write_text(_json.dumps(snapshot_doc))
    rc = tool.main(
        ["--schedule", "--json", "--checkpoint-snapshot", str(snap), "--regions", "busan-haeundae"]
    )
    assert rc == 0
    payload = _out(capsys)
    assert payload["region_states"]["busan-haeundae"] == "DUE"  # never RECENTLY_COLLECTED


def test_p5cc_legacy_partial_result_cursor_does_not_transfer(monkeypatch, capsys, tmp_path):
    import json as _json

    _no_io_wiring(monkeypatch)
    legacy = _apply_result(
        scope_contract=None,
        exhausted=False,
        places=2,
        places_attempted=2,
        places_completed=2,
        stop_reason="request_budget_exhausted",
        next_after_place_id="place-2",
    )
    del legacy["scope_contract"]
    result = tmp_path / "old.json"
    result.write_text(_json.dumps(legacy))
    rc = tool.main(["--export-checkpoint", "--json", "--from-collector-result", str(result)])
    assert rc == 0
    entry = _json.loads(capsys.readouterr().out)["entries"][0]
    assert entry["qualified_scope"] is False
    # Legacy cursor credit stripped: next == input (here null start).
    assert entry["next_after_place_id"] == entry["input_after_place_id"]


def test_p5cc_legacy_committed_quota_result_keeps_global_stop(monkeypatch, capsys, tmp_path):
    import json as _json

    _no_io_wiring(monkeypatch)
    legacy = _apply_result(
        ok=False,
        status="failed",
        exhausted=False,
        places=1,
        places_attempted=1,
        places_completed=0,
        places_deferred=0,
        stop_reason="fatal_provider_failure",
        next_after_place_id="p0",
        after_place_id="p0",
        failure_tally={"naver_blog": {"quota_exceeded": 1}},
    )
    del legacy["scope_contract"]
    result = tmp_path / "old.json"
    result.write_text(_json.dumps(legacy))
    rc = tool.main(["--export-checkpoint", "--json", "--from-collector-result", str(result)])
    assert rc == 0
    snapshot_doc = _json.loads(capsys.readouterr().out)
    entry = snapshot_doc["entries"][0]
    assert entry["blocked"] == "auth_quota"  # stop signal survives invalidation
    assert entry["qualified_scope"] is False

    snapshot_doc["scope_contract"] = "tour_api_province_qualified_v1"
    snap = tmp_path / "cp.json"
    snap.write_text(_json.dumps(snapshot_doc))
    rc = tool.main(
        [
            "--schedule",
            "--json",
            "--checkpoint-snapshot",
            str(snap),
            "--regions",
            "seoul-seongdong,incheon-yeonsu",
        ]
    )
    assert rc == 0
    payload = _out(capsys)
    assert payload["auth_quota_blocked"] is True
    assert payload["planned_argv"] == []


def test_p5cc_unknown_result_marker_fails_closed(monkeypatch, capsys, tmp_path):
    import json as _json

    _no_io_wiring(monkeypatch)
    result = tmp_path / "future.json"
    result.write_text(_json.dumps(_apply_result(scope_contract="future-contract")))
    rc = tool.main(["--export-checkpoint", "--json", "--from-collector-result", str(result)])
    assert rc == 2
    assert "unknown to this bridge" in _out(capsys)["error"]


def test_p5cc_new_apply_result_carries_qualified_marker(monkeypatch, capsys, tmp_path):

    places = [_place("p1")]
    script = {p.place_id: _collection(p.place_id) for p in places}
    _wire(monkeypatch, places=places, script=script)
    monkeypatch.setenv(tool.ALLOW_ENV, "1")
    rc = tool.main(
        ["--apply", "--json", "--confirm", tool.CONFIRM_TEXT, "--region", "busan-haeundae"]
    )
    assert rc == 0
    payload = _out(capsys)
    assert payload["scope_contract"] == "tour_api_province_qualified_v1"
