"""Runtime secret profiles and the AWS Secrets Manager contract.

The API and worker profiles intentionally do not read dotenv, process secret
values, or the legacy Azure Key Vault.  Only the explicit local profile may
load a developer dotenv file.  Error and status objects contain logical
secret names only; secret values and resource identifiers never cross this
module's observability boundary.
"""

from __future__ import annotations

import os
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path

from apps.api.app.core import aws_secrets
from apps.api.app.core.aws_secrets import AwsSecretLookupError

RUNTIME_PROFILES = frozenset({"local", "ci", "api", "worker"})


@dataclass(frozen=True)
class SecretSpec:
    env_name: str
    secret_name: str


SECRET_REGISTRY: tuple[SecretSpec, ...] = (
    SecretSpec("IOS_API_KEY", "ios-api-key"),
    SecretSpec("API_BEARER_TOKEN", "api-bearer-token"),
    SecretSpec("LOGTO_ENDPOINT", "logto-endpoint"),
    SecretSpec("LOGTO_API_AUDIENCE", "logto-api-audience"),
    SecretSpec("LOGTO_MANAGEMENT_ENDPOINT", "logto-management-endpoint"),
    SecretSpec("LOGTO_MANAGEMENT_CLIENT_ID", "logto-management-client-id"),
    SecretSpec("LOGTO_MANAGEMENT_CLIENT_SECRET", "logto-management-client-secret"),
    SecretSpec("OAUTH_ISSUER", "oauth-issuer"),
    SecretSpec("OAUTH_AUDIENCE", "oauth-audience"),
    SecretSpec("OAUTH_JWKS_URL", "oauth-jwks-url"),
    SecretSpec("OAUTH_CLIENT_ID", "oauth-client-id"),
    SecretSpec("OAUTH_REQUIRED_SCOPES", "oauth-required-scopes"),
    SecretSpec("KAKAO_REST_API_KEY", "kakao-rest-api-key"),
    SecretSpec("KAKAO_JAVASCRIPT_KEY", "kakao-javascript-key"),
    SecretSpec("KAKAO_REDIRECT_URI", "kakao-redirect-uri"),
    SecretSpec("NAVER_CLIENT_ID", "naver-client-id"),
    SecretSpec("NAVER_CLIENT_SECRET", "naver-client-secret"),
    SecretSpec("KOPIS_API_KEY", "kopis-api-key"),
    SecretSpec("PUBLIC_DATA_SERVICE_KEY", "public-data-service-key"),
    SecretSpec("GYEONGGI_DATA_DREAM_API_KEY", "gyeonggi-data-dream-api-key"),
    SecretSpec("DB_DSN", "db-dsn"),
    SecretSpec("OPENAI_API_KEY", "openai-api-key"),
    SecretSpec("OPENAI_BASE_URL", "openai-base-url"),
    SecretSpec("OPENAI_EMBEDDING_MODEL", "openai-embedding-model"),
    SecretSpec("OPENAI_REVIEW_BATCH_MODEL", "openai-review-batch-model"),
    SecretSpec("OPENAI_REVIEW_RECHECK_MODEL", "openai-review-recheck-model"),
    SecretSpec("OPENAI_DOCENT_MODEL", "openai-docent-model"),
    SecretSpec("OPENAI_PLACE_ENRICHMENT_MODEL", "openai-place-enrichment-model"),
    SecretSpec("AZURE_SPEECH_REGION", "azure-speech-region"),
    SecretSpec("AZURE_SPEECH_ENDPOINT", "azure-speech-endpoint"),
    SecretSpec("AZURE_SPEECH_KEY", "azure-speech-key"),
    SecretSpec("CORS_ALLOW_ORIGINS", "cors-allow-origins"),
)
_REGISTRY_BY_ENV = {item.env_name: item for item in SECRET_REGISTRY}


class RuntimeSecretError(RuntimeError):
    """Base error whose string representation is secret-safe."""


class RuntimeSecretLookupError(RuntimeSecretError):
    pass


class RuntimeSecretContractError(RuntimeSecretError):
    pass


@dataclass(frozen=True)
class SecretContractStatus:
    profile: str
    status: str
    required_names: tuple[str, ...] = ()
    configured_names: tuple[str, ...] = ()
    missing_names: tuple[str, ...] = ()

    def to_dict(self) -> dict[str, object]:
        return {
            "profile": self.profile,
            "status": self.status,
            "required_names": list(self.required_names),
            "configured_names": list(self.configured_names),
            "missing_names": list(self.missing_names),
        }


def get_runtime_profile(environ: Mapping[str, str] | None = None) -> str:
    env = environ if environ is not None else os.environ
    raw = (env.get("LALA_RUNTIME_PROFILE") or "").strip().lower()
    if not raw:
        return "local"
    if raw not in RUNTIME_PROFILES:
        raise RuntimeSecretContractError(
            "LALA_RUNTIME_PROFILE must be one of local, ci, api, worker."
        )
    return raw


def load_runtime_environment() -> None:
    """Load dotenv only when the caller explicitly selected local profile."""
    env = os.environ
    if (env.get("LALA_RUNTIME_PROFILE") or "").strip().lower() != "local":
        return
    from dotenv import load_dotenv

    explicit_file = (env.get("LALA_LOCAL_ENV_FILE") or "").strip()
    if explicit_file:
        load_dotenv(dotenv_path=Path(explicit_file), override=False)
        return
    load_dotenv(dotenv_path=Path(".env.local"), override=False)
    load_dotenv(dotenv_path=Path(".env"), override=False)


def resolve_runtime_secret(
    env_name: str,
    secret_name: str,
    *,
    key_vault_loader: Callable[[str, str], str] | None = None,
    environ: Mapping[str, str] | None = None,
    required: bool = False,
) -> str:
    env = environ if environ is not None else os.environ
    spec = _spec_for(env_name, secret_name)
    profile = get_runtime_profile(env)

    if profile in {"api", "worker"}:
        try:
            value = aws_secrets.get_aws_sm_secret(spec.secret_name, required=required)
        except AwsSecretLookupError:
            raise RuntimeSecretLookupError(
                f"AWS Secrets Manager lookup failed for {spec.secret_name}."
            ) from None
        if required and not _usable_secret(value):
            raise RuntimeSecretLookupError(
                f"Required runtime secret is unavailable: {spec.secret_name}."
            )
        return value.strip()

    if profile == "ci":
        return (env.get(spec.env_name) or "").strip()

    value = (env.get(spec.env_name) or "").strip()
    if value:
        return value
    # Local AWS/Key Vault use is opt-in for developer verification only.
    if (env.get("LALA_LOCAL_USE_AWS_SECRETS") or "").strip().lower() in {"1", "true", "yes"}:
        value = aws_secrets.get_aws_sm_secret(spec.secret_name)
        if value:
            return value.strip()
    if key_vault_loader is not None:
        return (
            key_vault_loader((env.get("KEY_VAULT_URL") or "").strip(), spec.secret_name) or ""
        ).strip()
    return ""


def required_secret_names(
    profile: str, *, worker_job_id: str | None = None, values: Mapping[str, object] | None = None
) -> tuple[str, ...]:
    if profile not in {"api", "worker"}:
        return ()
    current = values or {}
    names = ["DB_DSN"]
    guest = bool(current.get("guest_access") or current.get("public_contest_access"))
    has_auth = bool(
        current.get("ios_api_key")
        or current.get("api_bearer_token")
        or (
            current.get("oauth_issuer")
            and current.get("oauth_audience")
            and current.get("oauth_jwks_url")
        )
    )
    if profile == "api" and not guest and not has_auth:
        names.extend(("API_BEARER_TOKEN", "OAUTH_ISSUER", "OAUTH_AUDIENCE", "OAUTH_JWKS_URL"))
    if bool(current.get("enable_live_ai")):
        names.append("OPENAI_API_KEY")
    if bool(current.get("enable_live_speech")):
        names.extend(("AZURE_SPEECH_KEY", "AZURE_SPEECH_REGION"))
    if profile == "worker" and worker_job_id == "weather-refresh":
        names.append("PUBLIC_DATA_SERVICE_KEY")
    return tuple(dict.fromkeys(names))


def validate_secret_contract(
    profile: str,
    values: Mapping[str, object],
    *,
    environ: Mapping[str, str] | None = None,
    worker_job_id: str | None = None,
) -> SecretContractStatus:
    required = required_secret_names(profile, worker_job_id=worker_job_id, values=values)
    configured = tuple(
        name for name in required if _usable_secret(str(values.get(_env_for_secret(name), "")))
    )
    missing = tuple(name for name in required if name not in configured)
    if missing:
        raise RuntimeSecretContractError(
            f"Runtime secret contract failed for profile {profile}; missing: {', '.join(missing)}."
        )
    return SecretContractStatus(profile, "ok", required, configured, missing)


def _spec_for(env_name: str, secret_name: str) -> SecretSpec:
    spec = _REGISTRY_BY_ENV.get(env_name)
    if spec is None or spec.secret_name != secret_name:
        raise RuntimeSecretContractError(f"Unregistered runtime secret contract: {env_name}.")
    return spec


def _env_for_secret(secret_name: str) -> str:
    for spec in SECRET_REGISTRY:
        if spec.secret_name == secret_name:
            return spec.env_name
    return secret_name.upper().replace("-", "_")


def _usable_secret(value: str) -> bool:
    normalized = value.strip().lower()
    if not normalized:
        return False
    return normalized not in {
        "placeholder",
        "changeme",
        "change-me",
        "dummy",
        "test-secret",
        "<secret>",
    } and not normalized.startswith("<")
