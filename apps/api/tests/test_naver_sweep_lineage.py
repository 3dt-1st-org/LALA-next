"""P5D2 contiguous multi-page sweep lineage: real CLI export->state->schedule.

Every page is a REAL-shaped raw committed result exported through the actual
--export-checkpoint CLI into a persistent local state file (reload between
pages), then consumed by --schedule. No live provider/DB/settings — sentinels
throughout.
"""

from __future__ import annotations

import json

from apps.api.app.tools import run_naver_review_collect as tool


def _no_io(monkeypatch):
    def _boom(*a, **kw):  # pragma: no cover - sentinel
        raise AssertionError("lineage tests must not touch settings/DB/providers")

    monkeypatch.setattr(tool, "get_settings", _boom)
    monkeypatch.setattr(tool, "_open_connection", _boom)
    monkeypatch.setattr(tool, "collect_mentions_for_place", _boom)


def _raw_page(
    *,
    input_cursor,
    next_cursor,
    exhausted,
    status="succeeded",
    ok=True,
    tally=None,
    places=2,
    attempted=2,
    completed=2,
    deferred=0,
    stop=None,
    observed,
    region="busan-haeundae",
):
    return {
        "ok": ok,
        "status": status,
        "mode": "apply",
        "committed": True,
        "region": region,
        "region_applied": True,
        "cursor_scope": region,
        "after_place_id": input_cursor,
        "next_after_place_id": next_cursor,
        "exhausted": exhausted,
        "places": places,
        "places_attempted": attempted,
        "places_completed": completed,
        "places_deferred": deferred,
        "places_name_skipped": 0,
        "requests_used": 4,
        "stop_reason": stop,
        "failure_tally": tally or {},
        "observation_time": observed,
        "scope_contract": "tour_api_province_qualified_v1",
    }


def _export_state(monkeypatch, capsys, tmp_path, state, page, name):
    (tmp_path / name).write_text(json.dumps(page))
    rc = tool.main(
        [
            "--export-checkpoint",
            "--json",
            "--from-collector-result",
            str(tmp_path / name),
            "--checkpoint-state",
            str(state),
        ]
    )
    return rc


def _schedule(monkeypatch, capsys, state, regions="busan-haeundae"):
    rc = tool.main(
        ["--schedule", "--json", "--checkpoint-snapshot", str(state), "--regions", regions]
    )
    assert rc == 0
    return json.loads(capsys.readouterr().out)


def test_full_chain_null_to_terminal_with_reload_between_pages(monkeypatch, capsys, tmp_path):
    from datetime import UTC, datetime

    _no_io(monkeypatch)
    frozen = datetime(2026, 9, 6, 20, 0, tzinfo=UTC)
    monkeypatch.setattr(tool, "_now_utc", lambda: frozen)
    state = tmp_path / "state.json"

    pages = [
        _raw_page(
            input_cursor=None,
            next_cursor="p2",
            exhausted=False,
            observed="2026-09-06T11:00:00+00:00",
        ),
        _raw_page(
            input_cursor="p2",
            next_cursor="p4",
            exhausted=False,
            observed="2026-09-06T11:30:00+00:00",
        ),
        _raw_page(
            input_cursor="p4",
            next_cursor="p4",
            exhausted=True,
            observed="2026-09-06T12:00:00+00:00",
            places=0,
            attempted=0,
            completed=0,
        ),
    ]
    for i, page in enumerate(pages):
        assert _export_state(monkeypatch, capsys, tmp_path, state, page, f"p{i}.json") == 0
        capsys.readouterr()
        json.loads(state.read_text(encoding="utf-8"))  # REAL reload between pages

    doc = json.loads(state.read_text(encoding="utf-8"))
    entry = doc["entries"][0]
    assert entry["sweep_pages"] == 3
    assert entry["sweep_chain_started_at"] == "2026-09-06T11:00:00+00:00"
    assert entry["whole_region_complete"] is True
    assert entry["empty_scope"] == "window"  # terminal empty tail ≠ empty region

    payload = _schedule(monkeypatch, capsys, state)
    # Recency anchored to the EARLIEST page (11:00), not the fresh tail.
    assert payload["region_states"]["busan-haeundae"] == "RECENTLY_COLLECTED"

    # Identical replay of the FINAL page is idempotent (no double count).
    assert _export_state(monkeypatch, capsys, tmp_path, state, pages[2], "again.json") == 0
    capsys.readouterr()
    entry2 = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert entry2 == entry


def test_old_prefix_new_tail_recency_uses_earliest(monkeypatch, capsys, tmp_path):
    from datetime import UTC, datetime

    _no_io(monkeypatch)
    frozen = datetime(2026, 9, 14, 0, 0, tzinfo=UTC)  # prefix now >168h old
    monkeypatch.setattr(tool, "_now_utc", lambda: frozen)
    state = tmp_path / "state.json"
    assert (
        _export_state(
            monkeypatch,
            capsys,
            tmp_path,
            state,
            _raw_page(
                input_cursor=None,
                next_cursor="p2",
                exhausted=False,
                observed="2026-09-06T11:00:00+00:00",
            ),
            "a.json",
        )
        == 0
    )
    capsys.readouterr()
    assert (
        _export_state(
            monkeypatch,
            capsys,
            tmp_path,
            state,
            _raw_page(
                input_cursor="p2",
                next_cursor="p2",
                exhausted=True,
                observed="2026-09-09T23:00:00+00:00",
                places=0,
                attempted=0,
                completed=0,
            ),
            "b.json",
        )
        == 0
    )
    capsys.readouterr()
    payload = _schedule(monkeypatch, capsys, state)
    # Fresh tail cannot make the days-old prefix newly fresh.
    assert payload["region_states"]["busan-haeundae"] == "DUE_REFRESH"


def test_hole_and_wrong_cursor_tails_never_mend(monkeypatch, capsys, tmp_path):
    _no_io(monkeypatch)
    state = tmp_path / "state.json"
    assert (
        _export_state(
            monkeypatch,
            capsys,
            tmp_path,
            state,
            _raw_page(
                input_cursor=None,
                next_cursor="p2",
                exhausted=False,
                observed="2026-09-06T11:00:00+00:00",
            ),
            "a.json",
        )
        == 0
    )
    capsys.readouterr()
    # Arbitrary tail from the WRONG cursor (hole): recorded, no chain credit.
    assert (
        _export_state(
            monkeypatch,
            capsys,
            tmp_path,
            state,
            _raw_page(
                input_cursor="p9",
                next_cursor="p9",
                exhausted=True,
                observed="2026-09-06T12:00:00+00:00",
            ),
            "hole.json",
        )
        == 0
    )
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert "sweep_pages" not in entry
    assert entry["whole_region_complete"] is False


def test_degraded_page_advances_without_terminal_credit(monkeypatch, capsys, tmp_path):
    _no_io(monkeypatch)
    state = tmp_path / "state.json"
    assert (
        _export_state(
            monkeypatch,
            capsys,
            tmp_path,
            state,
            _raw_page(
                input_cursor=None,
                next_cursor="p2",
                exhausted=False,
                observed="2026-09-06T11:00:00+00:00",
            ),
            "a.json",
        )
        == 0
    )
    capsys.readouterr()
    degraded = _raw_page(
        input_cursor="p2",
        next_cursor="p4",
        exhausted=False,
        status="degraded",
        tally={"naver_blog": {"network_error": 1}},
        completed=1,
        observed="2026-09-06T11:30:00+00:00",
    )
    assert _export_state(monkeypatch, capsys, tmp_path, state, degraded, "d.json") == 0
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert entry["sweep_pages"] == 2
    assert entry["next_after_place_id"] == "p4"  # ACTUAL committed cursor preserved
    assert entry["whole_region_complete"] is False
    # A later terminal page from the preserved cursor may still close the chain.
    assert (
        _export_state(
            monkeypatch,
            capsys,
            tmp_path,
            state,
            _raw_page(
                input_cursor="p4",
                next_cursor="p4",
                exhausted=True,
                observed="2026-09-06T12:00:00+00:00",
                places=0,
                attempted=0,
                completed=0,
            ),
            "t.json",
        )
        == 0
    )
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert entry["sweep_pages"] == 3 and entry["whole_region_complete"] is True


def test_failed_page_keeps_head_and_no_credit(monkeypatch, capsys, tmp_path):
    _no_io(monkeypatch)
    state = tmp_path / "state.json"
    assert (
        _export_state(
            monkeypatch,
            capsys,
            tmp_path,
            state,
            _raw_page(
                input_cursor=None,
                next_cursor="p2",
                exhausted=False,
                observed="2026-09-06T11:00:00+00:00",
            ),
            "a.json",
        )
        == 0
    )
    capsys.readouterr()
    failed = _raw_page(
        input_cursor="p2",
        next_cursor="p2",
        exhausted=False,
        status="failed",
        ok=False,
        tally={"naver_blog": {"network_error": 2}},
        completed=0,
        stop="fatal_provider_failure",
        observed="2026-09-06T11:30:00+00:00",
    )
    assert _export_state(monkeypatch, capsys, tmp_path, state, failed, "f.json") == 0
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert entry["sweep_pages"] == 1  # head retained, no page increment
    assert entry["next_after_place_id"] == "p2"
    assert entry["whole_region_complete"] is False


def test_null_start_degraded_or_unqualified_opens_no_chain(monkeypatch, capsys, tmp_path):
    _no_io(monkeypatch)
    state = tmp_path / "state.json"
    degraded_start = _raw_page(
        input_cursor=None,
        next_cursor="p2",
        exhausted=False,
        status="degraded",
        tally={"naver_cafe": {"parse_error": 1}},
        completed=1,
        observed="2026-09-06T11:00:00+00:00",
    )
    assert _export_state(monkeypatch, capsys, tmp_path, state, degraded_start, "d0.json") == 0
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert "sweep_pages" not in entry  # degraded start: no chain proof


def test_zero_progress_nonterminal_page_rejected(monkeypatch, capsys, tmp_path):
    _no_io(monkeypatch)
    state = tmp_path / "state.json"
    assert (
        _export_state(
            monkeypatch,
            capsys,
            tmp_path,
            state,
            _raw_page(
                input_cursor=None,
                next_cursor="p2",
                exhausted=False,
                observed="2026-09-06T11:00:00+00:00",
            ),
            "a.json",
        )
        == 0
    )
    capsys.readouterr()
    prior = state.read_bytes()
    zero = _raw_page(
        input_cursor="p2", next_cursor="p2", exhausted=False, observed="2026-09-06T11:30:00+00:00"
    )
    rc = _export_state(monkeypatch, capsys, tmp_path, state, zero, "z.json")
    assert rc == 2
    assert "zero-progress" in json.loads(capsys.readouterr().out)["error"]
    assert state.read_bytes() == prior


def test_over_cap_lineage_fails_closed(monkeypatch, capsys, tmp_path):
    from apps.api.app.services import collector_checkpoint as cc

    _no_io(monkeypatch)
    monkeypatch.setattr(cc, "SWEEP_MAX_PAGES", 2)
    state = tmp_path / "state.json"
    for i, page in enumerate(
        [
            _raw_page(
                input_cursor=None,
                next_cursor="p2",
                exhausted=False,
                observed="2026-09-06T11:00:00+00:00",
            ),
            _raw_page(
                input_cursor="p2",
                next_cursor="p4",
                exhausted=False,
                observed="2026-09-06T11:30:00+00:00",
            ),
        ]
    ):
        assert _export_state(monkeypatch, capsys, tmp_path, state, page, f"c{i}.json") == 0
        capsys.readouterr()
    prior = state.read_bytes()
    third = _raw_page(
        input_cursor="p4", next_cursor="p6", exhausted=False, observed="2026-09-06T12:00:00+00:00"
    )
    rc = _export_state(monkeypatch, capsys, tmp_path, state, third, "c2.json")
    assert rc == 2
    assert "bounded page count" in json.loads(capsys.readouterr().out)["error"]
    assert state.read_bytes() == prior


def test_standalone_tail_stays_unknown_and_legacy_gains_no_credit(monkeypatch, capsys, tmp_path):
    _no_io(monkeypatch)
    # Standalone tail export (no state) remains unproven through --schedule.
    result = tmp_path / "tail.json"
    result.write_text(
        json.dumps(
            _raw_page(
                input_cursor="p2",
                next_cursor="p2",
                exhausted=True,
                places=0,
                attempted=0,
                completed=0,
                observed="2026-09-06T12:00:00+00:00",
            )
        )
    )
    rc = tool.main(["--export-checkpoint", "--json", "--from-collector-result", str(result)])
    assert rc == 0
    snap = tmp_path / "snap.json"
    snap.write_text(capsys.readouterr().out)
    from datetime import UTC, datetime

    monkeypatch.setattr(tool, "_now_utc", lambda: datetime(2026, 9, 6, 13, 0, tzinfo=UTC))
    rc = tool.main(["--schedule", "--json", "--checkpoint-snapshot", str(snap)])
    assert rc == 0
    assert json.loads(capsys.readouterr().out)["region_states"]["busan-haeundae"] == (
        "UNKNOWN_COMPLETION"
    )
