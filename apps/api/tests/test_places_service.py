from __future__ import annotations

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

    monkeypatch.setattr(
        places_service.db_repository, "fetch_places", fake_fetch_places
    )
    return captured


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
    captured = _patch_db_fetch_places(
        monkeypatch, places=[{"name": "spot", "score": 0.5}]
    )

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
def test_list_places_normalizes_language(
    language: str | None, expected: str, monkeypatch
) -> None:
    monkeypatch.setattr(places_service, "get_settings", lambda: _fake_settings())
    captured = _patch_db_fetch_places(
        monkeypatch, places=[{"name": "spot", "score": 0.5}]
    )

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
    assert result["places"] == places
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


def test_list_places_returns_empty_payload_when_no_results_and_no_fallback(
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        places_service, "get_settings", lambda: _fake_settings(static_snapshot_fallback=False, db_dsn="")
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
        places_service, "get_settings", lambda: _fake_settings(static_snapshot_fallback=False, db_dsn="postgres://x")
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
def test_places_without_scores_nullifies_score_field(
    place: dict, expected_score
) -> None:
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
