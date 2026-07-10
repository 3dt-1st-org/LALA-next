from __future__ import annotations

from apps.api.app.core.config import Settings, get_settings
from apps.api.app.core.jwt_auth import is_oauth_jwt_validation_configured
from apps.api.app.services import db_repository, public_mvp_data
from apps.workers.app import contracts as worker_contracts


def _status(value: str, *, required: bool = False) -> str:
    if value:
        return "configured"
    return "missing" if required else "skipped"


def _configuration_status(*values: object) -> str:
    configured = tuple(bool(value) for value in values)
    if all(configured):
        return "configured"
    if any(configured):
        return "partial"
    return "skipped"


def _worker_contract_status() -> str:
    try:
        jobs = worker_contracts.list_worker_jobs()
    except Exception:
        return "degraded"
    return "configured" if jobs else "missing"


def _client_identity_status(settings: Settings) -> str:
    if settings.guest_access:
        return "guest"
    if settings.public_contest_access:
        return "public-contest"
    if settings.static_snapshot_fallback:
        return "snapshot-fallback"
    oauth_configured = is_oauth_jwt_validation_configured(settings)
    static_configured = bool(settings.ios_api_key or settings.api_bearer_token)
    if oauth_configured and static_configured:
        return "transition"
    if oauth_configured:
        return "oauth-configured"
    if static_configured:
        return "static"
    return "missing"


def _runtime_mode(checks: dict[str, str]) -> dict[str, str]:
    mode = {
        "data": _data_mode(
            db_status=checks.get("db", "skipped"),
            postgis_status=checks.get("postgis", "skipped"),
            snapshot_fallback_status=checks.get("static_snapshot_fallback", "disabled"),
            public_snapshot_status=checks.get("public_data_snapshot", "missing"),
        ),
        "ai": _live_dependency_mode(
            enabled=checks.get("live_ai") == "enabled",
            required_statuses=(
                checks.get("azure_openai_endpoint", "skipped"),
                checks.get("azure_openai_deployment", "skipped"),
                checks.get("azure_openai_key", "skipped"),
            ),
        ),
        "speech": _live_dependency_mode(
            enabled=checks.get("live_speech") == "enabled",
            required_statuses=(
                checks.get("azure_speech_key", "skipped"),
                _any_configured(
                    checks.get("azure_speech_region", "skipped"),
                    checks.get("azure_speech_endpoint", "skipped"),
                ),
            ),
        ),
        "worker": _worker_mode(checks.get("worker_contracts", "missing")),
    }
    return {
        "overall": _overall_runtime_mode(mode),
        **mode,
    }


def _data_mode(
    *,
    db_status: str,
    postgis_status: str,
    snapshot_fallback_status: str,
    public_snapshot_status: str,
) -> str:
    if db_status == "configured" and postgis_status == "configured":
        return "db-backed"
    if db_status == "degraded" or postgis_status == "degraded":
        return "degraded"
    if snapshot_fallback_status == "enabled" and public_snapshot_status == "configured":
        return "public-cache"
    return "unavailable"


def _live_dependency_mode(*, enabled: bool, required_statuses: tuple[str, ...]) -> str:
    if not enabled:
        return "disabled"
    if all(status == "configured" for status in required_statuses):
        return "live-azure"
    return "degraded"


def _any_configured(*statuses: str) -> str:
    return "configured" if any(status == "configured" for status in statuses) else "missing"


def _worker_mode(worker_status: str) -> str:
    if worker_status == "configured":
        return "dry-run"
    return "degraded"


def _overall_runtime_mode(mode: dict[str, str]) -> str:
    if any(value == "degraded" for value in mode.values()):
        return "degraded"
    if mode["data"] == "db-backed":
        return "db-backed"
    if mode["data"] == "public-cache":
        return "public-cache"
    if mode["ai"] == "live-azure" or mode["speech"] == "live-azure":
        return "live-azure"
    return "degraded"


def build_readiness(settings: Settings | None = None) -> dict:
    settings = settings or get_settings()
    jwt_validation_configured = is_oauth_jwt_validation_configured(settings)
    client_auth_status = "missing"
    if settings.guest_access:
        client_auth_status = "configured"
    elif settings.public_contest_access:
        client_auth_status = "public-contest"
    elif settings.static_snapshot_fallback:
        client_auth_status = "snapshot-fallback"
    elif settings.ios_api_key or settings.api_bearer_token or jwt_validation_configured:
        client_auth_status = "configured"

    db_status = db_repository.check_db_status(settings.db_dsn)
    postgis_status = (
        db_repository.check_postgis_status(settings.db_dsn)
        if db_status == "configured"
        else db_status
    )
    data_freshness_status = (
        db_repository.check_data_freshness_status(
            settings.db_dsn,
            weather_max_hours=settings.weather_freshness_max_hours,
        )
        if db_status == "configured"
        else db_status
    )
    checks = {
        "client_auth": client_auth_status,
        "client_identity": _client_identity_status(settings),
        "guest_access": "enabled" if settings.guest_access else "disabled",
        "public_contest_access": "enabled" if settings.public_contest_access else "disabled",
        "static_snapshot_fallback": "enabled" if settings.static_snapshot_fallback else "disabled",
        "public_data_snapshot": public_mvp_data.snapshot_status(),
        "public_data_service_key": _status(settings.public_data_service_key, required=False),
        "api_key": _status(settings.ios_api_key, required=False),
        "bearer_token": _status(settings.api_bearer_token, required=False),
        "jwt_validation": _configuration_status(
            settings.oauth_issuer,
            settings.oauth_audience,
            settings.oauth_jwks_url,
        ),
        "oauth_issuer": _status(settings.oauth_issuer, required=False),
        "oauth_audience": _status(settings.oauth_audience, required=False),
        "oauth_jwks_url": _status(settings.oauth_jwks_url, required=False),
        "oauth_client_id": _status(settings.oauth_client_id, required=False),
        "oauth_required_scopes": "configured" if settings.oauth_required_scopes else "skipped",
        "logto_management": _configuration_status(
            settings.logto_management_endpoint,
            settings.logto_management_client_id,
            settings.logto_management_client_secret,
        ),
        "db": db_status,
        "postgis": postgis_status,
        "data_freshness": data_freshness_status,
        "key_vault": _status(settings.key_vault_url, required=False),
        "azure_openai_endpoint": _status(settings.azure_openai_endpoint, required=False),
        "azure_openai_deployment": _status(settings.azure_openai_deployment, required=False),
        "azure_openai_key": _status(settings.azure_openai_key, required=False),
        "live_ai": "enabled" if settings.enable_live_ai else "disabled",
        "azure_speech_region": _status(settings.azure_speech_region, required=False),
        "azure_speech_endpoint": _status(settings.azure_speech_endpoint, required=False),
        "azure_speech_key": _status(settings.azure_speech_key, required=False),
        "live_speech": "enabled" if settings.enable_live_speech else "disabled",
        "worker_contracts": _worker_contract_status(),
    }
    mode = _runtime_mode(checks)
    return {
        "status": _overall_readiness_status(checks=checks, mode=mode),
        "checks": checks,
        "mode": mode,
    }


def _overall_readiness_status(*, checks: dict[str, str], mode: dict[str, str]) -> str:
    if checks["client_auth"] == "missing":
        return "degraded"
    if mode["overall"] == "degraded":
        return "degraded"
    if mode["data"] == "unavailable":
        return "degraded"
    return "ok"
