"""Local PostgreSQL regressions; opt in using TEST_DB_DSN (loopback only)."""

from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from uuid import UUID, uuid4

import psycopg2
import pytest

from apps.api.app.core.config import Settings
from apps.api.app.core.errors import ServiceError
from apps.api.app.routers import community_chat as chat
from apps.api.app.services import community_service as community
from apps.api.app.services import local_signals_service as signals
from apps.api.app.services.community_chat_service import CommunityChatRepository
from apps.api.tests.local_database import local_test_dsn


@pytest.fixture
def database():
    dsn = local_test_dsn()
    issuer, subject = "https://audit.invalid", str(uuid4())
    settings = Settings(db_dsn=dsn, feature_flags={"LOCAL_SIGNALS_WRITE": True})
    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO identity.users (issuer, subject) VALUES (%s,%s) RETURNING id",
            (issuer, subject),
        )
        user_id = cur.fetchone()[0]
    yield settings, issuer, subject, user_id
    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        cur.execute(
            "DELETE FROM community.local_signals WHERE author_issuer=%s AND author_subject=%s",
            (issuer, subject),
        )
        cur.execute(
            "DELETE FROM community.chat_rooms WHERE created_by_issuer=%s AND created_by_subject=%s",
            (issuer, subject),
        )
        cur.execute("DELETE FROM identity.users WHERE issuer=%s AND subject=%s", (issuer, subject))


def values():
    return dict(
        kind="place_tip",
        source_language="ko",
        title="A local tip",
        body="A dated observation.",
        locality_level="district",
        locality_code="suwon:paldal",
        commercial_disclosure="none",
        observation_date=date(2026, 7, 26),
        aggregate_opt_in=False,
        place_links=[],
    )


def test_real_author_alias_and_comment_rollback(database, monkeypatch):
    settings, issuer, subject, user_id = database
    repo = community.CommunityRepository(settings)
    post = repo.create_post(issuer=issuer, subject=subject, title="Title", body="Body", tags=[])
    assert str(post["author_user_id"]) == str(user_id)
    comment = repo.create_comment(post_id=post["id"], issuer=issuer, subject=subject, body="hello")
    assert str(comment["author_user_id"]) == str(user_id)
    original = community._comment_payload

    def fail_response(row):
        raise ValueError("injected response failure")

    monkeypatch.setattr(community, "_comment_payload", fail_response)
    with pytest.raises(community.CommunityRepositoryUnavailable):
        repo.create_comment(
            post_id=post["id"], issuer=issuer, subject=subject, body="must rollback"
        )
    monkeypatch.setattr(community, "_comment_payload", original)
    with psycopg2.connect(settings.db_dsn) as conn, conn.cursor() as cur:
        cur.execute("SELECT body FROM community.post_comments WHERE post_id=%s", (str(post["id"]),))
        assert cur.fetchall() == [("hello",)]
    chat_repo = CommunityChatRepository(settings)
    room = chat_repo.create_room(
        name="Audit room", visibility="private", issuer=issuer, subject=subject
    )
    message = chat_repo.create_message(
        room_id=room["id"], issuer=issuer, subject=subject, body="Hello"
    )
    assert str(message["author_user_id"]) == str(user_id)
    assert chat_repo.authorized_actors(
        room_id=room["id"], actors=[(issuer, subject), (issuer, "absent")]
    ) == {f"{issuer}:{subject}"}


def test_local_signals_durable_concurrent_retry_submit_and_rollback(database, monkeypatch):
    settings, issuer, subject, _ = database

    def service():
        return signals.LocalSignalsService(
            signals.LocalSignalsRepository(settings), settings=settings
        )

    def create():
        return service().create_draft(
            issuer=issuer, subject=subject, values=values(), idempotency_key="draft"
        )

    with ThreadPoolExecutor(max_workers=4) as executor:
        results = list(executor.map(lambda _: create(), range(4)))
    assert all(row == results[0] for row in results)
    signals.reset_local_signals_state_for_tests()
    assert create() == results[0]
    # A fresh interpreter has no inherited repository or in-memory replay state.
    restarted = subprocess.run(
        [
            sys.executable,
            "-c",
            """
import json, os
from apps.api.app.core.config import Settings
from apps.api.app.services.local_signals_service import LocalSignalsRepository, LocalSignalsService
settings = Settings(db_dsn=os.environ['TEST_DB_DSN'], feature_flags={'LOCAL_SIGNALS_WRITE': True})
service = LocalSignalsService(LocalSignalsRepository(settings), settings=settings)
print(json.dumps(service.create_draft(issuer=os.environ['AUDIT_ISSUER'], subject=os.environ['AUDIT_SUBJECT'], values=json.loads(os.environ['AUDIT_VALUES']), idempotency_key='draft')))
""",
        ],
        env={
            **os.environ,
            "TEST_DB_DSN": settings.db_dsn,
            "AUDIT_ISSUER": issuer,
            "AUDIT_SUBJECT": subject,
            "AUDIT_VALUES": json.dumps(values(), default=str),
        },
        check=True,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert json.loads(restarted.stdout) == results[0]
    signal_id = UUID(results[0]["id"])

    def submit():
        return service().submit(
            signal_id=signal_id, issuer=issuer, subject=subject, idempotency_key="submit"
        )

    first = submit()
    signals.reset_local_signals_state_for_tests()
    assert submit() == first
    assert first["status"] == "submitted"
    with pytest.raises(ServiceError) as conflict:
        service().create_draft(
            issuer=issuer,
            subject=subject,
            values={**values(), "title": "Changed"},
            idempotency_key="draft",
        )
    assert conflict.value.code == "IDEMPOTENCY_KEY_REUSED"
    original = signals._mutation_payload
    monkeypatch.setattr(
        signals,
        "_mutation_payload",
        lambda row: (_ for _ in ()).throw(ValueError("response failure")),
    )
    with pytest.raises(ServiceError):
        service().create_draft(
            issuer=issuer, subject=subject, values=values(), idempotency_key="rollback"
        )
    monkeypatch.setattr(signals, "_mutation_payload", original)
    with psycopg2.connect(settings.db_dsn) as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT count(*) FROM community.local_signals WHERE author_issuer=%s AND author_subject=%s",
            (issuer, subject),
        )
        assert cur.fetchone()[0] == 1
        cur.execute(
            "SELECT count(*) FROM community.idempotency_keys WHERE actor_issuer=%s AND actor_subject=%s",
            (issuer, subject),
        )
        assert cur.fetchone()[0] == 2
    assert (
        service().create_draft(
            issuer=issuer, subject=subject, values=values(), idempotency_key="rollback"
        )["status"]
        == "draft"
    )
    with psycopg2.connect(settings.db_dsn) as conn, conn.cursor() as cur:
        cur.execute(
            "UPDATE identity.users SET status='deleting' WHERE issuer=%s AND subject=%s",
            (issuer, subject),
        )
    with pytest.raises(ServiceError) as denied:
        submit()
    assert denied.value.code == "ACCOUNT_DELETION_PENDING"


def test_chat_db_offload_is_responsive_and_cancellation_keeps_capacity(monkeypatch):
    async def run():
        entered, release = threading.Event(), threading.Event()
        slots = threading.BoundedSemaphore(1)
        monkeypatch.setattr(chat, "_db_work_slots", slots)

        def slow():
            entered.set()
            release.wait(2)

        task = asyncio.create_task(chat._run_db(slow))
        try:
            while not entered.is_set():
                await asyncio.sleep(0.001)
            ticks = 0
            for _ in range(5):
                await asyncio.sleep(0.001)
                ticks += 1
            assert ticks == 5
            task.cancel()
            with pytest.raises(asyncio.CancelledError):
                await task
            with pytest.raises(ServiceError):
                await chat._run_db(lambda: None)
        finally:
            release.set()
        for _ in range(100):
            if slots.acquire(blocking=False):
                slots.release()
                break
            await asyncio.sleep(0.005)
        else:
            pytest.fail("worker slot was not returned")

    asyncio.run(run())


def test_chat_slow_receiver_does_not_delay_healthy_socket(monkeypatch):
    class Socket:
        def __init__(self, slow=False):
            self.slow, self.sent, self.closed = slow, [], None

        async def accept(self):
            pass

        async def send_json(self, payload):
            if self.slow:
                await asyncio.sleep(10)
            self.sent.append(payload)

        async def close(self, code):
            self.closed = code

    async def run():
        monkeypatch.setattr(chat, "SEND_TIMEOUT_SECONDS", 0.03)
        manager = chat.ConnectionManager()
        room = uuid4()

        async def verify(room_id, actors):
            return {f"{issuer}:{subject}" for issuer, subject in actors}

        manager.attach_access_verifier(verify)
        slow, healthy = Socket(True), Socket()
        await manager.connect(slow, room_id=room, issuer="i", subject="slow")
        await manager.connect(healthy, room_id=room, issuer="i", subject="healthy")
        started = time.monotonic()
        pending = asyncio.create_task(manager.broadcast(room_id=room, payload={"hello": True}))
        await asyncio.sleep(0.01)
        assert healthy.sent == [{"hello": True}]
        await pending
        assert time.monotonic() - started < 0.2
        assert slow.closed == 1013
        assert manager.room_connection_count(room) == 1

    asyncio.run(run())


def test_fanout_scheduling_has_a_hard_pending_bound():
    from types import SimpleNamespace

    from apps.api.app.services.community_chat_fanout import (
        _MAX_PENDING_DELIVERIES,
        ChatFanoutBridge,
    )

    async def run():
        release = asyncio.Event()
        calls = []

        async def deliver(payload):
            calls.append(payload)
            await release.wait()

        bridge = ChatFanoutBridge(fetcher_factory=lambda: None, deliver=deliver)
        generation = SimpleNamespace(stop=threading.Event(), loop=asyncio.get_running_loop())
        bridge._generation = generation
        for index in range(_MAX_PENDING_DELIVERIES + 50):
            bridge._schedule_deliver(generation, {"id": index})
        await asyncio.sleep(0.01)
        assert len(calls) == _MAX_PENDING_DELIVERIES
        release.set()
        await asyncio.sleep(0.01)
        bridge._schedule_deliver(generation, {"id": "after-drain"})
        await asyncio.sleep(0.01)
        assert calls[-1] == {"id": "after-drain"}

    asyncio.run(run())


def test_inbound_chat_frame_keeps_event_loop_responsive(monkeypatch):
    async def run():
        entered, release = threading.Event(), threading.Event()

        class Service:
            def create_message(self, **kwargs):
                entered.set()
                release.wait(2)
                return {"id": str(uuid4()), "room_id": str(kwargs["room_id"])}

        class Socket:
            async def send_json(self, payload):
                pytest.fail(f"unexpected error frame: {payload}")

        monkeypatch.setattr(chat, "enforce_chat_message_rate_limit", lambda **kwargs: None)
        task = asyncio.create_task(
            chat._handle_chat_message(
                websocket=Socket(),
                room_id=uuid4(),
                issuer="i",
                subject="s",
                client_key="c",
                raw='{"body":"hello"}',
                service=Service(),
            )
        )
        try:
            for _ in range(100):
                if entered.is_set():
                    break
                await asyncio.sleep(0.001)
            assert entered.is_set()
            assert not task.done()
            await asyncio.sleep(0.01)
            assert not task.done()
        finally:
            release.set()
        await task

    asyncio.run(run())
