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
from apps.api.app.services.region_catalog import manual_region_place_names
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

    def fake_read(cur, limit, region_place_names=None, after_place_id=None):
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

    tool._read_places_on_cursor(cur, 25, names, "p1")

    sql, params = cur.queries[0]
    assert "AND region_name_ko = ANY(%s)" in sql
    assert "AND place_id > %s" in sql
    assert sql.index("ANY(%s)") < sql.index("place_id > %s") < sql.index("ORDER BY place_id")
    assert sql.index("place_id > %s") < sql.index("LIMIT %s")
    assert params == (list(names), "p1", 25)


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
        tool, "_read_places_on_cursor", lambda cur, limit, names=None, cursor=None: list(places)
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


# == P5B: offline regional schedule mode =========================================


def _no_io_wiring(monkeypatch):
    def _boom(*a, **kw):  # pragma: no cover - sentinel
        raise AssertionError("schedule/plan mode must not touch settings/DB/providers")

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
                "entries": entries,
            }
        )
    )


def _entry(
    region, *, cursor=None, exhausted=False, blocked=None, empty=False, hours_ago=1, stop=None
):
    from datetime import UTC as _UTC
    from datetime import datetime as _dt
    from datetime import timedelta as _td

    observed = (_dt.now(_UTC) - _td(hours=hours_ago)).isoformat()
    return {
        "region": region,
        "next_after_place_id": cursor,
        "exhausted": exhausted,
        "stop_reason": stop,
        "blocked": blocked,
        "empty_observed": empty,
        "observed_at": observed,
    }


def test_schedule_rejects_preview_apply_combination(monkeypatch, capsys):
    _no_io_wiring(monkeypatch)
    for combo in (["--schedule", "--preview"], ["--schedule", "--apply"]):
        rc = tool.main([*combo, "--json"])
        assert rc == 2
        assert "cannot combine" in _out(capsys)["error"]


def test_schedule_zero_io_and_default_due(monkeypatch, capsys):
    _no_io_wiring(monkeypatch)
    rc = tool.main(["--schedule", "--json", "--regions", "seoul-seongdong,busan-haeundae"])
    assert rc == 0
    payload = _out(capsys)
    assert payload["ok"] is True
    assert payload["mode"] == "schedule"
    assert payload["db_mutation"] is False
    assert payload["checkpoint_snapshot_supplied"] is False
    # No snapshot: honest unknown, so both clean regions are DUE internally and
    # get scheduled within the default bounded batch.
    assert payload["statuses"] == {
        "busan-haeundae": "SCHEDULED",
        "seoul-seongdong": "SCHEDULED",
    }
    assert [p["region"] for p in payload["planned_arguments"]] == [
        "busan-haeundae",
        "seoul-seongdong",
    ]
    for planned in payload["planned_arguments"]:
        assert planned["after_place_id"] is None
        assert planned["limit"] == 50
        assert planned["max_requests"] == 100  # 2 x default limit


def test_schedule_regions_subset_sorted_dedup_and_unknown_fails(monkeypatch, capsys):
    _no_io_wiring(monkeypatch)
    rc = tool.main(
        ["--schedule", "--json", "--regions", "seoul-seongdong, busan-haeundae,seoul-seongdong"]
    )
    assert rc == 0
    assert [p["region"] for p in _out(capsys)["planned_arguments"]] == [
        "busan-haeundae",
        "seoul-seongdong",
    ]

    rc = tool.main(["--schedule", "--json", "--regions", "seoul-seongdong,not-a-region"])
    assert rc == 2
    payload = _out(capsys)
    assert "unknown/non-canonical" in payload["error"]
    assert "not-a-region" not in json.dumps(payload)


def test_schedule_odd_total_budget_defers(monkeypatch, capsys):
    _no_io_wiring(monkeypatch)
    rc = tool.main(
        [
            "--schedule",
            "--json",
            "--regions",
            "busan-haeundae,seoul-seongdong,incheon-yeonsu",
            "--per-region-requests",
            "2",
            "--total-request-ceiling",
            "5",
            "--max-regions",
            "3",
        ]
    )
    assert rc == 0
    payload = _out(capsys)
    assert payload["regions_scheduled"] == 2  # 2+2=4 <= 5; the third no longer fits
    assert payload["regions_deferred"] == 1
    # Sorted enumeration: busan-haeundae, incheon-yeonsu, seoul-seongdong —
    # the last (seoul) is the one that no longer fits.
    assert payload["statuses"]["seoul-seongdong"] == "DEFERRED"
    assert payload["statuses"]["incheon-yeonsu"] == "SCHEDULED"
    assert sum(p["max_requests"] for p in payload["planned_arguments"]) <= 5


@pytest.mark.parametrize(
    ("extra", "fragment"),
    [
        (["--per-region-requests", "1"], "between 2"),
        (
            ["--total-request-ceiling", "2", "--per-region-requests", "4"],
            ">= --per-region-requests",
        ),
        (["--max-regions", "0"], "--max-regions"),
        (["--refresh-interval-hours", "0"], "--refresh-interval-hours"),
    ],
)
def test_schedule_invalid_budgets_fail_closed(extra, fragment, monkeypatch, capsys):
    _no_io_wiring(monkeypatch)
    rc = tool.main(["--schedule", "--json", *extra])
    assert rc == 2
    assert fragment in _out(capsys)["error"]


def test_schedule_continuation_and_refresh(monkeypatch, capsys, tmp_path):
    from datetime import UTC as _UTC
    from datetime import datetime as _dt

    _no_io_wiring(monkeypatch)
    frozen = _dt(2026, 9, 6, 12, 0, tzinfo=_UTC)
    monkeypatch.setattr(tool, "_now_utc", lambda: frozen)
    snapshot = tmp_path / "cp.json"
    _write_snapshot(
        snapshot,
        [
            _entry("busan-haeundae", cursor="place-42", hours_ago=1),  # partial -> RESUME
            _entry("seoul-seongdong", exhausted=True, hours_ago=2),  # fresh complete
            _entry("incheon-yeonsu", exhausted=True, hours_ago=200),  # older than 168h
            _entry("seoul-mapo", exhausted=True, empty=True, hours_ago=1),  # observed empty
        ],
    )

    rc = tool.main(
        [
            "--schedule",
            "--json",
            "--checkpoint-snapshot",
            str(snapshot),
            "--max-regions",
            "5",
            "--regions",
            "busan-haeundae,seoul-seongdong,incheon-yeonsu,seoul-mapo",
        ]
    )

    assert rc == 0
    payload = _out(capsys)
    statuses = payload["statuses"]
    assert statuses["seoul-seongdong"] == "RECENTLY_COLLECTED"
    assert statuses["seoul-mapo"] == "EMPTY_OBSERVED"
    assert statuses["incheon-yeonsu"] == "SCHEDULED"
    assert payload["region_states"]["incheon-yeonsu"] == "DUE_REFRESH"
    assert statuses["busan-haeundae"] == "SCHEDULED"
    planned = {p["region"]: p for p in payload["planned_arguments"]}
    # Same-region cursor preserved on resume; refresh restarts from scratch.
    assert planned["busan-haeundae"]["after_place_id"] == "place-42"
    assert planned["incheon-yeonsu"]["after_place_id"] is None
    assert "seoul-seongdong" not in planned and "seoul-mapo" not in planned


def test_schedule_future_observation_is_due_not_fresh(monkeypatch, capsys, tmp_path):
    from datetime import UTC as _UTC
    from datetime import datetime as _dt
    from datetime import timedelta as _td

    _no_io_wiring(monkeypatch)
    frozen = _dt(2026, 9, 6, 12, 0, tzinfo=_UTC)
    monkeypatch.setattr(tool, "_now_utc", lambda: frozen)
    snapshot = tmp_path / "cp.json"
    _write_snapshot(
        snapshot,
        [
            {
                **_entry("busan-haeundae", exhausted=True),
                "observed_at": (frozen + _td(hours=3)).isoformat(),  # future clock skew
            }
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
    # Future/inconsistent observation is UNKNOWN -> DUE -> scheduled; had it
    # been misread as fresh it would be RECENTLY_COLLECTED and NOT scheduled.
    assert payload["statuses"]["busan-haeundae"] == "SCHEDULED"
    assert payload["region_states"]["busan-haeundae"] == "DUE"


def test_schedule_auth_quota_block_requires_reset(monkeypatch, capsys, tmp_path):
    _no_io_wiring(monkeypatch)
    snapshot = tmp_path / "cp.json"
    _write_snapshot(
        snapshot,
        [
            _entry(
                "busan-haeundae", cursor="p9", blocked="auth_quota", stop="fatal_provider_failure"
            ),
            _entry("seoul-seongdong"),  # unrelated DUE region
        ],
    )

    rc = tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(snapshot)])

    assert rc == 0
    payload = _out(capsys)
    assert payload["auth_quota_blocked"] is True
    assert payload["requires_reset_decision"] is True
    # No marching through more regions: nothing is scheduled at all.
    assert payload["planned_arguments"] == []
    assert payload["statuses"]["busan-haeundae"] == "AUTH_QUOTA_BLOCKED"
    # The unrelated region keeps its own classification (partial window here)
    # but is NOT scheduled: no marching through regions without a reset.
    assert payload["statuses"]["seoul-seongdong"] == "RESUME_PARTIAL"


@pytest.mark.parametrize(
    "mutate",
    [
        lambda e: e.update({"unexpected_field": 1}),
        lambda e: (
            e.update({"schema_version": 2})
            if "schema_version" in e
            else e.update({"stop_reason": "nope"})
        ),
    ],
)
def test_schedule_malformed_snapshot_fails_closed(mutate, monkeypatch, capsys, tmp_path):
    import json as _json

    _no_io_wiring(monkeypatch)
    snapshot = tmp_path / "cp.json"
    _write_snapshot(snapshot, [_entry("busan-haeundae")])
    document = _json.loads(snapshot.read_text())
    if "schema_version" in document:
        document["schema_version"] = 99
        snapshot.write_text(_json.dumps(document))
    else:
        mutate(document["entries"][0])
        snapshot.write_text(_json.dumps(document))

    rc = tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(snapshot)])

    assert rc == 2
    assert _out(capsys)["ok"] is False


def test_snapshot_rejects_duplicates_and_oversize(monkeypatch, capsys, tmp_path):
    _no_io_wiring(monkeypatch)
    dup = tmp_path / "dup.json"
    _write_snapshot(dup, [_entry("busan-haeundae"), _entry("busan-haeundae")])
    assert tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(dup)]) == 2

    big = tmp_path / "big.json"
    big.write_text("x" * (1024 * 64 + 1))
    assert tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(big)]) == 2


def test_collector_result_to_snapshot_to_cli_round_trip(monkeypatch, capsys, tmp_path):
    # Real committed-apply payload from THIS collector (P5A fakes) -> bridge ->
    # snapshot -> real --schedule planned argv preserves the region cursor.
    from datetime import UTC as _UTC
    from datetime import datetime as _dt

    from apps.api.app.services import collector_checkpoint as cc

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
    assert apply_payload["cursor_advanced"] is True

    entry = cc.build_region_checkpoint(apply_payload, observed_at=frozen)
    snapshot = tmp_path / "cp.json"
    _write_snapshot(snapshot, [entry])

    _no_io_wiring(monkeypatch)  # schedule mode must stay offline end-to-end
    rc = tool.main(
        [
            "--schedule",
            "--json",
            "--checkpoint-snapshot",
            str(snapshot),
            "--regions",
            "busan-haeundae,seoul-seongdong",
        ]
    )

    assert rc == 0
    payload = _out(capsys)
    planned = {p["region"]: p for p in payload["planned_arguments"]}
    # Partial window (limit 2, both places done but limit-sized -> not exhausted):
    # the region is a RESUME candidate with the committed cursor preserved.
    assert payload["statuses"]["busan-haeundae"] == "SCHEDULED"
    assert payload["region_states"]["busan-haeundae"] == "RESUME_PARTIAL"
    assert payload["statuses"]["seoul-seongdong"] == "SCHEDULED"
    assert planned["busan-haeundae"]["after_place_id"] == apply_payload["next_after_place_id"]


def test_schedule_alias_collision_regions_are_blocked_scope(monkeypatch, capsys):
    # Offline catalog fact: districts like daegu-jung share the 중구 alias with
    # five other cities; the collector's region_name_ko = ANY(...) predicate
    # cannot scope them. The plan must never emit argv for them and must keep
    # them in coverage accounting with the recorded collector scope gap.
    from apps.api.app.services import collector_checkpoint as cc

    collisions = cc.region_alias_collisions()
    assert "daegu-jung" in collisions and "seoul-jung" in collisions["daegu-jung"]

    _no_io_wiring(monkeypatch)
    rc = tool.main(["--schedule", "--json", "--regions", "daegu-jung,seoul-seongdong"])
    assert rc == 0
    payload = _out(capsys)
    assert payload["statuses"]["daegu-jung"] == "BLOCKED_SCOPE"
    assert payload["regions_scope_blocked"] == 1
    assert payload["regions_total"] == 2
    assert [p["region"] for p in payload["planned_arguments"]] == ["seoul-seongdong"]
    assert "province-aware" in payload["collector_scope_gap"]


def test_schedule_all_catalog_accounts_for_collisions(monkeypatch, capsys):
    from apps.api.app.services import collector_checkpoint as cc

    _no_io_wiring(monkeypatch)
    rc = tool.main(["--schedule", "--json", "--max-regions", "2"])
    assert rc == 0
    payload = _out(capsys)
    # Every region appears in coverage accounting; ambiguous ones are blocked,
    # never deferred/scheduled, regardless of evidence absence.
    assert payload["regions_total"] == len(cc.canonical_region_ids())
    assert payload["regions_scope_blocked"] == len(cc.region_alias_collisions())
    blocked = [r for r, s in payload["statuses"].items() if s == "BLOCKED_SCOPE"]
    assert len(blocked) == payload["regions_scope_blocked"]
    assert payload["regions_scheduled"] == 2
