from __future__ import annotations

import os
from dataclasses import dataclass

from dotenv import load_dotenv

from apps.api.app.core.key_vault import get_secret_if_configured

load_dotenv()


@dataclass(frozen=True)
class Settings:
    app_name: str = "LALA-next Public API"
    app_version: str = "0.1.0"
    ios_api_key: str = ""
    db_dsn: str = ""
    key_vault_url: str = ""
    azure_openai_endpoint: str = ""
    azure_openai_deployment: str = ""
    azure_openai_api_version: str = ""
    azure_openai_key: str = ""
    azure_speech_region: str = ""
    azure_speech_key: str = ""
    log_level: str = "INFO"

    @classmethod
    def from_env(cls) -> "Settings":
        key_vault_url = (os.getenv("KEY_VAULT_URL") or "").strip()
        return cls(
            ios_api_key=_env_or_secret("IOS_API_KEY", "ios-api-key", key_vault_url),
            db_dsn=_env_or_secret("DB_DSN", "db-dsn", key_vault_url),
            key_vault_url=key_vault_url,
            azure_openai_endpoint=_env_or_secret(
                "AZURE_OPENAI_ENDPOINT",
                "azure-openai-endpoint",
                key_vault_url,
            ),
            azure_openai_deployment=_env_or_secret(
                "AZURE_OPENAI_DEPLOYMENT",
                "azure-openai-deployment",
                key_vault_url,
            ),
            azure_openai_api_version=_env_or_secret(
                "AZURE_OPENAI_API_VERSION",
                "azure-openai-api-version",
                key_vault_url,
            ),
            azure_openai_key=_env_or_secret("AZURE_OPENAI_KEY", "azure-openai-key", key_vault_url),
            azure_speech_region=_env_or_secret("AZURE_SPEECH_REGION", "azure-speech-region", key_vault_url),
            azure_speech_key=_env_or_secret("AZURE_SPEECH_KEY", "azure-speech-key", key_vault_url),
            log_level=(os.getenv("LOG_LEVEL") or "INFO").strip(),
        )


def get_settings() -> Settings:
    return Settings.from_env()


def _env_or_secret(env_name: str, secret_name: str, key_vault_url: str) -> str:
    value = (os.getenv(env_name) or "").strip()
    if value:
        return value
    return get_secret_if_configured(key_vault_url, secret_name)
