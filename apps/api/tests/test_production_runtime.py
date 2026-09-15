from __future__ import annotations

import asyncio
import socket
import threading
import time
from contextlib import closing

import psycopg2
import pytest
import uvicorn
from fastapi import FastAPI, WebSocket
from fastapi.testclient import TestClient
from websockets.sync.client import connect

from apps.api.app.core import database
from apps.api.app.core.config import Settings
from apps.api.app.core.request_limits import RequestBodyLimitMiddleware
from apps.api.app.main import create_app
from apps.api.app.routers import health
from apps.api.tests.local_database import local_test_dsn


def test_chunked_body_is_bounded_before_application():
    sent = []
    chunks = iter(
        [
            {"type": "http.request", "body": b"123", "more_body": True},
            {"type": "http.request", "body": b"456", "more_body": False},
        ]
    )

    async def receive():
        return next(chunks)

    async def send(message):
        sent.append(message)

    async def app(*args):
        pytest.fail("Oversized request reached application")

    asyncio.run(
        RequestBodyLimitMiddleware(app, max_bytes=5)(
            {"type": "http", "headers": [], "method": "POST", "path": "/"}, receive, send
        )
    )
    assert sent[0]["status"] == 413
    assert b"x-request-id" in dict(sent[0]["headers"])


def test_cors_write_preflight_and_body_rejection(monkeypatch):
    monkeypatch.setenv("CORS_ALLOW_ORIGINS", "https://client.example")
    client = TestClient(create_app())
    for method in ("PUT", "PATCH"):
        response = client.options(
            "/v1/me/plans",
            headers={
                "Origin": "https://client.example",
                "Access-Control-Request-Method": method,
                "Access-Control-Request-Headers": "authorization,idempotency-key",
            },
        )
        assert response.status_code == 200
    response = client.post(
        "/v1/docent/script", content=b"x" * 262145, headers={"Origin": "https://client.example"}
    )
    assert response.status_code == 413
    assert response.headers["access-control-allow-origin"] == "https://client.example"


def test_unexpected_error_is_safe_correlated_and_counted():
    app = create_app()

    @app.get("/test-failure")
    def fail():
        raise RuntimeError("secret database parameters")

    client = TestClient(app)
    response = client.get("/test-failure", headers={"X-Request-ID": "runtime-test"})
    assert response.status_code == 500
    assert response.headers["X-Request-ID"] == "runtime-test"
    assert "secret database" not in response.text
    metrics = client.get("/metrics").text
    assert any("/test-failure" in line and "500" in line for line in metrics.splitlines())


def test_readiness_is_cached_and_returns_unavailable(monkeypatch):
    calls = []
    monkeypatch.setattr(
        health, "build_readiness", lambda: calls.append(1) or {"status": "degraded"}
    )
    client = TestClient(create_app())
    assert client.get("/readyz").status_code == 503
    assert client.get("/readyz").status_code == 503
    assert len(calls) == 1


def test_operational_metrics_rejects_untrusted_peer(monkeypatch):
    monkeypatch.setenv("LALA_METRICS_TOKEN", "test-metrics-only")
    client = TestClient(create_app())
    monkeypatch.setattr(health, "get_settings", lambda: Settings(runtime_profile="api"))
    assert client.get("/metrics", headers={"X-Forwarded-For": "127.0.0.1"}).status_code == 403
    assert (
        client.get("/metrics", headers={"Authorization": "Bearer test-metrics-only"}).status_code
        == 200
    )


def test_local_pool_bounds_reuses_and_rolls_back(monkeypatch):
    dsn = local_test_dsn()
    database.close_database_pools()
    monkeypatch.setenv("LALA_DB_POOL_SIZE", "1")
    monkeypatch.setenv("LALA_DB_POOL_WAIT_MS", "20")
    monkeypatch.setenv("LALA_DB_STATEMENT_TIMEOUT_MS", "30")
    try:
        with closing(database.connect_db(dsn)) as connection:
            with connection.cursor() as cur:
                cur.execute("SELECT pg_backend_pid()")
                pid = cur.fetchone()[0]
                cur.execute("SELECT set_config('application_name', 'rollback-marker', true)")
            with pytest.raises(database.DatabaseBusyError):
                database.connect_db(dsn)
        with closing(database.connect_db(dsn)) as connection:
            with connection.cursor() as cur:
                cur.execute("SELECT pg_backend_pid(), current_setting('application_name')")
                current_pid, name = cur.fetchone()
                assert current_pid == pid
                assert name != "rollback-marker"
                with pytest.raises(psycopg2.errors.QueryCanceled):
                    cur.execute("SELECT pg_sleep(1)")
    finally:
        database.close_database_pools()


def test_installed_uvicorn_accepts_real_websocket_upgrade():
    app = FastAPI()

    @app.websocket("/runtime-probe")
    async def echo(websocket: WebSocket):
        await websocket.accept()
        await websocket.send_text(await websocket.receive_text())
        await websocket.close()

    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen(16)
        port = listener.getsockname()[1]
        server = uvicorn.Server(uvicorn.Config(app, log_level="error", lifespan="off"))
        thread = threading.Thread(target=server.run, kwargs={"sockets": [listener]}, daemon=True)
        thread.start()
        try:
            deadline = time.monotonic() + 5
            while not server.started and time.monotonic() < deadline:
                time.sleep(0.01)
            assert server.started
            with connect(f"ws://127.0.0.1:{port}/runtime-probe", proxy=None, open_timeout=3) as ws:
                ws.send("local-only")
                assert ws.recv(timeout=3) == "local-only"
        finally:
            server.should_exit = True
            thread.join(timeout=5)
            assert not thread.is_alive()
