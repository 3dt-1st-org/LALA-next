from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi

from apps.api.app.core.config import Settings

V1_PATH_PREFIX = "/api/v1/"
DOCENT_AUDIO_PATH = "/api/v1/docents/audio"
HEALTHZ_PATH = "/healthz"
METRICS_PATH = "/metrics"
READYZ_PATH = "/readyz"
PLACES_PATH = "/api/v1/places"
WEATHER_PATH = "/api/v1/weather"
DOCENT_SCRIPT_PATH = "/api/v1/docents/script"
DAILY_PLAN_PATH = "/api/v1/plans/daily"
INTERVENTION_PATH = "/api/v1/plans/intervention"
ME_PATH = "/api/v1/me"

OPERATION_TIMEOUT_SECONDS = {
    HEALTHZ_PATH: 3,
    METRICS_PATH: 3,
    READYZ_PATH: 3,
    PLACES_PATH: 12,
    WEATHER_PATH: 12,
    DOCENT_SCRIPT_PATH: 30,
    DOCENT_AUDIO_PATH: 30,
    DAILY_PLAN_PATH: 20,
    INTERVENTION_PATH: 12,
    ME_PATH: 12,
}


def configure_openapi(app: FastAPI, settings: Settings) -> None:
    def custom_openapi() -> dict[str, Any]:
        if app.openapi_schema:
            return app.openapi_schema

        schema = get_openapi(
            title=app.title,
            version=settings.app_version,
            description=app.description,
            routes=app.routes,
        )
        _add_client_auth_security(schema)
        _fix_docent_audio_success_content(schema)
        _add_success_envelope_responses(schema)
        _add_operation_contract_extensions(schema)
        _add_standard_response_headers(schema)
        app.openapi_schema = schema
        return app.openapi_schema

    app.openapi = custom_openapi  # type: ignore[method-assign]


def _add_client_auth_security(schema: dict[str, Any]) -> None:
    components = schema.setdefault("components", {})
    security_schemes = components.setdefault("securitySchemes", {})
    schemas = components.setdefault("schemas", {})
    schemas.setdefault("ApiMeta", _api_meta_schema())
    schemas.setdefault("ApiError", _api_error_schema())
    schemas.setdefault("ApiSuccessEnvelope", _api_success_envelope_schema())
    schemas.setdefault("ApiErrorEnvelope", _api_error_envelope_schema())
    schemas.setdefault("HealthzData", _healthz_data_schema())
    schemas.setdefault("HealthzSuccessEnvelope", _success_envelope_schema("HealthzData"))
    schemas.setdefault("ReadinessChecks", _readiness_checks_schema())
    schemas.setdefault("RuntimeMode", _runtime_mode_schema())
    schemas.setdefault("ReadyzData", _readyz_data_schema())
    schemas.setdefault("ReadyzSuccessEnvelope", _success_envelope_schema("ReadyzData"))
    schemas.setdefault("Coordinate", _coordinate_schema())
    schemas.setdefault("PlaceScoreComponents", _place_score_components_schema())
    schemas.setdefault("PlaceScore", _place_score_schema())
    schemas.setdefault("Place", _place_schema())
    schemas.setdefault("PlacesQuery", _places_query_schema())
    schemas.setdefault("PlacesData", _places_data_schema())
    schemas.setdefault("PlacesSuccessEnvelope", _success_envelope_schema("PlacesData"))
    schemas.setdefault("Dust", _dust_schema())
    schemas.setdefault("ForecastItem", _forecast_item_schema())
    schemas.setdefault("WeatherData", _weather_data_schema())
    schemas.setdefault("WeatherSuccessEnvelope", _success_envelope_schema("WeatherData"))
    schemas.setdefault("DocentScriptData", _docent_script_data_schema())
    schemas.setdefault(
        "DocentScriptSuccessEnvelope",
        _success_envelope_schema("DocentScriptData"),
    )
    schemas.setdefault("DailyPlanSlot", _daily_plan_slot_schema())
    schemas.setdefault("DailyPlanData", _daily_plan_data_schema())
    schemas.setdefault("DailyPlanSuccessEnvelope", _success_envelope_schema("DailyPlanData"))
    schemas.setdefault("InterventionData", _intervention_data_schema())
    schemas.setdefault(
        "InterventionSuccessEnvelope",
        _success_envelope_schema("InterventionData"),
    )
    schemas.setdefault("MeData", _me_data_schema())
    schemas.setdefault("MeSuccessEnvelope", _success_envelope_schema("MeData"))

    security_schemes["BearerAuth"] = {
        "type": "http",
        "scheme": "bearer",
        "description": "Optional credential for guest-accessible tourism routes. Presented static or OAuth bearer credentials are always validated.",
    }
    security_schemes["OAuthBearerAuth"] = {
        "type": "http",
        "scheme": "bearer",
        "description": "Logto OAuth API access token required for account operations. Static bearer tokens are not accepted.",
    }
    security_schemes["MigrationApiKey"] = {
        "type": "apiKey",
        "in": "header",
        "name": "X-API-Key",
        "description": "Migration client key from IOS_API_KEY.",
    }

    for path, path_item in (schema.get("paths") or {}).items():
        if not path.startswith(V1_PATH_PREFIX) or not isinstance(path_item, Mapping):
            continue
        for method, operation in path_item.items():
            if isinstance(operation, dict):
                if path == ME_PATH:
                    operation["security"] = [{"OAuthBearerAuth": []}]
                    _remove_generated_auth_parameters(operation)
                else:
                    operation["security"] = [
                        {},
                        {"BearerAuth": []},
                        {"MigrationApiKey": []},
                    ]
                _add_error_envelope_responses(operation)
                if path == ME_PATH:
                    _add_account_error_responses(
                        operation,
                        include_conflict=method.lower() == "get",
                    )


def _remove_generated_auth_parameters(operation: dict[str, Any]) -> None:
    parameters = operation.get("parameters")
    if not isinstance(parameters, list):
        return
    operation["parameters"] = [
        parameter
        for parameter in parameters
        if not (
            isinstance(parameter, dict)
            and parameter.get("in") == "header"
            and parameter.get("name") in {"Authorization", "X-API-Key"}
        )
    ]


def _add_error_envelope_responses(operation: dict[str, Any]) -> None:
    responses = operation.setdefault("responses", {})
    responses.setdefault(
        "401",
        {
            "description": "Client authentication required or invalid.",
            "content": {
                "application/json": {"schema": {"$ref": "#/components/schemas/ApiErrorEnvelope"}}
            },
        },
    )
    responses["422"] = {
        "description": "Request validation failed.",
        "content": {
            "application/json": {"schema": {"$ref": "#/components/schemas/ApiErrorEnvelope"}}
        },
    }


def _add_account_error_responses(
    operation: dict[str, Any],
    *,
    include_conflict: bool,
) -> None:
    responses = operation.setdefault("responses", {})
    unavailable_description = (
        "Identity storage is unavailable."
        if include_conflict
        else "Identity storage or account deletion service is unavailable."
    )
    errors = [("503", unavailable_description)]
    if include_conflict:
        errors.append(("409", "Account deletion is already in progress."))
        errors.append(("410", "The Logto identity was previously deleted."))
    for status_code, description in errors:
        responses.setdefault(
            status_code,
            {
                "description": description,
                "content": {
                    "application/json": {
                        "schema": {"$ref": "#/components/schemas/ApiErrorEnvelope"}
                    }
                },
            },
        )


def _fix_docent_audio_success_content(schema: dict[str, Any]) -> None:
    audio_operation = (schema.get("paths") or {}).get(DOCENT_AUDIO_PATH, {}).get("post")
    if not isinstance(audio_operation, dict):
        return
    success_response = (audio_operation.get("responses") or {}).get("200")
    if not isinstance(success_response, dict):
        return
    content = success_response.setdefault("content", {})
    if "audio/mpeg" in content:
        success_response["content"] = {"audio/mpeg": content["audio/mpeg"]}
    _ensure_generation_identity_headers(success_response)


def _add_success_envelope_responses(schema: dict[str, Any]) -> None:
    for path, path_item in (schema.get("paths") or {}).items():
        if path == DOCENT_AUDIO_PATH or not isinstance(path_item, Mapping):
            continue
        for operation in path_item.values():
            if not isinstance(operation, dict):
                continue
            success_response = (operation.get("responses") or {}).get("200")
            if not isinstance(success_response, dict):
                continue
            content = success_response.get("content") or {}
            json_content = content.get("application/json") if isinstance(content, dict) else None
            if isinstance(json_content, dict):
                json_content["schema"] = _success_response_ref(path)


def _add_operation_contract_extensions(schema: dict[str, Any]) -> None:
    for path, path_item in (schema.get("paths") or {}).items():
        timeout_seconds = OPERATION_TIMEOUT_SECONDS.get(path)
        if timeout_seconds is None or not isinstance(path_item, Mapping):
            continue
        for operation in path_item.values():
            if not isinstance(operation, dict):
                continue
            operation["x-lala-timeout-seconds"] = timeout_seconds
            operation["x-lala-auth-required"] = path == ME_PATH


def _add_standard_response_headers(schema: dict[str, Any]) -> None:
    for path_item in (schema.get("paths") or {}).values():
        if not isinstance(path_item, Mapping):
            continue
        for operation in path_item.values():
            if not isinstance(operation, dict):
                continue
            for response in (operation.get("responses") or {}).values():
                if isinstance(response, dict):
                    _ensure_standard_headers(response)


def _ensure_standard_headers(response: dict[str, Any]) -> None:
    headers = response.setdefault("headers", {})
    headers.setdefault(
        "X-Request-ID",
        {
            "description": "Safe request correlation id generated or accepted by the API.",
            "schema": {"type": "string"},
        },
    )
    headers.setdefault(
        "X-Request-Duration-Ms",
        {
            "description": "Server-side request duration in milliseconds.",
            "schema": {"type": "string"},
        },
    )


def _ensure_generation_identity_headers(response: dict[str, Any]) -> None:
    headers = response.setdefault("headers", {})
    headers.setdefault(
        "X-LALA-Request-Hash",
        {
            "description": "Deterministic SHA-256 hash of the normalized generation request.",
            "schema": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
        },
    )
    headers.setdefault(
        "X-LALA-Cache-Key",
        {
            "description": "Opaque client-safe generation cache key derived from the request hash.",
            "schema": {"type": "string"},
        },
    )


def _api_meta_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": ["request_id"],
        "properties": {
            "request_id": {"type": "string"},
        },
        "additionalProperties": True,
    }


def _api_error_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": ["code", "message", "retryable"],
        "properties": {
            "code": {"type": "string"},
            "message": {"type": "string"},
            "retryable": {"type": "boolean"},
            "details": {},
        },
        "additionalProperties": True,
    }


def _api_success_envelope_schema() -> dict[str, Any]:
    return _success_envelope_schema()


def _success_envelope_schema(data_schema_name: str | None = None) -> dict[str, Any]:
    # data: 구체 타입(있으면) 또는 nullable 객체(제네릭 fallback). 빈 스키마({})는
    # openapi-generator 가 dynamic 으로 취급해 빌드가 깨지므로 구체 타입을 부여한다.
    if data_schema_name:
        data_schema: dict[str, Any] = {"$ref": f"#/components/schemas/{data_schema_name}"}
    else:
        data_schema = {"type": "object", "nullable": True}
    return {
        "type": "object",
        # error 는 성공 응답에서 항상 null 이므로 required 에서 제외 → optional/nullable 로
        # 역직렬화(dart-dio 가 required+nullable 을 non-nullable 로 만드는 것을 회피).
        "required": ["ok", "data", "meta"],
        "properties": {
            "ok": {"type": "boolean", "const": True},
            "data": data_schema,
            "meta": {"$ref": "#/components/schemas/ApiMeta"},
            # error: 성공 응답에서는 항상 null. type:"null" 은 dart-dio 가 ModelNull 을 참조해 빠지고,
            # nullable ApiError 는 직렬화 시 null 을 ApiError 로 빌드하려다 code(non-null) 누락으로 실패.
            # 따라서 generic nullable 객체(JsonObject?)로 둬 null 이 깔끔히 역직렬화되게 한다.
            "error": {"type": "object", "nullable": True},
        },
        "additionalProperties": False,
    }


def _api_error_envelope_schema() -> dict[str, Any]:
    return {
        "type": "object",
        # data 는 에러 응답에서 항상 null 이므로 required 에서 제외 → optional/nullable.
        "required": ["ok", "meta", "error"],
        "properties": {
            "ok": {"type": "boolean", "const": False},
            "data": {"type": "object", "nullable": True},
            "meta": {"$ref": "#/components/schemas/ApiMeta"},
            "error": {"$ref": "#/components/schemas/ApiError"},
        },
        "additionalProperties": False,
    }


def _success_response_ref(path: str) -> dict[str, Any]:
    if path == HEALTHZ_PATH:
        return {"$ref": "#/components/schemas/HealthzSuccessEnvelope"}
    if path == READYZ_PATH:
        return {"$ref": "#/components/schemas/ReadyzSuccessEnvelope"}
    if path == PLACES_PATH:
        return {"$ref": "#/components/schemas/PlacesSuccessEnvelope"}
    if path == WEATHER_PATH:
        return {"$ref": "#/components/schemas/WeatherSuccessEnvelope"}
    if path == DOCENT_SCRIPT_PATH:
        return {"$ref": "#/components/schemas/DocentScriptSuccessEnvelope"}
    if path == DAILY_PLAN_PATH:
        return {"$ref": "#/components/schemas/DailyPlanSuccessEnvelope"}
    if path == INTERVENTION_PATH:
        return {"$ref": "#/components/schemas/InterventionSuccessEnvelope"}
    if path == ME_PATH:
        return {"$ref": "#/components/schemas/MeSuccessEnvelope"}
    return {"$ref": "#/components/schemas/ApiSuccessEnvelope"}


def _healthz_data_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": ["status", "service", "version"],
        "properties": {
            "status": {"type": "string", "enum": ["ok"]},
            "service": {"type": "string", "enum": ["lala-next-api"]},
            "version": {"type": "string"},
        },
        "additionalProperties": False,
    }


def _readyz_data_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": ["status", "checks", "mode"],
        "properties": {
            "status": {"type": "string", "enum": ["ok", "degraded"]},
            "checks": {"$ref": "#/components/schemas/ReadinessChecks"},
            "mode": {"$ref": "#/components/schemas/RuntimeMode"},
        },
        "additionalProperties": False,
    }


def _readiness_checks_schema() -> dict[str, Any]:
    configured_or_skipped = {"type": "string", "enum": ["configured", "skipped"]}
    configured_or_missing = {"type": "string", "enum": ["configured", "missing"]}
    configured_skipped_degraded = {
        "type": "string",
        "enum": ["configured", "skipped", "degraded"],
    }
    enabled_or_disabled = {"type": "string", "enum": ["enabled", "disabled"]}
    return {
        "type": "object",
        "required": [
            "client_auth",
            "client_identity",
            "guest_access",
            "public_contest_access",
            "static_snapshot_fallback",
            "public_data_snapshot",
            "public_data_service_key",
            "api_key",
            "bearer_token",
            "jwt_validation",
            "oauth_issuer",
            "oauth_audience",
            "oauth_jwks_url",
            "oauth_client_id",
            "oauth_required_scopes",
            "logto_management",
            "db",
            "identity_schema",
            "postgis",
            "key_vault",
            "azure_openai_endpoint",
            "azure_openai_deployment",
            "azure_openai_key",
            "live_ai",
            "azure_speech_region",
            "azure_speech_endpoint",
            "azure_speech_key",
            "live_speech",
            "worker_contracts",
        ],
        "properties": {
            "client_auth": {
                "type": "string",
                "enum": [
                    "configured",
                    "missing",
                    "snapshot-fallback",
                    "public-contest",
                ],
            },
            "client_identity": {
                "type": "string",
                "enum": [
                    "guest",
                    "static",
                    "transition",
                    "oauth-configured",
                    "snapshot-fallback",
                    "public-contest",
                    "missing",
                ],
            },
            "guest_access": enabled_or_disabled,
            "public_contest_access": enabled_or_disabled,
            "static_snapshot_fallback": enabled_or_disabled,
            "public_data_snapshot": configured_or_missing,
            "public_data_service_key": configured_or_skipped,
            "api_key": configured_or_skipped,
            "bearer_token": configured_or_skipped,
            "jwt_validation": {
                "type": "string",
                "enum": ["configured", "partial", "skipped"],
            },
            "oauth_issuer": configured_or_skipped,
            "oauth_audience": configured_or_skipped,
            "oauth_jwks_url": configured_or_skipped,
            "oauth_client_id": configured_or_skipped,
            "oauth_required_scopes": configured_or_skipped,
            "logto_management": {
                "type": "string",
                "enum": ["configured", "partial", "skipped"],
            },
            "db": configured_skipped_degraded,
            "identity_schema": configured_skipped_degraded,
            "postgis": configured_skipped_degraded,
            "key_vault": configured_or_skipped,
            "azure_openai_endpoint": configured_or_skipped,
            "azure_openai_deployment": configured_or_skipped,
            "azure_openai_key": configured_or_skipped,
            "live_ai": enabled_or_disabled,
            "azure_speech_region": configured_or_skipped,
            "azure_speech_endpoint": configured_or_skipped,
            "azure_speech_key": configured_or_skipped,
            "live_speech": enabled_or_disabled,
            "worker_contracts": {
                "type": "string",
                "enum": ["configured", "missing", "degraded"],
            },
        },
        "additionalProperties": True,
    }


def _runtime_mode_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": ["overall", "data", "ai", "speech", "worker"],
        "properties": {
            "overall": {
                "type": "string",
                "enum": ["public-cache", "db-backed", "live-azure", "degraded"],
            },
            "data": {
                "type": "string",
                "enum": ["unavailable", "public-cache", "db-backed", "degraded"],
            },
            "ai": {"type": "string", "enum": ["disabled", "live-azure", "degraded"]},
            "speech": {
                "type": "string",
                "enum": ["disabled", "live-azure", "degraded"],
            },
            "worker": {"type": "string", "enum": ["dry-run", "degraded"]},
        },
        "additionalProperties": False,
    }


def _me_data_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": ["user_id", "created_at", "authenticated"],
        "properties": {
            "user_id": {"type": "string", "format": "uuid"},
            "created_at": {"type": "string", "format": "date-time"},
            "authenticated": {"type": "boolean", "const": True},
        },
        "additionalProperties": False,
    }


def _coordinate_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": ["lat", "lng"],
        "properties": {
            "lat": {"type": "number", "format": "double"},
            "lng": {"type": "number", "format": "double"},
        },
        "additionalProperties": False,
    }


def _place_score_components_schema() -> dict[str, Any]:
    nullable_score = {
        "type": "number",
        "format": "double",
        "minimum": 0,
        "maximum": 1,
        "nullable": True,
    }
    return {
        "type": "object",
        "required": [
            "local_spending_score",
            "small_merchant_fit_score",
            "demand_dispersion_score",
            "culture_relevance_score",
            "weather_fit_score",
            "review_quality_score",
            "accessibility_fit_score",
        ],
        "properties": {
            "local_spending_score": nullable_score,
            "small_merchant_fit_score": nullable_score,
            "demand_dispersion_score": nullable_score,
            "culture_relevance_score": nullable_score,
            "weather_fit_score": nullable_score,
            "review_quality_score": nullable_score,
            "accessibility_fit_score": nullable_score,
        },
        "additionalProperties": False,
    }


def _place_score_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": [
            "final_score",
            "formula_version",
            "components",
            "data_basis",
            "features",
        ],
        "properties": {
            "final_score": {
                "type": "number",
                "format": "double",
                "minimum": 0,
                "maximum": 1,
            },
            "formula_version": {"type": "string"},
            "components": {"$ref": "#/components/schemas/PlaceScoreComponents"},
            "data_basis": {
                "type": "string",
                "enum": [
                    "analytics.place_score_snapshots",
                    "public_mvp_snapshot",
                ],
            },
            "features": {"type": "object"},
        },
        "additionalProperties": False,
    }


def _place_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": [
            "place_id",
            "name",
            "category",
            "lat",
            "lng",
            "address",
            "distance_m",
            "source",
        ],
        "properties": {
            "place_id": {"type": "string"},
            "name": {"type": "string"},
            "name_ko": {"type": "string", "nullable": True},
            "name_en": {"type": "string", "nullable": True},
            "category": {
                "type": "string",
                "enum": ["attraction", "restaurant", "event", "culture_venue"],
            },
            "lat": {"type": "number", "format": "double"},
            "lng": {"type": "number", "format": "double"},
            "address": {"type": "string"},
            "image_url": {"type": "string", "format": "uri", "nullable": True},
            "region_ko": {"type": "string", "nullable": True},
            "region_en": {"type": "string", "nullable": True},
            "event_start_date": {"type": "string", "format": "date", "nullable": True},
            "event_end_date": {"type": "string", "format": "date", "nullable": True},
            "event_url": {"type": "string", "format": "uri", "nullable": True},
            "is_ongoing": {"type": "boolean", "nullable": True},
            "is_approximate_location": {"type": "boolean", "nullable": True},
            "distance_m": {"type": "integer"},
            "source": {"type": "string", "enum": ["public_mvp_snapshot", "db"]},
            "upstream_source": {"type": "string", "nullable": True},
            "score": {"$ref": "#/components/schemas/PlaceScore", "nullable": True},
        },
        "additionalProperties": True,
    }


def _places_query_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": [
            "lat",
            "lng",
            "radius_m",
            "category",
            "language",
            "include_scores",
            "limit",
        ],
        "properties": {
            "lat": {"type": "number", "format": "double"},
            "lng": {"type": "number", "format": "double"},
            "radius_m": {"type": "integer"},
            "category": {
                "type": "string",
                "enum": ["all", "attraction", "restaurant", "event", "culture_venue"],
            },
            "language": {"type": "string", "enum": ["ko", "en"]},
            "include_scores": {"type": "boolean"},
            "limit": {"type": "integer", "minimum": 1, "maximum": 100},
        },
        "additionalProperties": False,
    }


def _places_data_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": ["count", "places", "query", "source", "location_engine"],
        "properties": {
            "count": {"type": "integer"},
            "places": {
                "type": "array",
                "items": {"$ref": "#/components/schemas/Place"},
            },
            "query": {"$ref": "#/components/schemas/PlacesQuery"},
            "source": {"type": "string", "enum": ["public_mvp_snapshot", "db"]},
            "location_engine": {
                "type": "string",
                "enum": ["postgis", "static_snapshot", "none"],
            },
        },
        "additionalProperties": False,
    }


def _dust_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": [
            "pm10",
            "pm25",
            "grade",
            "grade_ko",
            "pm10_grade",
            "pm10_grade_ko",
            "pm25_grade",
            "pm25_grade_ko",
        ],
        "properties": {
            "pm10": {"type": "string"},
            "pm25": {"type": "string"},
            "grade": {"type": "string"},
            "grade_ko": {"type": "string"},
            "pm10_grade": {"type": "string"},
            "pm10_grade_ko": {"type": "string"},
            "pm25_grade": {"type": "string"},
            "pm25_grade_ko": {"type": "string"},
        },
        "additionalProperties": False,
    }


def _forecast_item_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": ["time", "temp", "icon"],
        "properties": {
            "time": {"type": "string"},
            "temp": {"type": "string"},
            "icon": {"type": "string"},
        },
        "additionalProperties": False,
    }


def _weather_data_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": [
            "lat",
            "lng",
            "temp",
            "icon",
            "dust",
            "forecast",
            "outdoor_status",
            "force",
            "source",
        ],
        "properties": {
            "lat": {"type": "number", "format": "double"},
            "lng": {"type": "number", "format": "double"},
            "location": {"type": "string", "nullable": True},
            "temp": {"type": "string"},
            "icon": {"type": "string"},
            "dust": {"$ref": "#/components/schemas/Dust"},
            "forecast": {
                "type": "array",
                "items": {"$ref": "#/components/schemas/ForecastItem"},
            },
            "outdoor_status": {"type": "string", "enum": ["good", "bad", "unknown"]},
            "force": {"type": "boolean"},
            "location_match": {"type": "boolean", "nullable": True},
            "record_time": {"type": "string", "nullable": True},
            "source": {
                "type": "string",
                "enum": [
                    "db",
                    "db+airkorea_sido_realtime",
                    "kma_ultra_srt_ncst",
                    "airkorea_sido_realtime",
                    "kma_ultra_srt_ncst+airkorea_sido_realtime",
                    "unavailable",
                ],
            },
        },
        "additionalProperties": True,
    }


def _docent_script_data_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": [
            "place_id",
            "category",
            "language",
            "mode",
            "script",
            "source",
            "request_hash",
            "cache_key",
        ],
        "properties": {
            "place_id": {"type": "string"},
            "category": {
                "type": "string",
                "enum": ["attraction", "restaurant", "event", "culture_venue"],
            },
            "language": {"type": "string", "enum": ["ko", "en"]},
            "mode": {"type": "string", "enum": ["brief", "detail"]},
            "script": {"type": "string"},
            "source": {
                "type": "string",
                "enum": ["rule_based_curation", "db_cache", "azure_openai"],
            },
            "generated_at": {"type": "string", "nullable": True},
            "ttl_sec": {"type": "integer", "nullable": True},
            "grounding_count": {"type": "integer"},
            "grounding_sources": {"type": "array", "items": {"type": "string"}},
            "request_hash": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
            "cache_key": {"type": "string"},
        },
        "additionalProperties": False,
    }


def _daily_plan_slot_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": ["period", "title"],
        "properties": {
            "period": {"type": "string"},
            "title": {"type": "string"},
            "place": {"$ref": "#/components/schemas/Place"},
            "weather_hint": {"type": "string", "nullable": True},
        },
        "additionalProperties": False,
    }


def _daily_plan_data_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": [
            "language",
            "center",
            "radius_m",
            "weather",
            "slots",
            "source",
            "request_hash",
            "cache_key",
        ],
        "properties": {
            "language": {"type": "string", "enum": ["ko", "en"]},
            "center": {"$ref": "#/components/schemas/Coordinate"},
            "radius_m": {"type": "integer"},
            "weather": {"$ref": "#/components/schemas/WeatherData"},
            "slots": {
                "type": "array",
                "items": {"$ref": "#/components/schemas/DailyPlanSlot"},
            },
            "source": {
                "type": "string",
                "enum": ["unavailable", "public_mvp_snapshot", "db", "mixed"],
            },
            "request_hash": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
            "cache_key": {"type": "string"},
        },
        "additionalProperties": False,
    }


def _intervention_data_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": [
            "center",
            "radius_m",
            "should_intervene",
            "reason",
            "recommended_action",
            "source",
        ],
        "properties": {
            "center": {"$ref": "#/components/schemas/Coordinate"},
            "radius_m": {"type": "integer"},
            "should_intervene": {"type": "boolean"},
            "reason": {"type": "string"},
            "recommended_action": {"type": "string"},
            "place": {"$ref": "#/components/schemas/Place", "nullable": True},
            "source": {
                "type": "string",
                "enum": ["unavailable", "public_mvp_snapshot", "db", "mixed"],
            },
        },
        "additionalProperties": False,
    }
