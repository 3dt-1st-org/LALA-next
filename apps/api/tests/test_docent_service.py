from __future__ import annotations

from types import SimpleNamespace

import pytest

from apps.api.app.core.errors import ServiceError
from apps.api.app.schemas.docent import DocentScriptRequest
from apps.api.app.services import docent_service


def _make_request(**overrides) -> DocentScriptRequest:
    defaults: dict[str, object] = {"place_id": "place-1", "category": "attraction"}
    defaults.update(overrides)
    return DocentScriptRequest(**defaults)


@pytest.mark.parametrize(
    ("value", "threshold", "expected"),
    [
        (None, 0.6, False),
        (0.6, 0.6, True),
        (0.59, 0.6, False),
        (0.9, 0.6, True),
        (1.5, 0.6, True),
        (-0.5, 0.6, False),
        (0.0, 0.0, True),
    ],
)
def test_score_at_least_clamps_to_unit_range_and_compares(
    value: float | None, threshold: float, expected: bool
) -> None:
    assert docent_service._score_at_least(value, threshold) is expected


@pytest.mark.parametrize(
    ("scores", "expected"),
    [
        ({}, False),
        ({"final_score": 0.5}, True),
        ({"local_spending_score": 0.1}, True),
        ({"small_merchant_fit_score": 0.1}, True),
        ({"demand_dispersion_score": 0.1}, True),
        ({"weather_fit_score": 0.1}, True),
        ({"culture_relevance_score": 0.9}, True),
    ],
)
def test_has_score_context_detects_any_score(scores: dict[str, object], expected: bool) -> None:
    assert docent_service._has_score_context(_make_request(**scores)) is expected


@pytest.mark.parametrize(
    ("fields", "expected"),
    [
        ({}, False),
        ({"place_name": "화성행궁"}, True),
        ({"address": "수원"}, True),
        ({"region_ko": "경기"}, True),
        ({"region_en": "Gyeonggi"}, True),
        ({"upstream_source": "tour_api"}, True),
        ({"distance_m": 0}, True),
        ({"distance_m": 120}, True),
    ],
)
def test_has_request_context_detects_location_fields(
    fields: dict[str, object], expected: bool
) -> None:
    assert docent_service._has_request_context(_make_request(**fields)) is expected


@pytest.mark.parametrize(
    ("fields", "expected"),
    [
        ({}, False),
        ({"weather_temp": "23"}, True),
        ({"weather_icon": "partly-cloudy"}, True),
        ({"weather_outdoor_status": "good"}, True),
        ({"dust_grade": "보통"}, True),
        ({"dust_pm10": "31"}, True),
        ({"dust_pm25": "14"}, True),
        ({"dust_pm10_grade": "보통"}, True),
        ({"dust_pm25_grade": "좋음"}, True),
    ],
)
def test_has_weather_context_detects_weather_fields(
    fields: dict[str, object], expected: bool
) -> None:
    assert docent_service._has_weather_context(_make_request(**fields)) is expected


@pytest.mark.parametrize(
    ("language", "scores", "expected"),
    [
        (
            "ko",
            {"local_spending_score": 0.7},
            "LALA는 실제 내국인 소비 흐름을 함께 보고 이 장소를 고릅니다.",
        ),
        (
            "en",
            {"local_spending_score": 0.7},
            "LALA selected this stop by reading real domestic spending patterns together.",
        ),
        (
            "ko",
            {"local_spending_score": 0.7, "small_merchant_fit_score": 0.6},
            "LALA는 실제 내국인 소비 흐름, 그리고 소상공인 상권과의 연결성을 함께 보고 이 장소를 고릅니다.",
        ),
        (
            "en",
            {"local_spending_score": 0.7, "small_merchant_fit_score": 0.6},
            "LALA selected this stop by reading real domestic spending patterns, and small local business fit together.",
        ),
        (
            "ko",
            {
                "local_spending_score": 0.7,
                "small_merchant_fit_score": 0.6,
                "demand_dispersion_score": 0.6,
            },
            "LALA는 실제 내국인 소비 흐름, 소상공인 상권과의 연결성, 그리고 붐비는 관광지에만 몰리지 않는 관광 수요 분산 동선을 함께 보고 이 장소를 고릅니다.",
        ),
        (
            "en",
            {
                "local_spending_score": 0.7,
                "small_merchant_fit_score": 0.6,
                "demand_dispersion_score": 0.6,
            },
            "LALA selected this stop by reading real domestic spending patterns, small local business fit, and a route that disperses demand beyond crowded spots together.",
        ),
        (
            "ko",
            {"final_score": 0.5},
            "LALA는 공식 데이터와 현재 위치 조건의 균형을 함께 보고 이 장소를 고릅니다.",
        ),
        (
            "en",
            {"final_score": 0.5},
            "LALA selected this stop by reading a balanced match between official data and your location together.",
        ),
        ("ko", {"local_spending_score": 0.3}, ""),
        ("en", {"local_spending_score": 0.3}, ""),
    ],
)
def test_score_sentence_branches_by_language(
    language: str, scores: dict[str, object], expected: str
) -> None:
    request = _make_request(language=language, **scores)
    sentence = (
        docent_service._ko_score_sentence(request)
        if language == "ko"
        else docent_service._en_score_sentence(request)
    )
    assert sentence == expected


@pytest.mark.parametrize(
    ("language", "weather", "expected"),
    [
        (
            "ko",
            {
                "weather_temp": "23",
                "weather_icon": "partly-cloudy",
                "dust_pm10_grade": "보통",
                "dust_pm10": "31",
                "dust_pm25_grade": "좋음",
                "dust_pm25": "14",
                "weather_outdoor_status": "good",
            },
            "현재 날씨는 기온 23°C, 하늘 상태 구름 조금, 미세먼지 보통(PM10 31) · 초미세먼지 좋음(PM2.5 14)입니다. 외부 활동에 무리가 적은 편입니다.",
        ),
        (
            "ko",
            {"dust_pm10_grade": "보통", "weather_outdoor_status": "good"},
            "현재 날씨는 미세먼지 보통입니다. 외부 활동에 무리가 적은 편입니다.",
        ),
        (
            "ko",
            {"dust_grade": "보통"},
            "현재 날씨는 미세먼지 보통입니다. 날씨와 대기 상황을 보며 동선을 짧게 조정하는 편이 좋습니다.",
        ),
        ("ko", {}, ""),
        (
            "en",
            {
                "weather_temp": "23",
                "weather_icon": "partly-cloudy",
                "dust_pm10_grade": "normal",
                "dust_pm10": "31",
                "dust_pm25_grade": "good",
                "dust_pm25": "14",
                "weather_outdoor_status": "good",
            },
            "Current weather is 23°C, sky partly cloudy, PM10 normal (31) / PM2.5 good (14), so this stop is suitable for walking.",
        ),
        (
            "en",
            {"dust_grade": "bad"},
            "Current weather is dust bad, so this stop is better for a shorter route.",
        ),
        ("en", {}, ""),
    ],
)
def test_weather_sentence_branches_by_language(
    language: str, weather: dict[str, object], expected: str
) -> None:
    request = _make_request(language=language, **weather)
    sentence = (
        docent_service._ko_weather_sentence(request)
        if language == "ko"
        else docent_service._en_weather_sentence(request)
    )
    assert sentence == expected


@pytest.mark.parametrize(
    ("parts", "expected"),
    [
        (["a", "b", "c"], "a b c"),
        (["  a  ", "b", "", "   ", None, "c"], "a b c"),
        ([], ""),
        (["", "   ", None], ""),
        (["one"], "one"),
    ],
)
def test_join_script_parts_strips_and_drops_empty(parts: list[str | None], expected: str) -> None:
    assert docent_service._join_script_parts(parts) == expected


@pytest.mark.parametrize(
    ("item", "expected"),
    [
        ({"source_type": "place_profile", "source_id": "p1"}, (0, "p1")),
        (
            {"source_type": "tour_api", "body_ko": "역사의 현장", "source_id": "s1"},
            (1, "s1"),
        ),
        ({"source_type": "naver_review", "source_id": "r1"}, (2, "r1")),
        ({"source_type": "culture_event", "source_id": "c1"}, (3, "c1")),
        ({"source_type": "weather_context", "source_id": "w1"}, (4, "w1")),
        ({"source_type": "misc", "source_id": "m1"}, (5, "m1")),
        ({"source_type": "misc"}, (5, "")),
        (
            {"source_type": "blog", "body_ko": "이곳의 전설", "source_id": "b1"},
            (1, "b1"),
        ),
    ],
)
def test_grounding_priority_key_ranks_by_source_type(
    item: dict[str, object], expected: tuple[int, str]
) -> None:
    assert docent_service._grounding_priority_key(item) == expected


@pytest.mark.parametrize(
    ("item", "expected"),
    [
        ({"body_ko": "이곳은 역사가 깊다"}, True),
        ({"title_ko": "전설의 심장"}, True),
        ({"body_en": "a hidden legend"}, False),
        ({"body_ko": "일반 안내 문구입니다"}, False),
        ({}, False),
    ],
)
def test_contains_story_hint_matches_korean_keywords(
    item: dict[str, object], expected: bool
) -> None:
    assert docent_service._contains_story_hint(item) is expected


@pytest.mark.parametrize(
    ("category", "item", "expected"),
    [
        ("restaurant", {"source_type": "naver_review", "body_ko": "근처 맛집"}, False),
        ("attraction", {"source_type": "tour_api", "body_ko": "근처 맛집"}, False),
        ("attraction", {"source_type": "naver_review", "body_ko": "깨끗한 공원"}, False),
        ("attraction", {"source_type": "naver_review", "body_ko": "근처 맛집 추천"}, True),
        ("attraction", {"source_type": "blog", "body_ko": "근처 맛집, 명소 방문"}, False),
        ("culture_venue", {"source_type": "community", "body_ko": "카페 좋음"}, True),
    ],
)
def test_is_noisy_attraction_review_context_guards_attraction_categories(
    category: str, item: dict[str, object], expected: bool
) -> None:
    request = _make_request(category=category)
    assert docent_service._is_noisy_attraction_review_context(request, item) is expected


def test_prepare_docent_grounding_context_filters_noise_and_sorts_by_priority() -> None:
    request = _make_request(category="attraction")
    items = [
        {"source_type": "naver_review", "body_ko": "근처 맛집 추천", "source_id": "a"},
        {"source_type": "culture_event", "source_id": "d"},
        {"source_type": "tour_api", "body_ko": "역사의 현장", "source_id": "c"},
        {"source_type": "place_profile", "title_ko": "화성행궁", "source_id": "b"},
    ]

    prepared = docent_service._prepare_docent_grounding_context(request, grounding_context=items)

    assert [item["source_id"] for item in prepared] == ["b", "c", "d"]
    assert docent_service._prepare_docent_grounding_context(request, grounding_context=[]) == []


@pytest.mark.parametrize(
    ("language", "mode", "category", "marker"),
    [
        ("ko", "brief", "attraction", "현재 위치와 공식 데이터를 함께 보고 고른"),
        ("ko", "detail", "attraction", "LALA가 현재 위치 주변에서 고른"),
        ("ko", "brief", "restaurant", "고른 맛집입니다"),
        ("en", "brief", "attraction", "LALA stop"),
        ("en", "detail", "restaurant", "recommended by LALA"),
    ],
)
def test_rule_based_script_picks_language_and_mode_copy(
    language: str, mode: str, category: str, marker: str
) -> None:
    request = _make_request(
        place_id="place-1",
        place_name="테스트 장소" if language == "ko" else "Test Place",
        language=language,
        mode=mode,
        category=category,
    )

    script = docent_service._rule_based_script(request, grounding_context=[])

    assert marker in script
    assert script.strip() != ""


def test_script_identity_is_deterministic_and_sensitive_to_scores() -> None:
    request = _make_request(final_score=0.8, local_spending_score=0.7)

    first = docent_service.script_identity(request)
    second = docent_service.script_identity(request)

    assert first == second
    assert first["cache_key"].startswith("docent_script:")
    assert len(first["request_hash"]) == 64

    different = docent_service.script_identity(
        _make_request(final_score=0.9, local_spending_score=0.7)
    )
    assert different["request_hash"] != first["request_hash"]


def _stub_db_grounding(monkeypatch: pytest.MonkeyPatch) -> None:
    # Pure-helper tests stay DB-free; get_settings stub keeps the live-DB guard dormant.
    monkeypatch.setattr(docent_service, "get_settings", lambda: SimpleNamespace(db_dsn=""))
    monkeypatch.setattr(
        docent_service.db_repository, "fetch_docent_knowledge_context", lambda **kw: []
    )
    monkeypatch.setattr(
        docent_service.db_repository,
        "fetch_docent_place_profile_context",
        lambda **kw: [],
    )


def test_generate_script_raises_when_no_context_and_no_cache(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_db_grounding(monkeypatch)
    monkeypatch.setattr(
        docent_service.db_repository, "fetch_docent_script_cache", lambda **kw: None
    )
    request = _make_request(place_id="place-1", category="attraction")

    with pytest.raises(ServiceError) as exc:
        docent_service.generate_script(request)

    assert exc.value.code == "DOCENT_CONTEXT_REQUIRED"


def test_generate_script_returns_cached_script_when_available(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_db_grounding(monkeypatch)
    cached = {"script": "캐시된 도슨트 대본", "source": "cache_hit"}
    monkeypatch.setattr(
        docent_service.db_repository,
        "fetch_docent_script_cache",
        lambda **kw: dict(cached),
    )
    request = _make_request(place_id="place-1", category="attraction")

    result = docent_service.generate_script(request)

    assert result["script"] == "캐시된 도슨트 대본"
    assert result["source"] == "cache_hit"
    assert result["grounding_count"] == 0
    assert result["cache_key"].startswith("docent_script:")


def test_generate_script_produces_rule_based_korean_script(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_db_grounding(monkeypatch)
    monkeypatch.setattr(docent_service.ai_service, "live_ai_enabled", lambda: False)
    request = _make_request(
        place_id="place-1",
        category="attraction",
        language="ko",
        final_score=0.8,
        local_spending_score=0.7,
    )

    result = docent_service.generate_script(request)

    assert result["source"] == "rule_based_curation"
    assert result["place_id"] == "place-1"
    assert result["ttl_sec"] == 604800
    assert "LALA" in result["script"]


def test_generate_script_produces_rule_based_english_script(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_db_grounding(monkeypatch)
    monkeypatch.setattr(docent_service.ai_service, "live_ai_enabled", lambda: False)
    request = _make_request(
        place_id="tour-api-9",
        category="restaurant",
        language="en",
        place_name="Pasta House",
        final_score=0.8,
    )

    result = docent_service.generate_script(request)

    assert result["source"] == "rule_based_curation"
    assert "LALA" in result["script"]
