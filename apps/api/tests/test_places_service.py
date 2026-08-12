from __future__ import annotations

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest

from apps.api.app.core.errors import ServiceError
from apps.api.app.services import places_service


def _fake_settings(*, static_snapshot_fallback: bool = False, db_dsn: str = ""):
    return SimpleNamespace(
        static_snapshot_fallback=static_snapshot_fallback,
        db_dsn=db_dsn,
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


def _patch_weather(
    monkeypatch,
    *,
    outdoor_status: str = "good",
) -> None:
    """Stub ``weather_service.current_weather`` so list_places derivation stays hermetic.

    list_places now reads current weather to derive the indoor-fit reason, so any
    test exercising a non-empty places path must keep this off the live KMA/AirKorea
    providers. Returns a minimal deterministic payload mirroring the real shape.
    """
    monkeypatch.setattr(
        places_service.weather_service,
        "current_weather",
        lambda *, lat, lng: {
            "outdoor_status": outdoor_status,
            "source": "test_stub",
            "icon": "partly-cloudy",
        },
    )


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
    _patch_weather(monkeypatch)
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
    _patch_weather(monkeypatch)
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
    _patch_weather(monkeypatch)
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
    _patch_weather(monkeypatch)
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
    # 모든 신호가 있는 경우: 운영중 + 날씨 적합 + 근접 + 공식 데이터
    place = {
        "category": "restaurant",
        "distance_m": 300,
        "upstream_source": "korean_tourism_org",
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

    # 모든 신호가 결합된 결정론적 결과
    assert result == "영업중 · 실내활동 적합 · 근접 · 공식 데이터"


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
        "upstream_source": "official",
    }
    current_weather = {"outdoor_status": "good"}
    slot_time = "23:00"  # 영업시간 외

    result = places_service._derive_place_reason(
        place=place,
        current_weather=current_weather,
        slot_time=slot_time,
    )

    # closed면 운영 reason 추가 안 함 (honest empty)
    assert result == "근접 · 공식 데이터"


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


def test_format_freshness_today() -> None:
    # 하루 이상: "오늘"
    now = datetime(2026, 8, 12, 18, 0, 0, tzinfo=UTC)
    updated_at = "2026-08-11T09:00:00Z"

    result = places_service._format_freshness(updated_at, now)

    assert result == "오늘"


def test_format_freshness_honest_none() -> None:
    # updated_at 없음: honest None
    now = datetime(2026, 8, 12, 10, 30, 0, tzinfo=UTC)

    result = places_service._format_freshness(None, now)

    assert result is None


def test_format_freshness_invalid_format() -> None:
    # 파싱 불가능한 형식: honest None
    now = datetime(2026, 8, 12, 10, 30, 0, tzinfo=UTC)

    result = places_service._format_freshness("invalid-date", now)

    assert result is None


# ─────────────────────────────────────────────────────────────────────────
# V1-RC1: list_places end-to-end reason/freshness 바인딩 검증
# ─────────────────────────────────────────────────────────────────────────


def test_list_places_db_path_binds_reason_and_honest_none_freshness(monkeypatch) -> None:
    # DB payload shape: db_repository.fetch_places does NOT return updated_at,
    # so freshness must degrade to honest None (never fabricated). reason is
    # derived from real signals (category + open hours + proximity + source).
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())
    _patch_weather(monkeypatch, outdoor_status="good")
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
    # Reason derived from signals (운영중 + 근접 + 공식 데이터); weather good → no indoor line.
    assert place["reason"] == "영업중 · 근접 · 공식 데이터"
    # DB payload omits updated_at → honest None freshness (no fabrication).
    assert place["freshness"] is None
    # Score compatibility preserved.
    assert place["score"] == 0.9


def test_list_places_db_path_freshness_from_updated_at_when_present(monkeypatch) -> None:
    # If a future payload carries updated_at, freshness is formatted truthfully.
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())
    _patch_weather(monkeypatch, outdoor_status="good")
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
