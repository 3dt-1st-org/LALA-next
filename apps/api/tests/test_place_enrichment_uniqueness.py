"""
Fake-DB/SQL contract tests for place enrichment uniqueness constraint.
Tests ON CONFLICT handling without live database calls.
"""

from pathlib import Path

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
    from types import SimpleNamespace

    def connect(dsn: str, connect_timeout: int) -> FakeConnection:
        return FakeConnection(executed)

    class Json:
        def __init__(self, obj):
            self.obj = obj

    extras = SimpleNamespace(Json=Json)
    psycopg2_module = SimpleNamespace(connect=connect, RealDictCursor=FakeCursor, extras=extras)

    return {"psycopg2": psycopg2_module, "psycopg2.extras": extras}


def test_local_place_enrichment_insert_on_conflict_do_nothing(monkeypatch):
    """Verify local_place_enrichment uses ON CONFLICT DO NOTHING when replace_existing=False."""
    import sys

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
        reason="Test enrichment",
    )

    result = local_place_enrichment.apply_local_enrichments(
        dsn="postgresql://redacted",
        enrichments=[enrichment],
        connect_timeout=5,
        replace_existing=False,
    )

    assert result == 1
    assert executed[-1][1]["place_id"] == "test-place-1"
    assert "ON CONFLICT" in executed[-1][0]
    assert "(place_id, enrichment_type, prompt_version)" in executed[-1][0]
    assert "DO NOTHING" in executed[-1][0]


def test_local_place_enrichment_insert_on_conflict_do_update(monkeypatch):
    """Verify local_place_enrichment uses ON CONFLICT DO UPDATE when replace_existing=True."""
    import sys

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
        reason="Test enrichment",
    )

    result = local_place_enrichment.apply_local_enrichments(
        dsn="postgresql://redacted",
        enrichments=[enrichment],
        connect_timeout=5,
        replace_existing=True,
    )

    assert result == 1
    assert executed[-1][1]["place_id"] == "test-place-1"
    assert "ON CONFLICT" in executed[-1][0]
    assert "(place_id, enrichment_type, prompt_version)" in executed[-1][0]
    assert "DO UPDATE SET" in executed[-1][0]
    assert "name_en = EXCLUDED.name_en" in executed[-1][0]


def test_review_attribute_batch_accepted_row_insert(monkeypatch):
    """Verify review_attribute_batch executes enrichment INSERT for accepted rows."""
    import sys

    executed: list = []
    fake_modules = fake_psycopg2_connect(executed)
    for module_name, module_obj in fake_modules.items():
        monkeypatch.setitem(sys.modules, module_name, module_obj)

    candidate = review_attribute_batch.ReviewAttributeCandidate(
        mention_id="test-mention-1",
        week_start="2026-08-05",
        place_id="test-place-1",
        place_name_ko="테스트",
        provider="test_provider",
        category="attraction",
        mention_count=10,
        organic_mention_count=8,
        sentiment_score=0.5,
        attributes={},
        posts=(),
    )

    enrichment = review_attribute_batch.ReviewAttributeEnrichment(
        mention_id="test-mention-1",
        schema_version="review-attributes-v1",
        sentiment_score=0.5,
        sentiment_confidence=0.8,
        attribute_scores={"cultural_story": 0.7},
        attribute_confidence_avg=0.8,
        evidence_terms={},
        summary_ko=None,
        reason=None,
        source_method="openai",
        status="accepted",
    )

    result = review_attribute_batch.apply_review_attribute_enrichments(
        dsn="postgresql://redacted",
        candidates=[candidate],
        enrichments=[enrichment],
        source_method="openai",
        connect_timeout=5,
    )

    assert result == 1

    # Find the INSERT INTO travel.place_enrichments statement
    insert_statements = [
        sql for sql, params in executed if "INSERT INTO travel.place_enrichments" in sql
    ]
    assert len(insert_statements) == 1
    insert_sql = insert_statements[0]

    assert "ON CONFLICT (place_id, enrichment_type, prompt_version) DO NOTHING" in insert_sql
    assert "'review_attributes'" in insert_sql


def test_review_attribute_batch_rejected_row_no_insert(monkeypatch):
    """Verify review_attribute_batch does not execute enrichment INSERT for rejected rows."""
    import sys

    executed: list = []
    fake_modules = fake_psycopg2_connect(executed)
    for module_name, module_obj in fake_modules.items():
        monkeypatch.setitem(sys.modules, module_name, module_obj)

    candidate = review_attribute_batch.ReviewAttributeCandidate(
        mention_id="test-mention-1",
        week_start="2026-08-05",
        place_id="test-place-1",
        place_name_ko="테스트",
        provider="test_provider",
        category="attraction",
        mention_count=10,
        organic_mention_count=8,
        sentiment_score=0.5,
        attributes={},
        posts=(),
    )

    enrichment = review_attribute_batch.ReviewAttributeEnrichment(
        mention_id="test-mention-1",
        schema_version="review-attributes-v1",
        sentiment_score=0.5,
        sentiment_confidence=0.8,
        attribute_scores={"cultural_story": 0.7},
        attribute_confidence_avg=0.8,
        evidence_terms={},
        summary_ko=None,
        reason=None,
        source_method="openai",
        status="quarantined",
    )

    result = review_attribute_batch.apply_review_attribute_enrichments(
        dsn="postgresql://redacted",
        candidates=[candidate],
        enrichments=[enrichment],
        source_method="openai",
        connect_timeout=5,
    )

    assert result == 1

    # Verify no INSERT INTO travel.place_enrichments statement was executed
    insert_statements = [
        sql for sql, params in executed if "INSERT INTO travel.place_enrichments" in sql
    ]
    assert len(insert_statements) == 0


def test_place_enrichment_uniqueness_three_column_null_safe():
    """Test that uniqueness constraint is three-column and null-safe."""
    repo_root = Path(__file__).resolve().parents[3]
    migration_064 = repo_root / "sql" / "canonical" / "064_place_enrichment_replay_uniqueness.sql"
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
