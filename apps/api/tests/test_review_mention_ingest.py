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

        def cursor(self, cursor_factory=None):
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


def test_preview_and_attributes_redact_url_shaped_external_keys():
    """S1: raw URL-shaped external keys must never reach preview or attributes."""
    retained_key = "https://example.test/post/123?x=1"
    filtered_key = "https://example.test/post/456?q=ad#section"
    posts = [
        _post(retained_key, "카페포렛 커피와 디저트가 맛있고 서비스도 친절"),
        _post(filtered_key, "카페포렛 협찬 원고료 제공받아 작성"),
    ]
    places = [_place("cafe", "카페포렛", "restaurant")]

    result = review_mention_ingest.build_review_mention_result(
        posts=posts,
        places=places,
        limit=10,
    )

    serialized = json.dumps(result.to_public_dict(), ensure_ascii=False)
    # Raw key, and every URL-shaped fragment of it, must be absent.
    for fragment in (
        retained_key,
        filtered_key,
        "example.test",
        "post/123",
        "post/456",
        "x=1",
        "q=ad",
    ):
        assert fragment not in serialized

    aggregate = result.aggregates[0]
    attributes_json = json.dumps(aggregate.attributes, ensure_ascii=False)
    for fragment in ("example.test", "post/123", "post/456"):
        assert fragment not in attributes_json

    preprocess = aggregate.attributes["preprocess"]
    # Only digests survive; the un-consumed filtered list is now a count.
    assert "filtered_external_keys" not in preprocess
    assert preprocess["filtered_external_key_count"] == 1
    assert preprocess["retained_external_keys"] == [
        review_mention_ingest.external_key_sha256("naver_blog", retained_key)
    ]
    # Digests must be 64-char hex, never URL-shaped.
    for digest in preprocess["retained_external_keys"]:
        assert len(digest) == 64
        assert all(char in "0123456789abcdef" for char in digest)


def test_external_key_sha256_is_provider_scoped():
    """Same key under a different provider must yield a different digest."""
    key = "https://example.test/post/789"
    naver = review_mention_ingest.external_key_sha256("naver_blog", key)
    instagram = review_mention_ingest.external_key_sha256("instagram", key)

    assert naver != instagram
    assert len(naver) == 64
    assert key not in naver


def test_external_key_digest_bound_is_fail_closed_not_truncate_hash():
    """S1 boundary: at-limit material digests normally; over-limit is excluded.

    Truncate-then-hash would make a 4097-char key whose first 4096 chars equal a
    shorter key's material collide into the SAME digest — over-bound keys must
    therefore yield None, never a truncated digest.
    """
    bound = review_mention_ingest._EXTERNAL_KEY_HASH_INPUT_MAX
    provider = "naver_blog"
    at_limit_key = "k" * (bound - len(provider) - 1)  # material exactly 4096
    over_limit_key = "k" * (bound - len(provider))  # material 4097

    assert len(f"{provider}|{at_limit_key}") == bound
    at_limit = review_mention_ingest.external_key_sha256(provider, at_limit_key)
    assert at_limit is not None and len(at_limit) == 64
    # No truncation fallback: over-bound yields None, never a truncated digest.
    assert review_mention_ingest.external_key_sha256(provider, over_limit_key) is None
    # Distinct in-bound materials never collide (sanity on the digest itself).
    assert review_mention_ingest.external_key_sha256(provider, at_limit_key[:-1] + "z") != at_limit


def test_over_bound_key_is_excluded_from_preview_and_attributes():
    """S1: an over-bound key contributes no digest and no value anywhere."""
    provider = "naver_blog"
    bound = review_mention_ingest._EXTERNAL_KEY_HASH_INPUT_MAX
    over_limit_key = (
        "https://example.test/overbound?" + "z" * bound  # far past the material bound
    )
    posts = [
        _post(over_limit_key, "카페포렛 커피와 디저트가 맛있고 서비스도 친절"),
        _post("https://example.test/ok/1", "카페포렛 브런치 메뉴가 좋고 분위기가 조용"),
    ]
    places = [_place("cafe", "카페포렛", "restaurant")]

    result = review_mention_ingest.build_review_mention_result(
        posts=posts,
        places=places,
        limit=10,
    )

    serialized = json.dumps(result.to_public_dict(), ensure_ascii=False)
    assert over_limit_key not in serialized
    # Preview decisions are limited to the first 5; the over-bound one is there.
    assert any(
        item["external_key_sha256"] is None
        for item in result.to_public_dict()["preview"]["decisions"]
    )
    assert any(
        item["external_key_sha256"] is not None
        for item in result.to_public_dict()["preview"]["decisions"]
    )

    preprocess = result.aggregates[0].attributes["preprocess"]
    # No digest for the over-bound key — only the in-bound key's digest.
    assert preprocess["retained_external_keys"] == [
        review_mention_ingest.external_key_sha256(provider, "https://example.test/ok/1")
    ]
    assert preprocess["retained_external_key_bounded_count"] == 1
    attributes_json = json.dumps(result.aggregates[0].attributes, ensure_ascii=False)
    assert "example.test/overbound" not in attributes_json


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


def test_cli_date_filter_validation_rejects_invalid_format(capsys):
    """Test that CLI rejects invalid date formats."""
    exit_code = run_review_mention_ingest.main(["--preview", "--since", "not-a-date", "--json"])

    assert exit_code == 2
    payload = json.loads(capsys.readouterr().out)
    assert payload["ok"] is False
    assert "Invalid --since date format" in payload["error"]
    # Ensure error message doesn't echo the supplied invalid value
    assert "not-a-date" not in payload["error"]


def test_cli_date_filter_validation_rejects_inverted_range(capsys):
    """Test that CLI rejects inverted date ranges."""
    exit_code = run_review_mention_ingest.main(
        ["--preview", "--since", "2026-06-30", "--until", "2026-06-01", "--json"]
    )

    assert exit_code == 2
    payload = json.loads(capsys.readouterr().out)
    assert payload["ok"] is False
    assert "Invalid --until date range" in payload["error"]
    # Ensure error message doesn't echo the supplied date values
    assert "2026-06-30" not in payload["error"]
    assert "2026-06-01" not in payload["error"]


def test_cli_place_id_validation_rejects_blank(capsys):
    """Test that CLI rejects blank place_id."""
    exit_code = run_review_mention_ingest.main(["--preview", "--place-id", "", "--json"])

    assert exit_code == 2
    payload = json.loads(capsys.readouterr().out)
    assert payload["ok"] is False
    assert "Invalid --place-id value" in payload["error"]


def test_cli_place_id_validation_rejects_unsafe_characters(capsys):
    """Test that CLI rejects unsafe characters in place_id."""
    exit_code = run_review_mention_ingest.main(
        ["--preview", "--place-id", "museum'; DROP TABLE--", "--json"]
    )

    assert exit_code == 2
    payload = json.loads(capsys.readouterr().out)
    assert payload["ok"] is False
    assert "Invalid --place-id format" in payload["error"]
    # Ensure error message doesn't echo the supplied unsafe value or attack marker
    assert "museum" not in payload["error"]
    assert "DROP" not in payload["error"]
    assert "'" not in payload["error"]


def test_cli_trims_whitespace_padded_place_id(monkeypatch, capsys):
    """Test that CLI trims whitespace from valid place_id before passing to service."""
    executed = []

    class Cursor:
        def __init__(self):
            self.rows = []

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))
            self.rows = []

        def fetchall(self):
            return self.rows

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self, cursor_factory=None):
            return Cursor()

    def connect(dsn, connect_timeout):
        return Connection()

    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))
    monkeypatch.setitem(
        sys.modules,
        "psycopg2.extras",
        SimpleNamespace(RealDictCursor=Cursor),
    )

    exit_code = run_review_mention_ingest.main(
        ["--preview", "--place-id", "  hoam-museum-123  ", "--json"]
    )

    assert exit_code == 0
    # Verify place_id filter was passed to places query as trimmed value
    places_query = executed[1]
    assert "places" in places_query[0].lower()
    params = places_query[1]
    assert "place_id" in params
    assert params["place_id"] == "hoam-museum-123"  # trimmed, not "  hoam-museum-123  "


def test_cli_accepts_valid_date_filters(monkeypatch, capsys):
    """Test that CLI accepts valid date filters and passes them to service."""
    executed = []

    class Cursor:
        def __init__(self):
            self.rows = []

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))
            self.rows = []

        def fetchall(self):
            return self.rows

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self, cursor_factory=None):
            return Cursor()

    def connect(dsn, connect_timeout):
        return Connection()

    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))
    monkeypatch.setitem(
        sys.modules,
        "psycopg2.extras",
        SimpleNamespace(RealDictCursor=Cursor),
    )

    exit_code = run_review_mention_ingest.main(
        ["--preview", "--since", "2026-06-01", "--until", "2026-06-30", "--json"]
    )

    assert exit_code == 0
    # Verify date filters were passed to the query
    assert len(executed) >= 2  # At least posts and places queries
    posts_query = executed[0]
    assert "posts" in posts_query[0].lower()
    # Check that date parameters were included
    params = posts_query[1]
    assert "since" in params
    assert "until" in params
    assert params["since"] == "2026-06-01"
    assert params["until"] == "2026-06-30"


def test_cli_accepts_valid_place_id_filter(monkeypatch, capsys):
    """Test that CLI accepts valid place_id filter and passes it to service."""
    executed = []

    class Cursor:
        def __init__(self):
            self.rows = []

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))
            self.rows = []

        def fetchall(self):
            return self.rows

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self, cursor_factory=None):
            return Cursor()

    def connect(dsn, connect_timeout):
        return Connection()

    monkeypatch.setenv("DB_DSN", "postgresql://redacted")
    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))
    monkeypatch.setitem(
        sys.modules,
        "psycopg2.extras",
        SimpleNamespace(RealDictCursor=Cursor),
    )

    exit_code = run_review_mention_ingest.main(
        ["--preview", "--place-id", "hoam-museum-123", "--json"]
    )

    assert exit_code == 0
    # Verify place_id filter was passed to places query
    places_query = executed[1]
    assert "places" in places_query[0].lower()
    params = places_query[1]
    assert "place_id" in params
    assert params["place_id"] == "hoam-museum-123"


def test_date_parsing_supports_multiple_formats():
    """Test that _parse_date supports various date formats."""
    # YYYY-MM-DD format
    result = run_review_mention_ingest._parse_date("2026-06-15")
    assert result is not None
    assert result.year == 2026
    assert result.month == 6
    assert result.day == 15

    # ISO datetime format
    result = run_review_mention_ingest._parse_date("2026-06-15T14:30:00Z")
    assert result is not None
    assert result.year == 2026
    assert result.month == 6
    assert result.day == 15
    assert result.hour == 14
    assert result.minute == 30

    # Space-separated datetime format
    result = run_review_mention_ingest._parse_date("2026-06-15 14:30:00")
    assert result is not None
    assert result.year == 2026
    assert result.month == 6
    assert result.day == 15
    assert result.hour == 14
    assert result.minute == 30

    # Invalid format
    result = run_review_mention_ingest._parse_date("invalid")
    assert result is None


def test_service_includes_date_filters_in_query(monkeypatch):
    """Test that fetch_review_mention_inputs properly applies date filters in SQL."""
    executed = []

    class Cursor:
        def __init__(self):
            self.rows = []

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))
            self.rows = []

        def fetchall(self):
            return self.rows

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self, cursor_factory=None):
            return Cursor()

    def connect(dsn, connect_timeout):
        return Connection()

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))
    monkeypatch.setitem(
        sys.modules,
        "psycopg2.extras",
        SimpleNamespace(RealDictCursor=Cursor),
    )

    review_mention_ingest.fetch_review_mention_inputs(
        dsn="postgresql://redacted",
        limit=100,
        provider="naver_blog",
        connect_timeout=5,
        since="2026-06-01",
        until="2026-06-30",
        place_id="test-place",
    )

    # Check posts query has date filters
    posts_query = executed[0][0]
    posts_params = executed[0][1]
    assert ">=" in posts_query
    assert "<" in posts_query
    assert posts_params["since"] == "2026-06-01"
    assert posts_params["until"] == "2026-06-30"

    # Check places query has place_id filter
    places_query = executed[1][0]
    places_params = executed[1][1]
    assert "place_id" in places_query
    assert places_params["place_id"] == "test-place"


def test_service_without_filters_uses_default_behavior(monkeypatch):
    """Test that fetch_review_mention_inputs works without filters (backward compatibility)."""
    executed = []

    class Cursor:
        def __init__(self):
            self.rows = []

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))
            self.rows = []

        def fetchall(self):
            return self.rows

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self, cursor_factory=None):
            return Cursor()

    def connect(dsn, connect_timeout):
        return Connection()

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))
    monkeypatch.setitem(
        sys.modules,
        "psycopg2.extras",
        SimpleNamespace(RealDictCursor=Cursor),
    )

    review_mention_ingest.fetch_review_mention_inputs(
        dsn="postgresql://redacted",
        limit=100,
        provider="all",
        connect_timeout=5,
    )

    # Check posts query doesn't have date filters
    posts_params = executed[0][1]
    assert "since" not in posts_params
    assert "until" not in posts_params
    assert "place_id" not in posts_params

    # Check places query doesn't have place_id filter
    places_params = executed[1][1]
    assert "place_id" not in places_params


def test_plan_mode_validates_invalid_date_and_exits_2(capsys):
    """Test that plan mode validates date filters and exits 2 for invalid dates."""
    exit_code = run_review_mention_ingest.main(["--since", "not-a-date", "--json"])

    assert exit_code == 2
    payload = json.loads(capsys.readouterr().out)
    assert payload["ok"] is False
    assert "Invalid --since date format" in payload["error"]
    # Ensure error message doesn't echo the supplied invalid value
    assert "not-a-date" not in payload["error"]


def test_plan_mode_validates_inverted_range_and_exits_2(capsys):
    """Test that plan mode validates date filters and exits 2 for inverted ranges."""
    exit_code = run_review_mention_ingest.main(
        ["--since", "2026-06-30", "--until", "2026-06-01", "--json"]
    )

    assert exit_code == 2
    payload = json.loads(capsys.readouterr().out)
    assert payload["ok"] is False
    assert "Invalid --until date range" in payload["error"]
    # Ensure error message doesn't echo the supplied date values
    assert "2026-06-30" not in payload["error"]
    assert "2026-06-01" not in payload["error"]


def test_plan_mode_with_valid_filters_includes_metadata_and_no_db_call(capsys, monkeypatch):
    """Test that plan mode with valid filters includes normalized metadata and doesn't call DB."""
    db_called = False

    def connect(dsn, connect_timeout):
        nonlocal db_called
        db_called = True
        raise RuntimeError("DB should not be called in plan mode")

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))

    exit_code = run_review_mention_ingest.main(
        ["--since", "2026-06-01", "--until", "2026-06-30", "--place-id", "museum-123", "--json"]
    )

    assert exit_code == 0
    assert not db_called, "Plan mode should not connect to database"

    payload = json.loads(capsys.readouterr().out)
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["since"] == "2026-06-01"
    assert payload["until"] == "2026-06-30"
    assert payload["place_id"] == "museum-123"


def test_plan_mode_without_filters_remains_compatible(capsys, monkeypatch):
    """Test that plan mode without filters remains backward compatible."""
    db_called = False

    def connect(dsn, connect_timeout):
        nonlocal db_called
        db_called = True
        raise RuntimeError("DB should not be called in plan mode")

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))

    exit_code = run_review_mention_ingest.main(["--json"])

    assert exit_code == 0
    assert not db_called, "Plan mode should not connect to database"

    payload = json.loads(capsys.readouterr().out)
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    # Old plan payload keys should still be present
    assert "target" in payload
    assert "job_name" in payload
    assert "prompt_version" in payload
    assert "apply_required_env" in payload
    assert "review_rules" in payload
    # No filter keys should be present
    assert "since" not in payload
    assert "until" not in payload
    assert "place_id" not in payload
