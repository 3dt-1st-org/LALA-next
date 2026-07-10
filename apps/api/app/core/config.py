from __future__ import annotations

import os
from dataclasses import dataclass
from urllib.parse import urlsplit, urlunsplit

from dotenv import load_dotenv

from apps.api.app.core.key_vault import get_secret_if_configured

load_dotenv()


@dataclass(frozen=True)
class Settings:
    app_name: str = "LALA-next Public API"
    app_version: str = "0.1.0"
    ios_api_key: str = ""
    api_bearer_token: str = ""
    logto_endpoint: str = ""
    logto_api_audience: str = ""
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
    public_contest_access: bool = False
    guest_access: bool = False
    static_snapshot_fallback: bool = False
    db_dsn: str = ""
    key_vault_url: str = ""
    azure_openai_endpoint: str = ""
    azure_openai_deployment: str = ""
    azure_openai_docent_deployment: str = ""
    azure_openai_review_batch_deployment: str = ""
    azure_openai_embedding_deployment: str = ""
    azure_openai_api_version: str = ""
    azure_openai_embedding_api_version: str = ""
    azure_openai_key: str = ""
    openai_api_key: str = ""
    openai_base_url: str = ""
    openai_embedding_model: str = ""
    enable_live_ai: bool = False
    azure_speech_region: str = ""
    azure_speech_endpoint: str = ""
    azure_speech_key: str = ""
    enable_live_speech: bool = False
    paid_route_rate_limit_enabled: bool = True
    docent_script_rate_limit_per_minute: int = 60
    docent_audio_rate_limit_per_minute: int = 30
    weather_freshness_max_hours: int = 24
    cors_allow_origins: tuple[str, ...] = ()
    log_level: str = "INFO"
    access_log_path: str = ""

    @property
    def guest_access_enabled(self) -> bool:
        return self.guest_access or self.public_contest_access

    @classmethod
    def from_env(cls) -> "Settings":
        key_vault_url = (os.getenv("KEY_VAULT_URL") or "").strip()
        logto_endpoint = _env_or_secret("LOGTO_ENDPOINT", "logto-endpoint", key_vault_url)
        logto_api_audience = _env_or_secret(
            "LOGTO_API_AUDIENCE",
            "logto-api-audience",
            key_vault_url,
        )
        logto_issuer, logto_jwks_url = _derive_logto_oidc_urls(logto_endpoint)
        logto_validation_configured = bool(
            logto_issuer and logto_jwks_url and logto_api_audience
        )
        azure_openai_deployment = _env_or_secret(
            "AZURE_OPENAI_DEPLOYMENT",
            "azure-openai-deployment",
            key_vault_url,
        )
        azure_openai_docent_deployment = (
            _env_or_secret(
                "AZURE_OPENAI_DOCENT_DEPLOYMENT",
                "azure-openai-docent-deployment",
                key_vault_url,
            )
            or azure_openai_deployment
        )
        azure_openai_review_batch_deployment = (
            _env_or_secret(
                "AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT",
                "azure-openai-review-batch-deployment",
                key_vault_url,
            )
            or azure_openai_deployment
        )
        return cls(
            ios_api_key=_env_or_secret("IOS_API_KEY", "ios-api-key", key_vault_url),
            api_bearer_token=_env_or_secret("API_BEARER_TOKEN", "api-bearer-token", key_vault_url),
            logto_endpoint=logto_endpoint,
            logto_api_audience=logto_api_audience,
            oauth_issuer=(
                logto_issuer if logto_validation_configured else ""
                or _env_or_secret("OAUTH_ISSUER", "oauth-issuer", key_vault_url)
            ),
            oauth_audience=(
                logto_api_audience if logto_validation_configured else ""
                or _env_or_secret("OAUTH_AUDIENCE", "oauth-audience", key_vault_url)
            ),
            oauth_jwks_url=(
                logto_jwks_url if logto_validation_configured else ""
                or _env_or_secret("OAUTH_JWKS_URL", "oauth-jwks-url", key_vault_url)
            ),
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
            public_contest_access=_bool_env("LALA_PUBLIC_CONTEST_ACCESS", default=False),
            guest_access=_bool_env("LALA_GUEST_ACCESS", default=False),
            static_snapshot_fallback=_static_snapshot_fallback_enabled(),
            db_dsn=_env_or_secret("DB_DSN", "db-dsn", key_vault_url),
            key_vault_url=key_vault_url,
            azure_openai_endpoint=_env_or_secret(
                "AZURE_OPENAI_ENDPOINT",
                "azure-openai-endpoint",
                key_vault_url,
            ),
            azure_openai_deployment=azure_openai_deployment,
            azure_openai_docent_deployment=azure_openai_docent_deployment,
            azure_openai_review_batch_deployment=azure_openai_review_batch_deployment,
            azure_openai_embedding_deployment=_env_or_secret(
                "AZURE_OPENAI_EMBEDDING_DEPLOYMENT",
                "azure-openai-embedding-deployment",
                key_vault_url,
            ),
            azure_openai_api_version=_env_or_secret(
                "AZURE_OPENAI_API_VERSION",
                "azure-openai-api-version",
                key_vault_url,
            ),
            azure_openai_embedding_api_version=(
                _env_or_secret(
                    "AZURE_OPENAI_EMBEDDING_API_VERSION",
                    "azure-openai-embedding-api-version",
                    key_vault_url,
                )
                or _env_or_secret(
                    "AZURE_OPENAI_API_VERSION",
                    "azure-openai-api-version",
                    key_vault_url,
                )
            ),
            azure_openai_key=_env_or_secret("AZURE_OPENAI_KEY", "azure-openai-key", key_vault_url),
            openai_api_key=_env_or_secret("OPENAI_API_KEY", "openai-api-key", key_vault_url),
            openai_base_url=(
                _env_or_secret("OPENAI_BASE_URL", "openai-base-url", key_vault_url)
                or "https://api.openai.com/v1"
            ),
            openai_embedding_model=(
                _env_or_secret("OPENAI_EMBEDDING_MODEL", "openai-embedding-model", key_vault_url)
                or "text-embedding-3-small"
            ),
            enable_live_ai=_bool_env("LALA_ENABLE_LIVE_AI", default=False),
            azure_speech_region=_env_or_secret("AZURE_SPEECH_REGION", "azure-speech-region", key_vault_url),
            azure_speech_endpoint=_env_or_secret("AZURE_SPEECH_ENDPOINT", "azure-speech-endpoint", key_vault_url),
            azure_speech_key=_env_or_secret("AZURE_SPEECH_KEY", "azure-speech-key", key_vault_url),
            enable_live_speech=_bool_env("LALA_ENABLE_LIVE_SPEECH", default=False),
            paid_route_rate_limit_enabled=_bool_env(
                "LALA_PAID_ROUTE_RATE_LIMIT_ENABLED",
                default=True,
            ),
            docent_script_rate_limit_per_minute=_int_env(
                "LALA_DOCENT_SCRIPT_RATE_LIMIT_PER_MINUTE",
                default=60,
                minimum=1,
            ),
            docent_audio_rate_limit_per_minute=_int_env(
                "LALA_DOCENT_AUDIO_RATE_LIMIT_PER_MINUTE",
                default=30,
                minimum=1,
            ),
            weather_freshness_max_hours=_int_env(
                "LALA_WEATHER_FRESHNESS_MAX_HOURS",
                default=24,
                minimum=1,
            ),
            cors_allow_origins=_csv_value(
                _env_or_secret("CORS_ALLOW_ORIGINS", "cors-allow-origins", key_vault_url)
            ),
            log_level=(os.getenv("LOG_LEVEL") or "INFO").strip(),
            access_log_path=(os.getenv("LALA_ACCESS_LOG_PATH") or "").strip(),
        )


def get_settings() -> Settings:
    return Settings.from_env()


def _env_or_secret(env_name: str, secret_name: str, key_vault_url: str = "") -> str:
    value = (os.getenv(env_name) or "").strip()
    if value:
        return value
    # AWS Secrets Manager (AWS 운영 환경 우선)
    from apps.api.app.core.aws_secrets import get_aws_sm_secret

    aws_value = get_aws_sm_secret(secret_name)
    if aws_value:
        return aws_value
    # Azure Key Vault (레거시 폴백)
    return get_secret_if_configured(key_vault_url, secret_name)


def _bool_env(env_name: str, *, default: bool) -> bool:
    raw = (os.getenv(env_name) or "").strip().lower()
    if not raw:
        return default
    return raw in {"1", "true", "yes", "on"}


def _int_env(env_name: str, *, default: int, minimum: int) -> int:
    raw = (os.getenv(env_name) or "").strip()
    if not raw:
        return default
    try:
        value = int(raw)
    except ValueError:
        return default
    return max(minimum, value)


def _static_snapshot_fallback_enabled() -> bool:
    return _bool_env("LALA_STATIC_SNAPSHOT_FALLBACK", default=False)


def _derive_logto_oidc_urls(endpoint: str) -> tuple[str, str]:
    """Derive Logto's fixed OIDC issuer and JWKS URL from a safe base endpoint."""
    try:
        parsed = urlsplit(endpoint)
    except ValueError:
        return "", ""
    if (
        parsed.scheme.lower() != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
    ):
        return "", ""
    base_url = urlunsplit((parsed.scheme.lower(), parsed.netloc, "", "", ""))
    issuer = f"{base_url}/oidc"
    return issuer, f"{issuer}/jwks"


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
