from __future__ import annotations


def test_places_route_returns_envelope(client, auth_headers):
    response = client.get(
        "/api/v1/places?lat=37.2&lng=127.0&radius_m=1200&category=event&lang=en",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["count"] == 1
    assert body["data"]["places"][0]["category"] == "event"
    assert body["data"]["places"][0]["name"] == "Suwon Hwaseong"
    assert body["meta"]["request_id"]


def test_places_invalid_category_returns_json_error(client, auth_headers):
    response = client.get("/api/v1/places?category=bad", headers=auth_headers)

    assert response.status_code == 400
    body = response.json()
    assert body["ok"] is False
    assert body["error"]["code"] == "INVALID_CATEGORY"


def test_weather_route_returns_envelope(client, auth_headers):
    response = client.get("/api/v1/weather?lat=37.2&lng=127.0", headers=auth_headers)

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["source"] == "skeleton"
    assert body["data"]["dust"]["grade"] == "normal"


def test_docent_script_returns_envelope(client, auth_headers):
    response = client.post(
        "/api/v1/docents/script",
        headers=auth_headers,
        json={
            "place_id": "event-1",
            "category": "event",
            "language": "ko",
            "mode": "brief",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["place_id"] == "event-1"
    assert body["data"]["script"]


def test_docent_audio_success_returns_mpeg(client, auth_headers):
    response = client.post(
        "/api/v1/docents/audio",
        headers=auth_headers,
        json={"script": "hello", "language": "en"},
    )

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("audio/mpeg")
    assert response.content.startswith(b"ID3")


def test_docent_audio_validation_failure_returns_json_envelope(client, auth_headers):
    response = client.post(
        "/api/v1/docents/audio",
        headers=auth_headers,
        json={"script": "", "language": "en"},
    )

    assert response.status_code == 422
    body = response.json()
    assert body["ok"] is False
    assert body["error"]["code"] == "VALIDATION_ERROR"


def test_daily_plan_route_returns_envelope(client, auth_headers):
    response = client.post(
        "/api/v1/plans/daily",
        headers=auth_headers,
        json={"lat": 37.2, "lng": 127.0, "language": "ko"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["slots"]


def test_intervention_route_returns_envelope(client, auth_headers):
    response = client.get(
        "/api/v1/plans/intervention?lat=37.2&lng=127.0&radius_m=1000",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["recommended_action"]

