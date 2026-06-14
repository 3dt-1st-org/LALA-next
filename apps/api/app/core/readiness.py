from __future__ import annotations

from apps.api.app.core.config import Settings, get_settings
from apps.api.app.core.jwt_auth import is_oauth_jwt_validation_configured
from apps.api.app.services import db_repository
from apps.workers.app import contracts as worker_contracts


def _status(value: str, *, required: bool = False) -> str:
    if value:
        return "configured"
    return "missing" if required else "skipped"


def _worker_contract_status() -> str:
    try:
        jobs = worker_contracts.list_worker_jobs()
    except Exception:
        return "degraded"
    return "configured" if jobs else "missing"


def _client_identity_status(settings: Settings) -> str:
    if settings.public_demo_mode:
        return "public-demo"
    oauth_configured = all(
        (
            settings.oauth_issuer,
            settings.oauth_audience,
            settings.oauth_jwks_url,
            settings.oauth_client_id,
            settings.oauth_required_scopes,
        )
    )
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
        "data": _data_mode(checks.get("db", "skipped")),
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


def _data_mode(db_status: str) -> str:
    if db_status == "configured":
        return "db-backed"
    if db_status == "degraded":
        return "degraded"
    return "skeleton"


def _live_dependency_mode(*, enabled: bool, required_statuses: tuple[str, ...]) -> str:
    if not enabled:
        return "skeleton"
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
    if mode["ai"] == "live-azure" or mode["speech"] == "live-azure":
        return "live-azure"
    if mode["data"] == "db-backed":
        return "db-backed"
    return "skeleton"


def build_readiness(settings: Settings | None = None) -> dict:
    settings = settings or get_settings()
    jwt_validation_configured = is_oauth_jwt_validation_configured(settings)
    client_auth_status = "missing"
    if settings.public_demo_mode:
        client_auth_status = "public-demo"
    elif settings.ios_api_key or settings.api_bearer_token or jwt_validation_configured:
        client_auth_status = "configured"

    checks = {
        "client_auth": client_auth_status,
        "client_identity": _client_identity_status(settings),
        "public_demo_mode": "enabled" if settings.public_demo_mode else "disabled",
        "api_key": _status(settings.ios_api_key, required=False),
        "bearer_token": _status(settings.api_bearer_token, required=False),
        "jwt_validation": "configured" if jwt_validation_configured else "skipped",
        "oauth_issuer": _status(settings.oauth_issuer, required=False),
        "oauth_audience": _status(settings.oauth_audience, required=False),
        "oauth_jwks_url": _status(settings.oauth_jwks_url, required=False),
        "oauth_client_id": _status(settings.oauth_client_id, required=False),
        "oauth_required_scopes": "configured" if settings.oauth_required_scopes else "skipped",
        "db": db_repository.check_db_status(settings.db_dsn),
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
    if checks["client_auth"] == "missing":
        overall = "degraded"
    elif any(value == "degraded" for value in checks.values()):
        overall = "degraded"
    elif any(value == "missing" for value in checks.values()):
        overall = "degraded"
    elif any(value == "skipped" for value in checks.values()):
        overall = "degraded"
    else:
        overall = "ok"
    return {
        "status": overall,
        "checks": checks,
        "mode": _runtime_mode(checks),
    }
