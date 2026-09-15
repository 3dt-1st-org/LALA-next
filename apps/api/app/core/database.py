from __future__ import annotations

import os
from threading import BoundedSemaphore, Lock
from typing import Any

from psycopg2.pool import ThreadedConnectionPool


class DatabaseBusyError(RuntimeError):
    """The bounded connection budget could not be acquired in time."""


def _positive_int(name: str, default: int, maximum: int) -> int:
    try:
        return min(maximum, max(1, int(os.environ.get(name, str(default)))))
    except ValueError:
        return default


class _Pool:
    def __init__(self, dsn: str, connect_timeout: int) -> None:
        size = _positive_int("LALA_DB_POOL_SIZE", 8, 64)
        self.slots = BoundedSemaphore(size)
        self.wait_seconds = _positive_int("LALA_DB_POOL_WAIT_MS", 1000, 10000) / 1000
        statement_ms = _positive_int("LALA_DB_STATEMENT_TIMEOUT_MS", 5000, 60000)
        lock_ms = _positive_int("LALA_DB_LOCK_TIMEOUT_MS", 1000, 10000)
        self.pool = ThreadedConnectionPool(
            1,
            size,
            dsn,
            connect_timeout=connect_timeout,
            options=(
                f"-c statement_timeout={statement_ms} -c lock_timeout={lock_ms} "
                "-c idle_in_transaction_session_timeout=10000"
            ),
        )

    def borrow(self) -> _Lease:
        if not self.slots.acquire(timeout=self.wait_seconds):
            raise DatabaseBusyError("Database connection budget exhausted.")
        try:
            return _Lease(self, self.pool.getconn())
        except BaseException:
            self.slots.release()
            raise


class _Lease:
    """Keep existing transaction contexts; close returns the connection to its pool."""

    def __init__(self, owner: _Pool, connection: Any) -> None:
        self._owner = owner
        self._connection = connection
        self._returned = False

    def __getattr__(self, name: str) -> Any:
        return getattr(self._connection, name)

    def __enter__(self) -> _Lease:
        self._connection.__enter__()
        return self

    def __exit__(self, *args: Any) -> Any:
        return self._connection.__exit__(*args)

    def close(self) -> None:
        if self._returned:
            return
        self._returned = True
        discard = bool(self._connection.closed)
        try:
            if not discard:
                try:
                    self._connection.rollback()
                except Exception:
                    discard = True
            self._owner.pool.putconn(self._connection, close=discard)
        finally:
            self._owner.slots.release()

    def discard(self) -> None:
        """Drop an unsafe session instead of returning session locks/state to callers."""
        if self._returned:
            return
        self._returned = True
        try:
            self._owner.pool.putconn(self._connection, close=True)
        finally:
            self._owner.slots.release()


_pools: dict[tuple[int, str, int], _Pool] = {}
_pool_lock = Lock()


def connect_db(dsn: str, connect_timeout: int = 3) -> _Lease:
    key = (os.getpid(), dsn, connect_timeout)
    with _pool_lock:
        pool = _pools.get(key)
        if pool is None:
            if len(_pools) >= 8:
                raise DatabaseBusyError("Database pool configuration limit reached.")
            pool = _Pool(dsn, connect_timeout)
            _pools[key] = pool
    return pool.borrow()


def close_database_pools() -> None:
    """Call after requests drain at application shutdown (or isolated tests)."""
    with _pool_lock:
        for pool in _pools.values():
            pool.pool.closeall()
        _pools.clear()
