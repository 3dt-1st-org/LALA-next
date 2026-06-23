from __future__ import annotations

import json
import sys
from datetime import UTC, datetime
from types import SimpleNamespace

from apps.api.app.services import review_mention_ingest
from apps.api.app.tools import run_review_mention_ingest


def test_review_mention_ingest_plan_uses_data_dictionary_names(capsys):
    exit_code = run_review_mention_ingest.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["db_mutation"] is False
    assert payload["target"] == "community.place_mentions_weekly"
    assert payload["input_relations"] == ["community.posts", "travel.places"]
    assert payload["apply_required_env"] == [
        "DB_DSN",
        run_review_mention_ingest.ALLOW_ENV,
    ]
    assert "attraction_food_only_review_rejected" in payload["review_rules"]


def test_preprocessing_filters_ads_food_noise_and_keeps_restaurant_food_terms():
    posts = [
        _post("ad", "호암미술관 전시가 좋았지만 협찬 원고료 제공받아 작성"),
        _post("food-noise", "호암미술관 맛집 카페 메뉴판 디저트 추천"),
        _post("restaurant", "카페포렛 커피와 디저트가 맛있고 서비스도 친절"),
    ]
    places = [
        _place("museum", "호암미술관", "culture_venue"),
        _place("cafe", "카페포렛", "restaurant"),
    ]

    result = review_mention_ingest.build_review_mention_result(
        posts=posts,
        places=places,
        limit=10,
    )

    decisions = {item.post.external_key: item for item in result.decisions}
    assert decisions["ad"].retained is False
    assert decisions["ad"].reason == "advertising_filtered"
    assert decisions["food-noise"].retained is False
    assert decisions["food-noise"].reason == "attraction_food_only_review_rejected"
    assert decisions["restaurant"].retained is True
    assert decisions["restaurant"].category_policy == "restaurant_food_terms_retained"
    assert result.retained_count == 1

    aggregates = {item.place_id: item for item in result.aggregates}
    assert aggregates["museum"].mention_count == 2
    assert aggregates["museum"].organic_mention_count == 0
    assert aggregates["museum"].attributes["filtered_ad_count"] == 1
    assert aggregates["cafe"].mention_count == 1
    assert aggregates["cafe"].organic_mention_count == 1
    assert "커피" in aggregates["cafe"].attributes["top_terms"]


def test_ambiguous_place_match_is_not_retained():
    posts = [_post("ambiguous", "호암미술관 전시와 산책 동선이 좋았어요")]
    places = [
        _place("museum-a", "호암미술관", "culture_venue"),
        _place("museum-b", "호암 미술관", "culture_venue"),
    ]

    result = review_mention_ingest.build_review_mention_result(
        posts=posts,
        places=places,
        limit=10,
    )

    assert result.ambiguous_count == 1
    assert result.decisions[0].reason == "ambiguous_match"
    assert result.decisions[0].retained is False
    assert result.aggregates[0].organic_mention_count == 0
    assert result.aggregates[0].attributes["category_policy"] == "place_experience_terms_retained"


def test_aggregate_adds_deterministic_review_attributes_for_sufficient_evidence():
    posts = [
        _post("restaurant-1", "카페포렛 커피와 디저트가 맛있고 서비스가 친절"),
        _post("restaurant-2", "카페포렛 브런치 메뉴가 좋고 분위기가 조용"),
        _post("restaurant-3", "카페포렛 반찬과 커피가 맛있고 안내가 편리"),
    ]
    places = [_place("cafe", "카페포렛", "restaurant")]

    result = review_mention_ingest.build_review_mention_result(
        posts=posts,
        places=places,
        limit=10,
    )

    aggregate = result.aggregates[0]
    assert aggregate.organic_mention_count == 3
    assert aggregate.attributes["review_attributes"]["schema_version"] == (
        "review-attributes-deterministic-v1"
    )
    assert aggregate.attributes["review_attributes"]["attribute_mean"] > 0.45
    assert aggregate.attributes["review_quality"]["schema_version"] == (
        "review-quality-deterministic-v1"
    )
    assert aggregate.attributes["review_quality"]["score"] > 0


def test_clean_review_text_removes_html_urls_hashtags_and_collapses_spaces():
    text = review_mention_ingest.clean_review_text(
        "<b>호암미술관</b>",
        "https://example.com/a",
        "전시!!!### 산책",
    )

    assert text == "호암미술관 전시!! 산책"


def test_apply_requires_guard_before_reading_db(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.delenv(run_review_mention_ingest.ALLOW_ENV, raising=False)

    exit_code = run_review_mention_ingest.main(
        ["--apply", "--confirm", run_review_mention_ingest.CONFIRM_TEXT]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_review_mention_ingest.ALLOW_ENV in output
    assert dsn not in output
    assert password not in output


def test_insert_review_mention_aggregates_targets_community_table(monkeypatch):
    executed = []

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

    inserted = review_mention_ingest.insert_review_mention_aggregates(
        dsn="postgresql://redacted",
        aggregates=[
            review_mention_ingest.ReviewMentionWeeklyAggregate(
                week_start=datetime(2026, 6, 22, tzinfo=UTC).date(),
                place_id="museum",
                place_name_ko="호암미술관",
                provider="naver_blog",
                category="culture_venue",
                mention_count=3,
                organic_mention_count=2,
                sentiment_score=0.5,
                attributes={"prompt_version": review_mention_ingest.PROMPT_VERSION},
            )
        ],
        connect_timeout=7,
    )

    assert inserted == 1
    assert "INSERT INTO community.place_mentions_weekly" in executed[1][0]
    assert "jsonb_build_object" in executed[1][0]
    assert "review-attributes-deterministic" in executed[1][0]
    assert executed[1][1]["place_id"] == "museum"
    assert executed[1][1]["organic_mention_count"] == 2
    assert executed[-1] == ("commit", None)


def _post(external_key: str, text: str) -> review_mention_ingest.ReviewMentionPost:
    return review_mention_ingest.ReviewMentionPost(
        provider="naver_blog",
        external_key=external_key,
        keyword=None,
        region_slug="suwon",
        title=text,
        body=None,
        post_url=None,
        created_at_source=datetime(2026, 6, 23, 9, 0, tzinfo=UTC),
        collected_at=datetime(2026, 6, 23, 10, 0, tzinfo=UTC),
    )


def _place(
    place_id: str,
    name_ko: str,
    category: str,
) -> review_mention_ingest.ReviewMentionPlace:
    return review_mention_ingest.ReviewMentionPlace(
        place_id=place_id,
        name_ko=name_ko,
        category=category,
        region_name_ko="용인시",
    )
