from __future__ import annotations

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest

from apps.api.app.core.errors import ServiceError
from apps.api.app.services import places_service, weather_service


def _fake_settings(
    *,
    static_snapshot_fallback: bool = False,
    db_dsn: str = "",
    feature_flags: dict | None = None,
):
    return SimpleNamespace(
        static_snapshot_fallback=static_snapshot_fallback,
        db_dsn=db_dsn,
        feature_flags=feature_flags or {},
    )


def _patch_db_fetch_places(monkeypatch, *, places=None, raises=None):
    """Replace ``db_repository.fetch_places`` used by ``places_service``.

    When ``raises`` is given it is raised instead of returning ``places``.
    The captured call kwargs are appended to the returned list's ``calls``.
    """
    captured: list[dict] = []

    def fake_fetch_places(**kwargs):
        captured.append(kwargs)
        if raises is not None:
            raise raises
        return list(places or [])

    monkeypatch.setattr(places_service.db_repository, "fetch_places", fake_fetch_places)
    return captured


def _freeze_service_now(monkeypatch, *, fixed: datetime) -> None:
    """Pin the wall-clock ``list_places`` reads via ``datetime.now``.

    ``list_places`` derives ``slot_time`` (the operating-status check) and the
    freshness ``now`` from ``datetime.now(UTC)``. Without freezing, an assertion
    on a category's "영업중" reason flickers with the CI run's UTC hour.
    ``fixed`` must be timezone-aware.
    """

    class _FrozenDateTime(datetime):
        @classmethod
        def now(cls, tz=None):
            return fixed.astimezone(tz) if tz else fixed.replace(tzinfo=None)

    monkeypatch.setattr(places_service, "datetime", _FrozenDateTime)


@pytest.mark.parametrize(
    "category",
    [
        "foo",
        "restaurants",
        "attractions",
        "events",
        "culture",
        "culture venue",
        "cafe",
        "hotel",
        "FOO",
        "  foo  ",
    ],
)
def test_list_places_rejects_invalid_category(category: str, monkeypatch) -> None:
    # Validation runs before any DB/repository call, so no DB is needed.
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())

    with pytest.raises(ServiceError) as exc_info:
        places_service.list_places(
            lat=37.5665,
            lng=126.978,
            radius_m=1000,
            category=category,
            language="ko",
        )

    err = exc_info.value
    assert err.status_code == 400
    assert err.code == "INVALID_CATEGORY"
    assert err.retryable is False


@pytest.mark.parametrize(
    ("category", "expected"),
    [
        ("all", "all"),
        ("attraction", "attraction"),
        ("restaurant", "restaurant"),
        ("event", "event"),
        ("culture_venue", "culture_venue"),
        # Case differences normalize to lowercase before validation.
        ("All", "all"),
        ("ATTRACTION", "attraction"),
        ("Restaurant", "restaurant"),
        # Surrounding whitespace is stripped before validation.
        (" event ", "event"),
        # Empty / None default to "all" via `(category or "all")`.
        ("", "all"),
        (None, "all"),
    ],
)
def test_list_places_accepts_valid_category_and_normalizes(
    category: str | None, expected: str, monkeypatch
) -> None:
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())
    captured = _patch_db_fetch_places(monkeypatch, places=[{"name": "spot", "score": 0.5}])

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category=category,
        language="ko",
    )

    assert result["source"] == "db"
    assert result["query"]["category"] == expected
    # The normalized category is forwarded to the repository.
    assert captured[0]["category"] == expected


@pytest.mark.parametrize(
    ("language", "expected"),
    [
        ("ko", "ko"),
        ("KOR", "ko"),
        ("Korean", "ko"),
        ("kr", "ko"),
        ("KO", "ko"),
        ("en", "en"),
        ("ENG", "en"),
        ("English", "en"),
        # Unknown / empty / None fall back to the default ("ko").
        ("ja", "ko"),
        ("français", "ko"),
        ("", "ko"),
        (None, "ko"),
        ("xyz", "ko"),
    ],
)
def test_list_places_normalizes_language(language: str | None, expected: str, monkeypatch) -> None:
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())
    captured = _patch_db_fetch_places(monkeypatch, places=[{"name": "spot", "score": 0.5}])

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="all",
        language=language,
    )

    assert result["query"]["language"] == expected
    assert captured[0]["language"] == expected


def test_list_places_forwards_query_params_to_repository(monkeypatch) -> None:
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())
    captured = _patch_db_fetch_places(monkeypatch, places=[{"name": "spot"}])

    places_service.list_places(
        lat=37.2636,
        lng=127.0286,
        radius_m=2500,
        category="restaurant",
        language="en",
        include_scores=True,
        limit=25,
    )

    call = captured[0]
    assert call["lat"] == 37.2636
    assert call["lng"] == 127.0286
    assert call["radius_m"] == 2500
    assert call["category"] == "restaurant"
    assert call["language"] == "en"
    assert call["include_scores"] is True
    assert call["limit"] == 25


def test_list_places_returns_db_payload_when_db_has_places(monkeypatch) -> None:
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())
    places = [
        {"name": "경복궁", "score": 0.9},
        {"name": "남산타워", "score": 0.8},
    ]
    _patch_db_fetch_places(monkeypatch, places=places)

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="attraction",
        language="ko",
        include_scores=True,
    )

    assert result["count"] == 2
    # V1-RC1: result places now include reason/freshness fields
    assert len(result["places"]) == 2
    assert result["places"][0]["name"] == "경복궁"
    assert result["places"][1]["name"] == "남산타워"
    # Original scores preserved
    assert result["places"][0]["score"] == 0.9
    assert result["places"][1]["score"] == 0.8
    # New V1-RC1 fields present
    assert "reason" in result["places"][0]
    assert "freshness" in result["places"][0]
    assert result["source"] == "db"
    assert result["location_engine"] == "postgis"
    assert result["query"]["include_scores"] is True


def test_list_places_raises_503_when_db_unavailable_and_no_fallback(
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        places_service, "get_settings", lambda: _fake_settings(static_snapshot_fallback=False)
    )
    _patch_db_fetch_places(
        monkeypatch,
        raises=places_service.db_repository.DatabaseReadError("places_query_failed"),
    )

    with pytest.raises(ServiceError) as exc_info:
        places_service.list_places(
            lat=37.5665,
            lng=126.978,
            radius_m=1000,
            category="all",
            language="ko",
        )

    err = exc_info.value
    assert err.status_code == 503
    assert err.code == "PLACES_DB_UNAVAILABLE"
    assert err.retryable is True


def test_list_places_falls_back_to_static_snapshot_without_scores(monkeypatch) -> None:
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(static_snapshot_fallback=True, db_dsn=""),
    )
    _patch_db_fetch_places(
        monkeypatch,
        raises=places_service.db_repository.DatabaseReadError("places_query_failed"),
    )
    public_places = [
        {"name": "경복궁", "score": 0.92},
        {"name": "광화문", "score": 0.81},
    ]
    monkeypatch.setattr(
        places_service.public_mvp_data,
        "fetch_places",
        lambda **kwargs: [dict(p) for p in public_places],
    )

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="attraction",
        language="ko",
        include_scores=False,
    )

    assert result["count"] == 2
    assert result["source"] == places_service.public_mvp_data.SOURCE_NAME
    assert result["location_engine"] == "static_snapshot"
    # Scores are nullified through _places_without_scores.
    assert all(place["score"] is None for place in result["places"])
    # Non-score fields are preserved.
    assert [p["name"] for p in result["places"]] == ["경복궁", "광화문"]


def test_list_places_keeps_scores_in_static_snapshot_when_requested(monkeypatch) -> None:
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(static_snapshot_fallback=True),
    )
    _patch_db_fetch_places(
        monkeypatch,
        raises=places_service.db_repository.DatabaseReadError("psycopg2_unavailable"),
    )
    public_places = [{"name": "경복궁", "score": 0.92}]
    monkeypatch.setattr(
        places_service.public_mvp_data,
        "fetch_places",
        lambda **kwargs: [dict(p) for p in public_places],
    )

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="attraction",
        language="ko",
        include_scores=True,
    )

    assert result["source"] == places_service.public_mvp_data.SOURCE_NAME
    assert result["places"][0]["score"] == 0.92


def test_list_places_snapshot_path_reports_honest_data_as_of(monkeypatch) -> None:
    # Truthfulness: data_as_of on the snapshot path is the real snapshot
    # generated_at string (never fabricated). We pin the helper to a known
    # value so the assertion is deterministic and independent of the fixture.
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(static_snapshot_fallback=True, db_dsn=""),
    )
    _patch_db_fetch_places(
        monkeypatch,
        raises=places_service.db_repository.DatabaseReadError("places_query_failed"),
    )
    monkeypatch.setattr(
        places_service.public_mvp_data,
        "fetch_places",
        lambda **kwargs: [{"name": "경복궁", "score": 0.92}],
    )
    monkeypatch.setattr(
        places_service.public_mvp_data,
        "snapshot_generated_at",
        lambda: "2026-06-19T02:24:44.557686+00:00",
    )

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="attraction",
        language="ko",
    )

    assert result["source"] == places_service.public_mvp_data.SOURCE_NAME
    assert result["data_as_of"] == "2026-06-19T02:24:44.557686+00:00"


def test_list_places_db_path_reports_honest_null_data_as_of(monkeypatch) -> None:
    # DB path: without a live max(updated_at) probe we must not invent a value.
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())
    _patch_db_fetch_places(monkeypatch, places=[{"name": "경복궁", "score": 0.9}])

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="attraction",
        language="ko",
    )

    assert result["source"] == "db"
    assert result["data_as_of"] is None


def test_list_places_empty_path_reports_honest_null_data_as_of(monkeypatch) -> None:
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(static_snapshot_fallback=False, db_dsn=""),
    )
    _patch_db_fetch_places(monkeypatch, places=[])

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="all",
        language="ko",
    )

    assert result["count"] == 0
    assert result["data_as_of"] is None


def test_list_places_returns_empty_payload_when_no_results_and_no_fallback(
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(static_snapshot_fallback=False, db_dsn=""),
    )
    _patch_db_fetch_places(monkeypatch, places=[])

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="all",
        language="ko",
    )

    assert result["count"] == 0
    assert result["places"] == []
    assert result["source"] == "db"
    # No DB DSN configured -> "none" engine.
    assert result["location_engine"] == "none"


def test_list_places_empty_payload_reports_postgis_when_db_dsn_set(monkeypatch) -> None:
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(static_snapshot_fallback=False, db_dsn="postgres://x"),
    )
    _patch_db_fetch_places(monkeypatch, places=[])

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="all",
        language="ko",
    )

    assert result["location_engine"] == "postgis"


@pytest.mark.parametrize(
    ("place", "expected_score"),
    [
        ({"name": "경복궁", "score": 0.9}, None),
        ({"name": "남산타워"}, None),
        ({"name": "x", "score": 0}, None),
        ({"name": "x", "score": "high"}, None),
    ],
)
def test_places_without_scores_nullifies_score_field(place: dict, expected_score) -> None:
    result = places_service._places_without_scores([dict(place)])

    assert result[0]["score"] == expected_score
    # Other fields are preserved.
    for key, value in place.items():
        if key == "score":
            continue
        assert result[0][key] == value


def test_places_without_scores_does_not_mutate_input() -> None:
    places = [{"name": "경복궁", "score": 0.9}]
    original = [dict(p) for p in places]

    result = places_service._places_without_scores(places)

    # Input list and its dicts are untouched.
    assert places == original
    assert places[0]["score"] == 0.9
    # And each output item is a brand-new dict.
    assert result[0] is not places[0]


def test_places_without_scores_handles_empty_list() -> None:
    assert places_service._places_without_scores([]) == []


# ─────────────────────────────────────────────────────────────────────────
# V1-RC1: reason/freshness 도출 테스트
# ─────────────────────────────────────────────────────────────────────────


def test_derive_place_reason_all_signals_present() -> None:
    # 모든 신호가 있는 경우: canonical order로 결합
    # [operating] · [weather(S3)] · [activity(S2)] · [event(D4)] · [proximity] · [source(S1)]
    place = {
        "category": "restaurant",
        "distance_m": 300,
        "upstream_source": "tour_api",
        "_local_activity_band": "active",  # S2 min-sample-gated token (Lane 1)
        "_has_linked_event": True,  # D4 linked event for any category (Lane 1)
        "is_ongoing": True,
    }
    current_weather = {
        "outdoor_status": "bad",  # 비/미세먼지로 실내 우선
    }
    slot_time = "12:30"  # 영업시간 내

    result = places_service._derive_place_reason(
        place=place,
        current_weather=current_weather,
        slot_time=slot_time,
    )

    # 모든 신호가 canonical order로 결합된 결정론적 결과
    assert result == (
        "영업중 · 실내활동 적합 · 로컬 소비 활발 · 진행 중인 행사 · 근접 · 한국관광공사 데이터"
    )


def test_derive_place_reason_only_open_nearby() -> None:
    # 날씨 좋고 근접: 운영중 + 근접만
    place = {
        "category": "attraction",
        "distance_m": 400,
        "upstream_source": "canonical",
    }
    current_weather = {"outdoor_status": "good"}  # 날씨 good → 추가 안 함
    slot_time = "14:00"

    result = places_service._derive_place_reason(
        place=place,
        current_weather=current_weather,
        slot_time=slot_time,
    )

    assert result == "영업중 · 근접"


def test_derive_place_reason_honest_empty_closed() -> None:
    # 폐장 상태: 운영 관련 reason 없음 (honest empty)
    place = {
        "category": "restaurant",
        "distance_m": 100,
        "upstream_source": "kopis",
    }
    current_weather = {"outdoor_status": "good"}
    slot_time = "23:00"  # 영업시간 외

    result = places_service._derive_place_reason(
        place=place,
        current_weather=current_weather,
        slot_time=slot_time,
    )

    # closed면 운영 reason 추가 안 함 (honest empty); D2 per-source phrase
    assert result == "근접 · 공연예술통합전산망 데이터"


def test_derive_place_reason_honest_empty_all_bad_signals() -> None:
    # 모든 신호가 부적합한 경우: 완전한 honest empty
    place = {
        "category": "attraction",
        "distance_m": 2000,  # 근접 아님
        "upstream_source": "canonical",  # 공식 아님
    }
    current_weather = {"outdoor_status": "good"}  # 날씨 good → 추가 안 함
    slot_time = "22:00"  # 폐장 가정

    result = places_service._derive_place_reason(
        place=place,
        current_weather=current_weather,
        slot_time=slot_time,
    )

    assert result == ""  # honest empty, never "이유 없음"


def test_derive_place_reason_indoor_only_bad_weather() -> None:
    # 실내 우선 카테고리 + bad weather만
    place = {
        "category": "culture_venue",
        "distance_m": 1200,
        "upstream_source": "canonical",
    }
    current_weather = {"outdoor_status": "bad"}
    slot_time = "15:00"

    result = places_service._derive_place_reason(
        place=place,
        current_weather=current_weather,
        slot_time=slot_time,
    )

    assert result == "영업중 · 실내활동 적합"


def test_derive_place_reason_proximity_under_500m() -> None:
    # 500m 이하만 근접 표시
    place = {
        "category": "event",
        "distance_m": 500,
        "upstream_source": "canonical",
    }
    current_weather = {"outdoor_status": "good"}
    slot_time = "10:00"

    result = places_service._derive_place_reason(
        place=place,
        current_weather=current_weather,
        slot_time=slot_time,
    )

    assert result == "영업중 · 근접"


def test_derive_place_reason_proximity_over_500m() -> None:
    # 500m 초과는 근접 reason 없음
    place = {
        "category": "restaurant",
        "distance_m": 501,
        "upstream_source": "canonical",
    }
    current_weather = {"outdoor_status": "good"}
    slot_time = "12:00"

    result = places_service._derive_place_reason(
        place=place,
        current_weather=current_weather,
        slot_time=slot_time,
    )

    assert result == "영업중"  # 근접 없음


def test_derive_place_reason_all_signals_present_en() -> None:
    # V7 i18n: language=en composes the same canonical order in natural EN —
    # segment gating is identical, only the copy changes (ko stays byte-identical).
    place = {
        "category": "restaurant",
        "distance_m": 300,
        "upstream_source": "tour_api",
        "_local_activity_band": "active",
        "_has_linked_event": True,
        "is_ongoing": True,
    }
    current_weather = {"outdoor_status": "bad"}
    slot_time = "12:30"

    result = places_service._derive_place_reason(
        place=place,
        current_weather=current_weather,
        slot_time=slot_time,
        language="en",
    )

    assert result == (
        "Open now · Indoor-friendly · Active local spending · Ongoing event · Nearby · "
        "Korea Tourism Organization data"
    )


def test_derive_place_reason_linked_not_ongoing_en() -> None:
    place = {
        "category": "event",
        "distance_m": 900,
        "upstream_source": "kcisa",
        "_has_linked_event": True,
        "is_ongoing": False,
    }
    current_weather = {"outdoor_status": "good", "temp": "30"}
    slot_time = "10:00"

    result = places_service._derive_place_reason(
        place=place,
        current_weather=current_weather,
        slot_time=slot_time,
        language="en",
    )

    assert (
        result == "Open now · Hot weather · Linked event · Korea Culture Information Service data"
    )


def test_derive_place_reason_unknown_language_falls_back_to_ko() -> None:
    # Contract: unknown/edge languages behave like normalize_language (→ ko);
    # the composer never invents a third branch.
    place = {
        "category": "attraction",
        "distance_m": 300,
        "upstream_source": "tour_api",
    }
    result = places_service._derive_place_reason(
        place=place,
        current_weather={"outdoor_status": "good"},
        slot_time="12:00",
        language="fr",
    )
    assert result == "영업중 · 근접 · 한국관광공사 데이터"


def test_format_freshness_now() -> None:
    # 방금 전 (1분 미만)
    now = datetime(2026, 8, 12, 10, 30, 0, tzinfo=UTC)
    updated_at = "2026-08-12T10:29:45Z"

    result = places_service._format_freshness(updated_at, now)

    assert result == "방금 전"


def test_format_freshness_minutes_ago() -> None:
    # N분 전
    now = datetime(2026, 8, 12, 10, 30, 0, tzinfo=UTC)
    updated_at = "2026-08-12T10:25:00Z"

    result = places_service._format_freshness(updated_at, now)

    assert result == "5분 전"


def test_format_freshness_hours_ago() -> None:
    # N시간 전
    now = datetime(2026, 8, 12, 14, 30, 0, tzinfo=UTC)
    updated_at = "2026-08-12T10:00:00Z"

    result = places_service._format_freshness(updated_at, now)

    assert result == "4시간 전"


def test_format_freshness_one_day_ago_is_truthful_days_not_today() -> None:
    # Regression: ≥1 day must report elapsed days ("N일 전"), never the
    # misleading "오늘". 33h elapsed → 1 day.
    now = datetime(2026, 8, 12, 18, 0, 0, tzinfo=UTC)
    updated_at = "2026-08-11T09:00:00Z"

    result = places_service._format_freshness(updated_at, now)

    assert result == "1일 전"


@pytest.mark.parametrize(
    ("updated_at", "expected"),
    [
        # 1s short of 24h → still hours (boundary is exclusive on the day side).
        ("2026-08-12T12:00:01Z", "23시간 전"),
        # Exactly 24h → first day bucket.
        ("2026-08-12T12:00:00Z", "1일 전"),
        # 24h + 1s → first day bucket (floor, no rounding up).
        ("2026-08-12T11:59:59Z", "1일 전"),
    ],
)
def test_format_freshness_24_hour_boundary(updated_at: str, expected: str) -> None:
    now = datetime(2026, 8, 13, 12, 0, 0, tzinfo=UTC)

    result = places_service._format_freshness(updated_at, now)

    assert result == expected


@pytest.mark.parametrize(
    ("updated_at", "expected"),
    [
        ("2026-08-10T12:00:00Z", "3일 전"),
        ("2026-07-14T12:00:00Z", "30일 전"),
    ],
)
def test_format_freshness_multiple_days(updated_at: str, expected: str) -> None:
    now = datetime(2026, 8, 13, 12, 0, 0, tzinfo=UTC)

    result = places_service._format_freshness(updated_at, now)

    assert result == expected


def test_format_freshness_future_timestamp_clamps_to_now() -> None:
    # A future source timestamp is corruption; clamp honestly to "방금 전"
    # rather than fabricating a negative/elapsed label.
    now = datetime(2026, 8, 13, 12, 0, 0, tzinfo=UTC)
    updated_at = "2026-08-13T13:00:00Z"  # 1h in the future

    result = places_service._format_freshness(updated_at, now)

    assert result == "방금 전"


def test_format_freshness_naive_input_treated_as_utc() -> None:
    # Naive (tz-less) timestamps are assumed UTC so the comparison is defined.
    now = datetime(2026, 8, 13, 12, 0, 0, tzinfo=UTC)
    updated_at = "2026-08-13 11:55:00"  # 5 minutes before, no offset

    result = places_service._format_freshness(updated_at, now)

    assert result == "5분 전"


def test_format_freshness_aware_offset_normalized_to_utc() -> None:
    # 20:55+09:00 == 11:55 UTC, so an offset-aware value must land at 5 min ago,
    # not be misread as later-than-now by the naive comparison.
    now = datetime(2026, 8, 13, 12, 0, 0, tzinfo=UTC)
    updated_at = "2026-08-13T20:55:00+09:00"

    result = places_service._format_freshness(updated_at, now)

    assert result == "5분 전"


@pytest.mark.parametrize(
    "updated_at",
    [None, "", "   "],
)
def test_format_freshness_missing_or_blank_is_honest_none(updated_at) -> None:
    # No source timestamp → never fabricate freshness.
    now = datetime(2026, 8, 12, 10, 30, 0, tzinfo=UTC)

    result = places_service._format_freshness(updated_at, now)

    assert result is None


@pytest.mark.parametrize(
    "updated_at",
    ["invalid-date", "2026-13-40T99:99:99Z", 12345, ["not", "a", "timestamp"]],
)
def test_format_freshness_malformed_or_wrong_type_is_honest_none(updated_at) -> None:
    # Unparseable / wrong-typed source → degrade honestly to None.
    now = datetime(2026, 8, 12, 10, 30, 0, tzinfo=UTC)

    result = places_service._format_freshness(updated_at, now)

    assert result is None


# ─────────────────────────────────────────────────────────────────────────
# V1-RC1: list_places end-to-end reason/freshness 바인딩 검증
# ─────────────────────────────────────────────────────────────────────────


def test_list_places_db_path_binds_reason_and_honest_none_freshness(monkeypatch) -> None:
    # DB payload shape: db_repository.fetch_places does NOT return updated_at,
    # so freshness must degrade to honest None (never fabricated). reason is
    # derived from real signals (category + open hours + proximity + source).
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())
    # Freeze the wall-clock list_places reads so the operating-status check
    # (slot_time vs attraction hours 09:00-18:00) is deterministic; otherwise the
    # asserted "영업중" flickers with the CI run's UTC hour.
    _freeze_service_now(monkeypatch, fixed=datetime(2026, 8, 13, 12, 0, 0, tzinfo=UTC))
    # attraction is open during day hours; near + non-canonical upstream source.
    places = [
        {
            "place_id": "p1",
            "name": "근처 명소",
            "category": "attraction",
            "distance_m": 300,
            "source": "db",
            "upstream_source": "tour_api",
            "score": 0.9,
        }
    ]
    _patch_db_fetch_places(monkeypatch, places=places)

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="attraction",
        language="ko",
        include_scores=True,
    )

    place = result["places"][0]
    # Reason derived from signals (운영중 + 근접 + per-source S1 phrase); weather good → no indoor line.
    assert place["reason"] == "영업중 · 근접 · 한국관광공사 데이터"
    # DB payload omits updated_at → honest None freshness (no fabrication).
    assert place["freshness"] is None
    # Score compatibility preserved.
    assert place["score"] == 0.9


def test_list_places_db_path_binds_en_reason_for_language_en(monkeypatch) -> None:
    # V7 fix: /places?language=en must bind EN reason copy (same signals as the
    # KO test above — only the language differs, proving the composer honors it).
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())
    _freeze_service_now(monkeypatch, fixed=datetime(2026, 8, 13, 12, 0, 0, tzinfo=UTC))
    places = [
        {
            "place_id": "p1",
            "name": "Nearby spot",
            "category": "attraction",
            "distance_m": 300,
            "source": "db",
            "upstream_source": "tour_api",
            "score": 0.9,
        }
    ]
    captured = _patch_db_fetch_places(monkeypatch, places=places)

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="attraction",
        language="en",
        include_scores=True,
    )

    place = result["places"][0]
    assert place["reason"] == "Open now · Nearby · Korea Tourism Organization data"
    # The fetch layer sees the normalized en language (name localization parity).
    assert captured[0]["language"] == "en"


def test_list_places_db_path_freshness_from_updated_at_when_present(monkeypatch) -> None:
    # If a future payload carries updated_at, freshness is formatted truthfully.
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())
    now = datetime.now(UTC)
    recent = (now - timedelta(minutes=5)).isoformat()
    places = [
        {
            "place_id": "p2",
            "name": "방금 갱신된 장소",
            "category": "event",
            "distance_m": 200,
            "source": "db",
            "upstream_source": "tour_api",
            "updated_at": recent,
        }
    ]
    _patch_db_fetch_places(monkeypatch, places=places)

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="event",
        language="ko",
    )

    place = result["places"][0]
    # ~5 minutes old → "N분 전".
    assert place["freshness"] is not None
    assert place["freshness"].endswith("분 전")


# ─────────────────────────────────────────────────────────────────────────
# V1-RC1 regression: place search must stay offline (no live weather provider)
# ─────────────────────────────────────────────────────────────────────────


def _fail_if_live_weather_invoked(*args, **kwargs):
    raise AssertionError("list_places must not call the live weather provider (KMA/AirKorea)")


def test_list_places_db_path_does_not_invoke_live_weather_provider(monkeypatch) -> None:
    # Regression: the DB search path must source weather only from the local DB
    # cache. If the live entry point or either provider fetcher were ever reached
    # on this path the sentinel raises, proving search stays offline.
    monkeypatch.setattr(weather_service, "current_weather", _fail_if_live_weather_invoked)
    monkeypatch.setattr(
        weather_service, "_fetch_kma_ultra_short_nowcast", _fail_if_live_weather_invoked
    )
    monkeypatch.setattr(
        weather_service, "_fetch_airkorea_sido_air_quality", _fail_if_live_weather_invoked
    )
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())
    # No cached local weather → indoor-fit reason is honestly omitted, still no provider call.
    monkeypatch.setattr(places_service.db_repository, "fetch_latest_weather", lambda **kw: None)
    _patch_db_fetch_places(
        monkeypatch, places=[{"name": "경복궁", "category": "event", "score": 0.9}]
    )

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="event",
        language="ko",
    )

    assert result["source"] == "db"
    assert result["count"] == 1


def test_list_places_snapshot_path_does_not_invoke_live_weather_provider(monkeypatch) -> None:
    # Regression: the static-snapshot fallback path must likewise stay offline.
    monkeypatch.setattr(weather_service, "current_weather", _fail_if_live_weather_invoked)
    monkeypatch.setattr(
        weather_service, "_fetch_kma_ultra_short_nowcast", _fail_if_live_weather_invoked
    )
    monkeypatch.setattr(
        weather_service, "_fetch_airkorea_sido_air_quality", _fail_if_live_weather_invoked
    )
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(static_snapshot_fallback=True, db_dsn=""),
    )
    monkeypatch.setattr(places_service.db_repository, "fetch_latest_weather", lambda **kw: None)
    _patch_db_fetch_places(
        monkeypatch,
        raises=places_service.db_repository.DatabaseReadError("places_query_failed"),
    )
    monkeypatch.setattr(
        places_service.public_mvp_data,
        "fetch_places",
        lambda **kwargs: [{"name": "경복궁", "score": 0.92}],
    )

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="attraction",
        language="ko",
    )

    assert result["source"] == places_service.public_mvp_data.SOURCE_NAME
    assert result["count"] == 1


# ─────────────────────────────────────────────────────────────────────────
# V1 three-signals Lane 2 — reason composer + internal-key stripping
# (contract §1a/§3/§4/§8). Developed in isolation off the base: the place dict
# from db_repository does NOT yet carry the internal keys, so these unit tests
# exercise the composer + stripping with SYNTHETIC dicts that DO set them.
# ─────────────────────────────────────────────────────────────────────────

# KO branch of the client externalSourceLabel (home_view_helpers.dart) — the
# reference the server S1 phrase must agree with for the real sources (§8).
_CLIENT_SOURCE_LABELS = {
    "tour_api": "한국관광공사",
    "kcisa": "문화정보원",
    "kopis": "공연예술통합전산망",
}


# --- _upstream_source_reason_phrase (S1, D2) ---


@pytest.mark.parametrize(
    ("upstream_source", "expected"),
    [
        ("tour_api", "한국관광공사 데이터"),
        ("kcisa", "문화정보원 데이터"),
        ("kopis", "공연예술통합전산망 데이터"),
        # canonical/empty/unknown → honest omit (no generic "공식 데이터" stamp)
        ("canonical", None),
        ("", None),
        ("unknown_source", None),
        ("korean_tourism_org", None),
    ],
)
def test_upstream_source_reason_phrase(upstream_source: str, expected) -> None:
    assert places_service._upstream_source_reason_phrase(upstream_source) == expected


def test_source_phrase_agrees_with_client_external_source_label() -> None:
    # §8 consistency over {tour_api, kcisa, kopis, canonical, ''}: the server S1
    # label for each real source must equal the client externalSourceLabel KO
    # branch (the phrase is "<label> 데이터"). canonical/'' are intentionally
    # STRICTER on the server — it omits where the client evidence panel may still
    # label canonical ("공식 장소"); that asymmetry is the accepted D2 cost of
    # dropping the generic stamp, asserted here rather than hidden as drift.
    for source, client_label in _CLIENT_SOURCE_LABELS.items():
        assert places_service._upstream_source_reason_phrase(source) == f"{client_label} 데이터"
    assert places_service._upstream_source_reason_phrase("canonical") is None
    assert places_service._upstream_source_reason_phrase("") is None


@pytest.mark.parametrize(
    ("upstream_source", "expected"),
    [
        ("tour_api", "Korea Tourism Organization data"),
        ("kcisa", "Korea Culture Information Service data"),
        ("kopis", "KOPIS performing arts data"),
        # Same honest-omit contract as the KO branch (contract D2).
        ("canonical", None),
        ("", None),
        ("unknown_source", None),
    ],
)
def test_upstream_source_reason_phrase_en(upstream_source: str, expected) -> None:
    assert places_service._upstream_source_reason_phrase(upstream_source, language="en") == expected


def test_source_phrase_en_agrees_with_docent_en_source_label() -> None:
    # V7: the EN S1 phrase is taken verbatim from docent_service._en_source_label
    # so one EN naming per source exists across API surfaces (no drift).
    from apps.api.app.services import docent_service

    for source in _CLIENT_SOURCE_LABELS:
        assert places_service._upstream_source_reason_phrase(
            source, language="en"
        ) == docent_service._en_source_label(source)


# --- _local_activity_reason_phrase (S2, D1) ---


@pytest.mark.parametrize(
    ("band", "expected"),
    [
        ("active", "로컬 소비 활발"),
        ("ACTIVE", "로컬 소비 활발"),  # any truthy token = above min-sample gate
        (None, None),
        ("", None),  # degenerate/empty band → honest omit
    ],
)
def test_local_activity_reason_phrase(band, expected) -> None:
    assert places_service._local_activity_reason_phrase(band) == expected


def test_local_activity_reason_phrase_en() -> None:
    assert (
        places_service._local_activity_reason_phrase("active", language="en")
        == "Active local spending"
    )
    assert places_service._local_activity_reason_phrase(None, language="en") is None


# --- _weather_band_phrase (S3, D3) ---


@pytest.mark.parametrize(
    ("weather", "category", "expected"),
    [
        # No cached weather → omit (honest; never fabricated).
        ({}, "restaurant", None),
        # bad ∧ indoor-pref → retained indoor-fit bit.
        ({"outdoor_status": "bad"}, "restaurant", "실내활동 적합"),
        ({"outdoor_status": "bad"}, "culture_venue", "실내활동 적합"),
        # bad ∧ outdoor category → honest silence (a bad-weather stamp is not useful).
        ({"outdoor_status": "bad"}, "attraction", None),
        ({"outdoor_status": "bad"}, "event", None),
        # Good weather, unparseable/absent temp → omit.
        ({"outdoor_status": "good"}, "attraction", None),
        ({"outdoor_status": "good", "temp": ""}, "attraction", None),
        # Good weather comfort band from temp (half-open thresholds).
        ({"outdoor_status": "good", "temp": "2"}, "attraction", "추운 날씨"),
        ({"outdoor_status": "good", "temp": "5"}, "attraction", "선선한 날씨"),
        ({"outdoor_status": "good", "temp": "15.5"}, "attraction", "선선한 날씨"),
        ({"outdoor_status": "good", "temp": "18"}, "attraction", "따뜻한 날씨"),
        ({"outdoor_status": "good", "temp": "26"}, "attraction", "따뜻한 날씨"),
        ({"outdoor_status": "good", "temp": "27"}, "attraction", "더운 날씨"),
        ({"outdoor_status": "good", "temp": "30"}, "attraction", "더운 날씨"),
        # temp as int / numeric string variants parse the same.
        ({"outdoor_status": "good", "temp": 10}, "restaurant", "선선한 날씨"),
    ],
)
def test_weather_band_phrase(weather, category, expected) -> None:
    assert places_service._weather_band_phrase(weather, category=category) == expected


@pytest.mark.parametrize(
    ("weather", "category", "expected"),
    [
        ({}, "restaurant", None),
        ({"outdoor_status": "bad"}, "restaurant", "Indoor-friendly"),
        ({"outdoor_status": "bad"}, "attraction", None),
        ({"outdoor_status": "good", "temp": "2"}, "attraction", "Cold weather"),
        ({"outdoor_status": "good", "temp": "15.5"}, "attraction", "Cool weather"),
        ({"outdoor_status": "good", "temp": "18"}, "attraction", "Warm weather"),
        ({"outdoor_status": "good", "temp": "27"}, "attraction", "Hot weather"),
        ({"outdoor_status": "good", "temp": ""}, "attraction", None),
    ],
)
def test_weather_band_phrase_en(weather, category, expected) -> None:
    assert places_service._weather_band_phrase(weather, category=category, language="en") == (
        expected
    )


def test_weather_band_is_a_phrase_not_numbers() -> None:
    # §1a: the list band is a coarse phrase, never the publicWeatherSummary numbers.
    phrase = places_service._weather_band_phrase(
        {"outdoor_status": "good", "temp": "15", "pm10": 40, "pm25": 20},
        category="attraction",
    )
    assert phrase == "선선한 날씨"
    # No per-card number (temp/dust) leaks into the band phrase.
    assert not any(ch.isdigit() for ch in phrase)


# --- _linked_event_reason_phrase (D4) ---


@pytest.mark.parametrize(
    ("has_linked_event", "is_ongoing", "expected"),
    [
        (True, True, "진행 중인 행사"),
        (True, False, "행사 연계"),
        (True, None, "행사 연계"),  # linked but not known ongoing
        (False, True, None),  # no linked event → omit regardless of is_ongoing
        (None, True, None),
    ],
)
def test_linked_event_reason_phrase(has_linked_event, is_ongoing, expected) -> None:
    assert (
        places_service._linked_event_reason_phrase(has_linked_event, is_ongoing=is_ongoing)
        == expected
    )


@pytest.mark.parametrize(
    ("has_linked_event", "is_ongoing", "expected"),
    [
        (True, True, "Ongoing event"),
        (True, False, "Linked event"),
        (True, None, "Linked event"),
        (False, True, None),
    ],
)
def test_linked_event_reason_phrase_en(has_linked_event, is_ongoing, expected) -> None:
    assert (
        places_service._linked_event_reason_phrase(
            has_linked_event, is_ongoing=is_ongoing, language="en"
        )
        == expected
    )


# --- _derive_place_reason: canonical order, honest-empty, no-score ---


def test_derive_place_reason_canonical_order_full() -> None:
    # All six segments present → joined in canonical order (§3).
    place = {
        "category": "culture_venue",
        "distance_m": 200,
        "upstream_source": "kcisa",
        "_local_activity_band": "active",
        "_has_linked_event": True,
        "is_ongoing": False,
    }
    current_weather = {"outdoor_status": "good", "temp": "16"}
    result = places_service._derive_place_reason(
        place=place, current_weather=current_weather, slot_time="11:00"
    )
    # [operating] · [weather] · [activity] · [event] · [proximity] · [source]
    assert result == (
        "영업중 · 선선한 날씨 · 로컬 소비 활발 · 행사 연계 · 근접 · 문화정보원 데이터"
    )


def test_derive_place_reason_all_null_is_honest_empty() -> None:
    # Every signal null/absent → "" (rendered as nothing, never "이유 없음").
    place = {
        "category": "attraction",
        "distance_m": 2000,  # not 근접
        "upstream_source": "canonical",  # omit
        "_local_activity_band": None,
        "_has_linked_event": None,
    }
    result = places_service._derive_place_reason(
        place=place,
        current_weather={},
        slot_time="23:00",  # closed (attraction 09-18)
    )
    assert result == ""


def test_derive_place_reason_never_leaks_score_number_or_components() -> None:
    # §4.1/§8: the reason carries PHRASES ONLY — the score number, formula,
    # component values, and raw transaction count are unreachable from it.
    place = {
        "category": "restaurant",
        "distance_m": 120,
        "upstream_source": "tour_api",
        "_local_activity_band": "active",
        "_has_linked_event": True,
        "is_ongoing": True,
        # Score-bearing fields that MUST NOT surface in the reason string.
        "final_score": 0.88,
        "score": 0.88,
        "local_spending_score": 0.5,
        "region_transaction_count": 12345,
        "region_spend_amount": 9876543,
    }
    current_weather = {"outdoor_status": "bad"}
    result = places_service._derive_place_reason(
        place=place, current_weather=current_weather, slot_time="12:30"
    )
    assert result == (
        "영업중 · 실내활동 적합 · 로컬 소비 활발 · 진행 중인 행사 · 근접 · 한국관광공사 데이터"
    )
    # No digit survives (no score/transaction count leaked).
    assert not any(ch.isdigit() for ch in result), result
    # No forbidden component/formula token either.
    lowered = result.lower()
    for forbidden in ("score", "final_score", "component", "transaction", "spend"):
        assert forbidden not in lowered, (forbidden, result)


# --- list_places: internal keys stripped from the serialized payload (§8) ---


def _place_with_internal_keys() -> dict:
    # Synthetic place carrying Lane-1 internal reason inputs (not yet projected
    # by db_repository at this base). The composer reads them; serialization strips them.
    return {
        "place_id": "p1",
        "name": "합격점 식당",
        "category": "restaurant",
        "distance_m": 200,
        "upstream_source": "tour_api",
        "_local_activity_band": "active",
        "_has_linked_event": True,
        "is_ongoing": True,
        "score": 0.9,
        "final_score": 0.9,
    }


def test_list_places_db_path_strips_internal_reason_inputs(monkeypatch) -> None:
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())
    _freeze_service_now(monkeypatch, fixed=datetime(2026, 8, 13, 12, 0, 0, tzinfo=UTC))
    _patch_db_fetch_places(monkeypatch, places=[_place_with_internal_keys()])

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="restaurant",
        language="ko",
        include_scores=True,
    )

    serialized = result["places"][0]
    # §8: neither internal key is serialized.
    assert "_local_activity_band" not in serialized
    assert "_has_linked_event" not in serialized
    # But the composer did consume them (activity + event phrases present).
    assert "로컬 소비 활발" in serialized["reason"]
    assert "진행 중인 행사" in serialized["reason"]


def test_list_places_snapshot_path_strips_internal_reason_inputs(monkeypatch) -> None:
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(static_snapshot_fallback=True, db_dsn=""),
    )
    _patch_db_fetch_places(
        monkeypatch,
        raises=places_service.db_repository.DatabaseReadError("places_query_failed"),
    )
    monkeypatch.setattr(
        places_service.public_mvp_data,
        "fetch_places",
        lambda **kwargs: [_place_with_internal_keys()],
    )

    result = places_service.list_places(
        lat=37.5665,
        lng=126.978,
        radius_m=1000,
        category="restaurant",
        language="ko",
        include_scores=False,
    )

    serialized = result["places"][0]
    assert "_local_activity_band" not in serialized
    assert "_has_linked_event" not in serialized
    # The score field is nullified via _places_without_scores; internal keys still stripped.
    assert serialized["score"] is None


def test_strip_internal_reason_inputs_is_idempotent_and_safe() -> None:
    place = {"name": "x", "_local_activity_band": "active", "_has_linked_event": True}
    places_service._strip_internal_reason_inputs(place)
    assert "_local_activity_band" not in place
    assert "_has_linked_event" not in place
    # Idempotent: a second pass is a no-op (no KeyError on absent keys).
    places_service._strip_internal_reason_inputs(place)
    assert place == {"name": "x"}


# ─────────────────────────────────────────────────────────────────────────
# V1 bounds query (Lane A) — service validation + query-echo gating
# (contract §3 B1–B4 / §7 D3). Bounds are validated and echoed ONLY while the
# PLACES_VIEWPORT_BOUNDS flag is on; flag-off ignores bounds entirely (B3: no
# 400, no echo, circle path) so a client may send bounds before the rollout
# flips without breaking. lat/lng/radius_m stay required (sort origin + fallback).
# ─────────────────────────────────────────────────────────────────────────


def test_list_places_echoes_bounds_when_flag_on_and_all_present(monkeypatch) -> None:
    # B1: flag on + all four bounds -> echoed in `query` and threaded to the repo.
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(feature_flags={"PLACES_VIEWPORT_BOUNDS": True}),
    )
    captured = _patch_db_fetch_places(monkeypatch, places=[{"name": "장소"}])

    result = places_service.list_places(
        lat=37.0,
        lng=127.0,
        radius_m=1000,
        category="all",
        language="ko",
        sw_lat=36.5,
        sw_lng=126.5,
        ne_lat=37.5,
        ne_lng=127.5,
    )

    query = result["query"]
    assert query["sw_lat"] == 36.5
    assert query["sw_lng"] == 126.5
    assert query["ne_lat"] == 37.5
    assert query["ne_lng"] == 127.5
    # Existing echo keys preserved (lat/lng/radius_m remain the sort origin).
    assert query["lat"] == 37.0
    assert query["lng"] == 127.0
    assert query["radius_m"] == 1000
    # Threaded through to the repository.
    assert captured[0]["sw_lat"] == 36.5
    assert captured[0]["sw_lng"] == 126.5
    assert captured[0]["ne_lat"] == 37.5
    assert captured[0]["ne_lng"] == 127.5


def test_list_places_omits_bounds_keys_when_flag_off(monkeypatch) -> None:
    # B3: flag off + bounds sent -> NO echo, NO 400; query stays byte-for-byte
    # today's shape. Bounds are still threaded (the repo gates the SQL shape).
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(feature_flags={"PLACES_VIEWPORT_BOUNDS": False}),
    )
    _patch_db_fetch_places(monkeypatch, places=[{"name": "장소"}])

    result = places_service.list_places(
        lat=37.0,
        lng=127.0,
        radius_m=1000,
        category="all",
        language="ko",
        sw_lat=36.5,
        sw_lng=126.5,
        ne_lat=37.5,
        ne_lng=127.5,
    )

    query = result["query"]
    assert "sw_lat" not in query
    assert "sw_lng" not in query
    assert "ne_lat" not in query
    assert "ne_lng" not in query
    assert set(query) == {
        "lat",
        "lng",
        "radius_m",
        "category",
        "language",
        "include_scores",
        "limit",
    }


def test_list_places_omits_bounds_keys_when_bounds_absent(monkeypatch) -> None:
    # B2: flag on + no bounds -> circle path; query has no bounds keys.
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(feature_flags={"PLACES_VIEWPORT_BOUNDS": True}),
    )
    _patch_db_fetch_places(monkeypatch, places=[{"name": "장소"}])

    result = places_service.list_places(
        lat=37.0, lng=127.0, radius_m=1000, category="all", language="ko"
    )

    query = result["query"]
    assert "sw_lat" not in query
    assert "ne_lat" not in query
    assert set(query) == {
        "lat",
        "lng",
        "radius_m",
        "category",
        "language",
        "include_scores",
        "limit",
    }


def test_list_places_bounds_empty_rectangle_returns_honest_empty(monkeypatch) -> None:
    # B4: flag on + bounds + no places in viewport -> count 0, places [], no
    # fabrication; bounds are still echoed (the rectangle was the actual query).
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(feature_flags={"PLACES_VIEWPORT_BOUNDS": True}),
    )
    _patch_db_fetch_places(monkeypatch, places=[])

    result = places_service.list_places(
        lat=37.0,
        lng=127.0,
        radius_m=1000,
        category="all",
        language="ko",
        sw_lat=36.5,
        sw_lng=126.5,
        ne_lat=37.5,
        ne_lng=127.5,
    )

    assert result["count"] == 0
    assert result["places"] == []
    assert result["query"]["sw_lat"] == 36.5


@pytest.mark.parametrize(
    ("sw_lat", "sw_lng", "ne_lat", "ne_lng"),
    [
        (36.5, 126.5, None, 127.5),
        (36.5, 126.5, 37.5, None),
        (None, 126.5, 37.5, 127.5),
        (36.5, None, 37.5, 127.5),
    ],
)
def test_list_places_rejects_partial_bounds(sw_lat, sw_lng, ne_lat, ne_lng, monkeypatch) -> None:
    # All-or-none: any-but-not-all -> 400 INVALID_BOUNDS (flag on).
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(feature_flags={"PLACES_VIEWPORT_BOUNDS": True}),
    )
    _patch_db_fetch_places(monkeypatch, places=[])

    with pytest.raises(ServiceError) as exc_info:
        places_service.list_places(
            lat=37.0,
            lng=127.0,
            radius_m=1000,
            category="all",
            language="ko",
            sw_lat=sw_lat,
            sw_lng=sw_lng,
            ne_lat=ne_lat,
            ne_lng=ne_lng,
        )

    err = exc_info.value
    assert err.status_code == 400
    assert err.code == "INVALID_BOUNDS"
    assert err.retryable is False


@pytest.mark.parametrize(
    ("sw_lat", "sw_lng", "ne_lat", "ne_lng"),
    [
        (37.5, 126.5, 36.5, 127.5),  # sw_lat > ne_lat
        (36.5, 127.5, 37.5, 126.5),  # sw_lng > ne_lng
    ],
)
def test_list_places_rejects_inverted_bounds(sw_lat, sw_lng, ne_lat, ne_lng, monkeypatch) -> None:
    # sw<=ne violation -> 400 INVALID_BOUNDS (flag on).
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(feature_flags={"PLACES_VIEWPORT_BOUNDS": True}),
    )
    _patch_db_fetch_places(monkeypatch, places=[])

    with pytest.raises(ServiceError) as exc_info:
        places_service.list_places(
            lat=37.0,
            lng=127.0,
            radius_m=1000,
            category="all",
            language="ko",
            sw_lat=sw_lat,
            sw_lng=sw_lng,
            ne_lat=ne_lat,
            ne_lng=ne_lng,
        )

    assert exc_info.value.status_code == 400
    assert exc_info.value.code == "INVALID_BOUNDS"


def test_list_places_malformed_bounds_ignored_when_flag_off(monkeypatch) -> None:
    # B3 forward-compat: flag off + partial/inverted bounds -> ignored entirely
    # (no 400); validation only runs while the flag is on.
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: _fake_settings(feature_flags={"PLACES_VIEWPORT_BOUNDS": False}),
    )
    _patch_db_fetch_places(monkeypatch, places=[{"name": "장소"}])

    result = places_service.list_places(
        lat=37.0,
        lng=127.0,
        radius_m=1000,
        category="all",
        language="ko",
        sw_lat=99.0,
        sw_lng=None,
        ne_lat=-99.0,
        ne_lng=None,
    )

    assert result["count"] == 1
    assert "sw_lat" not in result["query"]
