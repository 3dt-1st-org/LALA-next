"""P5D2 contiguous multi-page sweep lineage: real CLI export->state->schedule.

Every page is a REAL-shaped raw committed result exported through the actual
--export-checkpoint CLI into a persistent local state file (reload between
pages), then consumed by --schedule. No live provider/DB/settings — sentinels
throughout.
"""

from __future__ import annotations

import json

import pytest

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
    # ORIGINAL CONTRACT (H2 correction): an advancing degraded contribution
    # TAINTS the chain — a later clean terminal page alone must NOT grant
    # whole-region credit; the committed cursor stays preserved for resumption.
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
    assert entry["sweep_pages"] == 3
    assert entry["sweep_clean"] is False
    assert entry["whole_region_complete"] is False
    # A genuinely NEW clean null-start requalifies on its own.
    assert (
        _export_state(
            monkeypatch,
            capsys,
            tmp_path,
            state,
            _raw_page(
                input_cursor=None,
                next_cursor="q2",
                exhausted=False,
                observed="2026-09-06T13:00:00+00:00",
            ),
            "fresh.json",
        )
        == 0
    )
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert entry["sweep_pages"] == 1
    assert entry["sweep_clean"] is True
    assert entry["next_after_place_id"] == "q2"


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


def test_new_shape_counterexamples_fail_closed(monkeypatch, tmp_path):
    """Pre-commit review counterexamples: explicit null kind, tainted/impure
    whole credit, and orphan sweep_clean all fail safely; literal historical
    shapes stay loadable without new fields."""
    import json as _json

    from apps.api.app.services import collector_checkpoint as cc

    base = {
        "region": "busan-haeundae",
        "next_after_place_id": "p4",
        "input_after_place_id": "p2",
        "exhausted": True,
        "whole_region_complete": True,
        "empty_scope": None,
        "stop_reason": None,
        "blocked": None,
        "requests_used": 4,
        "observation_time": "2026-09-06T12:00:00+00:00",
        "qualified_scope": True,
        "lineage_page_kind": "terminal_clean",
        "sweep_pages": 2,
        "sweep_chain_started_at": "2026-09-06T11:00:00+00:00",
        "sweep_clean": True,
    }

    def _load_with(entry):
        doc = {
            "schema_version": 1,
            "source": "naver_review_collect_apply_payloads",
            "scope_contract": "tour_api_province_qualified_v1",
            "entries": [entry],
        }
        path = tmp_path / "case.json"
        path.write_text(_json.dumps(doc))
        try:
            cc.load_checkpoint_snapshot(path)
            return None
        except cc.CheckpointSnapshotError as exc:
            return str(exc)

    # Valid complete new shape loads.
    assert _load_with(base) is None

    # Explicitly present NULL kind with paired proof is rejected.
    err = _load_with({**base, "lineage_page_kind": None})
    assert err == "checkpoint lineage_page_kind is unknown"

    # Whole multi-page credit with a tainted chain is rejected.
    err = _load_with({**base, "sweep_clean": False})
    assert err == "checkpoint entry is internally inconsistent"

    # Whole credit with nonterminal/failed/degraded page kinds is rejected.
    for kind in ("clean_prefix", "degraded_page", "failed_page"):
        err = _load_with({**base, "lineage_page_kind": kind})
        assert err == "checkpoint entry is internally inconsistent", kind

    # Orphan sweep_clean without the complete lineage shape is rejected.
    orphan = {k: v for k, v in base.items() if k not in ("sweep_pages", "sweep_chain_started_at")}
    orphan["whole_region_complete"] = False
    err = _load_with(orphan)
    assert err == "checkpoint lineage metadata is partial"

    # Literal pre-P5D2 historical shape (no kind/sweep fields) still loads
    # with its conservative single-page semantics.
    legacy = {
        k: v
        for k, v in base.items()
        if k
        not in (
            "lineage_page_kind",
            "sweep_pages",
            "sweep_chain_started_at",
            "sweep_clean",
            "input_after_place_id",
        )
    }
    legacy["input_after_place_id"] = None
    assert _load_with(legacy) is None


# == P5D2 durable tracked regressions (corrected premises) ==========================


def _chain_page(
    inp, nxt, obs, *, exhausted=False, places=2, attempted=2, completed=2, deferred=0, **kw
):
    return _raw_page(
        input_cursor=inp,
        next_cursor=nxt,
        exhausted=exhausted,
        observed=obs,
        places=places,
        attempted=attempted,
        completed=completed,
        deferred=deferred,
        **kw,
    )


def test_r1_nonempty_terminal_chain_with_replay_after_each_publication(
    monkeypatch, capsys, tmp_path
):
    """Clean null-start -> advancing intermediate -> NONEMPTY terminal; replay
    immediately after EACH publication is rc0 with byte-identical state."""
    _no_io(monkeypatch)
    state = tmp_path / "state.json"
    pages = [
        _chain_page(None, "place-002", "2026-09-06T11:00:00+00:00"),
        _chain_page("place-002", "place-004", "2026-09-06T11:30:00+00:00"),
        # Nonempty terminal: 3 places, all settled, exhausted, cursor advanced.
        _chain_page(
            "place-004",
            "place-006",
            "2026-09-06T12:00:00+00:00",
            exhausted=True,
            places=3,
            attempted=3,
            completed=3,
        ),
    ]
    for i, page in enumerate(pages):
        assert _export_state(monkeypatch, capsys, tmp_path, state, page, f"r1-{i}.json") == 0
        capsys.readouterr()
        snapshot_after = state.read_bytes()
        # Same-time identical replay of the JUST-published page.
        assert _export_state(monkeypatch, capsys, tmp_path, state, page, f"r1-{i}-replay.json") == 0
        capsys.readouterr()
        assert state.read_bytes() == snapshot_after  # byte-identical proof/pages/times
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert entry["sweep_pages"] == 3
    assert entry["whole_region_complete"] is True
    assert entry["sweep_clean"] is True
    assert entry["sweep_chain_started_at"] == "2026-09-06T11:00:00+00:00"
    assert entry["empty_scope"] is None  # nonempty terminal is not an empty window


def test_r2_zero_place_terminal_tail_is_window(monkeypatch, capsys, tmp_path):
    """Separate FRESH chain whose final page is a genuine zero-place tail with
    input == the actual committed head cursor: empty_scope=window (not region),
    whole completion, identical replay."""
    _no_io(monkeypatch)
    state = tmp_path / "state2.json"
    head = _chain_page(None, "place-102", "2026-09-06T11:00:00+00:00")
    tail = _chain_page(
        "place-102",
        "place-102",
        "2026-09-06T11:20:00+00:00",
        exhausted=True,
        places=0,
        attempted=0,
        completed=0,
    )
    for i, page in enumerate([head, tail]):
        assert _export_state(monkeypatch, capsys, tmp_path, state, page, f"r2-{i}.json") == 0
        capsys.readouterr()
    snapshot = state.read_bytes()
    entry = json.loads(snapshot.decode("utf-8"))["entries"][0]
    assert entry["next_after_place_id"] == "place-102" == entry["input_after_place_id"]
    assert entry["empty_scope"] == "window"
    assert entry["whole_region_complete"] is True
    assert entry["sweep_pages"] == 2
    assert _export_state(monkeypatch, capsys, tmp_path, state, tail, "r2-replay.json") == 0
    capsys.readouterr()
    assert state.read_bytes() == snapshot


def test_r3_same_time_conflict_and_older_rejection(monkeypatch, capsys, tmp_path):
    _no_io(monkeypatch)
    state = tmp_path / "state3.json"
    stored_time = "2026-09-06T11:00:00+00:00"
    page = _chain_page(None, "place-202", stored_time)
    assert _export_state(monkeypatch, capsys, tmp_path, state, page, "r3-0.json") == 0
    capsys.readouterr()
    prior = state.read_bytes()

    # EXACT stored observation time; the conflicting page is DERIVED from the
    # stored page so ONLY requests_used differs (cursors identical).
    stored_page = _chain_page(None, "place-202", stored_time)
    conflicting = {**stored_page, "requests_used": 6}
    rc = _export_state(monkeypatch, capsys, tmp_path, state, conflicting, "r3-c.json")
    assert rc == 2
    assert "conflicting evidence" in json.loads(capsys.readouterr().out)["error"]
    assert state.read_bytes() == prior

    # Separate OLDER-time rejection.
    older = _chain_page(None, "place-202", "2026-09-06T10:00:00+00:00")
    rc = _export_state(monkeypatch, capsys, tmp_path, state, older, "r3-o.json")
    assert rc == 2
    assert "older" in json.loads(capsys.readouterr().out)["error"]
    assert state.read_bytes() == prior


def test_r4_incomplete_exhausted_tail_counters_not_hole(monkeypatch, capsys, tmp_path):
    """Tail with places3/attempted2/completed2/deferred1 whose input EQUALS the
    prefix's committed next cursor: rc0, advances without whole credit — the
    no-credit is attributable to counters, not a cursor hole."""
    from datetime import UTC, datetime

    _no_io(monkeypatch)
    frozen = datetime(2026, 9, 6, 13, 0, tzinfo=UTC)
    monkeypatch.setattr(tool, "_now_utc", lambda: frozen)
    state = tmp_path / "state4.json"
    prefix = _chain_page(None, "place-302", "2026-09-06T11:00:00+00:00")
    assert _export_state(monkeypatch, capsys, tmp_path, state, prefix, "r4-0.json") == 0
    capsys.readouterr()
    # Incomplete exhausted tail: prefix.next == tail.input (place-302).
    tail = _chain_page(
        "place-302",
        "place-302",
        "2026-09-06T11:30:00+00:00",
        exhausted=True,
        places=3,
        attempted=2,
        completed=2,
        deferred=1,
    )
    rc = _export_state(monkeypatch, capsys, tmp_path, state, tail, "r4-1.json")
    assert rc == 0  # exact expected outcome, not rc0-or-rc2
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert entry["sweep_pages"] == 2
    assert entry["whole_region_complete"] is False
    assert entry["sweep_clean"] is False
    payload = _schedule(monkeypatch, capsys, state)
    assert payload["region_states"]["busan-haeundae"] != "RECENTLY_COLLECTED"
    assert payload["region_states"]["busan-haeundae"] != "EMPTY_OBSERVED"


@pytest.mark.parametrize("cap", [2, 64])
def test_r5_mixed_fatal_stop_priority_and_cap(cap, monkeypatch, capsys, tmp_path):
    from apps.api.app.services import collector_checkpoint as cc

    _no_io(monkeypatch)
    # cap=2 exercises the boundary with a short real chain; cap=64 proves the
    # same semantics at the ACTUAL default limit with a full real chain.
    monkeypatch.setattr(cc, "SWEEP_MAX_PAGES", cap)
    state = tmp_path / "state5.json"
    # Other region preserved across every stop interaction.
    other = _raw_page(
        region="seoul-seongdong",
        input_cursor=None,
        next_cursor="s-2",
        exhausted=False,
        observed="2026-09-06T11:00:00+00:00",
    )
    assert _export_state(monkeypatch, capsys, tmp_path, state, other, "r5-o.json") == 0
    capsys.readouterr()
    # Real chain to the cap through actual exports (2 or 64 clean pages;
    # cap=64 exercises the ACTUAL default limit, not a lowered boundary).
    cursor = "place-402"
    for i in range(cap):
        nxt = f"place-{404 + 2 * i}"
        from datetime import UTC as _UTC
        from datetime import datetime as _dt
        from datetime import timedelta as _td

        observed = (_dt(2026, 9, 6, 11, 0, tzinfo=_UTC) + _td(minutes=i)).isoformat()
        assert (
            _export_state(
                monkeypatch,
                capsys,
                tmp_path,
                state,
                _chain_page(None if i == 0 else cursor, nxt, observed),
                f"r5-chain-{i}.json",
            )
            == 0
        )
        capsys.readouterr()
        cursor = nxt

    # Mixed success+fatal status=degraded with ZERO progress at the cap head:
    # sticky stop recorded (rc0), not a page-cap rejection.
    mixed = _raw_page(
        input_cursor=cursor,
        next_cursor=cursor,
        exhausted=False,
        status="degraded",
        places=2,
        attempted=2,
        completed=1,
        tally={"naver_blog": {"ok": 1}, "naver_cafe": {"quota_exceeded": 1}},
        observed="2026-09-06T12:00:00+00:00",
    )
    rc = _export_state(monkeypatch, capsys, tmp_path, state, mixed, "r5-m.json")
    assert rc == 0
    capsys.readouterr()
    entries = {e["region"]: e for e in json.loads(state.read_text(encoding="utf-8"))["entries"]}
    assert entries["busan-haeundae"]["blocked"] == "auth_quota"
    assert entries["busan-haeundae"]["whole_region_complete"] is False
    assert entries["seoul-seongdong"]["next_after_place_id"] == "s-2"  # preserved
    stopped = state.read_bytes()

    # Later clean reset attempt unchanged: sticky rejection.
    clean_reset = _chain_page(cursor, f"{cursor}-next", "2026-09-06T13:00:00+00:00")
    rc = _export_state(monkeypatch, capsys, tmp_path, state, clean_reset, "r5-r.json")
    assert rc == 2
    assert "sticky" in json.loads(capsys.readouterr().out)["error"]
    assert state.read_bytes() == stopped

    # Older VALID fatal stays sticky too (fresh state, newer success first) —
    # proving STATE2 itself retained the old stop with the newer region's
    # cursor/time preserved, then scheduling STATE2 (not the first scenario).
    state2 = tmp_path / "state5b.json"
    assert (
        _export_state(
            monkeypatch,
            capsys,
            tmp_path,
            state2,
            _chain_page(None, "place-502", "2026-09-06T12:00:00+00:00"),
            "r5-n.json",
        )
        == 0
    )
    capsys.readouterr()
    older_fatal = _raw_page(
        region="incheon-yeonsu",
        input_cursor=None,
        next_cursor=None,
        exhausted=False,
        status="failed",
        ok=False,
        places=1,
        attempted=1,
        completed=0,
        deferred=0,
        stop="fatal_provider_failure",
        tally={"naver_blog": {"auth_missing": 1}},
        observed="2026-09-06T10:00:00+00:00",
    )
    rc = _export_state(monkeypatch, capsys, tmp_path, state2, older_fatal, "r5-of.json")
    assert rc == 0
    capsys.readouterr()
    state2_entries = {
        e["region"]: e for e in json.loads(state2.read_text(encoding="utf-8"))["entries"]
    }
    # STATE2 retained the OLD fatal stop…
    assert state2_entries["incheon-yeonsu"]["blocked"] == "auth_quota"
    assert state2_entries["incheon-yeonsu"]["observation_time"] == ("2026-09-06T10:00:00+00:00")
    # …while preserving the newer region's actual cursor and time.
    assert state2_entries["busan-haeundae"]["next_after_place_id"] == "place-502"
    assert state2_entries["busan-haeundae"]["observation_time"] == "2026-09-06T12:00:00+00:00"
    payload2 = _schedule(monkeypatch, capsys, state2, regions="busan-haeundae,seoul-seongdong")
    assert payload2["auth_quota_blocked"] is True
    assert payload2["planned_argv"] == []
    # The FIRST scenario's state still blocks globally too.
    payload = _schedule(monkeypatch, capsys, state)
    assert payload["auth_quota_blocked"] is True
    assert payload["planned_argv"] == []


def test_r6_unqualified_tail_then_valid_update(monkeypatch, capsys, tmp_path):
    _no_io(monkeypatch)
    state = tmp_path / "state6.json"
    prefix = _chain_page(None, "place-602", "2026-09-06T11:00:00+00:00")
    assert _export_state(monkeypatch, capsys, tmp_path, state, prefix, "r6-0.json") == 0
    capsys.readouterr()
    # Unqualified (marker-less legacy) tail at the head cursor, NEWER time.
    unqualified = _chain_page("place-602", "place-604", "2026-09-06T11:30:00+00:00")
    del unqualified["scope_contract"]
    assert _export_state(monkeypatch, capsys, tmp_path, state, unqualified, "r6-u.json") == 0
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert "sweep_pages" not in entry  # chain dropped, no poison
    # Later ordinary NEWER VALID update: exact rc0, strict reload succeeds.
    valid = _chain_page(None, "place-612", "2026-09-06T12:00:00+00:00")
    rc = _export_state(monkeypatch, capsys, tmp_path, state, valid, "r6-v.json")
    assert rc == 0
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert entry["sweep_pages"] == 1 and entry["whole_region_complete"] is False


def test_r7_newer_failed_retry_then_clean_success(monkeypatch, capsys, tmp_path):
    _no_io(monkeypatch)
    state = tmp_path / "state7.json"
    assert (
        _export_state(
            monkeypatch,
            capsys,
            tmp_path,
            state,
            _chain_page(None, "place-702", "2026-09-06T11:00:00+00:00"),
            "r7-0.json",
        )
        == 0
    )
    capsys.readouterr()
    # NEWER failed nonfatal unchanged-cursor retry at the pending head.
    failed_retry = _raw_page(
        input_cursor="place-702",
        next_cursor="place-702",
        exhausted=False,
        status="failed",
        ok=False,
        places=2,
        attempted=2,
        completed=0,
        deferred=0,
        stop="fatal_provider_failure",
        tally={"naver_blog": {"network_error": 2}},
        observed="2026-09-06T11:30:00+00:00",
    )
    rc = _export_state(monkeypatch, capsys, tmp_path, state, failed_retry, "r7-f.json")
    assert rc == 0
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert entry["sweep_pages"] == 1  # proven clean prefix retained
    assert entry["sweep_clean"] is True
    # NEWER clean success at the SAME pending cursor continues the prefix.
    resumed = _chain_page("place-702", "place-704", "2026-09-06T12:00:00+00:00")
    rc = _export_state(monkeypatch, capsys, tmp_path, state, resumed, "r7-c.json")
    assert rc == 0
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert entry["sweep_pages"] == 2
    assert entry["sweep_clean"] is True
    assert entry["next_after_place_id"] == "place-704"


def test_r8_nonclean_tally_taints_like_degraded(monkeypatch, capsys, tmp_path):
    """Raw ACCEPTED status=succeeded page with a REAL nonclean acquisition
    tally (network_error — a genuine collector failure category, not a
    fabricated quarantine enum) taints the chain exactly like degraded
    status; e.g. quarantine surfaces through the same degrading categories."""
    from datetime import UTC, datetime

    _no_io(monkeypatch)
    frozen = datetime(2026, 9, 6, 13, 0, tzinfo=UTC)
    monkeypatch.setattr(tool, "_now_utc", lambda: frozen)
    state = tmp_path / "state8.json"
    assert (
        _export_state(
            monkeypatch,
            capsys,
            tmp_path,
            state,
            _chain_page(None, "place-802", "2026-09-06T11:00:00+00:00"),
            "r8-0.json",
        )
        == 0
    )
    capsys.readouterr()
    # status=succeeded but tally carries a real degrading category: the bridge
    # accepts it (committed) and the chain must taint.
    quarantined = _raw_page(
        input_cursor="place-802",
        next_cursor="place-804",
        exhausted=False,
        status="succeeded",
        places=2,
        attempted=2,
        completed=1,
        tally={"naver_blog": {"ok": 1}, "naver_cafe": {"network_error": 1}},
        observed="2026-09-06T11:30:00+00:00",
    )
    rc = _export_state(monkeypatch, capsys, tmp_path, state, quarantined, "r8-q.json")
    assert rc == 0
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert entry["sweep_clean"] is False
    assert entry["next_after_place_id"] == "place-804"
    # Later clean terminal from that exact cursor: still not fresh.
    terminal = _chain_page(
        "place-804",
        "place-804",
        "2026-09-06T12:00:00+00:00",
        exhausted=True,
        places=0,
        attempted=0,
        completed=0,
    )
    assert _export_state(monkeypatch, capsys, tmp_path, state, terminal, "r8-t.json") == 0
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert entry["whole_region_complete"] is False  # taint kills completion
    assert entry["empty_scope"] == "window"  # honest: the page DID see 0 places
    payload = _schedule(monkeypatch, capsys, state)
    assert payload["region_states"]["busan-haeundae"] != "RECENTLY_COLLECTED"
    # A genuinely new clean null-start requalifies.
    assert (
        _export_state(
            monkeypatch,
            capsys,
            tmp_path,
            state,
            _chain_page(None, "place-902", "2026-09-06T12:30:00+00:00"),
            "r8-n.json",
        )
        == 0
    )
    capsys.readouterr()
    entry = json.loads(state.read_text(encoding="utf-8"))["entries"][0]
    assert entry["sweep_pages"] == 1 and entry["sweep_clean"] is True
