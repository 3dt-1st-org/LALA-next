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
    event = next(place for place in places if place["place_id"] == "demo-suwon-night-walk")
    assert event["event_start_date"] == "2026-06-01"
    assert event["event_end_date"] == "2026-08-31"
    assert event["event_url"].endswith("/suwon-night-walk-2026")
    assert event["is_ongoing"] is True
    assert event["is_approximate_location"] is False


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
    assert all(not any("가" <= char <= "힣" for char in place["name"]) for place in places)
    assert all("Gyeonggi-do" in place["address"] for place in places)


def test_public_mvp_snapshot_has_publishable_english_labels() -> None:
    rows = public_mvp_data._load_snapshot()["places"]

    assert rows
    assert all(place.get("name_en") for place in rows)
    assert all(place.get("address_en") for place in rows)


def test_public_mvp_snapshot_does_not_show_generic_english_names() -> None:
    places = public_mvp_data.fetch_places(
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="all",
        language="en",
    )

    assert all(" in " not in place["name"] for place in places)


def test_public_mvp_snapshot_preserves_official_image_urls() -> None:
    places = public_mvp_data.fetch_places(
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="all",
        language="ko",
    )

    official_image = next(
        place for place in places if (place.get("image_url") or "").startswith("http")
    )
    assert "tong.visitkorea.or.kr" in official_image["image_url"]
