"""Atomic paid-generation budgets and single-flight cache.

Postgres session locks fence live owners even after a lease deadline: an expired
lease is reclaimed only after its owner's connection has gone away. Providers
have their own bounded timeouts. No configured DB failure falls back to memory.
"""

from __future__ import annotations

import base64
import hashlib
import json
from collections.abc import Callable
from contextlib import closing, contextmanager
from contextvars import ContextVar
from threading import RLock
from time import monotonic, sleep, time
from typing import Any

from apps.api.app.core.config import get_settings
from apps.api.app.core.errors import ApiError

paid_actor: ContextVar[str] = ContextVar("paid_actor", default="internal")
_lock = RLock()
_budgets: dict[tuple[str, int], list[int]] = {}
_cache: dict[str, tuple[float, bytes]] = {}
_active: set[str] = set()
_MAX_RESULT_BYTES = 2 * 1024 * 1024
_MAX_CACHE_BYTES = 16 * 1024 * 1024
_LEASE_SECONDS = 120
_WAIT_SECONDS = 25


def _error(code: str, status: int = 429) -> ApiError:
    return ApiError(
        status_code=status,
        code=code,
        message="Paid generation is temporarily unavailable. Please retry later.",
        retryable=True,
    )


def _connect():
    from apps.api.app.core.database import connect_db

    return connect_db(get_settings().db_dsn, connect_timeout=3)


@contextmanager
def _generation_connection(key):
    # Followers return the pooled connection before waiting so they cannot
    # starve the leader's retrieval queries of database connections.
    deadline = monotonic() + _WAIT_SECONDS
    while True:
        with closing(_connect()) as conn:
            try:
                with conn, conn.cursor() as cur:
                    cur.execute("SELECT pg_try_advisory_lock(hashtextextended(%s, 1))", (key,))
                    acquired = cur.fetchone()[0]
            except BaseException:
                # An interrupted acquire/commit may have taken the session
                # lock even if the acknowledgement did not reach this process.
                conn.discard()
                raise
            if acquired:
                try:
                    yield conn
                finally:
                    # Returning a pooled connection does not end its session.
                    # If cleanup fails, physically discard it so its lock can
                    # never leak to the next borrower.
                    try:
                        conn.rollback()
                        with conn, conn.cursor() as cur:
                            cur.execute(
                                "SELECT pg_advisory_unlock(hashtextextended(%s, 1))", (key,)
                            )
                    except BaseException:
                        conn.discard()
                        raise
                return
        if monotonic() >= deadline:
            raise _error("PAID_GENERATION_IN_PROGRESS")
        sleep(0.05)


def _limits() -> tuple[int, int, int, int, int]:
    s = get_settings()
    return (
        max(1, s.paid_daily_request_limit),
        max(1, s.paid_daily_unit_limit),
        max(1, min(s.paid_global_concurrency, 100)),
        max(1, min(s.paid_cache_ttl_sec, 86400)),
        max(1, min(s.paid_memory_max_entries, 4096)),
    )


def _encode(value: object) -> bytes:
    data = json.dumps(
        {"bytes": base64.b64encode(value).decode()}
        if isinstance(value, bytes)
        else {"json": value},
        ensure_ascii=False,
    ).encode()
    if len(data) > _MAX_RESULT_BYTES:
        raise _error("PAID_RESULT_TOO_LARGE", 503)
    return data


def _decode(data: bytes):
    value = json.loads(data)
    return base64.b64decode(value["bytes"]) if "bytes" in value else value["json"]


def run_paid_generation(key: str, units: int, generate: Callable[[], Any]) -> Any:
    """Charge conservative cost units once on a cache miss (failed calls count).

    Keys contain normalized request context and provider/prompt versions. Request
    budgets count actual generation attempts; per-minute HTTP limits count hits.
    """
    key = hashlib.sha256(key.encode()).hexdigest()
    actor = hashlib.sha256(paid_actor.get().encode()).hexdigest()
    units = max(1, units)
    if get_settings().db_dsn:
        try:
            return _run_db(key, actor, units, generate)
        except ApiError:
            raise
        except Exception as exc:
            raise _error("PAID_CONTROL_UNAVAILABLE", 503) from exc
    return _run_memory(key, actor, units, generate)


def _prune_memory(now: float, day: int) -> None:
    for key, value in list(_cache.items()):
        if value[0] <= now:
            del _cache[key]
    for key in list(_budgets):
        if key[1] != day:
            del _budgets[key]


def _run_memory(key, actor, units, generate):
    requests, unit_limit, concurrency, ttl, capacity = _limits()
    deadline = monotonic() + _WAIT_SECONDS
    while True:
        with _lock:
            day = int(time() // 86400)
            _prune_memory(monotonic(), day)
            if key in _cache:
                return _decode(_cache[key][1])
            if key not in _active:
                if len(_active) >= concurrency:
                    raise _error("PAID_CONCURRENCY_LIMITED")
                if (
                    len(_cache) + len(_active) >= capacity
                    or sum(len(item[1]) for item in _cache.values())
                    + (len(_active) + 1) * _MAX_RESULT_BYTES
                    > _MAX_CACHE_BYTES
                ):
                    raise _error("PAID_CONTROL_CAPACITY", 503)
                budget_key = (actor, day)
                if budget_key not in _budgets and len(_budgets) >= capacity:
                    raise _error("PAID_CONTROL_CAPACITY", 503)
                count, used = _budgets.get(budget_key, [0, 0])
                if count >= requests or used + units > unit_limit:
                    raise _error("PAID_DAILY_LIMITED")
                _budgets[budget_key] = [count + 1, used + units]
                _active.add(key)
                break
        if monotonic() >= deadline:
            raise _error("PAID_GENERATION_IN_PROGRESS")
        sleep(0.05)
    try:
        value = generate()
        data = _encode(value)
        with _lock:
            if sum(len(item[1]) for item in _cache.values()) + len(data) > _MAX_CACHE_BYTES:
                raise _error("PAID_CONTROL_CAPACITY", 503)
            _cache[key] = (monotonic() + ttl, data)
        return value
    finally:
        with _lock:
            _active.discard(key)


def _run_db(key, actor, units, generate):
    requests, unit_limit, concurrency, ttl, _ = _limits()
    with _generation_connection(key) as conn:
        # The owner holds a session lock, but never an open transaction during
        # provider calls. Cleanup above releases the lock before pool return.
        with conn, conn.cursor() as cur:
            cur.execute("SELECT pg_advisory_xact_lock(714031204)")
            cur.execute(
                "SELECT response FROM ops.api_paid_generations WHERE key=%s "
                "AND response IS NOT NULL AND expires_at > clock_timestamp()",
                (key,),
            )
            cached = cur.fetchone()
            if cached:
                return _decode(bytes(cached[0]))
            cur.execute(
                "DELETE FROM ops.api_paid_generations WHERE expires_at <= clock_timestamp() "
                "AND (response IS NOT NULL OR pg_try_advisory_xact_lock(hashtextextended(key, 1)))"
            )
            cur.execute(
                "DELETE FROM ops.api_paid_budgets WHERE day < (clock_timestamp() AT TIME ZONE 'UTC')::date"
            )
            cur.execute("SELECT count(*) FROM ops.api_paid_generations WHERE response IS NULL")
            if cur.fetchone()[0] >= concurrency:
                raise _error("PAID_CONCURRENCY_LIMITED")
            cur.execute(
                "INSERT INTO ops.api_paid_budgets(actor,day,requests,units) "
                "VALUES(%s,(clock_timestamp() AT TIME ZONE 'UTC')::date,1,%s) "
                "ON CONFLICT(actor,day) DO UPDATE SET requests=ops.api_paid_budgets.requests+1, "
                "units=ops.api_paid_budgets.units+EXCLUDED.units "
                "WHERE ops.api_paid_budgets.requests < %s AND ops.api_paid_budgets.units+EXCLUDED.units <= %s "
                "RETURNING requests",
                (actor, units, requests, unit_limit),
            )
            if units > unit_limit or cur.fetchone() is None:
                raise _error("PAID_DAILY_LIMITED")
            cur.execute(
                "INSERT INTO ops.api_paid_generations(key,expires_at) "
                "VALUES(%s,clock_timestamp()+%s*interval '1 second') "
                "ON CONFLICT(key) DO UPDATE SET response=NULL, expires_at=EXCLUDED.expires_at",
                (key, _LEASE_SECONDS),
            )
        try:
            value = generate()
            data = _encode(value)
            with conn, conn.cursor() as cur:
                cur.execute(
                    "UPDATE ops.api_paid_generations SET response=%s, "
                    "expires_at=clock_timestamp()+%s*interval '1 second' WHERE key=%s",
                    (data, ttl, key),
                )
            return value
        except BaseException:
            with conn, conn.cursor() as cur:
                cur.execute("DELETE FROM ops.api_paid_generations WHERE key=%s", (key,))
            raise


def enforce_db_window(key: str, limit: int) -> bool:
    """Atomic per-minute request admission; fail closed on storage failure."""
    try:
        with closing(_connect()) as conn, conn, conn.cursor() as cur:
            cur.execute("DELETE FROM ops.api_paid_windows WHERE expires_at <= clock_timestamp()")
            cur.execute(
                "INSERT INTO ops.api_paid_windows(key,count,expires_at) "
                "VALUES(%s,1,clock_timestamp()+interval '60 seconds') "
                "ON CONFLICT(key) DO UPDATE SET count=ops.api_paid_windows.count+1 "
                "WHERE ops.api_paid_windows.count < %s RETURNING count",
                (key, max(1, limit)),
            )
            return cur.fetchone() is not None
    except Exception as exc:
        raise _error("PAID_CONTROL_UNAVAILABLE", 503) from exc


def reset_paid_state_for_tests():
    with _lock:
        _budgets.clear()
        _cache.clear()
        _active.clear()
    paid_actor.set("internal")
