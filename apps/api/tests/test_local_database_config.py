from __future__ import annotations

import pytest
from psycopg2.extensions import make_dsn

from apps.api.tests.local_database import local_test_dsn


def test_application_database_is_never_used(monkeypatch):
    monkeypatch.delenv("TEST_DB_DSN", raising=False)
    monkeypatch.delenv("TEST_DB_ENV_FILE", raising=False)
    monkeypatch.setenv("DB_DSN", "production-must-not-be-read")
    with pytest.raises(pytest.skip.Exception):
        local_test_dsn()


def test_explicit_environment_file_and_process_override(tmp_path, monkeypatch):
    path = tmp_path / ".env.test.local"
    file_dsn = make_dsn(host="localhost", dbname="file_fixture")
    path.write_text(f"TEST_DB_DSN={file_dsn}\n")
    monkeypatch.delenv("TEST_DB_DSN", raising=False)
    monkeypatch.setenv("TEST_DB_ENV_FILE", str(path))
    assert local_test_dsn() == file_dsn
    override = make_dsn(host="localhost", dbname="process_fixture")
    monkeypatch.setenv("TEST_DB_DSN", override)
    assert local_test_dsn() == override


def test_environment_file_cannot_select_external_database(tmp_path, monkeypatch):
    path = tmp_path / ".env.test.local"
    path.write_text("TEST_DB_DSN=host=external.invalid dbname=fixture\n")
    monkeypatch.delenv("TEST_DB_DSN", raising=False)
    monkeypatch.setenv("TEST_DB_ENV_FILE", str(path))
    with pytest.raises(ValueError, match="loopback"):
        local_test_dsn()
