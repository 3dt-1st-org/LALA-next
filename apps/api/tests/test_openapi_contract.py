from __future__ import annotations


def test_openapi_schema_is_public_and_lists_wave1_routes(client):
    response = client.get("/openapi.json")

    assert response.status_code == 200
    schema = response.json()
    paths = schema["paths"]
    for route in (
        "/healthz",
        "/metrics",
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
    security_schemes = schema["components"]["securitySchemes"]

    assert any(
        param["name"] == "X-API-Key" and param["in"] == "header"
        for param in places_params
    )
    assert any(
        param["name"] == "Authorization" and param["in"] == "header"
        for param in places_params
    )
    assert security_schemes["BearerAuth"]["scheme"] == "bearer"
    assert security_schemes["MigrationApiKey"]["name"] == "X-API-Key"
    assert schema["paths"]["/api/v1/places"]["get"]["security"] == [
        {"BearerAuth": []},
        {"MigrationApiKey": []},
    ]
    assert "security" not in schema["paths"]["/healthz"]["get"]


def test_openapi_documents_public_route_timeout_expectations(client):
    schema = client.get("/openapi.json").json()
    route_contracts = {
        "/healthz": ("get", 3, False),
        "/readyz": ("get", 3, False),
        "/metrics": ("get", 3, False),
        "/api/v1/places": ("get", 5, True),
        "/api/v1/weather": ("get", 5, True),
        "/api/v1/docents/script": ("post", 30, True),
        "/api/v1/docents/audio": ("post", 30, True),
        "/api/v1/plans/daily": ("post", 20, True),
        "/api/v1/plans/intervention": ("get", 5, True),
    }

    for path, (method, timeout_seconds, auth_required) in route_contracts.items():
        operation = schema["paths"][path][method]
        assert operation["x-lala-timeout-seconds"] == timeout_seconds
        assert operation["x-lala-auth-required"] is auth_required


def test_openapi_documents_v1_error_envelope(client):
    schema = client.get("/openapi.json").json()
    places_operation = schema["paths"]["/api/v1/places"]["get"]
    responses = places_operation["responses"]

    assert schema["components"]["schemas"]["ApiErrorEnvelope"]["properties"]["error"] == {
        "$ref": "#/components/schemas/ApiError"
    }
    assert responses["401"]["content"]["application/json"]["schema"] == {
        "$ref": "#/components/schemas/ApiErrorEnvelope"
    }
    assert responses["422"]["content"]["application/json"]["schema"] == {
        "$ref": "#/components/schemas/ApiErrorEnvelope"
    }
    assert responses["422"]["description"] == "Request validation failed."


def test_openapi_documents_json_success_envelope(client):
    schema = client.get("/openapi.json").json()
    healthz_ref = {"$ref": "#/components/schemas/HealthzSuccessEnvelope"}
    readyz_ref = {"$ref": "#/components/schemas/ReadyzSuccessEnvelope"}
    places_ref = {"$ref": "#/components/schemas/PlacesSuccessEnvelope"}

    assert schema["components"]["schemas"]["ApiSuccessEnvelope"]["properties"]["ok"] == {
        "type": "boolean",
        "const": True,
    }
    assert (
        schema["paths"]["/healthz"]["get"]["responses"]["200"]["content"]["application/json"][
            "schema"
        ]
        == healthz_ref
    )
    assert (
        schema["paths"]["/readyz"]["get"]["responses"]["200"]["content"]["application/json"][
            "schema"
        ]
        == readyz_ref
    )
    assert (
        schema["paths"]["/api/v1/places"]["get"]["responses"]["200"]["content"][
            "application/json"
        ]["schema"]
        == places_ref
    )
    assert "application/json" not in schema["paths"]["/api/v1/docents/audio"]["post"][
        "responses"
    ]["200"]["content"]


def test_openapi_documents_readyz_runtime_mode(client):
    schema = client.get("/openapi.json").json()
    schemas = schema["components"]["schemas"]

    assert schemas["ReadyzSuccessEnvelope"]["properties"]["data"] == {
        "$ref": "#/components/schemas/ReadyzData"
    }
    assert schemas["ReadyzData"]["properties"]["mode"] == {
        "$ref": "#/components/schemas/RuntimeMode"
    }
    runtime_mode = schemas["RuntimeMode"]["properties"]
    assert runtime_mode["overall"]["enum"] == [
        "skeleton",
        "db-backed",
        "live-azure",
        "degraded",
    ]
    assert runtime_mode["data"]["enum"] == ["skeleton", "db-backed", "degraded"]
    assert runtime_mode["worker"]["enum"] == ["dry-run", "degraded"]
    readiness_checks = schemas["ReadinessChecks"]["properties"]
    assert readiness_checks["client_auth"]["enum"] == [
        "configured",
        "missing",
        "public-demo",
    ]
    assert readiness_checks["client_identity"]["enum"] == [
        "static",
        "transition",
        "oauth-configured",
        "public-demo",
        "missing",
    ]
    assert readiness_checks["public_demo_mode"]["enum"] == ["enabled", "disabled"]
    assert readiness_checks["jwt_validation"]["enum"] == ["configured", "skipped"]
    assert readiness_checks["oauth_jwks_url"]["enum"] == ["configured", "skipped"]


def test_openapi_documents_v1_success_data_schemas(client):
    schema = client.get("/openapi.json").json()
    schemas = schema["components"]["schemas"]

    assert schema["paths"]["/api/v1/weather"]["get"]["responses"]["200"]["content"][
        "application/json"
    ]["schema"] == {"$ref": "#/components/schemas/WeatherSuccessEnvelope"}
    assert schema["paths"]["/api/v1/docents/script"]["post"]["responses"]["200"][
        "content"
    ]["application/json"]["schema"] == {
        "$ref": "#/components/schemas/DocentScriptSuccessEnvelope"
    }
    assert schema["paths"]["/api/v1/plans/daily"]["post"]["responses"]["200"][
        "content"
    ]["application/json"]["schema"] == {
        "$ref": "#/components/schemas/DailyPlanSuccessEnvelope"
    }
    assert schema["paths"]["/api/v1/plans/intervention"]["get"]["responses"]["200"][
        "content"
    ]["application/json"]["schema"] == {
        "$ref": "#/components/schemas/InterventionSuccessEnvelope"
    }

    assert schemas["PlacesSuccessEnvelope"]["properties"]["data"] == {
        "$ref": "#/components/schemas/PlacesData"
    }
    assert schemas["PlacesData"]["properties"]["places"]["items"] == {
        "$ref": "#/components/schemas/Place"
    }
    assert "distance_m" in schemas["Place"]["required"]
    assert schemas["Place"]["properties"]["score"] == {
        "$ref": "#/components/schemas/PlaceScore",
        "nullable": True,
    }
    assert schemas["PlaceScore"]["properties"]["components"] == {
        "$ref": "#/components/schemas/PlaceScoreComponents"
    }
    assert schemas["PlaceScoreComponents"]["properties"]["local_spending_score"]["nullable"] is True
    assert schemas["WeatherData"]["properties"]["dust"] == {
        "$ref": "#/components/schemas/Dust"
    }
    assert schemas["DocentScriptData"]["properties"]["source"]["enum"] == [
        "skeleton",
        "db_cache",
        "azure_openai",
    ]
    assert "request_hash" in schemas["DocentScriptData"]["required"]
    assert schemas["DocentScriptData"]["properties"]["request_hash"]["pattern"] == (
        "^[0-9a-f]{64}$"
    )
    assert schemas["DailyPlanData"]["properties"]["weather"] == {
        "$ref": "#/components/schemas/WeatherData"
    }
    assert "cache_key" in schemas["DailyPlanData"]["required"]
    assert schemas["DailyPlanData"]["properties"]["cache_key"] == {"type": "string"}
    assert schemas["InterventionData"]["properties"]["recommended_action"] == {
        "type": "string"
    }


def test_openapi_documents_standard_response_headers(client):
    schema = client.get("/openapi.json").json()

    for response in (
        schema["paths"]["/healthz"]["get"]["responses"]["200"],
        schema["paths"]["/api/v1/places"]["get"]["responses"]["200"],
        schema["paths"]["/api/v1/places"]["get"]["responses"]["401"],
        schema["paths"]["/api/v1/places"]["get"]["responses"]["422"],
        schema["paths"]["/api/v1/docents/audio"]["post"]["responses"]["200"],
    ):
        headers = response["headers"]
        assert headers["X-Request-ID"]["schema"] == {"type": "string"}
        assert headers["X-Request-Duration-Ms"]["schema"] == {"type": "string"}


def test_openapi_documents_daily_plan_coordinate_bounds(client):
    schema = client.get("/openapi.json").json()
    daily_plan = schema["components"]["schemas"]["DailyPlanRequest"]["properties"]

    assert daily_plan["lat"]["minimum"] == -90
    assert daily_plan["lat"]["maximum"] == 90
    assert daily_plan["lng"]["minimum"] == -180
    assert daily_plan["lng"]["maximum"] == 180


def test_openapi_documents_docent_audio_mpeg_success(client):
    schema = client.get("/openapi.json").json()
    success_response = schema["paths"]["/api/v1/docents/audio"]["post"]["responses"]["200"]

    assert set(success_response["content"]) == {"audio/mpeg"}
    assert "audio/mpeg" in success_response["content"]
    assert success_response["content"]["audio/mpeg"]["schema"] == {
        "type": "string",
        "format": "binary",
    }
    assert success_response["headers"]["X-LALA-Request-Hash"]["schema"] == {
        "type": "string",
        "pattern": "^[0-9a-f]{64}$",
    }
    assert success_response["headers"]["X-LALA-Cache-Key"]["schema"] == {
        "type": "string"
    }
