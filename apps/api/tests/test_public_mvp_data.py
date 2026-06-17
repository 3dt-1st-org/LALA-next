from __future__ import annotations

from apps.api.app.services import public_mvp_data


def test_public_mvp_snapshot_is_available() -> None:
    assert public_mvp_data.snapshot_status() == "configured"


def test_public_mvp_snapshot_returns_nearby_ranked_places() -> None:
    places = public_mvp_data.fetch_places(
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="all",
        language="ko",
    )

    assert places
    assert places[0]["source"] == "public_mvp_snapshot"
    assert places[0]["score"]["data_basis"] == "public_mvp_snapshot"
    assert {place["category"] for place in places} >= {"attraction", "event"}


def test_public_mvp_snapshot_filters_culture_venues() -> None:
    places = public_mvp_data.fetch_places(
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="culture_venue",
        language="ko",
    )

    assert places
    assert all(place["category"] == "culture_venue" for place in places)


def test_public_mvp_snapshot_uses_english_fields_when_requested() -> None:
    places = public_mvp_data.fetch_places(
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="all",
        language="en",
    )

    assert places
    enriched = next(place for place in places if place.get("name_en"))
    assert enriched["name"] == enriched["name_en"]
    assert "Gyeonggi-do" in enriched["address"]
    fallback = next(place for place in places if not place.get("name_en"))
    assert fallback["name"] == fallback["name_ko"]
