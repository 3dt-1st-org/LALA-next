from __future__ import annotations

import json
import sys
from types import SimpleNamespace

import pytest

from apps.api.app.services import rag_index
from apps.api.app.tools import run_rag_index


def test_local_hash_embedding_is_deterministic_and_pgvector_sized():
    first = rag_index.build_local_embedding("수원 화성행궁 문화 행사 추천")
    second = rag_index.build_local_embedding("수원 화성행궁 문화 행사 추천")

    assert first == second
    assert len(first) == rag_index.VECTOR_DIMENSIONS
    assert sum(abs(value) for value in first) > 0
    assert rag_index.vector_to_pgvector(first).startswith("[")
    assert rag_index.vector_to_pgvector(first).endswith("]")


def test_place_profile_chunk_keeps_public_value_score_context():
    chunk = rag_index._place_profile_chunk(
        {
            "place_id": "place-1",
            "name_ko": "수원 화성행궁",
            "category": "attraction",
            "address_ko": "경기도 수원시 팔달구",
            "region_name_ko": "수원시",
            "is_indoor": False,
            "primary_source": "tour_api",
            "source_record_id": "123",
            "final_score": 0.82,
            "local_spending_score": 0.7,
            "small_merchant_fit_score": 0.76,
            "demand_dispersion_score": 0.6,
            "weather_fit_score": 0.9,
            "review_quality_score": None,
            "culture_relevance_score": 0.8,
            "accessibility_fit_score": 0.62,
            "formula_version": "local-value-v2",
            "features": {"card_month": "2026-05-01"},
        }
    )

    assert chunk.source_type == "place_profile"
    assert chunk.source_table == "travel.places"
    assert chunk.place_id == "place-1"
    assert "카테고리는 명소" in chunk.body_ko
    assert "attraction" not in chunk.body_ko
    assert "내국인 소비" in chunk.body_ko
    assert "관광 수요 분산" in chunk.body_ko
    assert chunk.metadata["score"]["features"]["card_month"] == "2026-05-01"


def test_place_profile_chunk_localizes_culture_venue_category():
    chunk = rag_index._place_profile_chunk(
        {
            "place_id": "place-2",
            "name_ko": "중랑아트센터",
            "category": "culture_venue",
            "address_ko": "서울특별시 중랑구",
            "region_name_ko": "중랑구",
            "is_indoor": True,
            "primary_source": "tour_api",
            "source_record_id": "3066000",
            "final_score": None,
            "local_spending_score": None,
            "demand_dispersion_score": None,
            "weather_fit_score": None,
            "review_quality_score": None,
            "culture_relevance_score": None,
            "formula_version": "local-value-v2",
            "features": {},
        }
    )

    assert "카테고리는 문화공간" in chunk.body_ko
    assert "culture_venue" not in chunk.body_ko


def test_rag_index_plan_uses_intuitive_table_names(capsys):
    exit_code = run_rag_index.main(["--json"])

    output = capsys.readouterr().out
    payload = json.loads(output)
    assert exit_code == 0
    assert payload["target"] == "rag.knowledge_chunks"
    assert payload["job_name"] == run_rag_index.JOB_NAME
    assert payload["input_relations"] == [
        "travel.places",
        "analytics.place_score_snapshots",
        "culture.events",
        "community.posts",
        "community.place_mentions_weekly",
        "travel.weather_observations",
    ]
    assert "place_profile" in payload["static_source_types"]
    assert "culture_event" in payload["dynamic_source_types"]


def test_rag_index_apply_requires_guard(monkeypatch, capsys):
    monkeypatch.delenv(run_rag_index.ALLOW_ENV, raising=False)
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")

    exit_code = run_rag_index.main(["--apply", "--confirm", run_rag_index.CONFIRM_TEXT])

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_rag_index.ALLOW_ENV in output
    assert "postgresql://" not in output


def test_rag_index_apply_rejects_live_local_hash_before_db_connect(monkeypatch, capsys):
    # R1: the embedding guard is wired into the shared apply gate, so a live-AI +
    # local-hash misconfiguration is rejected even with confirm/env satisfied, and before any
    # DB-connecting function runs.
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(run_rag_index.ALLOW_ENV, "1")
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.delenv("LALA_RAG_ALLOW_LOCAL_HASH_LIVE", raising=False)

    def fail_if_called(**kwargs):
        raise AssertionError("must not fetch candidate chunks before the guard runs")

    monkeypatch.setattr(run_rag_index, "fetch_candidate_chunks", fail_if_called)
    monkeypatch.setattr(run_rag_index, "upsert_knowledge_chunks", fail_if_called)

    exit_code = run_rag_index.main(["--apply", "--confirm", run_rag_index.CONFIRM_TEXT, "--json"])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert "LALA_RAG_ALLOW_LOCAL_HASH_LIVE" in payload["error"]


def test_rag_index_reindex_apply_rejects_live_local_hash_before_db_connect(monkeypatch, capsys):
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(run_rag_index.ALLOW_ENV, "1")
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.delenv("LALA_RAG_ALLOW_LOCAL_HASH_LIVE", raising=False)

    def fail_if_called(**kwargs):
        raise AssertionError("must not select/reindex stale chunks before the guard runs")

    monkeypatch.setattr(run_rag_index, "select_stale_chunks", fail_if_called)
    monkeypatch.setattr(run_rag_index, "reindex_stale_chunks", fail_if_called)

    exit_code = run_rag_index.main(
        ["--reindex", "--apply", "--confirm", run_rag_index.CONFIRM_TEXT, "--json"]
    )

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert "LALA_RAG_ALLOW_LOCAL_HASH_LIVE" in payload["error"]


def test_rag_index_apply_records_succeeded_job_run(monkeypatch, capsys):
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(run_rag_index.ALLOW_ENV, "1")
    recorded_runs = []

    def fake_fetch_candidate_chunks(**kwargs):
        return [
            rag_index.KnowledgeChunk(
                source_type="place_profile",
                source_id="place:place-1",
                source_table="travel.places",
                place_id="place-1",
                title_ko="수원 화성행궁",
                body_ko="수원 화성행궁 장소 맥락입니다.",
                metadata={"formula_version": "local-value-v2"},
            )
        ]

    def fake_upsert_knowledge_chunks(**kwargs):
        assert kwargs["dsn"] == "postgresql://redacted"
        assert list(kwargs["chunks"])[0].source_id == "place:place-1"
        assert kwargs["embedding_method"] == "local-hash"
        return 1

    monkeypatch.setattr(run_rag_index, "fetch_candidate_chunks", fake_fetch_candidate_chunks)
    monkeypatch.setattr(run_rag_index, "upsert_knowledge_chunks", fake_upsert_knowledge_chunks)
    monkeypatch.setattr(
        run_rag_index,
        "record_job_run",
        lambda **kwargs: recorded_runs.append(kwargs),
    )

    exit_code = run_rag_index.main(["--apply", "--confirm", run_rag_index.CONFIRM_TEXT, "--json"])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["upserted_rows"] == 1
    assert payload["job_name"] == run_rag_index.JOB_NAME
    assert len(recorded_runs) == 1
    assert recorded_runs[0]["job_name"] == run_rag_index.JOB_NAME
    assert recorded_runs[0]["status"] == "succeeded"
    assert recorded_runs[0]["error_message"] is None


def test_rag_index_apply_failure_records_redacted_job_run(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.setenv(run_rag_index.ALLOW_ENV, "1")
    recorded_runs = []

    def fail(**kwargs):
        raise RuntimeError(f"connection failed for {dsn} password={password}")

    monkeypatch.setattr(run_rag_index, "fetch_candidate_chunks", fail)
    monkeypatch.setattr(
        run_rag_index,
        "record_job_run",
        lambda **kwargs: recorded_runs.append(kwargs),
    )

    exit_code = run_rag_index.main(["--apply", "--confirm", run_rag_index.CONFIRM_TEXT, "--json"])

    output = capsys.readouterr().out
    payload = json.loads(output)
    assert exit_code == 2
    assert "[redacted]" in payload["error"]
    assert dsn not in output
    assert password not in output
    assert len(recorded_runs) == 1
    assert recorded_runs[0]["job_name"] == run_rag_index.JOB_NAME
    assert recorded_runs[0]["status"] == "failed"
    assert "[redacted]" in recorded_runs[0]["error_message"]
    assert dsn not in recorded_runs[0]["error_message"]
    assert password not in recorded_runs[0]["error_message"]


def test_rag_query_prints_bounded_result_summary(monkeypatch, capsys):
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")

    def fake_query_knowledge_chunks(**kwargs):
        assert kwargs["query"] == "수원 문화 행사"
        assert kwargs["source"] == "dynamic"
        return [
            rag_index.RagSearchResult(
                source_type="culture_event",
                source_id="event:kcisa-1",
                source_table="culture.events",
                title_ko="수원 전시",
                body_ko="수원 전시 정보입니다.",
                place_id=None,
                metadata={"primary_source": "kcisa"},
                similarity=0.91,
                embedding_model="local-hash-v1",
                updated_at="2026-06-18T00:00:00+09:00",
            )
        ]

    monkeypatch.setattr(run_rag_index, "query_knowledge_chunks", fake_query_knowledge_chunks)

    exit_code = run_rag_index.main(["--query", "수원 문화 행사", "--source", "dynamic"])

    output = capsys.readouterr().out
    assert exit_code == 0
    assert "result_count=1" in output
    assert "culture_event" in output
    assert "postgresql://" not in output


def test_build_embedding_routes_openai_method(monkeypatch):
    called = {}

    def fake_build_openai(text):
        called["text"] = text
        return [0.0] * rag_index.VECTOR_DIMENSIONS

    monkeypatch.setattr(rag_index, "build_openai_embedding", fake_build_openai)
    monkeypatch.setattr(
        rag_index, "settings_openai_embedding_model_name", lambda: "text-embedding-3-small"
    )

    vector, model = rag_index.build_embedding("수원 화성", method="openai")
    assert called["text"] == "수원 화성"
    assert len(vector) == rag_index.VECTOR_DIMENSIONS
    assert model == "text-embedding-3-small"


def test_openai_embedding_missing_key_raises(monkeypatch):
    class FakeSettings:
        openai_api_key = ""
        openai_base_url = ""
        openai_embedding_model = ""
        enable_live_ai = True

    monkeypatch.setattr(rag_index, "get_settings", lambda: FakeSettings())

    raised = False
    try:
        rag_index.build_openai_embedding("수원 화성")
    except RuntimeError as exc:
        raised = True
        assert "OPENAI_API_KEY" in str(exc)
    assert raised, "expected RuntimeError when OPENAI_API_KEY is missing"


# ---------------------------------------------------------------------------
# Embedding method/generation contract (no silent semantic fallback)
# ---------------------------------------------------------------------------


class _EmbedSettings:
    """Minimal settings stub for the embedding-contract guards."""

    def __init__(self, **kwargs: object) -> None:
        self.enable_live_ai = kwargs.get("enable_live_ai", False)
        self.rag_embedding_method = kwargs.get("rag_embedding_method", "local-hash")
        self.rag_allow_local_hash_live = kwargs.get("rag_allow_local_hash_live", False)


def test_resolve_serving_embedding_method_rejects_unknown(monkeypatch):
    monkeypatch.setattr(
        rag_index, "get_settings", lambda: _EmbedSettings(rag_embedding_method="bogus")
    )
    with pytest.raises(ValueError):
        rag_index.resolve_serving_embedding_method()


def test_assert_semantic_embedding_when_live_off_is_noop(monkeypatch):
    monkeypatch.setattr(rag_index, "get_settings", lambda: _EmbedSettings(enable_live_ai=False))
    rag_index.assert_semantic_embedding_when_live()  # no raise


def test_assert_semantic_embedding_when_live_raises_on_local_hash(monkeypatch):
    monkeypatch.setattr(
        rag_index,
        "get_settings",
        lambda: _EmbedSettings(enable_live_ai=True, rag_embedding_method="local-hash"),
    )
    with pytest.raises(RuntimeError):
        rag_index.assert_semantic_embedding_when_live()


def test_assert_semantic_embedding_when_live_allows_openai(monkeypatch):
    monkeypatch.setattr(
        rag_index,
        "get_settings",
        lambda: _EmbedSettings(enable_live_ai=True, rag_embedding_method="openai"),
    )
    rag_index.assert_semantic_embedding_when_live()  # no raise


def test_assert_semantic_embedding_when_live_allows_local_hash_with_hatch(monkeypatch):
    monkeypatch.setattr(
        rag_index,
        "get_settings",
        lambda: _EmbedSettings(
            enable_live_ai=True,
            rag_embedding_method="local-hash",
            rag_allow_local_hash_live=True,
        ),
    )
    rag_index.assert_semantic_embedding_when_live()  # no raise


# ---------------------------------------------------------------------------
# create_app() boot wiring for the live-AI embedding guard (R1)
# ---------------------------------------------------------------------------


def test_create_app_boot_fails_for_hybrid_live_local_hash(monkeypatch):
    from apps.api.app.main import create_app

    monkeypatch.setenv("LALA_RAG_RETRIEVAL_MODE", "hybrid")
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.delenv("LALA_RAG_EMBEDDING_METHOD", raising=False)  # defaults to local-hash
    monkeypatch.delenv("LALA_RAG_ALLOW_LOCAL_HASH_LIVE", raising=False)

    with pytest.raises(RuntimeError):
        create_app()


def test_create_app_boots_for_hybrid_live_openai(monkeypatch):
    from apps.api.app.main import create_app

    monkeypatch.setenv("LALA_RAG_RETRIEVAL_MODE", "hybrid")
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.setenv("LALA_RAG_EMBEDDING_METHOD", "openai")

    create_app()  # no raise


def test_create_app_boots_for_legacy_default_with_live_ai(monkeypatch):
    from apps.api.app.main import create_app

    # rag_retrieval_mode defaults to "legacy" — the guard must never trigger, so a live-AI
    # deploy that hasn't opted into hybrid retrieval sees zero behavior change.
    monkeypatch.delenv("LALA_RAG_RETRIEVAL_MODE", raising=False)
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.delenv("LALA_RAG_EMBEDDING_METHOD", raising=False)

    create_app()  # no raise


# ---------------------------------------------------------------------------
# Stale-chunk predicate + idempotent reindex lifecycle (no external call)
# ---------------------------------------------------------------------------


def test_is_chunk_stale_generation_lag():
    assert (
        rag_index.is_chunk_stale(stored_generation=0, serving_generation=2, has_embedding=True)
        is True
    )


def test_is_chunk_stale_missing_embedding():
    assert (
        rag_index.is_chunk_stale(stored_generation=2, serving_generation=2, has_embedding=False)
        is True
    )


def test_is_chunk_stale_current_not_stale():
    assert (
        rag_index.is_chunk_stale(stored_generation=2, serving_generation=2, has_embedding=True)
        is False
    )


def _install_fake_psycopg2(monkeypatch, *, fetchall_rows):
    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            self.sql = sql

        def fetchall(self):
            return list(fetchall_rows)

    class Conn:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self, cursor_factory=None):
            return Cursor()

        def commit(self):
            return None

    monkeypatch.setitem(
        sys.modules, "psycopg2", SimpleNamespace(connect=lambda dsn, connect_timeout: Conn())
    )


def test_select_stale_chunks_is_read_only_and_maps_rows(monkeypatch):
    rows = [
        {
            "source_type": "place_profile",
            "source_id": "place:a",
            "title_ko": "수원 화성",
            "body_ko": "본문 a",
            "body_en": "a en",
            "content_sha256": "sha-a",
            "embedding_generation": 0,
            "embedding_is_null": False,
        },
        {
            "source_type": "culture_event",
            "source_id": "event:1",
            "title_ko": None,
            "body_ko": "행사 본문",
            "body_en": None,
            "content_sha256": "sha-e",
            "embedding_generation": 2,
            "embedding_is_null": False,
        },
    ]
    captured = {}

    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            captured["sql"] = sql

        def fetchall(self):
            return list(rows)

    class Conn:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self, cursor_factory=None):
            return Cursor()

    monkeypatch.setitem(
        sys.modules, "psycopg2", SimpleNamespace(connect=lambda dsn, connect_timeout: Conn())
    )
    monkeypatch.setitem(sys.modules, "psycopg2.extras", SimpleNamespace(RealDictCursor=object))

    stale = rag_index.select_stale_chunks(
        dsn="postgresql://redacted", serving_generation=2, limit=10, connect_timeout=5
    )

    assert len(stale) == 2
    assert stale[0].source_id == "place:a"
    assert stale[0].reason == "generation_lag"
    assert stale[0].content_sha256 == "sha-a"
    assert "수원 화성" in stale[0].text_for_embedding
    # Read-only: the executed statement is a SELECT, never a mutation.
    assert captured["sql"].lstrip().upper().startswith("SELECT")


def test_reindex_stale_chunks_reembeds_and_is_idempotent(monkeypatch):
    stale_first = [
        rag_index.StaleChunk("place_profile", "place:a", "text a", "sha-a", 0, "generation_lag"),
        rag_index.StaleChunk("place_profile", "place:b", "text b", "sha-b", 0, "generation_lag"),
    ]
    select_calls = {"count": 0}

    def fake_select(**kwargs):
        select_calls["count"] += 1
        return [] if select_calls["count"] > 1 else stale_first

    updates: list = []

    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            if sql.lstrip().upper().startswith("UPDATE"):
                updates.append(params)

    class Conn:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self, cursor_factory=None):
            return Cursor()

        def commit(self):
            return None

    monkeypatch.setattr(rag_index, "select_stale_chunks", fake_select)
    monkeypatch.setattr(
        rag_index,
        "build_embedding",
        lambda text, method: ([0.0] * rag_index.VECTOR_DIMENSIONS, "local-hash-v1"),
    )
    monkeypatch.setitem(
        sys.modules, "psycopg2", SimpleNamespace(connect=lambda dsn, connect_timeout: Conn())
    )

    first = rag_index.reindex_stale_chunks(
        dsn="postgresql://redacted",
        serving_generation=1,
        embedding_method="local-hash",
        batch_size=10,
        chunk_cap=10,
        connect_timeout=5,
    )
    assert first.reembedded == 2
    assert first.capped is False
    assert len(updates) == 2

    # Resumable/idempotent: once the stale predicate returns nothing, nothing is re-embedded.
    second = rag_index.reindex_stale_chunks(
        dsn="postgresql://redacted",
        serving_generation=1,
        embedding_method="local-hash",
        batch_size=10,
        chunk_cap=10,
        connect_timeout=5,
    )
    assert second.reembedded == 0


def test_reindex_stale_chunks_respects_chunk_cap(monkeypatch):
    stale = [
        rag_index.StaleChunk("place_profile", f"place:{i}", f"t{i}", f"sha{i}", 0, "generation_lag")
        for i in range(5)
    ]

    def fake_select(**kwargs):
        return stale[: kwargs["limit"]]

    monkeypatch.setattr(rag_index, "select_stale_chunks", fake_select)
    monkeypatch.setattr(
        rag_index,
        "build_embedding",
        lambda text, method: ([0.0] * rag_index.VECTOR_DIMENSIONS, "local-hash-v1"),
    )
    _install_fake_psycopg2(monkeypatch, fetchall_rows=[])

    result = rag_index.reindex_stale_chunks(
        dsn="postgresql://redacted",
        serving_generation=1,
        embedding_method="local-hash",
        batch_size=2,
        chunk_cap=3,
        connect_timeout=5,
    )
    assert result.reembedded == 3
    assert result.capped is True


# ---------------------------------------------------------------------------
# run_rag_index --reindex: dry-run default, confirm+env gate, no secret leak
# ---------------------------------------------------------------------------


def test_rag_index_reindex_plan_is_dry_run_and_does_not_require_dsn(capsys):
    exit_code = run_rag_index.main(["--reindex", "--json"])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["mode"] == "reindex-plan"
    assert payload["db_mutation"] is False
    assert payload["serving_generation"] == 1  # default rag_embedding_generation
    assert payload["requires"].startswith("sql/canonical/064")


def test_rag_index_reindex_apply_requires_guard(monkeypatch, capsys):
    monkeypatch.delenv(run_rag_index.ALLOW_ENV, raising=False)
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")

    exit_code = run_rag_index.main(
        ["--reindex", "--apply", "--confirm", run_rag_index.CONFIRM_TEXT, "--json"]
    )

    output = capsys.readouterr().out
    payload = json.loads(output)
    assert exit_code == 2
    assert run_rag_index.ALLOW_ENV in payload["error"]
    assert "postgresql://" not in output


def test_rag_index_reindex_apply_runs_and_records_succeeded_job(monkeypatch, capsys):
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setenv(run_rag_index.ALLOW_ENV, "1")
    recorded: list = []
    monkeypatch.setattr(
        run_rag_index,
        "reindex_stale_chunks",
        lambda **kwargs: rag_index.ReindexResult(examined=2, reembedded=2, capped=False),
    )
    monkeypatch.setattr(run_rag_index, "record_job_run", lambda **kwargs: recorded.append(kwargs))

    exit_code = run_rag_index.main(
        ["--reindex", "--apply", "--confirm", run_rag_index.CONFIRM_TEXT, "--json"]
    )

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["mode"] == "reindex-apply"
    assert payload["db_mutation"] is True
    assert payload["reembedded"] == 2
    assert len(recorded) == 1
    assert recorded[0]["status"] == "succeeded"


def test_rag_index_reindex_preview_is_read_only(monkeypatch, capsys):
    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setattr(
        run_rag_index,
        "select_stale_chunks",
        lambda **kwargs: [
            rag_index.StaleChunk("place_profile", "place:a", "t", "sha", 0, "generation_lag")
        ],
    )

    exit_code = run_rag_index.main(["--reindex", "--preview", "--json"])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["mode"] == "reindex-preview"
    assert payload["db_mutation"] is False
    assert payload["stale_count"] == 1
