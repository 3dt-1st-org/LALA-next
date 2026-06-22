from __future__ import annotations

import json
import sys
from datetime import date
from types import SimpleNamespace

from apps.api.app.services import review_attribute_scoring
from apps.api.app.tools import run_review_attribute_batch


def test_review_attribute_plan_is_non_mutating(capsys):
    exit_code = run_review_attribute_batch.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["db_mutation"] is False
    assert payload["source"] == "community.place_mentions_weekly"
    assert payload["target"] == [
        "community.place_mentions_weekly",
        "travel.place_enrichments",
    ]
    assert "review_quality.score" in payload["score_outputs"]


def test_restaurant_review_quality_uses_food_and_service_terms():
    aggregate = review_attribute_scoring.ReviewMentionAggregate(
        id="agg-1",
        week_start=date(2026, 6, 15),
        place_id="place-1",
        place_name_ko="한국관",
        provider="naver_blog",
        category="restaurant",
        mention_count=8,
        organic_mention_count=7,
        sentiment_score=None,
        attributes={
            "top_terms": ["맛", "메뉴", "친절", "서비스", "분위기"],
            "filtered_ad_count": 1,
        },
    )

    score = review_attribute_scoring.score_review_aggregate(aggregate)

    assert score.review_quality_score is not None
    assert score.sentiment_score > 0
    assert score.attributes["taste"].count >= 2
    assert score.attributes["service"].count >= 2
    assert score.confidence <= 0.65


def test_low_evidence_keeps_review_quality_null():
    aggregate = review_attribute_scoring.ReviewMentionAggregate(
        id="agg-2",
        week_start=date(2026, 6, 15),
        place_id="place-2",
        place_name_ko="수원화성",
        provider="naver_blog",
        category="attraction",
        mention_count=2,
        organic_mention_count=2,
        sentiment_score=None,
        attributes={"top_terms": ["역사", "산책"], "filtered_ad_count": 0},
    )

    score = review_attribute_scoring.score_review_aggregate(aggregate)

    assert score.review_quality_score is None
    assert score.insufficient_reason == "insufficient_organic_review_count"


def test_apply_requires_guard_before_fetch(monkeypatch, capsys):
    password = "example-password"
    dsn = "host=example.postgres.database.azure.com user=user password=" + password
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.delenv(run_review_attribute_batch.ALLOW_ENV, raising=False)

    def fail_fetch(**kwargs):
        raise AssertionError("fetch should not run before apply guard")

    monkeypatch.setattr(run_review_attribute_batch, "fetch_review_attribute_candidates", fail_fetch)

    exit_code = run_review_attribute_batch.main(
        [
            "--apply",
            "--confirm",
            run_review_attribute_batch.CONFIRM_TEXT,
        ]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_review_attribute_batch.ALLOW_ENV in output
    assert dsn not in output
    assert password not in output


def test_apply_review_attribute_scores_updates_weekly_and_inserts_enrichment(monkeypatch):
    aggregate = review_attribute_scoring.ReviewMentionAggregate(
        id="agg-3",
        week_start=date(2026, 6, 15),
        place_id="place-3",
        place_name_ko="경기아트센터",
        provider="naver_blog",
        category="culture_venue",
        mention_count=10,
        organic_mention_count=9,
        sentiment_score=None,
        attributes={"top_terms": ["전시", "문화", "동선", "사진"], "filtered_ad_count": 1},
    )
    score = review_attribute_scoring.score_review_aggregate(aggregate)
    executed = []

    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))
            self.rowcount = 1

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self):
            return Cursor()

        def commit(self):
            executed.append(("commit", None))

        def close(self):
            executed.append(("close", None))

    def connect(dsn, connect_timeout):
        executed.append(("connect", {"dsn": dsn, "connect_timeout": connect_timeout}))
        return Connection()

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))
    monkeypatch.setitem(sys.modules, "psycopg2.extras", SimpleNamespace(Json=lambda value, dumps: value))

    payload = review_attribute_scoring.apply_review_attribute_scores(
        dsn="host=db.example dbname=lala",
        scores=[score],
        connect_timeout=7,
    )

    assert payload["updated_weekly_aggregates"] == 1
    assert payload["inserted_enrichments"] == 1
    assert "UPDATE community.place_mentions_weekly" in executed[1][0]
    assert "INSERT INTO travel.place_enrichments" in executed[2][0]
    assert executed[-2] == ("commit", None)
    assert executed[-1] == ("close", None)
