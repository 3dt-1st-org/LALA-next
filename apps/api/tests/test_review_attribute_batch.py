from __future__ import annotations

import json
import sys
from datetime import date
from types import SimpleNamespace

from apps.api.app.services import review_attribute_batch
from apps.api.app.tools import run_review_attribute_batch


def test_review_attribute_batch_plan_is_safe(capsys):
    exit_code = run_review_attribute_batch.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["live_ai_call"] is False
    assert payload["db_mutation"] is False
    assert payload["target"] == "community.place_mentions_weekly"
    assert payload["model_role"] == "bulk_review_batch"
    assert "AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT" in payload["model_deployment_envs"]
    assert "community.posts" in payload["input_relations"]
    assert "attributes.review_attributes" in payload["output_attributes"]
    assert run_review_attribute_batch.ALLOW_ENV in payload["apply_required_env"]


def test_deterministic_preview_builds_review_quality_for_sufficient_evidence():
    candidate = _candidate(
        category="restaurant",
        organic=3,
        posts=[
            {"title": "카페포렛 커피 맛집", "body": "디저트가 맛있고 직원이 친절했어요"},
            {"title": "카페포렛 브런치", "body": "분위기가 조용하고 메뉴가 좋았어요"},
        ],
    )

    enrichment = review_attribute_batch.build_deterministic_enrichments([candidate])[0]
    quality = review_attribute_batch.review_quality_payload(candidate, enrichment)

    assert enrichment.schema_version == review_attribute_batch.DETERMINISTIC_VERSION
    assert enrichment.attribute_scores["taste"] > 0.45
    assert enrichment.attribute_scores["service"] > 0.45
    assert quality is not None
    assert quality["schema_version"] == review_attribute_batch.QUALITY_VERSION
    assert quality["score"] > 0


def test_low_evidence_keeps_review_quality_null():
    candidate = _candidate(category="culture_venue", organic=2)
    enrichment = review_attribute_batch.build_deterministic_enrichments([candidate])[0]

    assert review_attribute_batch.review_quality_payload(candidate, enrichment) is None


def test_parse_ai_response_filters_category_attributes_and_keeps_ids():
    candidate = _candidate(category="culture_venue", organic=3)
    raw = json.dumps(
        {
            "results": [
                {
                    "mention_id": candidate.mention_id,
                    "sentiment_score": 0.4,
                    "sentiment_confidence": 0.8,
                    "attribute_scores": {
                        "cultural_story": 0.9,
                        "taste": 0.99,
                        "walking_comfort": 0.7,
                    },
                    "attribute_confidence_avg": 0.75,
                    "evidence_terms": {
                        "cultural_story": ["전시 동선"],
                        "taste": ["맛집"],
                    },
                    "summary_ko": "전시와 동선 신호가 좋습니다.",
                    "reason": "official review evidence",
                }
            ]
        },
        ensure_ascii=False,
    )

    parsed = review_attribute_batch.parse_ai_response(raw, [candidate])[0]

    assert parsed.mention_id == candidate.mention_id
    assert parsed.schema_version == review_attribute_batch.PROMPT_VERSION
    assert parsed.sentiment_score == 0.4
    assert parsed.attribute_scores == {
        "cultural_story": 0.9,
        "walking_comfort": 0.7,
    }
    assert "taste" not in parsed.evidence_terms


def test_apply_requires_guard_before_reading_db(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.delenv(run_review_attribute_batch.ALLOW_ENV, raising=False)

    exit_code = run_review_attribute_batch.main(
        ["--apply", "--confirm", run_review_attribute_batch.CONFIRM_TEXT]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_review_attribute_batch.ALLOW_ENV in output
    assert dsn not in output
    assert password not in output


def test_apply_review_attribute_enrichments_targets_mentions_and_quality(monkeypatch):
    executed = []
    candidate = _candidate(category="restaurant", organic=3)
    enrichment = review_attribute_batch.build_deterministic_enrichments([candidate])[0]

    class Cursor:
        rowcount = 1

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self):
            return Cursor()

        def commit(self):
            executed.append(("commit", None))

    def connect(dsn, connect_timeout):
        executed.append(("connect", {"dsn": dsn, "connect_timeout": connect_timeout}))
        return Connection()

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))
    monkeypatch.setitem(
        sys.modules,
        "psycopg2.extras",
        SimpleNamespace(Json=lambda value: value),
    )

    updated = review_attribute_batch.apply_review_attribute_enrichments(
        dsn="postgresql://redacted",
        candidates=[candidate],
        enrichments=[enrichment],
        source_method="deterministic",
        connect_timeout=7,
    )

    assert updated == 1
    assert "UPDATE community.place_mentions_weekly" in executed[1][0]
    assert "review_attribute_batch" in executed[1][0]
    assert executed[1][1]["mention_id"] == candidate.mention_id
    assert executed[1][1]["review_quality"]["schema_version"] == (
        review_attribute_batch.QUALITY_VERSION
    )
    assert executed[-1] == ("commit", None)


def test_generate_ai_enrichments_prefers_review_batch_specific_deployment(monkeypatch):
    captured: dict[str, object] = {}
    candidate = _candidate(category="restaurant", organic=3)

    class FakeCompletions:
        def create(self, **kwargs):
            captured["completion"] = kwargs
            return SimpleNamespace(
                choices=[
                    SimpleNamespace(
                        message=SimpleNamespace(
                            content=json.dumps(
                                {
                                    "results": [
                                        {
                                            "mention_id": candidate.mention_id,
                                            "schema_version": review_attribute_batch.PROMPT_VERSION,
                                            "sentiment_score": 0.6,
                                            "sentiment_confidence": 0.8,
                                            "attribute_scores": {
                                                "taste": 0.9,
                                                "service": 0.7,
                                            },
                                            "attribute_confidence_avg": 0.75,
                                            "evidence_terms": {
                                                "taste": ["숯불 향"],
                                                "service": ["친절"],
                                            },
                                            "summary_ko": "맛과 서비스가 좋습니다.",
                                            "reason": "organic review evidence",
                                        }
                                    ]
                                },
                                ensure_ascii=False,
                            )
                        )
                    )
                ]
            )

    class FakeAzureOpenAI:
        def __init__(self, **kwargs):
            self.chat = SimpleNamespace(completions=FakeCompletions())

    fake_openai = SimpleNamespace(AzureOpenAI=FakeAzureOpenAI)
    monkeypatch.setitem(sys.modules, "openai", fake_openai)
    monkeypatch.setattr(
        review_attribute_batch,
        "get_settings",
        lambda: SimpleNamespace(
            azure_openai_endpoint="https://example.openai.azure.com",
            azure_openai_key="secret",
            azure_openai_api_version="2024-02-15-preview",
            azure_openai_deployment="generic-deployment",
            azure_openai_review_batch_deployment="review-nano-deployment",
        ),
    )

    enrichments = review_attribute_batch.generate_ai_enrichments(
        candidates=[candidate],
        batch_size=10,
        retry_attempts=1,
        retry_delay_sec=0.0,
    )

    assert len(enrichments) == 1
    assert captured["completion"]["model"] == "review-nano-deployment"


def _candidate(
    *,
    category: str,
    organic: int,
    posts: list[dict[str, str]] | None = None,
) -> review_attribute_batch.ReviewAttributeCandidate:
    return review_attribute_batch.ReviewAttributeCandidate(
        mention_id="11111111-1111-1111-1111-111111111111",
        week_start=date(2026, 6, 22),
        place_id="place-1",
        place_name_ko="카페포렛",
        provider="naver_blog",
        category=category,
        mention_count=max(organic, 1),
        organic_mention_count=organic,
        sentiment_score=0.2,
        attributes={
            "top_terms": ["커피", "디저트", "친절", "전시"],
            "filtered_ad_count": 0,
            "category_policy": "restaurant_food_terms_retained",
        },
        posts=tuple(posts or [{"title": "카페포렛 후기", "body": "전시 동선과 분위기가 좋았어요"}]),
    )
