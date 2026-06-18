from __future__ import annotations

from apps.api.app.services import public_mvp_data


GYEONGGI_REGIONS = {
    "가평군",
    "고양시",
    "과천시",
    "광명시",
    "광주시",
    "구리시",
    "군포시",
    "김포시",
    "남양주시",
    "동두천시",
    "부천시",
    "성남시",
    "수원시",
    "시흥시",
    "안산시",
    "안성시",
    "안양시",
    "양주시",
    "양평군",
    "여주시",
    "연천군",
    "오산시",
    "용인시",
    "의왕시",
    "의정부시",
    "이천시",
    "파주시",
    "평택시",
    "포천시",
    "하남시",
    "화성시",
}


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
    event = next(place for place in places if place["category"] == "event")
    assert event["place_id"].startswith("tour-api-")
    assert event["upstream_source"] == "tour_api"
    assert event["image_url"]
    assert event["is_approximate_location"] is False


def test_public_mvp_snapshot_ranking_keeps_map_center_local() -> None:
    places = public_mvp_data.fetch_places(
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="all",
        language="ko",
    )

    assert any(place["distance_m"] <= 1000 for place in places[:5])


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
    assert all(place.get("region_en") for place in rows)


def test_public_mvp_snapshot_covers_all_gyeonggi_regions() -> None:
    rows = public_mvp_data._load_snapshot()["places"]

    assert rows
    assert {place.get("region_ko") for place in rows} == GYEONGGI_REGIONS


def test_public_mvp_snapshot_uses_only_real_official_images() -> None:
    rows = public_mvp_data._load_snapshot()["places"]
    image_urls = [place.get("image_url") for place in rows if place.get("image_url")]

    assert image_urls
    assert all(url.startswith("https://") for url in image_urls)
    assert all("tong.visitkorea.or.kr" in url for url in image_urls)
    assert all("placeholder" not in url.lower() for url in image_urls)
    assert all("mock" not in url.lower() for url in image_urls)


def test_public_mvp_snapshot_does_not_include_dev_seed_rows() -> None:
    rows = public_mvp_data._load_snapshot()["places"]

    assert rows
    assert all(place.get("upstream_source") != "dev_seed" for place in rows)


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
