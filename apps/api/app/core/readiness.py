from __future__ import annotations

from apps.api.app.core.config import Settings, get_settings
from apps.api.app.services import db_repository


def _status(value: str, *, required: bool = False) -> str:
    if value:
        return "configured"
    return "missing" if required else "skipped"


def build_readiness(settings: Settings | None = None) -> dict:
    settings = settings or get_settings()
    checks = {
        "api_key": _status(settings.ios_api_key, required=True),
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
    }
    if checks["api_key"] == "missing":
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
    }
