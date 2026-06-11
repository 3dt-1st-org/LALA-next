from __future__ import annotations


def test_openapi_schema_is_public_and_lists_wave1_routes(client):
    response = client.get("/openapi.json")

    assert response.status_code == 200
    schema = response.json()
    paths = schema["paths"]
    for route in (
        "/healthz",
        "/readyz",
        "/api/v1/places",
        "/api/v1/weather",
        "/api/v1/docents/script",
        "/api/v1/docents/audio",
        "/api/v1/plans/daily",
        "/api/v1/plans/intervention",
    ):
        assert route in paths


def test_openapi_documents_client_auth_headers_on_v1_routes(client):
    schema = client.get("/openapi.json").json()
    places_params = schema["paths"]["/api/v1/places"]["get"]["parameters"]

    assert any(
        param["name"] == "X-API-Key" and param["in"] == "header"
        for param in places_params
    )
    assert any(
        param["name"] == "Authorization" and param["in"] == "header"
        for param in places_params
    )


def test_openapi_documents_docent_audio_mpeg_success(client):
    schema = client.get("/openapi.json").json()
    success_response = schema["paths"]["/api/v1/docents/audio"]["post"]["responses"]["200"]

    assert "audio/mpeg" in success_response["content"]
    assert success_response["content"]["audio/mpeg"]["schema"] == {
        "type": "string",
        "format": "binary",
    }
