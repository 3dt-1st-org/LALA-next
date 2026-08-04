"""
Fake-DB/SQL contract tests for place enrichment uniqueness constraint.
Tests ON CONFLICT handling without live database calls.
"""

from __future__ import annotations

import sys
from datetime import date
from types import SimpleNamespace

import pytest

from apps.api.app.services import local_place_enrichment, review_attribute_batch


class FakeCursor:
    def __init__(self, executed: list) -> None:
        self.executed = executed
        self.rowcount = 1

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return None

    def execute(self, sql: str, params: dict | None = None) -> None:
        self.executed.append((sql, params))

    def fetchone(self):
        return (1,)

    def fetchall(self):
        return [{"place_id": "test-1", "name_ko": "테스트"}]


class FakeConnection:
    def __init__(self, executed: list) -> None:
        self.executed = executed
        self.committed = False

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return None

    def cursor(self):
        return FakeCursor(self.executed)

    def commit(self):
        self.committed = True


def fake_psycopg2_connect(executed: list):
    def connect(dsn: str, connect_timeout: int) -> FakeConnection:
        return FakeConnection(executed)
    
    # Fake Json class from psycopg2.extras
    class Json:
        def __init__(self, obj):
            self.obj = obj
    
    extras = SimpleNamespace(Json=Json)
    psycopg2_module = SimpleNamespace(connect=connect, RealDictCursor=FakeCursor, extras=extras)
    
    # Set up both psycopg2 and psycopg2.extras in sys.modules
    return {"psycopg2": psycopg2_module, "psycopg2.extras": extras}


def test_local_place_enrichment_insert_on_conflict_do_nothing(monkeypatch):
    """Verify local_place_enrichment uses ON CONFLICT for duplicate prevention."""
    executed: list = []
    fake_modules = fake_psycopg2_connect(executed)
    for module_name, module_obj in fake_modules.items():
        monkeypatch.setitem(sys.modules, module_name, module_obj)

    enrichment = local_place_enrichment.LocalPlaceEnrichment(
        place_id="test-place-1",
        name_en="Test Place",
        address_en="123 Test St",
        region_name_en="Test Region",
        confidence=0.62,
        reason="Test enrichment"
    )

    result = local_place_enrichment.apply_local_enrichments(
        dsn="postgresql://redacted",
        enrichments=[enrichment],
        connect_timeout=5,
        replace_existing=False
    )

    assert result == 1
    assert executed[-1][1]["place_id"] == "test-place-1"
    assert "ON CONFLICT" in executed[-1][0]
    assert "(place_id, enrichment_type, prompt_version)" in executed[-1][0]
    assert "DO NOTHING" in executed[-1][0]


def test_review_attribute_batch_insert_on_conflict_do_nothing():
    """Verify review_attribute_batch uses ON CONFLICT for duplicate prevention."""
    # Read the actual source code to verify SQL structure
    from pathlib import Path
    
    source_file = Path("/Users/geondongkim/orca/workspaces/LALA-next/lala-p1-2-place-enrichment-uniqueness-orca/apps/api/app/services/review_attribute_batch.py")
    source_text = source_file.read_text(encoding="utf-8")
    
    # Find the INSERT INTO travel.place_enrichments statement
    assert "INSERT INTO travel.place_enrichments" in source_text
    assert "ON CONFLICT (place_id, enrichment_type, prompt_version) DO NOTHING" in source_text


def test_place_enrichment_uniqueness_three_column_null_safe():
    """Test that uniqueness constraint is three-column and null-safe."""
    # Verify the migration SQL uses UNIQUE NULLS NOT DISTINCT
    from pathlib import Path

    migration_064 = Path("/Users/geondongkim/orca/workspaces/LALA-next/lala-p1-2-place-enrichment-uniqueness-orca/sql/canonical/064_place_enrichment_replay_uniqueness.sql")
    migration_text = migration_064.read_text(encoding="utf-8")

    assert "UNIQUE NULLS NOT DISTINCT" in migration_text
    assert "(place_id, enrichment_type, prompt_version)" in migration_text
    assert "place_enrichments_place_type_prompt_unique" in migration_text


def test_db_schema_includes_place_enrichments_unique_constraint():
    """Verify db_schema.py requires the new uniqueness constraint."""
    from apps.api.app.services import db_schema

    constraint_key = "travel.place_enrichments(place_id,enrichment_type,prompt_version)"
    assert constraint_key in db_schema.REQUIRED_UNIQUE_CONSTRAINTS

    schema, table, columns = db_schema.REQUIRED_UNIQUE_CONSTRAINTS[constraint_key]
    assert schema == "travel"
    assert table == "place_enrichments"
    assert columns == ("place_id", "enrichment_type", "prompt_version")
