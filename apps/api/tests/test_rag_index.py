from __future__ import annotations

import json

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
