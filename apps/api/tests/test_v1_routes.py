from __future__ import annotations

import logging

from apps.api.app.services import public_mvp_data


def test_places_route_returns_envelope(client, auth_headers):
    response = client.get(
        "/api/v1/places?lat=37.2&lng=127.0&radius_m=1200&category=event&lang=en",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["count"] == 0
    assert body["data"]["places"] == []
    assert body["data"]["source"] == "db"
    assert body["data"]["query"]["category"] == "event"
    assert body["data"]["query"]["language"] == "en"
    assert body["meta"]["request_id"]


def test_places_accepts_legacy_english_language_value(client, auth_headers):
    response = client.get(
        "/api/v1/places?lat=37.2&lng=127.0&lang=English",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["query"]["language"] == "en"
    assert body["data"]["places"] == []


def test_places_accepts_language_query_alias(client, auth_headers, monkeypatch):
    monkeypatch.setenv("LALA_STATIC_SNAPSHOT_FALLBACK", "true")
    response = client.get(
        "/api/v1/places?lat=37.2636&lng=127.0286&radius_m=50000&language=en",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["query"]["language"] == "en"
    enriched = next(place for place in body["data"]["places"] if place.get("name_en"))
    assert enriched["name"] == enriched["name_en"]
    assert "Gyeonggi-do" in enriched["address"]


def test_places_normalizes_kr_language_alias(client, auth_headers):
    response = client.get(
        "/api/v1/places?lat=37.2&lng=127.0&lang=kr",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["query"]["language"] == "ko"


def test_places_uses_db_repository_when_rows_exist(client, auth_headers, monkeypatch):
    monkeypatch.setattr(
        "apps.api.app.services.db_repository.fetch_places",
        lambda **kwargs: [
            {
                "place_id": "db-place-1",
                "name": "DB Place",
                "name_ko": "DB 장소",
                "name_en": "DB Place",
                "category": "event",
                "lat": 37.2,
                "lng": 127.0,
                "address": "DB address",
                "distance_m": 25,
                "source": "db",
                "score": {
                    "final_score": 0.84,
                    "formula_version": "local-value-v2",
                    "components": {
                        "local_spending_score": 0.9,
                        "small_merchant_fit_score": 0.7,
                        "demand_dispersion_score": 0.8,
                        "culture_relevance_score": 0.8,
                        "weather_fit_score": 0.7,
                        "review_quality_score": None,
                        "accessibility_fit_score": 0.6,
                    },
                    "data_basis": "analytics.place_score_snapshots",
                    "features": {},
                },
            }
        ],
    )

    response = client.get(
        "/api/v1/places?lat=37.2&lng=127.0&category=event&lang=en&include_scores=true",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["source"] == "db"
    assert body["data"]["count"] == 1
    assert body["data"]["query"]["include_scores"] is True
    assert body["data"]["places"][0]["place_id"] == "db-place-1"
    assert body["data"]["places"][0]["score"]["final_score"] == 0.84


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


def test_validation_error_details_do_not_echo_input_values(client, auth_headers):
    marker = "should-not-be-echoed-validation-input"
    response = client.post(
        "/api/v1/docents/audio",
        headers=auth_headers,
        json={"script": {"secret": marker}, "language": "ko"},
    )

    assert response.status_code == 422
    body = response.json()
    assert body["ok"] is False
    assert body["error"]["code"] == "VALIDATION_ERROR"
    assert "details" in body["error"]
    assert '"input"' not in response.text
    assert marker not in response.text


def test_weather_route_returns_envelope(client, auth_headers):
    response = client.get("/api/v1/weather?lat=37.2&lng=127.0", headers=auth_headers)

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["source"] == "unavailable"
    assert body["data"]["temp"] == ""
    assert body["data"]["forecast"] == []
    assert body["data"]["outdoor_status"] == "unknown"
    assert body["data"]["dust"]["grade"] == "unknown"
    assert body["data"]["dust"]["pm10_grade"] == "unknown"
    assert body["data"]["dust"]["pm25_grade_ko"] == "확인 중"


def test_weather_uses_db_repository_when_available(client, auth_headers, monkeypatch):
    monkeypatch.setattr(
        "apps.api.app.services.db_repository.fetch_latest_weather",
        lambda **kwargs: {
            "lat": kwargs["lat"],
            "lng": kwargs["lng"],
            "temp": "18.5",
            "icon": "rain",
            "dust": {
                "pm10": "40",
                "pm25": "18",
                "grade": "normal",
                "grade_ko": "보통",
                "pm10_grade": "normal",
                "pm10_grade_ko": "보통",
                "pm25_grade": "normal",
                "pm25_grade_ko": "보통",
            },
            "forecast": [],
            "outdoor_status": "bad",
            "record_time": "2026-06-18T00:00:00+09:00",
            "source": "db",
        },
    )

    response = client.get("/api/v1/weather?lat=37.2&lng=127.0", headers=auth_headers)

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["source"] == "db"
    assert body["data"]["temp"] == "18.5"
    assert len(body["data"]["forecast"]) == 4
    assert body["data"]["forecast"][0]["temp"] == "18.5"
    assert body["data"]["force"] is False


def test_intervention_treats_unknown_weather_as_neutral(client, auth_headers):
    response = client.get(
        "/api/v1/plans/intervention?lat=37.2&lng=127.0", headers=auth_headers
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["should_intervene"] is False
    assert "pending" in body["data"]["reason"]
    assert "indoor" not in body["data"]["recommended_action"].lower()


def test_docent_script_returns_envelope(client, auth_headers):
    response = client.post(
        "/api/v1/docents/script",
        headers=auth_headers,
        json={
            "place_id": "tour-api-3066000",
            "place_name": "중랑아트센터",
            "address": "서울특별시 중랑구 망우로 353",
            "region_ko": "중랑구",
            "distance_m": 840,
            "source": "db",
            "upstream_source": "tour_api",
            "final_score": 0.86,
            "local_spending_score": 0.82,
            "small_merchant_fit_score": 0.76,
            "demand_dispersion_score": 0.78,
            "weather_fit_score": 0.74,
            "culture_relevance_score": 0.91,
            "category": "event",
            "language": "ko",
            "mode": "brief",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["place_id"] == "tour-api-3066000"
    assert body["data"]["script"]
    assert "중랑아트센터" in body["data"]["script"]
    assert "중랑구" in body["data"]["script"]
    assert "840m" in body["data"]["script"]
    assert "한국관광공사" in body["data"]["script"]
    assert "추천 근거" in body["data"]["script"]
    assert "종합 추천 점수 86점" in body["data"]["script"]
    assert "내국인 소비 신호 강함" in body["data"]["script"]
    assert "소상공인 적합도 보통 이상" in body["data"]["script"]
    assert "관광 수요 분산 효과 보통 이상" in body["data"]["script"]
    assert "날씨 적합도 보통 이상" in body["data"]["script"]
    assert "문화 연계성 강함" in body["data"]["script"]
    assert body["data"]["source"] == "rule_based_curation"
    assert len(body["data"]["request_hash"]) == 64
    assert body["data"]["cache_key"].startswith("docent_script:")


def test_docent_script_accepts_culture_venue_category(client, auth_headers):
    response = client.post(
        "/api/v1/docents/script",
        headers=auth_headers,
        json={
            "place_id": "culture-venue-1",
            "category": "culture_venue",
            "language": "ko",
            "mode": "brief",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["category"] == "culture_venue"
    assert body["data"]["script"]


def test_docent_script_uses_db_cache_before_generation(
    client, auth_headers, monkeypatch
):
    monkeypatch.setattr(
        "apps.api.app.services.db_repository.fetch_docent_script_cache",
        lambda **kwargs: {
            "place_id": kwargs["place_id"],
            "category": kwargs["category"],
            "language": kwargs["language"],
            "mode": kwargs["mode"],
            "script": "Cached DB docent script.",
            "source": "db_cache",
            "generated_at": "2026-06-11T00:00:00+00:00",
            "ttl_sec": 0,
        },
    )

    response = client.post(
        "/api/v1/docents/script",
        headers=auth_headers,
        json={
            "place_id": "event-cache",
            "category": "event",
            "language": "ko",
            "mode": "brief",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["source"] == "db_cache"
    assert body["data"]["script"] == "Cached DB docent script."
    assert len(body["data"]["request_hash"]) == 64
    assert body["data"]["cache_key"].startswith("docent_script:")


def test_docent_script_score_context_skips_stale_cache(
    client, auth_headers, monkeypatch
):
    def fail_if_cache_is_read(**kwargs):
        raise AssertionError("score-aware docent generation must not use stale cache")

    monkeypatch.setattr(
        "apps.api.app.services.db_repository.fetch_docent_script_cache",
        fail_if_cache_is_read,
    )

    response = client.post(
        "/api/v1/docents/script",
        headers=auth_headers,
        json={
            "place_id": "tour-api-score-aware",
            "place_name": "화성행궁",
            "category": "attraction",
            "language": "ko",
            "mode": "brief",
            "final_score": 0.91,
            "local_spending_score": 0.84,
            "demand_dispersion_score": 0.67,
            "weather_fit_score": 0.83,
            "culture_relevance_score": 0.96,
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["source"] == "rule_based_curation"
    assert "종합 추천 점수 91점" in body["data"]["script"]
    assert "내국인 소비 신호 강함" in body["data"]["script"]
    assert "관광 수요 분산 효과 보통 이상" in body["data"]["script"]


def test_docent_script_accepts_legacy_detail_mode_and_english_language(
    client, auth_headers
):
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
    assert "event legacy" in body["data"]["script"]
    assert "official tourism and culture data" in body["data"]["script"]
    assert "local spending signals" in body["data"]["script"]
    assert "skeleton" not in body["data"]["script"].lower()


def test_docent_script_generation_identity_is_deterministic(client, auth_headers):
    payload = {
        "place_id": " event-identity ",
        "category": "event",
        "language": "English",
        "mode": "detail",
    }

    first = client.post("/api/v1/docents/script", headers=auth_headers, json=payload)
    second = client.post(
        "/api/v1/docents/script",
        headers=auth_headers,
        json={**payload, "place_id": "event-identity", "language": "en"},
    )

    assert first.status_code == 200
    assert second.status_code == 200
    first_data = first.json()["data"]
    second_data = second.json()["data"]
    assert first_data["request_hash"] == second_data["request_hash"]
    assert first_data["cache_key"] == second_data["cache_key"]


def test_docent_script_generation_identity_changes_with_score_context(
    client, auth_headers
):
    base_payload = {
        "place_id": "score-identity",
        "category": "event",
        "language": "ko",
        "mode": "brief",
        "final_score": 0.7,
    }

    first = client.post(
        "/api/v1/docents/script", headers=auth_headers, json=base_payload
    )
    second = client.post(
        "/api/v1/docents/script",
        headers=auth_headers,
        json={**base_payload, "final_score": 0.9},
    )

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["data"]["request_hash"] != second.json()["data"]["request_hash"]
    assert first.json()["data"]["cache_key"] != second.json()["data"]["cache_key"]


def test_docent_script_uses_live_ai_when_enabled(client, auth_headers, monkeypatch):
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.setenv("AZURE_OPENAI_ENDPOINT", "https://example.openai.azure.com/")
    monkeypatch.setenv("AZURE_OPENAI_KEY", "test-key")
    monkeypatch.setenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4o-mini")
    monkeypatch.setenv("AZURE_OPENAI_API_VERSION", "2024-10-21")
    saved_calls = []
    monkeypatch.setattr(
        "apps.api.app.services.db_repository.fetch_docent_script_cache",
        lambda **kwargs: None,
    )
    monkeypatch.setattr(
        "apps.api.app.services.ai_service.generate_docent_script_text",
        lambda request: f"AI script for {request.place_id}",
    )
    monkeypatch.setattr(
        "apps.api.app.services.db_repository.save_docent_script_cache",
        lambda **kwargs: saved_calls.append(kwargs) or True,
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
    assert saved_calls == [
        {
            "place_id": "event-2",
            "category": "event",
            "language": "ko",
            "mode": "brief",
            "script": "AI script for event-2",
            "source": "azure_openai",
            "ttl_sec": 604800,
        }
    ]


def test_docent_script_live_ai_score_context_does_not_write_generic_cache(
    client,
    auth_headers,
    monkeypatch,
):
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.setenv("AZURE_OPENAI_ENDPOINT", "https://example.openai.azure.com/")
    monkeypatch.setenv("AZURE_OPENAI_KEY", "test-key")
    monkeypatch.setenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4o-mini")
    monkeypatch.setenv("AZURE_OPENAI_API_VERSION", "2024-10-21")

    def fail_if_cache_is_read(**kwargs):
        raise AssertionError("score-aware live AI generation must not use stale cache")

    saved_calls = []
    prompts = []
    monkeypatch.setattr(
        "apps.api.app.services.db_repository.fetch_docent_script_cache",
        fail_if_cache_is_read,
    )
    monkeypatch.setattr(
        "apps.api.app.services.ai_service.generate_docent_script_text",
        lambda request: prompts.append(request) or "AI score-aware script",
    )
    monkeypatch.setattr(
        "apps.api.app.services.db_repository.save_docent_script_cache",
        lambda **kwargs: saved_calls.append(kwargs) or True,
    )

    response = client.post(
        "/api/v1/docents/script",
        headers=auth_headers,
        json={
            "place_id": "event-score-aware",
            "category": "event",
            "language": "ko",
            "mode": "brief",
            "final_score": 0.88,
            "local_spending_score": 0.81,
            "small_merchant_fit_score": 0.79,
            "demand_dispersion_score": 0.73,
            "weather_fit_score": 0.7,
            "culture_relevance_score": 0.9,
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["source"] == "azure_openai"
    assert body["data"]["script"] == "AI score-aware script"
    assert prompts and prompts[0].final_score == 0.88
    assert saved_calls == []


def test_docent_script_cache_write_failure_keeps_live_ai_response(
    client,
    auth_headers,
    monkeypatch,
    caplog,
):
    caplog.set_level(logging.WARNING, logger="lala_next.api")
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.setenv("AZURE_OPENAI_ENDPOINT", "https://example.openai.azure.com/")
    monkeypatch.setenv("AZURE_OPENAI_KEY", "test-key")
    monkeypatch.setenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4o-mini")
    monkeypatch.setenv("AZURE_OPENAI_API_VERSION", "2024-10-21")
    saved_calls = []
    monkeypatch.setattr(
        "apps.api.app.services.db_repository.fetch_docent_script_cache",
        lambda **kwargs: None,
    )
    monkeypatch.setattr(
        "apps.api.app.services.ai_service.generate_docent_script_text",
        lambda request: f"AI script for {request.place_id}",
    )

    def fail_write(**kwargs):
        saved_calls.append(kwargs)
        return False

    monkeypatch.setattr(
        "apps.api.app.services.db_repository.save_docent_script_cache",
        fail_write,
    )

    response = client.post(
        "/api/v1/docents/script",
        headers=auth_headers,
        json={
            "place_id": "event-write-fail",
            "category": "event",
            "language": "ko",
            "mode": "brief",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["source"] == "azure_openai"
    assert body["data"]["script"] == "AI script for event-write-fail"
    assert len(saved_calls) == 1
    rendered_logs = " ".join(
        record.getMessage()
        for record in caplog.records
        if record.name == "lala_next.api"
    )
    assert "docent_script_write_failed" in rendered_logs
    assert "event-write-fail" in rendered_logs
    assert "AI script for event-write-fail" not in rendered_logs


def test_docent_script_rule_based_fallback_does_not_write_cache(
    client,
    auth_headers,
    monkeypatch,
):
    saved_calls = []
    monkeypatch.setattr(
        "apps.api.app.services.db_repository.fetch_docent_script_cache",
        lambda **kwargs: None,
    )
    monkeypatch.setattr(
        "apps.api.app.services.db_repository.save_docent_script_cache",
        lambda **kwargs: saved_calls.append(kwargs) or True,
    )

    response = client.post(
        "/api/v1/docents/script",
        headers=auth_headers,
        json={
            "place_id": "event-public",
            "place_name": "화성행궁",
            "category": "event",
            "language": "ko",
            "mode": "brief",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["source"] == "rule_based_curation"
    assert body["data"]["script"]
    assert "화성행궁" in body["data"]["script"]
    assert "event-public" not in body["data"]["script"]
    assert "인공지능" not in body["data"]["script"]
    assert "대체됩니다" not in body["data"]["script"]
    assert "skeleton" not in body["data"]["script"].lower()
    assert "azure openai" not in body["data"]["script"].lower()
    assert saved_calls == []


def test_docent_audio_success_returns_mpeg(client, auth_headers):
    response = client.post(
        "/api/v1/docents/audio",
        headers=auth_headers,
        json={"script": "hello", "language": "en"},
    )

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("audio/mpeg")
    assert response.content.startswith(b"ID3")
    assert len(response.headers["x-lala-request-hash"]) == 64
    assert response.headers["x-lala-cache-key"].startswith("docent_audio:")


def test_docent_audio_accepts_korean_language_alias(client, auth_headers):
    response = client.post(
        "/api/v1/docents/audio",
        headers=auth_headers,
        json={"script": " hello ", "language": "Korean"},
    )

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("audio/mpeg")
    assert b"ko: hello" in response.content


def test_docent_audio_generation_identity_uses_normalized_request(client, auth_headers):
    first = client.post(
        "/api/v1/docents/audio",
        headers=auth_headers,
        json={"script": " hello ", "language": "Korean"},
    )
    second = client.post(
        "/api/v1/docents/audio",
        headers=auth_headers,
        json={"script": "hello", "language": "ko"},
    )

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.headers["x-lala-request-hash"] == second.headers["x-lala-request-hash"]
    assert first.headers["x-lala-cache-key"] == second.headers["x-lala-cache-key"]


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
        json={"lat": 37.2, "lng": 127.0, "radius_m": 1200, "language": "ko"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["radius_m"] == 1200
    assert body["data"]["slots"]
    assert len(body["data"]["request_hash"]) == 64
    assert body["data"]["cache_key"].startswith("daily_plan:")


def test_daily_plan_normalizes_english_language(client, auth_headers):
    response = client.post(
        "/api/v1/plans/daily",
        headers=auth_headers,
        json={"lat": 37.2, "lng": 127.0, "language": "English"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["language"] == "en"
    assert body["data"]["slots"] == [
        {
            "period": "afternoon",
            "title": "Adjust by weather",
            "weather_hint": "unknown",
        }
    ]


def test_daily_plan_generation_identity_is_deterministic(client, auth_headers):
    first = client.post(
        "/api/v1/plans/daily",
        headers=auth_headers,
        json={"lat": 37.2, "lng": 127.0, "language": "English"},
    )
    second = client.post(
        "/api/v1/plans/daily",
        headers=auth_headers,
        json={"lat": 37.2, "lng": 127.0, "language": "en"},
    )

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["data"]["request_hash"] == second.json()["data"]["request_hash"]
    assert first.json()["data"]["cache_key"] == second.json()["data"]["cache_key"]


def test_daily_plan_generation_identity_includes_radius(client, auth_headers):
    first = client.post(
        "/api/v1/plans/daily",
        headers=auth_headers,
        json={"lat": 37.2, "lng": 127.0, "radius_m": 1000, "language": "ko"},
    )
    second = client.post(
        "/api/v1/plans/daily",
        headers=auth_headers,
        json={"lat": 37.2, "lng": 127.0, "radius_m": 50000, "language": "ko"},
    )

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["data"]["request_hash"] != second.json()["data"]["request_hash"]


def test_daily_plan_rejects_out_of_range_coordinates(client, auth_headers):
    response = client.post(
        "/api/v1/plans/daily",
        headers=auth_headers,
        json={"lat": 120, "lng": 127.0, "language": "ko"},
    )

    assert response.status_code == 422
    body = response.json()
    assert body["ok"] is False
    assert body["error"]["code"] == "VALIDATION_ERROR"
    assert '"input"' not in response.text


def test_daily_plan_marks_mixed_source_when_db_places_are_used(
    client, auth_headers, monkeypatch
):
    monkeypatch.setattr(
        "apps.api.app.services.db_repository.fetch_places",
        lambda **kwargs: [
            {
                "place_id": "db-plan-place",
                "name": "DB Plan Place",
                "category": "attraction",
                "lat": kwargs["lat"],
                "lng": kwargs["lng"],
                "address": "DB address",
                "distance_m": 15,
                "source": "db",
            }
        ],
    )

    response = client.post(
        "/api/v1/plans/daily",
        headers=auth_headers,
        json={"lat": 37.2, "lng": 127.0, "language": "ko"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["source"] == "mixed"
    assert body["data"]["slots"][0]["place"]["place_id"] == "db-plan-place"


def test_daily_plan_handles_empty_place_candidates(client, auth_headers, monkeypatch):
    monkeypatch.setattr(
        "apps.api.app.services.planner_service.list_places",
        lambda **kwargs: {
            "count": 0,
            "places": [],
            "query": kwargs,
            "source": "db",
        },
    )

    response = client.post(
        "/api/v1/plans/daily",
        headers=auth_headers,
        json={"lat": 0, "lng": 0, "radius_m": 1000, "language": "ko"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["slots"] == [
        {
            "period": "afternoon",
            "title": "날씨에 맞춰 조정",
            "weather_hint": "unknown",
        }
    ]


def test_daily_plan_uses_public_snapshot_radius_in_snapshot_fallback(
    client, monkeypatch
):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.delenv("API_BEARER_TOKEN", raising=False)
    monkeypatch.setenv("LALA_STATIC_SNAPSHOT_FALLBACK", "true")

    response = client.post(
        "/api/v1/plans/daily",
        json={"lat": 37.2636, "lng": 127.0286, "radius_m": 50000, "language": "ko"},
    )

    assert response.status_code == 200
    body = response.json()
    expected_place = public_mvp_data.fetch_places(
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="all",
        language="ko",
    )[0]
    assert body["data"]["source"] == "mixed"
    assert body["data"]["slots"][0]["place"]["source"] == "public_mvp_snapshot"
    assert body["data"]["slots"][0]["place"]["place_id"] == expected_place["place_id"]


def test_intervention_route_returns_envelope(client, auth_headers):
    response = client.get(
        "/api/v1/plans/intervention?lat=37.2&lng=127.0&radius_m=1000",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["data"]["recommended_action"]
    assert body["data"]["place"] is None


def test_intervention_uses_public_snapshot_candidate_in_snapshot_fallback(
    client, monkeypatch
):
    monkeypatch.delenv("IOS_API_KEY", raising=False)
    monkeypatch.delenv("API_BEARER_TOKEN", raising=False)
    monkeypatch.setenv("LALA_STATIC_SNAPSHOT_FALLBACK", "true")

    response = client.get(
        "/api/v1/plans/intervention?lat=37.2636&lng=127.0286&radius_m=50000",
    )

    assert response.status_code == 200
    body = response.json()
    expected_place = public_mvp_data.fetch_places(
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="all",
        language="ko",
    )[0]
    assert body["data"]["source"] == "mixed"
    assert body["data"]["place"]["source"] == "public_mvp_snapshot"
    assert body["data"]["place"]["place_id"] == expected_place["place_id"]
