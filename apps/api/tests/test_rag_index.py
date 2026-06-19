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
    assert "내국인 소비" in chunk.body_ko
    assert "관광 수요 분산" in chunk.body_ko
    assert chunk.metadata["score"]["features"]["card_month"] == "2026-05-01"


def test_rag_index_plan_uses_intuitive_table_names(capsys):
    exit_code = run_rag_index.main(["--json"])

    output = capsys.readouterr().out
    payload = json.loads(output)
    assert exit_code == 0
    assert payload["target"] == "rag.knowledge_chunks"
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
