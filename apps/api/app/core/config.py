from __future__ import annotations

import os
from dataclasses import dataclass, field, replace
from urllib.parse import urlsplit, urlunsplit

from apps.api.app.core.feature_flags import FeatureFlagValue, resolve_feature_flags
from apps.api.app.core.key_vault import get_secret_if_configured
from apps.api.app.core.runtime_secrets import (
    SecretContractStatus,
    get_runtime_profile,
    load_runtime_environment,
    resolve_runtime_secret,
    validate_secret_contract,
)

load_runtime_environment()


@dataclass(frozen=True)
class Settings:
    app_name: str = "LALA-next Public API"
    app_version: str = "0.1.0"
    ios_api_key: str = ""
    api_bearer_token: str = ""
    logto_endpoint: str = ""
    logto_api_audience: str = ""
    logto_management_endpoint: str = ""
    logto_management_client_id: str = ""
    logto_management_client_secret: str = ""
    oauth_issuer: str = ""
    oauth_audience: str = ""
    oauth_jwks_url: str = ""
    oauth_client_id: str = ""
    oauth_required_scopes: tuple[str, ...] = ()
    kakao_rest_api_key: str = ""
    naver_map_client_id: str = ""
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
    openai_api_key: str = ""
    openai_base_url: str = ""
    openai_embedding_model: str = ""
    # Standard OpenAI chat model names for the review-evidence lanes (Improvement B).
    # bulk review processing -> gpt-5.4-nano; low-confidence recheck -> gpt-5.4-mini.
    # Never use Azure OpenAI for LALA AI work.
    openai_review_batch_model: str = ""
    openai_review_recheck_model: str = ""
    openai_docent_model: str = ""
    openai_place_enrichment_model: str = ""
    # Non-secret model-id overrides. Values are read only from LALA_MODEL_ROLE_*.
    model_role_overrides: dict[str, str] = field(default_factory=dict)
    # Central W0-c registry values. Consumers remain unchanged until their wave.
    feature_flags: dict[str, FeatureFlagValue] = field(default_factory=dict)
    enable_live_ai: bool = False
    azure_speech_region: str = ""
    azure_speech_endpoint: str = ""
    azure_speech_key: str = ""
    enable_live_speech: bool = False
    # V5-C MOVE routing seam. Real Kakao/Naver Directions are BLOCKED_EXTERNAL/V7;
    # the flag only gates the hook. Default off keeps the Haversine estimate standalone.
    enable_live_routing: bool = False
    paid_route_rate_limit_enabled: bool = True
    docent_script_rate_limit_per_minute: int = 60
    docent_audio_rate_limit_per_minute: int = 30
    weather_freshness_max_hours: int = 24
    # RAG V1 retrieval + reindex lifecycle (defaults keep a no-op deploy on legacy behavior).
    rag_embedding_method: str = "local-hash"
    rag_embedding_generation: int = 1
    rag_retrieval_mode: str = "legacy"
    rag_reindex_chunk_cap: int = 500
    rag_reindex_batch_size: int = 100
    rag_allow_local_hash_live: bool = False
    docent_script_ttl_sec: int = 604800
    cors_allow_origins: tuple[str, ...] = ()
    log_level: str = "INFO"
    access_log_path: str = ""
    runtime_profile: str = "local"
    secret_contract: SecretContractStatus = field(
        default_factory=lambda: SecretContractStatus("local", "not_required")
    )

    @property
    def guest_access_enabled(self) -> bool:
        return self.guest_access or self.public_contest_access

    @classmethod
    def from_env(cls) -> Settings:
        profile = get_runtime_profile()
        key_vault_url = (os.getenv("KEY_VAULT_URL") or "").strip()
        logto_endpoint = _env_or_secret("LOGTO_ENDPOINT", "logto-endpoint", key_vault_url)
        logto_api_audience = _env_or_secret(
            "LOGTO_API_AUDIENCE",
            "logto-api-audience",
            key_vault_url,
        )
        logto_issuer, logto_jwks_url = derive_logto_oidc_urls(logto_endpoint)
        logto_validation_configured = bool(logto_issuer and logto_jwks_url and logto_api_audience)
        openai_docent_model = (
            _env_or_secret(
                "OPENAI_DOCENT_MODEL",
                "openai-docent-model",
                key_vault_url,
            )
            or "gpt-5.4-mini"
        )
        openai_place_enrichment_model = (
            _env_or_secret(
                "OPENAI_PLACE_ENRICHMENT_MODEL",
                "openai-place-enrichment-model",
                key_vault_url,
            )
            or "gpt-5.4-mini"
        )
        # Improvement B: standard OpenAI chat models for review evidence (never
        # Azure). Bulk -> gpt-5.4-nano, low-confidence recheck -> gpt-5.4-mini.
        openai_review_batch_model = (
            _env_or_secret(
                "OPENAI_REVIEW_BATCH_MODEL",
                "openai-review-batch-model",
                key_vault_url,
            )
            or "gpt-5.4-nano"
        )
        openai_review_recheck_model = (
            _env_or_secret(
                "OPENAI_REVIEW_RECHECK_MODEL",
                "openai-review-recheck-model",
                key_vault_url,
            )
            or "gpt-5.4-mini"
        )
        settings = cls(
            ios_api_key=_env_or_secret("IOS_API_KEY", "ios-api-key", key_vault_url),
            api_bearer_token=_env_or_secret("API_BEARER_TOKEN", "api-bearer-token", key_vault_url),
            logto_endpoint=logto_endpoint,
            logto_api_audience=logto_api_audience,
            logto_management_endpoint=(
                _env_or_secret(
                    "LOGTO_MANAGEMENT_ENDPOINT",
                    "logto-management-endpoint",
                    key_vault_url,
                )
                or logto_endpoint
            ),
            logto_management_client_id=_env_or_secret(
                "LOGTO_MANAGEMENT_CLIENT_ID",
                "logto-management-client-id",
                key_vault_url,
            ),
            logto_management_client_secret=_env_or_secret(
                "LOGTO_MANAGEMENT_CLIENT_SECRET",
                "logto-management-client-secret",
                key_vault_url,
            ),
            oauth_issuer=(
                logto_issuer
                if logto_validation_configured
                else "" or _env_or_secret("OAUTH_ISSUER", "oauth-issuer", key_vault_url)
            ),
            oauth_audience=(
                logto_api_audience
                if logto_validation_configured
                else "" or _env_or_secret("OAUTH_AUDIENCE", "oauth-audience", key_vault_url)
            ),
            oauth_jwks_url=(
                logto_jwks_url
                if logto_validation_configured
                else "" or _env_or_secret("OAUTH_JWKS_URL", "oauth-jwks-url", key_vault_url)
            ),
            oauth_client_id=_env_or_secret("OAUTH_CLIENT_ID", "oauth-client-id", key_vault_url),
            # Legacy Entra delegated scopes (e.g. access_as_user) are not Logto
            # API-resource scopes; requiring them on the authoritative Logto path
            # rejects every Logto-issued token. They only gate the legacy OAUTH_*
            # fallback below.
            oauth_required_scopes=(
                ()
                if logto_validation_configured
                else _csv_value(
                    _env_or_secret("OAUTH_REQUIRED_SCOPES", "oauth-required-scopes", key_vault_url)
                )
            ),
            kakao_rest_api_key=_env_or_secret(
                "KAKAO_REST_API_KEY", "kakao-rest-api-key", key_vault_url
            ),
            naver_map_client_id=_env_or_secret(
                "NAVER_MAP_CLIENT_ID",
                "naver-map-client-id",
                key_vault_url,
            ),
            kakao_redirect_uri=_env_or_secret(
                "KAKAO_REDIRECT_URI", "kakao-redirect-uri", key_vault_url
            ),
            naver_client_id=_env_or_secret("NAVER_CLIENT_ID", "naver-client-id", key_vault_url),
            naver_client_secret=_env_or_secret(
                "NAVER_CLIENT_SECRET", "naver-client-secret", key_vault_url
            ),
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
            openai_api_key=_env_or_secret("OPENAI_API_KEY", "openai-api-key", key_vault_url),
            openai_base_url=(
                _env_or_secret("OPENAI_BASE_URL", "openai-base-url", key_vault_url)
                or "https://api.openai.com/v1"
            ),
            openai_embedding_model=(
                _env_or_secret("OPENAI_EMBEDDING_MODEL", "openai-embedding-model", key_vault_url)
                or "text-embedding-3-small"
            ),
            openai_review_batch_model=openai_review_batch_model,
            openai_review_recheck_model=openai_review_recheck_model,
            openai_docent_model=openai_docent_model,
            openai_place_enrichment_model=openai_place_enrichment_model,
            model_role_overrides=_model_role_overrides_from_env(),
            feature_flags=resolve_feature_flags(),
            enable_live_ai=_bool_env("LALA_ENABLE_LIVE_AI", default=False),
            azure_speech_region=_env_or_secret(
                "AZURE_SPEECH_REGION", "azure-speech-region", key_vault_url
            ),
            azure_speech_endpoint=_env_or_secret(
                "AZURE_SPEECH_ENDPOINT", "azure-speech-endpoint", key_vault_url
            ),
            azure_speech_key=_env_or_secret("AZURE_SPEECH_KEY", "azure-speech-key", key_vault_url),
            enable_live_speech=_bool_env("LALA_ENABLE_LIVE_SPEECH", default=False),
            enable_live_routing=_bool_env("LALA_ENABLE_LIVE_ROUTING", default=False),
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
            rag_embedding_method=(
                (os.getenv("LALA_RAG_EMBEDDING_METHOD") or "").strip().lower() or "local-hash"
            ),
            rag_embedding_generation=_int_env(
                "LALA_RAG_EMBEDDING_GENERATION",
                default=1,
                minimum=0,
            ),
            rag_retrieval_mode=(
                (os.getenv("LALA_RAG_RETRIEVAL_MODE") or "").strip().lower() or "legacy"
            ),
            rag_reindex_chunk_cap=_int_env(
                "LALA_RAG_REINDEX_CHUNK_CAP",
                default=500,
                minimum=1,
            ),
            rag_reindex_batch_size=_int_env(
                "LALA_RAG_REINDEX_BATCH_SIZE",
                default=100,
                minimum=1,
            ),
            rag_allow_local_hash_live=_bool_env(
                "LALA_RAG_ALLOW_LOCAL_HASH_LIVE",
                default=False,
            ),
            docent_script_ttl_sec=_int_env(
                "LALA_DOCENT_SCRIPT_TTL_SEC",
                default=604800,
                minimum=1,
            ),
            cors_allow_origins=_csv_value(
                _env_or_secret("CORS_ALLOW_ORIGINS", "cors-allow-origins", key_vault_url)
            ),
            log_level=(os.getenv("LOG_LEVEL") or "INFO").strip(),
            access_log_path=(os.getenv("LALA_ACCESS_LOG_PATH") or "").strip(),
        )
        secret_values = {
            "ios_api_key": settings.ios_api_key,
            "api_bearer_token": settings.api_bearer_token,
            "oauth_issuer": settings.oauth_issuer,
            "oauth_audience": settings.oauth_audience,
            "oauth_jwks_url": settings.oauth_jwks_url,
            "db_dsn": settings.db_dsn,
            "openai_api_key": settings.openai_api_key,
            "enable_live_ai": settings.enable_live_ai,
            "enable_live_speech": settings.enable_live_speech,
            "azure_speech_key": settings.azure_speech_key,
            "azure_speech_region": settings.azure_speech_region,
            "guest_access": settings.guest_access,
            "public_contest_access": settings.public_contest_access,
        }
        contract = validate_secret_contract(profile, secret_values, environ=os.environ)
        return replace(settings, runtime_profile=profile, secret_contract=contract)


def get_settings() -> Settings:
    return Settings.from_env()


def resolve_openai_base_url_host(base_url: str | None) -> str:
    """Return only the safe host metadata for a general OpenAI base URL.

    LALA AI model lanes must never route through Azure OpenAI. The full URL is
    intentionally not returned or included in operator payloads.
    """
    raw_url = (base_url or "https://api.openai.com/v1").strip()
    try:
        parsed = urlsplit(raw_url)
    except ValueError as exc:
        raise ValueError("OPENAI_BASE_URL is not a valid URL.") from exc
    host = (parsed.hostname or "").strip().lower().rstrip(".")
    if not host:
        raise ValueError("OPENAI_BASE_URL must include a host.")
    if host == "openai.azure.com" or host.endswith(".openai.azure.com"):
        raise ValueError("Azure OpenAI base URLs are not supported for LALA AI model paths.")
    return host


def _env_or_secret(env_name: str, secret_name: str, key_vault_url: str = "") -> str:
    profile = get_runtime_profile()

    # For operational profiles (api/worker), never use Key Vault fallback
    # This ensures fail-closed behavior - secrets must come from AWS Secrets Manager
    if profile in {"api", "worker"}:
        return resolve_runtime_secret(
            env_name,
            secret_name,
            key_vault_loader=None,  # No Key Vault for operational profiles
        )

    # Local/ci profiles can use Key Vault as fallback for developer convenience
    return resolve_runtime_secret(
        env_name,
        secret_name,
        key_vault_loader=lambda _url, name: get_secret_if_configured(key_vault_url, name),
    )


def _model_role_overrides_from_env() -> dict[str, str]:
    """Read only non-secret role model-id overrides from the process environment."""
    roles = (
        "review_bulk",
        "review_recheck",
        "docent",
        "docent_qa",
        "place_enrichment",
        "embedding",
    )
    return {
        role: value
        for role in roles
        if (value := (os.getenv(f"LALA_MODEL_ROLE_{role.upper()}") or "").strip())
    }


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


def derive_logto_oidc_urls(endpoint: str) -> tuple[str, str]:
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
