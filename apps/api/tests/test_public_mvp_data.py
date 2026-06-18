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
    assert all(place.get("name_en") for place in places)
    assert all(place["name"] == place["name_en"] for place in places)
    assert all("Gyeonggi-do" in place["address"] for place in places)


def test_public_mvp_snapshot_preserves_official_image_urls() -> None:
    places = public_mvp_data.fetch_places(
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="all",
        language="ko",
    )

    hoam = next(place for place in places if place["place_id"] == "tour-api-129765")
    assert hoam["image_url"] == "http://tong.visitkorea.or.kr/cms/resource/93/3086393_image2_1.jpg"
