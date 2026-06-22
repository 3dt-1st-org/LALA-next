from __future__ import annotations

import json
import sys
from types import SimpleNamespace

from apps.api.app.services import review_mention_ingest
from apps.api.app.tools import run_review_mention_ingest


def test_review_mention_plan_is_non_mutating(capsys):
    exit_code = run_review_mention_ingest.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["live_api_call"] is False
    assert payload["db_mutation"] is False
    assert payload["target"] == [
        "community.posts",
        "community.place_mentions_weekly",
    ]
    assert "deterministic_ad_filter" in payload["filters"]


def test_non_restaurant_food_only_review_is_rejected():
    target = review_mention_ingest.ReviewMentionTarget(
        place_id="place-1",
        name_ko="수원화성",
        category="attraction",
        region_name_ko="수원시",
    )
    item = review_mention_ingest.NaverBlogItem(
        title="<b>수원화성</b> 근처 맛집",
        description="수원화성 앞 카페 디저트 메뉴판이 좋았던 내돈내산 맛집 후기",
        link="https://blog.example/a",
        postdate="20260621",
    )

    candidate = review_mention_ingest.preprocess_naver_blog_item(
        target=target,
        item=item,
        seen_hashes=set(),
    )

    assert candidate.is_relevant is False
    assert candidate.is_organic is False
    assert "food_only_non_restaurant" in candidate.rejection_reasons


def test_restaurant_food_terms_are_retained():
    target = review_mention_ingest.ReviewMentionTarget(
        place_id="place-2",
        name_ko="한국관",
        category="restaurant",
        region_name_ko="수원시",
    )
    item = review_mention_ingest.NaverBlogItem(
        title="한국관 맛집 후기",
        description="한국관은 반찬이 좋고 서비스가 친절해서 재방문하고 싶은 식당",
        link="https://blog.example/b",
        postdate="20260621",
    )

    candidate = review_mention_ingest.preprocess_naver_blog_item(
        target=target,
        item=item,
        seen_hashes=set(),
    )

    assert candidate.is_relevant is True
    assert candidate.is_organic is True
    assert "food_only_non_restaurant" not in candidate.rejection_reasons
    assert {"반찬", "서비스", "친절", "재방문"}.intersection(candidate.retained_terms)


def test_place_matching_accepts_reordered_name_tokens():
    target = review_mention_ingest.ReviewMentionTarget(
        place_id="place-2b",
        name_ko="사찰음식 전문점 발우공양",
        category="restaurant",
        region_name_ko="종로구",
    )
    item = review_mention_ingest.NaverBlogItem(
        title="발우공양 사찰음식 전문점 인사동 맛집",
        description="종로구에서 사찰음식 전문점 발우공양을 방문한 후기",
        link="https://blog.example/b2",
        postdate="20260621",
    )

    candidate = review_mention_ingest.preprocess_naver_blog_item(
        target=target,
        item=item,
        seen_hashes=set(),
    )

    assert candidate.is_relevant is True
    assert candidate.is_organic is True


def test_ads_and_duplicates_are_excluded_from_organic_count():
    target = review_mention_ingest.ReviewMentionTarget(
        place_id="place-3",
        name_ko="경기아트센터",
        category="culture_venue",
        region_name_ko="수원시",
    )
    items = [
        review_mention_ingest.NaverBlogItem(
            title="경기아트센터 전시 관람",
            description="경기아트센터 전시 동선이 좋고 사진 찍기 좋은 문화 공간",
            link="https://blog.example/c1",
            postdate="20260621",
        ),
        review_mention_ingest.NaverBlogItem(
            title="경기아트센터 전시 관람",
            description="경기아트센터 전시 동선이 좋고 사진 찍기 좋은 문화 공간",
            link="https://blog.example/c2",
            postdate="20260621",
        ),
        review_mention_ingest.NaverBlogItem(
            title="경기아트센터 협찬",
            description="경기아트센터 광고 체험단 제공받아 작성한 홍보 후기",
            link="https://blog.example/c3",
            postdate="20260621",
        ),
    ]

    result = review_mention_ingest.build_review_mention_result(
        targets=(target,),
        provider="naver_blog",
        items_by_place_id={target.place_id: items},
    )

    aggregate = result.aggregates[0]
    assert aggregate.mention_count == 3
    assert aggregate.organic_mention_count == 1
    assert aggregate.attributes["duplicate_count"] == 1
    assert aggregate.attributes["filtered_ad_count"] == 1
    assert "전시" in aggregate.attributes["top_terms"]


def test_apply_requires_guard_before_fetch(monkeypatch, capsys):
    password = "example-password"
    dsn = "host=example.postgres.database.azure.com user=user password=" + password
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.setenv("NAVER_CLIENT_ID", "client")
    monkeypatch.setenv("NAVER_CLIENT_SECRET", "secret")
    monkeypatch.delenv(run_review_mention_ingest.ALLOW_ENV, raising=False)

    def fail_fetch(**kwargs):
        raise AssertionError("fetch should not run before apply guard")

    monkeypatch.setattr(run_review_mention_ingest, "fetch_review_mention_targets", fail_fetch)

    exit_code = run_review_mention_ingest.main(
        [
            "--apply",
            "--confirm",
            run_review_mention_ingest.CONFIRM_TEXT,
        ]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_review_mention_ingest.ALLOW_ENV in output
    assert dsn not in output
    assert password not in output


def test_upsert_review_mentions_writes_posts_and_weekly_aggregates(monkeypatch):
    target = review_mention_ingest.ReviewMentionTarget(
        place_id="place-4",
        name_ko="한국관",
        category="restaurant",
        region_name_ko="수원시",
    )
    result = review_mention_ingest.build_review_mention_result(
        targets=(target,),
        provider="naver_blog",
        items_by_place_id={
            target.place_id: [
                review_mention_ingest.NaverBlogItem(
                    title="한국관 맛집",
                    description="한국관은 메뉴가 좋고 친절한 서비스가 기억남",
                    link="https://blog.example/d",
                    postdate="20260621",
                )
            ]
        },
    )
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

    payload = review_mention_ingest.upsert_review_mention_result(
        dsn="host=db.example dbname=lala",
        result=result,
        connect_timeout=7,
    )

    assert payload["inserted_posts"] == 1
    assert payload["upserted_aggregates"] == 1
    assert "INSERT INTO community.posts" in executed[1][0]
    assert "INSERT INTO community.place_mentions_weekly" in executed[2][0]
    assert executed[-2] == ("commit", None)
    assert executed[-1] == ("close", None)
