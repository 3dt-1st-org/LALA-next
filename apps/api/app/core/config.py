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
    api_bearer_token: str = ""
    oauth_issuer: str = ""
    oauth_audience: str = ""
    oauth_jwks_url: str = ""
    oauth_client_id: str = ""
    oauth_required_scopes: tuple[str, ...] = ()
    kakao_rest_api_key: str = ""
    kakao_javascript_key: str = ""
    kakao_redirect_uri: str = ""
    naver_client_id: str = ""
    naver_client_secret: str = ""
    kopis_api_key: str = ""
    public_data_service_key: str = ""
    gyeonggi_data_dream_api_key: str = ""
    public_demo_mode: bool = False
    db_dsn: str = ""
    key_vault_url: str = ""
    azure_openai_endpoint: str = ""
    azure_openai_deployment: str = ""
    azure_openai_api_version: str = ""
    azure_openai_key: str = ""
    enable_live_ai: bool = False
    azure_speech_region: str = ""
    azure_speech_endpoint: str = ""
    azure_speech_key: str = ""
    enable_live_speech: bool = False
    cors_allow_origins: tuple[str, ...] = ()
    log_level: str = "INFO"
    access_log_path: str = ""

    @classmethod
    def from_env(cls) -> "Settings":
        key_vault_url = (os.getenv("KEY_VAULT_URL") or "").strip()
        return cls(
            ios_api_key=_env_or_secret("IOS_API_KEY", "ios-api-key", key_vault_url),
            api_bearer_token=_env_or_secret("API_BEARER_TOKEN", "api-bearer-token", key_vault_url),
            oauth_issuer=_env_or_secret("OAUTH_ISSUER", "oauth-issuer", key_vault_url),
            oauth_audience=_env_or_secret("OAUTH_AUDIENCE", "oauth-audience", key_vault_url),
            oauth_jwks_url=_env_or_secret("OAUTH_JWKS_URL", "oauth-jwks-url", key_vault_url),
            oauth_client_id=_env_or_secret("OAUTH_CLIENT_ID", "oauth-client-id", key_vault_url),
            oauth_required_scopes=_csv_value(
                _env_or_secret("OAUTH_REQUIRED_SCOPES", "oauth-required-scopes", key_vault_url)
            ),
            kakao_rest_api_key=_env_or_secret("KAKAO_REST_API_KEY", "kakao-rest-api-key", key_vault_url),
            kakao_javascript_key=_env_or_secret(
                "KAKAO_JAVASCRIPT_KEY",
                "kakao-javascript-key",
                key_vault_url,
            ),
            kakao_redirect_uri=_env_or_secret("KAKAO_REDIRECT_URI", "kakao-redirect-uri", key_vault_url),
            naver_client_id=_env_or_secret("NAVER_CLIENT_ID", "naver-client-id", key_vault_url),
            naver_client_secret=_env_or_secret("NAVER_CLIENT_SECRET", "naver-client-secret", key_vault_url),
            kopis_api_key=_env_or_secret("KOPIS_API_KEY", "kopis-api-key", key_vault_url),
            public_data_service_key=_env_or_secret(
                "PUBLIC_DATA_SERVICE_KEY",
                "public-data-service-key",
                key_vault_url,
            ),
            gyeonggi_data_dream_api_key=_env_or_secret(
                "GYEONGGI_DATA_DREAM_API_KEY",
                "gyeonggi-data-dream-api-key",
                key_vault_url,
            ),
            public_demo_mode=_bool_env("LALA_PUBLIC_DEMO_MODE", default=False),
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
            enable_live_ai=_bool_env("LALA_ENABLE_LIVE_AI", default=False),
            azure_speech_region=_env_or_secret("AZURE_SPEECH_REGION", "azure-speech-region", key_vault_url),
            azure_speech_endpoint=_env_or_secret("AZURE_SPEECH_ENDPOINT", "azure-speech-endpoint", key_vault_url),
            azure_speech_key=_env_or_secret("AZURE_SPEECH_KEY", "azure-speech-key", key_vault_url),
            enable_live_speech=_bool_env("LALA_ENABLE_LIVE_SPEECH", default=False),
            cors_allow_origins=_csv_value(
                _env_or_secret("CORS_ALLOW_ORIGINS", "cors-allow-origins", key_vault_url)
            ),
            log_level=(os.getenv("LOG_LEVEL") or "INFO").strip(),
            access_log_path=(os.getenv("LALA_ACCESS_LOG_PATH") or "").strip(),
        )


def get_settings() -> Settings:
    return Settings.from_env()


def _env_or_secret(env_name: str, secret_name: str, key_vault_url: str) -> str:
    value = (os.getenv(env_name) or "").strip()
    if value:
        return value
    return get_secret_if_configured(key_vault_url, secret_name)


def _bool_env(env_name: str, *, default: bool) -> bool:
    raw = (os.getenv(env_name) or "").strip().lower()
    if not raw:
        return default
    return raw in {"1", "true", "yes", "on"}


def _csv_env(env_name: str) -> tuple[str, ...]:
    raw = (os.getenv(env_name) or "").strip()
    return _csv_value(raw)


def _csv_value(raw: str) -> tuple[str, ...]:
    raw = (raw or "").strip()
    if not raw:
        return ()
    values: list[str] = []
    for item in raw.split(","):
        value = item.strip().rstrip("/")
        if value:
            values.append(value)
    return tuple(values)
