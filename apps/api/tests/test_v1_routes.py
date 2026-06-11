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


def test_places_accepts_legacy_english_language_value(client, auth_headers):
    response = client.get(
        "/api/v1/places?lat=37.2&lng=127.0&lang=English",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["query"]["language"] == "en"
    assert body["data"]["places"][0]["name"] == "Suwon Hwaseong"


def test_places_normalizes_kr_language_alias(client, auth_headers):
    response = client.get(
        "/api/v1/places?lat=37.2&lng=127.0&lang=kr",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["query"]["language"] == "ko"


def test_places_invalid_category_returns_json_error(client, auth_headers):
    response = client.get("/api/v1/places?category=bad", headers=auth_headers)

    assert response.status_code == 400
    body = response.json()
    assert body["ok"] is False
    assert body["error"]["code"] == "INVALID_CATEGORY"


def test_places_rejects_out_of_range_coordinates(client, auth_headers):
    response = client.get("/api/v1/places?lat=120&lng=127.0", headers=auth_headers)

    assert response.status_code == 422
    body = response.json()
    assert body["ok"] is False
    assert body["error"]["code"] == "VALIDATION_ERROR"


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


def test_docent_script_accepts_legacy_detail_mode_and_english_language(client, auth_headers):
    response = client.post(
        "/api/v1/docents/script",
        headers=auth_headers,
        json={
            "place_id": " event-legacy ",
            "category": "event",
            "language": "English",
            "mode": "detail",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["place_id"] == "event-legacy"
    assert body["data"]["language"] == "en"
    assert body["data"]["mode"] == "detail"
    assert "detail English docent script" in body["data"]["script"]


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


def test_docent_audio_accepts_korean_language_alias(client, auth_headers):
    response = client.post(
        "/api/v1/docents/audio",
        headers=auth_headers,
        json={"script": " hello ", "language": "Korean"},
    )

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("audio/mpeg")
    assert b"ko: hello" in response.content


def test_docent_audio_uses_live_speech_when_enabled(client, auth_headers, monkeypatch):
    monkeypatch.setenv("LALA_ENABLE_LIVE_SPEECH", "true")
    monkeypatch.setenv("AZURE_SPEECH_REGION", "koreacentral")
    monkeypatch.setenv("AZURE_SPEECH_KEY", "test-key")
    monkeypatch.setattr(
        "apps.api.app.services.speech_service.synthesize_docent_audio",
        lambda request: b"live-mpeg-bytes",
    )

    response = client.post(
        "/api/v1/docents/audio",
        headers=auth_headers,
        json={"script": "hello", "language": "en"},
    )

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("audio/mpeg")
    assert response.content == b"live-mpeg-bytes"


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


def test_daily_plan_normalizes_english_language(client, auth_headers):
    response = client.post(
        "/api/v1/plans/daily",
        headers=auth_headers,
        json={"lat": 37.2, "lng": 127.0, "language": "English"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["language"] == "en"
    assert body["data"]["slots"][0]["place"]["name"] == "Suwon Hwaseong"


def test_intervention_route_returns_envelope(client, auth_headers):
    response = client.get(
        "/api/v1/plans/intervention?lat=37.2&lng=127.0&radius_m=1000",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["recommended_action"]
