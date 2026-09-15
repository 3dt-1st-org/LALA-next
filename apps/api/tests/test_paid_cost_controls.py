from __future__ import annotations

import hashlib
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path
from time import sleep

import pytest
from pydantic import ValidationError
from starlette.requests import Request

from apps.api.app.core import auth, rate_limit
from apps.api.app.core.config import Settings
from apps.api.app.core.errors import ApiError
from apps.api.app.schemas.docent import DocentAudioRequest, DocentScriptRequest
from apps.api.app.schemas.planning import SavePlanRequest, TripPreferenceOverridePayload
from apps.api.app.services import docent_service
from apps.api.app.services import paid_cost_control as cost
from apps.api.tests.local_database import local_test_dsn
from apps.api.tests.local_database import validate_local_test_dsn as _validate_local_test_dsn


@pytest.fixture(autouse=True)
def isolated(monkeypatch):
    settings = Settings(guest_access=True, paid_daily_request_limit=2, paid_daily_unit_limit=50000)
    for module in (cost, rate_limit, auth, docent_service):
        monkeypatch.setattr(module, "get_settings", lambda: settings)
    cost.reset_paid_state_for_tests()
    rate_limit.reset_rate_limit_state_for_tests()
    yield
    cost.reset_paid_state_for_tests()
    rate_limit.reset_rate_limit_state_for_tests()


def request(mode="public", peer="127.0.0.1", forwarded="1.1.1.1"):
    result = Request(
        {
            "type": "http",
            "client": (peer, 1234),
            "headers": [
                (b"cf-connecting-ip", forwarded.encode()),
                (b"x-forwarded-for", forwarded.encode()),
            ],
        }
    )
    result.state.identity = auth.RequestIdentity(mode=mode, issuer="issuer", subject="actor")
    return result


@pytest.mark.parametrize("mode", ["public", "static", "oauth"])
def test_all_auth_modes_limit_and_ignore_spoofed_headers(mode):
    rate_limit.enforce_public_contest_paid_route_limit(
        request(mode), route_key="audio", limit_per_minute=1
    )
    with pytest.raises(ApiError, match="Too many") as exc:
        rate_limit.enforce_public_contest_paid_route_limit(
            request(mode, forwarded="9.9.9.9"), route_key="audio", limit_per_minute=1
        )
    assert exc.value.status_code == 429


@pytest.mark.parametrize("mode", ["oauth", "static"])
def test_authenticated_budget_not_reset_by_peer_change(mode):
    rate_limit.enforce_public_contest_paid_route_limit(
        request(mode), route_key="audio", limit_per_minute=1
    )
    with pytest.raises(ApiError):
        rate_limit.enforce_public_contest_paid_route_limit(
            request(mode, peer="8.8.8.8"), route_key="audio", limit_per_minute=1
        )


def test_memory_rate_window_capacity_and_expiry(monkeypatch):
    monkeypatch.setattr(rate_limit, "get_settings", lambda: Settings(paid_memory_max_entries=2))
    now = [0.0]
    monkeypatch.setattr(rate_limit, "monotonic", lambda: now[0])
    assert rate_limit._window_allows(("a", "1"), 1)
    assert rate_limit._window_allows(("a", "2"), 1)
    assert not rate_limit._window_allows(("a", "3"), 1)
    now[0] = 61
    assert rate_limit._window_allows(("a", "3"), 1)
    assert len(rate_limit._windows) == 1


def test_daily_request_and_unit_limits_cache_hits_do_not_charge():
    assert cost.run_paid_generation("a", 10, lambda: b"one") == b"one"
    assert cost.run_paid_generation("a", 10, lambda: pytest.fail("duplicate")) == b"one"
    cost.run_paid_generation("b", 10, lambda: "two")
    with pytest.raises(ApiError) as exc:
        cost.run_paid_generation("c", 10, lambda: pytest.fail("over budget"))
    assert exc.value.code == "PAID_DAILY_LIMITED"
    cost.paid_actor.set("other actor")
    with pytest.raises(ApiError):
        cost.run_paid_generation("d", 50001, lambda: pytest.fail("over units"))


def test_memory_cache_ttl_and_capacity(monkeypatch):
    monkeypatch.setattr(
        cost, "get_settings", lambda: Settings(paid_memory_max_entries=1, paid_cache_ttl_sec=1)
    )
    now = [0.0]
    monkeypatch.setattr(cost, "monotonic", lambda: now[0])
    cost.run_paid_generation("a", 1, lambda: "a")
    with pytest.raises(ApiError) as exc:
        cost.run_paid_generation("b", 1, lambda: pytest.fail("full"))
    assert exc.value.code == "PAID_CONTROL_CAPACITY"
    now[0] = 2
    cost.run_paid_generation("b", 1, lambda: "b")
    assert len(cost._cache) == 1
    now[0] = 86402
    monkeypatch.setattr(cost, "time", lambda: 86400 * 90000)
    cost.paid_actor.set("new")
    cost.run_paid_generation("c", 1, lambda: "c")
    assert len(cost._budgets) == 1


def test_concurrent_audio_uses_one_fake_call(monkeypatch):
    calls = []

    def fake(body):
        calls.append(body.script)
        sleep(0.1)
        return b"fake mp3"

    monkeypatch.setattr(docent_service.speech_service, "synthesize_docent_audio", fake)
    body = DocentAudioRequest(script="Hello")
    with ThreadPoolExecutor(max_workers=5) as executor:
        results = list(executor.map(lambda _: docent_service.generate_audio(body), range(5)))
    assert results == [b"fake mp3"] * 5
    assert calls == ["Hello"]


def test_script_cache_covers_paid_retrieval_and_versions(monkeypatch):
    calls = []
    monkeypatch.setattr(docent_service.ai_service, "live_ai_enabled", lambda: True)
    monkeypatch.setattr(
        docent_service,
        "_generate_script",
        lambda body: calls.append(body.place_id) or {"script": "hello"},
    )
    body = DocentScriptRequest(place_id="one", category="attraction", place_name="Park")
    with ThreadPoolExecutor(max_workers=4) as executor:
        results = list(executor.map(lambda _: docent_service.generate_script(body), range(4)))
    assert results == [{"script": "hello"}] * 4
    assert calls == ["one"]
    monkeypatch.setattr(
        docent_service, "get_settings", lambda: Settings(rag_embedding_generation=2)
    )
    docent_service.generate_script(body)
    assert calls == ["one", "one"]


@pytest.mark.parametrize(
    "factory,payload",
    [
        (DocentAudioRequest, {"script": "x" * 12001}),
        (DocentScriptRequest, {"place_id": "x" * 129, "category": "attraction"}),
        (DocentScriptRequest, {"place_id": "x", "category": "attraction", "address": "x" * 513}),
        (SavePlanRequest, {"plan": {"slots": [None] * 129}}),
        (SavePlanRequest, {"plan": {"text": "x" * 12001}}),
        (SavePlanRequest, {"plan": {str(n): "한" * 12000 for n in range(5)}}),
        (TripPreferenceOverridePayload, {"companions": ["solo"] * 8}),
    ],
)
def test_bounded_inputs(factory, payload):
    with pytest.raises(ValidationError):
        factory(**payload)


def test_plan_depth_and_compatible_shape():
    plan = {"version": 1, "slots": [{"place": {"id": "p"}}], "extension": True}
    assert SavePlanRequest(plan=plan).plan == plan
    for _ in range(14):
        plan = {"nested": plan}
    with pytest.raises(ValidationError):
        SavePlanRequest(plan=plan)


def test_configured_db_fails_closed(monkeypatch):
    monkeypatch.setattr(cost, "get_settings", lambda: Settings(db_dsn="configured"))
    monkeypatch.setattr(cost, "_connect", lambda: (_ for _ in ()).throw(RuntimeError("offline")))
    with pytest.raises(ApiError) as exc:
        cost.run_paid_generation("a", 1, lambda: pytest.fail("must not call"))
    assert exc.value.code == "PAID_CONTROL_UNAVAILABLE"
    assert not cost._budgets


@pytest.fixture
def db(monkeypatch):
    dsn = local_test_dsn()
    monkeypatch.setenv("TEST_DB_DSN", dsn)
    import psycopg2

    with closing(psycopg2.connect(dsn)) as conn, conn, conn.cursor() as cur:
        cur.execute(Path("sql/canonical/071_api_cost_controls.sql").read_text())
        cur.execute("TRUNCATE ops.api_paid_budgets, ops.api_paid_generations, ops.api_paid_windows")
    monkeypatch.setattr(
        cost, "get_settings", lambda: Settings(db_dsn=dsn, paid_daily_request_limit=1)
    )
    return dsn


def test_db_budget_survives_local_reset(db):
    assert cost.run_paid_generation("one", 1, lambda: b"one") == b"one"
    cost.reset_paid_state_for_tests()
    assert cost.run_paid_generation("one", 1, lambda: pytest.fail("duplicate")) == b"one"
    with pytest.raises(ApiError) as exc:
        cost.run_paid_generation("two", 1, lambda: pytest.fail("over budget"))
    assert exc.value.code == "PAID_DAILY_LIMITED"


def test_db_shared_process_single_flight_and_restart(db):
    script = """
import os, time
from apps.api.app.core.config import Settings
from apps.api.app.services import paid_cost_control as c
c.get_settings = lambda: Settings(db_dsn=os.environ["TEST_DB_DSN"], paid_daily_request_limit=1)
def fake():
    print("PAID", flush=True)
    time.sleep(.2)
    return b"fake audio"
assert c.run_paid_generation("process-key", 10, fake) == b"fake audio"
"""
    children = [
        subprocess.Popen(
            [sys.executable, "-c", script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        for _ in range(3)
    ]
    outputs = [child.communicate(timeout=30) for child in children]
    assert all(child.returncode == 0 for child in children), outputs
    assert sum(out.count("PAID") for out, _ in outputs) == 1
    restart = subprocess.run(
        [sys.executable, "-c", script], capture_output=True, text=True, timeout=30
    )
    assert restart.returncode == 0, restart.stderr
    assert "PAID" not in restart.stdout


def test_db_concurrency_and_abandoned_lease(db, monkeypatch):
    import psycopg2

    monkeypatch.setattr(
        cost, "get_settings", lambda: Settings(db_dsn=db, paid_global_concurrency=1)
    )
    stale_key = hashlib.sha256(b"dead-owner").hexdigest()
    with closing(psycopg2.connect(db)) as owner:
        with owner, owner.cursor() as cur:
            cur.execute("SELECT pg_advisory_lock(hashtextextended(%s,1))", (stale_key,))
            cur.execute(
                "INSERT INTO ops.api_paid_generations(key,expires_at) VALUES(%s,now()-interval '1 second')",
                (stale_key,),
            )
        with pytest.raises(ApiError) as exc:
            cost.run_paid_generation("new", 1, lambda: pytest.fail("live lease"))
        assert exc.value.code == "PAID_CONCURRENCY_LIMITED"
    assert cost.run_paid_generation("new", 1, lambda: "reclaimed") == "reclaimed"


def test_db_atomic_request_window(db):
    with ThreadPoolExecutor(max_workers=4) as executor:
        admitted = list(executor.map(lambda _: cost.enforce_db_window("actor", 2), range(8)))
    assert sum(admitted) == 2


@pytest.mark.parametrize("mode", ["public", "static", "oauth"])
def test_daily_budget_bound_to_validated_actor_in_every_mode(mode):
    for index in range(2):
        rate_limit.enforce_public_contest_paid_route_limit(
            request(mode, forwarded=f"9.9.9.{index}"), route_key="audio", limit_per_minute=100
        )
        cost.run_paid_generation(f"request-{index}", 1, lambda: b"fake")
    rate_limit.enforce_public_contest_paid_route_limit(
        request(mode, forwarded="8.8.8.8"), route_key="audio", limit_per_minute=100
    )
    with pytest.raises(ApiError) as exc:
        cost.run_paid_generation("third", 1, lambda: pytest.fail("over actor budget"))
    assert exc.value.code == "PAID_DAILY_LIMITED"


def test_memory_global_concurrency_across_actors(monkeypatch):
    from threading import Event

    monkeypatch.setattr(cost, "get_settings", lambda: Settings(paid_global_concurrency=1))
    started, finish = Event(), Event()

    def held():
        started.set()
        assert finish.wait(3)
        return "done"

    with ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(cost.run_paid_generation, "held", 1, held)
        assert started.wait(3)
        try:
            cost.paid_actor.set("other")
            with pytest.raises(ApiError) as exc:
                cost.run_paid_generation("other", 1, lambda: pytest.fail("over concurrency"))
            assert exc.value.code == "PAID_CONCURRENCY_LIMITED"
        finally:
            finish.set()
        assert future.result() == "done"


def test_db_daily_budget_enforced_in_fresh_process(db):
    cost.run_paid_generation("first-process", 1, lambda: "done")
    script = """
import os
from apps.api.app.core.config import Settings
from apps.api.app.core.errors import ApiError
from apps.api.app.services import paid_cost_control as c
c.get_settings = lambda: Settings(db_dsn=os.environ["TEST_DB_DSN"], paid_daily_request_limit=1)
def forbidden():
    raise AssertionError("must not invoke paid client")
try:
    c.run_paid_generation("fresh-process", 1, forbidden)
except ApiError as exc:
    assert exc.code == "PAID_DAILY_LIMITED"
else:
    raise AssertionError("budget reset after restart")
"""
    child = subprocess.run(
        [sys.executable, "-c", script], capture_output=True, text=True, timeout=15
    )
    assert child.returncode == 0, child.stderr


@pytest.mark.parametrize(
    "dsn",
    [
        "postgresql://user@127.0.0.1/local",
        "postgresql://user@[::1]/local",
        "host=localhost dbname=local",
    ],
)
def test_destructive_db_fixture_accepts_only_explicit_loopback(dsn):
    _validate_local_test_dsn(dsn)


@pytest.mark.parametrize(
    "dsn",
    [
        "postgresql://user@remote.example/production",
        "postgresql://user@192.168.1.1/local",
        "host=127.0.0.1 hostaddr=8.8.8.8 dbname=local",
        "host=127.0.0.1,remote.example dbname=local",
        "dbname=local",
        "service=production host=127.0.0.1",
        "host=/tmp dbname=local",
    ],
)
def test_destructive_db_fixture_rejects_unsafe_target_before_connect(dsn):
    with pytest.raises(ValueError):
        _validate_local_test_dsn(dsn)


def _admit_write_lane(lane, peer):
    kwargs = dict(route_key=lane, actor_key="validated:actor", limit_per_minute=1)
    if lane == "chat":
        rate_limit.enforce_chat_message_rate_limit(client_key=peer, **kwargs)
    elif lane == "community":
        rate_limit.enforce_community_write_rate_limit(request(peer=peer), **kwargs)
    else:
        rate_limit.enforce_local_signals_rate_limit(request(peer=peer), **kwargs)


@pytest.mark.parametrize("lane", ["community", "local", "chat"])
def test_all_write_lanes_share_db_actor_window(db, monkeypatch, lane):
    monkeypatch.setattr(rate_limit, "get_settings", lambda: Settings(db_dsn=db))
    _admit_write_lane(lane, "127.0.0.1")
    rate_limit.reset_rate_limit_state_for_tests()
    with pytest.raises(ApiError) as exc:
        _admit_write_lane(lane, "127.0.0.2")
    assert exc.value.status_code == 429
    assert not rate_limit._windows


@pytest.mark.parametrize("lane", ["community", "local", "chat"])
def test_all_write_lanes_fail_closed_with_configured_db(monkeypatch, lane):
    monkeypatch.setattr(rate_limit, "get_settings", lambda: Settings(db_dsn="configured"))
    monkeypatch.setattr(cost, "_connect", lambda: (_ for _ in ()).throw(RuntimeError("offline")))
    with pytest.raises(ApiError) as exc:
        _admit_write_lane(lane, "127.0.0.1")
    assert exc.value.status_code == 503
    assert not rate_limit._windows


@pytest.mark.parametrize("failure", [False, True])
def test_db_generation_lock_released_on_success_and_exception(db, failure):
    import psycopg2

    key = hashlib.sha256(b"lock-cleanup").hexdigest()

    def generate():
        if failure:
            raise ValueError("fake provider failure")
        return "done"

    if failure:
        with pytest.raises(ApiError):
            cost.run_paid_generation("lock-cleanup", 1, generate)
    else:
        cost.run_paid_generation("lock-cleanup", 1, generate)
    with closing(psycopg2.connect(db)) as conn, conn, conn.cursor() as cur:
        cur.execute("SELECT pg_try_advisory_lock(hashtextextended(%s,1))", (key,))
        assert cur.fetchone()[0] is True


@pytest.mark.parametrize("failure_stage", ["acquire", "rollback", "unlock"])
def test_failed_session_lock_cleanup_discards_physical_connection(monkeypatch, failure_stage):
    class FakeLease:
        discarded = False
        closed = False

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def cursor(self):
            return self

        def execute(self, sql, params):
            if failure_stage == "acquire" and "try_advisory" in sql:
                raise RuntimeError("interrupted acquire")
            if failure_stage == "unlock" and "advisory_unlock" in sql:
                raise RuntimeError("interrupted unlock")

        def fetchone(self):
            return (True,)

        def rollback(self):
            if failure_stage == "rollback":
                raise RuntimeError("interrupted rollback")

        def discard(self):
            self.discarded = True

        def close(self):
            self.closed = True

    lease = FakeLease()
    monkeypatch.setattr(cost, "_connect", lambda: lease)
    with pytest.raises(RuntimeError):
        with cost._generation_connection("key"):
            pass
    assert lease.discarded and lease.closed


def test_script_paid_cache_key_versions_model_and_prompt(monkeypatch):
    keys = []
    monkeypatch.setattr(docent_service.ai_service, "live_ai_enabled", lambda: True)
    monkeypatch.setattr(cost, "run_paid_generation", lambda key, units, generate: keys.append(key))
    body = DocentScriptRequest(place_id="p", category="attraction", place_name="Park")
    docent_service.generate_script(body)
    monkeypatch.setattr(
        docent_service, "get_settings", lambda: Settings(openai_docent_model="new-model")
    )
    docent_service.generate_script(body)
    monkeypatch.setattr(docent_service, "_DOCENT_PROMPT_VERSION", "docent-v2")
    docent_service.generate_script(body)
    assert len(set(keys)) == 3


def test_all_write_lanes_keep_window_in_fresh_process(db, monkeypatch):
    monkeypatch.setattr(rate_limit, "get_settings", lambda: Settings(db_dsn=db))
    for lane in ("community", "local", "chat"):
        _admit_write_lane(lane, "127.0.0.1")
    script = """
import os
from starlette.requests import Request
from apps.api.app.core.config import Settings
from apps.api.app.core.errors import ApiError
from apps.api.app.core import rate_limit as r
from apps.api.app.services import paid_cost_control as c
r.get_settings = c.get_settings = lambda: Settings(db_dsn=os.environ["TEST_DB_DSN"])
request = Request({"type": "http", "client": ("127.0.0.2", 1), "headers": []})
for lane in ("community", "local", "chat"):
    kwargs = dict(route_key=lane, actor_key="validated:actor", limit_per_minute=1)
    try:
        if lane == "chat":
            r.enforce_chat_message_rate_limit(client_key=str(request.client.host), **kwargs)
        elif lane == "community":
            r.enforce_community_write_rate_limit(request, **kwargs)
        else:
            r.enforce_local_signals_rate_limit(request, **kwargs)
    except ApiError as exc:
        assert exc.status_code == 429
    else:
        raise AssertionError(lane + " window reset across processes")
"""
    child = subprocess.run(
        [sys.executable, "-c", script], capture_output=True, text=True, timeout=15
    )
    assert child.returncode == 0, child.stderr
