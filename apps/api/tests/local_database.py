"""Explicit test configuration; never fall back to application DB_DSN."""

from __future__ import annotations

import ipaddress
import os

from dotenv import dotenv_values
from psycopg2.extensions import parse_dsn


def validate_local_test_dsn(dsn: str) -> None:
    parsed = parse_dsn(dsn)
    if parsed.get("service") or parsed.get("hostaddr"):
        raise ValueError("TEST_DB_DSN must use an explicit loopback host")
    host = parsed.get("host", "")
    if host == "localhost":
        return
    try:
        allowed = ipaddress.ip_address(host).is_loopback
    except ValueError:
        allowed = False
    if not allowed:
        raise ValueError("TEST_DB_DSN must use an explicit loopback host")


def local_test_dsn() -> str:
    import pytest

    path = os.getenv("TEST_DB_ENV_FILE")
    values = dotenv_values(path, interpolate=False) if path else {}
    dsn = os.getenv("TEST_DB_DSN", values.get("TEST_DB_DSN") or "")
    if not dsn:
        pytest.skip("Configure TEST_DB_DSN for a disposable local test database")
    validate_local_test_dsn(dsn)
    return dsn
