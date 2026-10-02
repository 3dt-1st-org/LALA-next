from __future__ import annotations

import sys
import types

import pytest

from apps.api.app.services import db_repository


def _db_place(place_id: str, *, language: str = "ko", include_scores: bool = False) -> dict:
    return {
        "place_id": place_id,
        "name": "Public Place" if language == "en" else "공개 장소",
        "name_ko": "공개 장소",
        "name_en": "Public Place",
        "category": "attraction",
        "lat": 37.2,
        "lng": 127.0,
        "address": "Public address" if language == "en" else "공개 주소",
        "image_url": None,
        "region_ko": "수원시",
        "region_en": "Suwon-si",
        "event_start_date": None,
        "event_end_date": None,
        "event_url": None,
        "is_ongoing": None,
        "is_approximate_location": False,
        "is_indoor": None,
        "distance_m": None,
        "source": "db",
        "upstream_source": "tour_api",
        "_local_activity_band": "active",
        "_has_linked_event": False,
        "_updated_at": "2026-09-20T00:00:00Z",
        "score": {"final_score": 0.8} if include_scores else None,
    }


def test_single_place_lookup_preserves_public_shape_and_normalizes_language(
    client, auth_headers, monkeypatch
):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    captured = {}

    def fake_fetch(**kwargs):
        captured.update(kwargs)
        return [_db_place(kwargs["place_ids"][0], language=kwargs["language"])]

    monkeypatch.setattr(db_repository, "fetch_places_by_ids", fake_fetch)

    response = client.get(
        "/api/v1/places/public-1?language=English",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["place_id"] == "public-1"
    assert body["data"]["name"] == "Public Place"
    assert body["data"]["lat"] == 37.2
    assert body["data"]["lng"] == 127.0
    assert body["data"]["distance_m"] is None
    assert body["data"]["reason"] is None
    assert body["data"]["freshness"] is None
    assert body["data"]["score"] is None
    assert not any(key.startswith("_") for key in body["data"])
    assert body["meta"]["source"] == "db"
    assert body["meta"]["language"] == "en"
    assert captured == {
        "place_ids": ["public-1"],
        "language": "en",
        "include_scores": False,
    }


def test_single_lookup_accepts_encoded_slash_in_opaque_id(client, auth_headers, monkeypatch):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    captured = {}

    def fake_fetch(**kwargs):
        captured.update(kwargs)
        return [_db_place(kwargs["place_ids"][0])]

    monkeypatch.setattr(db_repository, "fetch_places_by_ids", fake_fetch)

    response = client.get("/api/v1/places/quoted%2Fid", headers=auth_headers)

    assert response.status_code == 200
    assert response.json()["data"]["place_id"] == "quoted/id"
    assert captured["place_ids"] == ["quoted/id"]


def test_single_unknown_returns_source_scoped_not_found(client, auth_headers, monkeypatch):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    monkeypatch.setattr(db_repository, "fetch_places_by_ids", lambda **kwargs: [])

    response = client.get("/api/v1/places/unknown", headers=auth_headers)

    assert response.status_code == 404
    assert response.json()["error"] == {
        "code": "PLACE_NOT_FOUND",
        "message": "The place ID is unknown in the selected public data source.",
        "retryable": False,
    }


def test_batch_lookup_deduplicates_and_orders_matches_and_misses(client, auth_headers, monkeypatch):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    calls = []

    def fake_fetch(**kwargs):
        calls.append(kwargs)
        return [
            _db_place(place_id, language=kwargs["language"], include_scores=True)
            for place_id in kwargs["place_ids"]
            if place_id != "missing"
        ]

    monkeypatch.setattr(db_repository, "fetch_places_by_ids", fake_fetch)

    response = client.post(
        "/api/v1/places/lookup?lang=eng&include_scores=true",
        headers=auth_headers,
        json={"place_ids": ["second", "missing", "first", "second", "missing"]},
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert [place["place_id"] for place in data["places"]] == ["second", "first"]
    assert data["missing_place_ids"] == ["missing"]
    assert data["query"] == {
        "place_ids": ["second", "missing", "first"],
        "language": "en",
        "include_scores": True,
    }
    assert data["places"][0]["score"]["final_score"] == 0.8
    assert len(calls) == 1
    assert calls[0]["place_ids"] == ["second", "missing", "first"]


@pytest.mark.parametrize(
    "place_ids",
    [[], [""], ["   "], ["bad\u0001id"], ["x" * 129]],
)
def test_invalid_batch_does_not_call_repository(client, auth_headers, monkeypatch, place_ids):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    monkeypatch.setattr(
        db_repository,
        "fetch_places_by_ids",
        lambda **kwargs: pytest.fail("repository must not be called"),
    )

    response = client.post(
        "/api/v1/places/lookup",
        headers=auth_headers,
        json={"place_ids": place_ids},
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"


def test_batch_rejects_more_than_one_hundred_before_repository(client, auth_headers, monkeypatch):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    monkeypatch.setattr(
        db_repository,
        "fetch_places_by_ids",
        lambda **kwargs: pytest.fail("repository must not be called"),
    )

    response = client.post(
        "/api/v1/places/lookup",
        headers=auth_headers,
        json={"place_ids": [f"place-{index}" for index in range(101)]},
    )

    assert response.status_code == 422


def test_batch_accepts_one_hundred_entries_and_maximum_length_id(client, auth_headers, monkeypatch):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    maximum_id = "x" * 128
    place_ids = [maximum_id, *[f"place-{index}" for index in range(99)]]
    captured = {}

    def fake_fetch(**kwargs):
        captured.update(kwargs)
        place = _db_place(maximum_id)
        place["address"] = None
        return [place]

    monkeypatch.setattr(db_repository, "fetch_places_by_ids", fake_fetch)

    response = client.post(
        "/api/v1/places/lookup",
        headers=auth_headers,
        json={"place_ids": place_ids},
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert captured["place_ids"] == place_ids
    assert data["places"][0]["place_id"] == maximum_id
    assert data["places"][0]["address"] is None
    assert data["missing_place_ids"] == place_ids[1:]


def test_batch_all_missing_is_success(client, auth_headers, monkeypatch):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    monkeypatch.setattr(db_repository, "fetch_places_by_ids", lambda **kwargs: [])

    response = client.post(
        "/api/v1/places/lookup",
        headers=auth_headers,
        json={"place_ids": ["missing-a", "missing-b"]},
    )

    assert response.status_code == 200
    assert response.json()["data"]["places"] == []
    assert response.json()["data"]["missing_place_ids"] == ["missing-a", "missing-b"]


def test_single_invalid_id_does_not_call_repository(client, auth_headers, monkeypatch):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    monkeypatch.setattr(
        db_repository,
        "fetch_places_by_ids",
        lambda **kwargs: pytest.fail("repository must not be called"),
    )

    response = client.get("/api/v1/places/%20", headers=auth_headers)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"


def test_lookup_without_db_or_explicit_fallback_is_retryable_503(client, auth_headers):
    response = client.post(
        "/api/v1/places/lookup",
        headers=auth_headers,
        json={"place_ids": ["public-1"]},
    )

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "PLACES_DB_UNAVAILABLE"
    assert response.json()["error"]["retryable"] is True


def test_db_outage_is_not_converted_to_not_found(client, auth_headers, monkeypatch):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")

    def fail_fetch(**kwargs):
        raise db_repository.DatabaseReadError("place_lookup_query_failed")

    monkeypatch.setattr(db_repository, "fetch_places_by_ids", fail_fetch)

    response = client.get("/api/v1/places/public-1", headers=auth_headers)

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "PLACES_DB_UNAVAILABLE"


def test_explicit_snapshot_fallback_preserves_provenance(client, auth_headers, monkeypatch):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    monkeypatch.setenv("LALA_STATIC_SNAPSHOT_FALLBACK", "true")
    monkeypatch.setattr(
        db_repository,
        "fetch_places_by_ids",
        lambda **kwargs: (_ for _ in ()).throw(db_repository.DatabaseReadError("outage")),
    )

    response = client.post(
        "/api/v1/places/lookup?include_scores=true",
        headers=auth_headers,
        json={"place_ids": ["tour-api-126618", "snapshot-missing"]},
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["source"] == "public_mvp_snapshot"
    assert data["places"][0]["source"] == "public_mvp_snapshot"
    assert data["places"][0]["distance_m"] is None
    assert data["missing_place_ids"] == ["snapshot-missing"]
    assert data["data_as_of"]


def test_unavailable_snapshot_fallback_returns_retryable_503(client, auth_headers, monkeypatch):
    from apps.api.app.services import public_mvp_data

    monkeypatch.setenv("LALA_STATIC_SNAPSHOT_FALLBACK", "true")
    monkeypatch.setattr(public_mvp_data, "snapshot_status", lambda: "missing")
    monkeypatch.setattr(
        public_mvp_data,
        "fetch_places_by_ids",
        lambda **kwargs: pytest.fail("unavailable snapshot must not be queried"),
    )

    response = client.post(
        "/api/v1/places/lookup",
        headers=auth_headers,
        json={"place_ids": ["public-1"]},
    )

    assert response.status_code == 503
    assert response.json()["error"] == {
        "code": "PLACES_DB_UNAVAILABLE",
        "message": "Place lookup is temporarily unavailable.",
        "retryable": True,
    }


def test_valid_snapshot_source_miss_remains_source_scoped_404(client, auth_headers, monkeypatch):
    from apps.api.app.services import public_mvp_data

    monkeypatch.setenv("LALA_STATIC_SNAPSHOT_FALLBACK", "true")
    monkeypatch.setattr(public_mvp_data, "snapshot_status", lambda: "configured")
    monkeypatch.setattr(public_mvp_data, "fetch_places_by_ids", lambda **kwargs: [])

    response = client.get("/api/v1/places/snapshot-missing", headers=auth_headers)

    assert response.status_code == 404
    assert response.json()["error"] == {
        "code": "PLACE_NOT_FOUND",
        "message": "The place ID is unknown in the selected public data source.",
        "retryable": False,
    }


def test_snapshot_lookup_does_not_invent_missing_coordinates(monkeypatch):
    from apps.api.app.services import public_mvp_data

    monkeypatch.setattr(
        public_mvp_data,
        "_load_snapshot",
        lambda: {
            "places": [
                {
                    "place_id": "invalid-coordinate-place",
                    "name_ko": "좌표 없음",
                    "category": "attraction",
                    "lat": None,
                    "lng": None,
                }
            ]
        },
    )

    assert (
        public_mvp_data.fetch_places_by_ids(
            place_ids=["invalid-coordinate-place"],
            language="ko",
        )
        == []
    )


def test_new_lookup_routes_preserve_client_auth(client, api_key, monkeypatch):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    monkeypatch.setattr(db_repository, "fetch_places_by_ids", lambda **kwargs: [])

    response = client.get("/api/v1/places/public-1")

    assert response.status_code == 401


def test_lookup_remains_guest_accessible_when_public_mode_is_enabled(client, monkeypatch):
    monkeypatch.setenv("LALA_GUEST_ACCESS", "true")
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    monkeypatch.setattr(
        db_repository,
        "fetch_places_by_ids",
        lambda **kwargs: [_db_place(kwargs["place_ids"][0])],
    )

    response = client.get("/api/v1/places/public-1")

    assert response.status_code == 200
    assert response.json()["data"]["place_id"] == "public-1"


def test_repository_uses_one_parameterized_public_view_query(monkeypatch):
    monkeypatch.setenv("DB_DSN", "postgresql://db.example/lala")
    captured = {"calls": 0}

    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql, params):
            captured["calls"] += 1
            captured["sql"] = sql
            captured["params"] = params

        def fetchall(self):
            return []

    class FakeConnection:
        def cursor(self, cursor_factory=None):
            return FakeCursor()

        def close(self):
            return None

    extras_module = types.ModuleType("psycopg2.extras")
    extras_module.RealDictCursor = object()
    monkeypatch.setitem(sys.modules, "psycopg2.extras", extras_module)
    monkeypatch.setattr(db_repository, "connect_db", lambda *args, **kwargs: FakeConnection())
    malicious_id = "quote'--유니코드"

    places = db_repository.fetch_places_by_ids(
        place_ids=[malicious_id, "public-2"],
        language="ko",
    )

    assert places == []
    assert captured["calls"] == 1
    assert "JOIN travel.public_places" in captured["sql"]
    assert "unnest(%s::text[])" in captured["sql"]
    assert malicious_id not in captured["sql"]
    assert captured["params"] == ([malicious_id, "public-2"],)


def test_geo_and_id_lookups_share_public_projection_mapping():
    row = {
        "place_id": "shared-place",
        "name_ko": "공유 장소",
        "name_en": "Shared Place",
        "category": "event",
        "address_ko": None,
        "address_en": None,
        "image_url": None,
        "region_ko": "수원시",
        "region_en": "Suwon-si",
        "lat": 37.2,
        "lng": 127.0,
        "source": "tour_api",
        "event_start_date": "2026-09-20",
        "event_end_date": "2026-09-22",
        "event_url": "https://example.test/event",
        "is_ongoing": True,
        "is_approximate_location": False,
        "is_indoor": True,
        "_local_activity_band": "active",
        "_has_linked_event": True,
        "final_score": None,
    }

    geo_place = db_repository._place_payload_from_row(
        row,
        language="en",
        include_scores=False,
        distance_m=125.4,
    )
    id_place = db_repository._place_payload_from_row(
        row,
        language="en",
        include_scores=False,
        distance_m=None,
    )

    assert geo_place["distance_m"] == 125
    assert id_place["distance_m"] is None
    assert {key: value for key, value in geo_place.items() if key != "distance_m"} == {
        key: value for key, value in id_place.items() if key != "distance_m"
    }
