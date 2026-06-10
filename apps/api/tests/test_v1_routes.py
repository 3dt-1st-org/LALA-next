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
    assert body["data"]["source"] == "skeleton"


def test_docent_script_uses_live_ai_when_enabled(client, auth_headers, monkeypatch):
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.setenv("AZURE_OPENAI_ENDPOINT", "https://example.openai.azure.com/")
    monkeypatch.setenv("AZURE_OPENAI_KEY", "test-key")
    monkeypatch.setenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4o-mini")
    monkeypatch.setenv("AZURE_OPENAI_API_VERSION", "2024-10-21")
    monkeypatch.setattr(
        "apps.api.app.services.ai_service.generate_docent_script_text",
        lambda request: f"AI script for {request.place_id}",
    )

    response = client.post(
        "/api/v1/docents/script",
        headers=auth_headers,
        json={
            "place_id": "event-2",
            "category": "event",
            "language": "ko",
            "mode": "brief",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["source"] == "azure_openai"
    assert body["data"]["script"] == "AI script for event-2"


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
