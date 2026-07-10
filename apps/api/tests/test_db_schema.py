from __future__ import annotations

import sys
from types import SimpleNamespace

from apps.api.app.services import db_schema
from apps.api.app.tools import verify_db_schema


class FakeCursor:
    def __init__(self, present: dict[str, bool]) -> None:
        self.present = present
        self.last_name = ""

    def __enter__(self) -> "FakeCursor":
        return self

    def __exit__(self, *args) -> None:
        return None

    def execute(self, sql: str, params: tuple[str, ...]) -> None:
        if "information_schema.columns" in sql:
            self.last_name = ".".join(params[:3])
        elif "FROM pg_constraint" in sql:
            self.last_name = f"{params[0]}.{params[1]}({','.join(params[2])})"
        else:
            self.last_name = params[0]

    def fetchone(self) -> tuple[bool]:
        return (self.present.get(self.last_name, False),)


class FakeConnection:
    def __init__(self, present: dict[str, bool]) -> None:
        self.present = present

    def __enter__(self) -> "FakeConnection":
        return self

    def __exit__(self, *args) -> None:
        return None

    def cursor(self) -> FakeCursor:
        return FakeCursor(self.present)


def install_fake_psycopg2(monkeypatch, present: dict[str, bool], calls: list[dict]) -> None:
    def connect(dsn: str, connect_timeout: int) -> FakeConnection:
        calls.append({"dsn": dsn, "connect_timeout": connect_timeout})
        return FakeConnection(present)

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))


def test_inspect_canonical_schema_reports_ok_when_all_required_objects_exist(monkeypatch):
    assert "economy.franchise_brands" in db_schema.REQUIRED_RELATIONS
    assert "economy.franchise_locations" in db_schema.REQUIRED_RELATIONS
    assert "analytics.place_business_identity" in db_schema.REQUIRED_RELATIONS
    assert "identity" in db_schema.REQUIRED_SCHEMAS
    assert "identity.users" in db_schema.REQUIRED_RELATIONS
    assert "identity.deleted_users" in db_schema.REQUIRED_RELATIONS
    assert "identity.deleted_users.identity_digest" in db_schema.REQUIRED_COLUMNS
    assert "identity.deleted_users(identity_digest)" in db_schema.REQUIRED_UNIQUE_CONSTRAINTS

    present = {
        name: True
        for name in (
            *db_schema.REQUIRED_EXTENSIONS,
            *db_schema.REQUIRED_SCHEMAS,
            *db_schema.REQUIRED_RELATIONS,
            *db_schema.REQUIRED_COLUMNS,
            *db_schema.REQUIRED_UNIQUE_CONSTRAINTS,
        )
    }
    calls: list[dict] = []
    install_fake_psycopg2(monkeypatch, present, calls)

    report = db_schema.inspect_canonical_schema(dsn="postgresql://redacted", connect_timeout=3)

    assert report.ok is True
    assert report.missing() == {
        "extensions": [],
        "schemas": [],
        "relations": [],
        "columns": [],
        "unique_constraints": [],
    }
    assert calls == [{"dsn": "postgresql://redacted", "connect_timeout": 3}]


def test_inspect_canonical_schema_lists_missing_objects(monkeypatch):
    present = {
        name: True
        for name in (
            *db_schema.REQUIRED_EXTENSIONS,
            *db_schema.REQUIRED_SCHEMAS,
            *db_schema.REQUIRED_RELATIONS,
            *db_schema.REQUIRED_COLUMNS,
            *db_schema.REQUIRED_UNIQUE_CONSTRAINTS,
        )
    }
    present["vector"] = False
    present["ops"] = False
    present["travel.latest_weather"] = False
    present["identity.deleted_users.deleted_at"] = False
    present["identity.users(issuer,subject)"] = False
    install_fake_psycopg2(monkeypatch, present, [])

    report = db_schema.inspect_canonical_schema(dsn="postgresql://redacted")

    assert report.ok is False
    assert report.missing() == {
        "extensions": ["vector"],
        "schemas": ["ops"],
        "relations": ["travel.latest_weather"],
        "columns": ["identity.deleted_users.deleted_at"],
        "unique_constraints": ["identity.users(issuer,subject)"],
    }
    assert report.to_dict()["ok"] is False


def test_verify_db_schema_cli_exits_degraded_without_dsn(monkeypatch, capsys):
    monkeypatch.delenv("DB_DSN", raising=False)
    monkeypatch.setattr(verify_db_schema, "get_settings", lambda: SimpleNamespace(db_dsn=""))

    exit_code = verify_db_schema.main([])

    output = capsys.readouterr().out
    assert exit_code == 2
    assert "DB_DSN is not configured." in output
    assert "postgresql://" not in output


def test_verify_db_schema_cli_prints_missing_without_dsn(monkeypatch, capsys):
    report = db_schema.DbSchemaReport(
        extensions={"postgis": True, "vector": False, "pgcrypto": True},
        schemas={"travel": True, "community": True, "ops": True},
        relations={"travel.public_places": True},
        columns={"identity.users.id": True},
        unique_constraints={"identity.users(issuer,subject)": True},
    )
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setattr(verify_db_schema, "inspect_canonical_schema", lambda **kwargs: report)

    exit_code = verify_db_schema.main([])

    output = capsys.readouterr().out
    assert exit_code == 2
    assert "missing_extensions=vector" in output
    assert "postgresql://" not in output


def test_verify_db_schema_cli_redacts_dsn_from_errors(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)

    def fail(**kwargs):
        raise RuntimeError(f"connection failed for {dsn} password={password}")

    monkeypatch.setattr(verify_db_schema, "inspect_canonical_schema", fail)

    exit_code = verify_db_schema.main([])

    output = capsys.readouterr().out
    assert exit_code == 2
    assert "[redacted DB_DSN]" in output
    assert password not in output
    assert dsn not in output
