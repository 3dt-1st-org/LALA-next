"""V5-C — MOVE routing boundary (flag-gated seam). Acceptance proofs C1–C6 + D4.

This lane adds a flag-gated routing seam to ``travel_time_service``. Real Kakao/Naver
Directions are BLOCKED_EXTERNAL / V7 (contract §3a): in V5 the hook is present but the
Directions invocation NEVER fires, so the authoritative ETA is honestly null regardless
of the flag state. The offline Haversine estimate stays byte-for-byte unchanged.

Acceptance matrix (contract §V5-C C4):
  C1  Flag OFF by default            -> config + registry assertion
  C2  Haversine output unchanged     -> golden table on estimate_walking_minutes
  C3  ETA null when routing OFF      -> response fixture shows null ETA
  C4  No Directions call             -> zero live-routing invocations (source + runtime)
  C5  Existing callers unchanged     -> estimate_walking_minutes call site + values identical
  C6  openapi field additive         -> one new nullable field, no existing field mutated
  D4  Honest ETA unavailable when off-> null, not a guess
"""

from __future__ import annotations

import ast
import socket
from pathlib import Path
from types import SimpleNamespace

import pytest

from apps.api.app.core.config import Settings
from apps.api.app.core.feature_flags import (
    default_feature_flag_values,
    feature_flag,
    resolve_feature_flags,
)
from apps.api.app.main import create_app
from apps.api.app.services import planner_service, travel_time_service
from apps.api.app.services.travel_time_service import (
    estimate_walking_minutes,
    haversine_distance_m,
    live_routing_enabled,
    resolve_travel_time_authority_minutes,
)

SERVICE_SRC = Path(travel_time_service.__file__)
SLOT_SCHEMA = "DailyPlanSlot"
ADDITIVE_FIELD = "travel_time_authority_minutes"


# --- helpers ---------------------------------------------------------------------------


def _enable_live_routing(monkeypatch, *, enabled: bool) -> None:
    """Toggle the routing flag for BOTH the planner gate and the seam's internal read.

    The planner reads ``live_routing_enabled`` from its own namespace; the seam reads
    it from travel_time_service's namespace. Patching both keeps them consistent.
    """
    monkeypatch.setattr(planner_service, "live_routing_enabled", lambda: enabled)
    monkeypatch.setattr(travel_time_service, "live_routing_enabled", lambda: enabled)


def _candidate(place_id: str, *, lat: float, lng: float) -> dict:
    return {
        "place_id": place_id,
        "name": place_id,
        "category": "attraction",
        "lat": lat,
        "lng": lng,
        "is_indoor": False,
    }


class _NoOutboundSockets:
    """Context manager that fails the test if any outbound socket is opened."""

    def __enter__(self) -> _NoOutboundSockets:
        self._real_socket = socket.socket

        def _guard(*_args: object, **_kwargs: object) -> socket.socket:
            pytest.fail("V5-C seam opened an outbound socket (no live call permitted in V5).")

        socket.socket = _guard  # type: ignore[assignment]
        return self

    def __exit__(self, *_exc: object) -> None:
        socket.socket = self._real_socket  # type: ignore[assignment]


# ======================================================================================
# C1 — Flag OFF by default (config + registry assertion)
# ======================================================================================


def test_c1_flag_defaults_off_on_settings(monkeypatch):
    monkeypatch.delenv("LALA_ENABLE_LIVE_ROUTING", raising=False)
    assert Settings().enable_live_routing is False
    assert Settings.from_env().enable_live_routing is False


def test_c1_flag_defaults_off_in_registry():
    flag = feature_flag("LALA_ENABLE_LIVE_ROUTING")
    assert flag.default is False
    assert flag.env_name == "LALA_ENABLE_LIVE_ROUTING"
    # No env override -> registry resolves to the default False.
    assert resolve_feature_flags({})["LALA_ENABLE_LIVE_ROUTING"] is False
    assert default_feature_flag_values()["LALA_ENABLE_LIVE_ROUTING"] is False


def test_c1_live_routing_enabled_reads_flag(monkeypatch):
    monkeypatch.setattr(
        travel_time_service, "get_settings", lambda: SimpleNamespace(enable_live_routing=False)
    )
    assert live_routing_enabled() is False
    monkeypatch.setattr(
        travel_time_service, "get_settings", lambda: SimpleNamespace(enable_live_routing=True)
    )
    assert live_routing_enabled() is True


# ======================================================================================
# C2 — Haversine output unchanged (golden table on estimate_walking_minutes)
# ======================================================================================

# Frozen ground truth for the unchanged offline Haversine path. These exact ints must
# stay byte-for-byte identical pre/post V5-C; any drift fails the golden guard.
_HAVERSINE_GOLDEN: tuple[tuple[str, float, float, float, float, int, int | None], ...] = (
    ("seoul_station_to_gangnam", 37.5563, 126.9724, 37.4979, 127.0276, 8116, 121),
    ("gwanghwamun_to_gyeongbokgung", 37.5759, 126.9769, 37.5796, 126.9770, 412, 6),
    ("gangnam_to_coex", 37.4979, 127.0276, 37.5125, 127.0584, 3165, 47),
    ("short_walk_300m", 37.5665, 126.9780, 37.5692, 126.9780, 300, 4),
    ("same_point", 37.5, 127.0, 37.5, 127.0, 0, 0),
)


@pytest.mark.parametrize("case", _HAVERSINE_GOLDEN)
def test_c2_haversine_golden_unchanged(case):
    _name, lat1, lng1, lat2, lng2, exp_distance, exp_minutes = case
    assert haversine_distance_m(lat1, lng1, lat2, lng2) == exp_distance
    assert estimate_walking_minutes(lat1, lng1, lat2, lng2) == exp_minutes


def test_c2_invalid_coordinates_still_none():
    # (0,0) origin stays None — the offline contract is unchanged.
    assert estimate_walking_minutes(0, 0, 37.5, 127.0) is None


# ======================================================================================
# C3 / D4 — ETA null when routing OFF / honest unavailable (response fixture)
# ======================================================================================


def test_c3_authority_null_when_routing_off():
    # Seam itself: flag off -> honest None, never a guess.
    assert resolve_travel_time_authority_minutes(37.5563, 126.9724, 37.4979, 127.0276) is None


def test_c3_plan_fixture_shows_null_eta_when_seam_on(monkeypatch):
    # With the seam flag ON, the authority surface is emitted and honestly null in V5
    # (Directions are BLOCKED_EXTERNAL/V7 -> no live call -> no fabricated ETA).
    _enable_live_routing(monkeypatch, enabled=True)
    candidates = [
        _candidate("a", lat=37.5563, lng=126.9724),
        _candidate("b", lat=37.4979, lng=127.0276),
        _candidate("c", lat=37.5125, lng=127.0584),
        _candidate("d", lat=37.5796, lng=126.9770),
    ]
    slots = planner_service._daily_plan_slots(
        place_candidates=candidates,
        weather={"outdoor_status": "good", "forecast": [], "dust": {"grade": "good"}},
        language="en",
    )
    # Every slot carries the authority surface; every value is null (D4 honest unavailable).
    for slot in slots:
        assert ADDITIVE_FIELD in slot
        assert slot[ADDITIVE_FIELD] is None
        # First slot has no previous place -> null is also structurally correct.
    # A slot with a previous place still reports null (no live Directions in V5).
    assert slots[1][ADDITIVE_FIELD] is None


def test_d4_authority_never_guesses_in_either_flag_state(monkeypatch):
    coords = (37.5563, 126.9724, 37.4979, 127.0276)
    _enable_live_routing(monkeypatch, enabled=False)
    assert resolve_travel_time_authority_minutes(*coords) is None
    _enable_live_routing(monkeypatch, enabled=True)
    assert resolve_travel_time_authority_minutes(*coords) is None


# ======================================================================================
# C4 — No Directions call (zero live-routing invocations; source + runtime proof)
# ======================================================================================


def test_c4_seam_module_imports_no_http_client():
    """Source proof: the seam module imports no HTTP/Directions client.

    The docstrings legitimately mention "Kakao/Naver Directions" to document the V7
    boundary, so we assert on the import graph (AST) and module globals — not on
    prose substrings.
    """
    tree = ast.parse(SERVICE_SRC.read_text(encoding="utf-8"))
    http_modules = {"requests", "httpx", "urllib", "urllib.request", "aiohttp", "kakao", "naver"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                assert alias.name not in http_modules, f"V5-C seam imports {alias.name}"
        elif isinstance(node, ast.ImportFrom):
            assert (node.module or "") not in http_modules, f"V5-C seam imports {node.module}"
    # Runtime globals: no HTTP/Directions client object is reachable from the module.
    for banned in ("requests", "httpx", "aiohttp"):
        assert not hasattr(travel_time_service, banned)


def test_c4_no_outbound_socket_in_either_flag_state(monkeypatch):
    """Runtime proof: invoking the seam in either flag state opens no socket."""
    coords = (37.5563, 126.9724, 37.4979, 127.0276)
    _enable_live_routing(monkeypatch, enabled=False)
    with _NoOutboundSockets():
        assert resolve_travel_time_authority_minutes(*coords) is None
    _enable_live_routing(monkeypatch, enabled=True)
    with _NoOutboundSockets():
        assert resolve_travel_time_authority_minutes(*coords) is None


# ======================================================================================
# C5 — Existing callers unchanged (estimate_walking_minutes call site + values)
# ======================================================================================


def test_c5_flag_off_slot_has_no_authority_key(monkeypatch):
    # Flag OFF (default) -> slot key set is byte-for-byte pre-V5: the additive
    # authority key is omitted entirely, never present-and-null.
    _enable_live_routing(monkeypatch, enabled=False)
    candidates = [
        _candidate("a", lat=37.5563, lng=126.9724),
        _candidate("b", lat=37.4979, lng=127.0276),
    ]
    slots = planner_service._daily_plan_slots(
        place_candidates=candidates,
        weather={"outdoor_status": "good", "forecast": [], "dust": {"grade": "good"}},
        language="en",
    )
    for slot in slots:
        assert ADDITIVE_FIELD not in slot


def test_c5_haversine_value_at_call_site_is_identical(monkeypatch):
    # The estimate_walking_minutes call site is unchanged: the emitted
    # travel_time_from_previous_minutes equals a direct Haversine computation.
    _enable_live_routing(monkeypatch, enabled=False)
    a = _candidate("a", lat=37.5563, lng=126.9724)
    b = _candidate("b", lat=37.4979, lng=127.0276)
    slots = planner_service._daily_plan_slots(
        place_candidates=[a, b],
        weather={"outdoor_status": "good", "forecast": [], "dust": {"grade": "good"}},
        language="en",
    )
    assert slots[1]["travel_time_from_previous_minutes"] == estimate_walking_minutes(
        a["lat"], a["lng"], b["lat"], b["lng"]
    )


# ======================================================================================
# C6 — openapi field additive (one new nullable field; no existing field mutated)
# ======================================================================================


def test_c6_openapi_authority_field_is_additive_and_nullable():
    schema = create_app().openapi()["components"]["schemas"][SLOT_SCHEMA]["properties"]
    # The one additive V5-C field exists and is nullable.
    assert ADDITIVE_FIELD in schema
    assert schema[ADDITIVE_FIELD] == {
        "anyOf": [{"type": "integer"}, {"type": "null"}],
        "description": (
            "Authoritative travel-time from previous slot (Directions ETA), "
            "or null when live routing is off/unavailable."
        ),
    }
    # It is the TRAVEL-TIME authority, distinct from the DWELL field stay_duration_minutes.
    assert ADDITIVE_FIELD != "stay_duration_minutes"
    # Pre-existing travel-time + dwell fields are intact (not renamed/removed/retyped).
    assert schema["travel_time_from_previous_minutes"]["anyOf"] == [
        {"type": "integer"},
        {"type": "null"},
    ]
    assert schema["stay_duration_minutes"]["anyOf"] == [
        {"type": "integer"},
        {"type": "null"},
    ]
