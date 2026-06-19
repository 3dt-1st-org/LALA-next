from __future__ import annotations

import re
import shlex
from dataclasses import dataclass
from typing import Any

DEFAULT_KEY_VAULT_NAME = "lala-key-vault"
DEFAULT_API_APP_NAME = "lala-next-api-dev"
DEFAULT_FLUTTER_APP_NAME = "lala-next-flutter-dev"
DEFAULT_API_APP_ID_URI = "api://lala-next-dev"
DEFAULT_REQUIRED_SCOPES = ("access_as_user",)
DEFAULT_BASE_URL = "http://127.0.0.1:8080"
KEY_VAULT_URL_PLACEHOLDER = "<KEY_VAULT_URL>"

OAUTH_KEY_VAULT_SECRET_NAMES = (
    "oauth-issuer",
    "oauth-audience",
    "oauth-jwks-url",
    "oauth-client-id",
    "oauth-required-scopes",
)

_AZURE_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_. -]{1,118}[A-Za-z0-9]$")
_SCOPE_RE = re.compile(r"^[A-Za-z0-9_.-]{1,80}$")


@dataclass(frozen=True)
class IdentityRolloutPlanStep:
    order: int
    title: str
    command: str
    approval_required: bool
    secret_sensitive: bool = False
    notes: tuple[str, ...] = ()

    def to_dict(self) -> dict[str, Any]:
        return {
            "order": self.order,
            "title": self.title,
            "command": self.command,
            "approval_required": self.approval_required,
            "secret_sensitive": self.secret_sensitive,
            "notes": list(self.notes),
        }


@dataclass(frozen=True)
class IdentityRolloutPlan:
    key_vault_name: str
    api_app_name: str
    flutter_app_name: str
    api_app_id_uri: str
    required_scopes: tuple[str, ...]
    base_url: str
    key_vault_secret_names: tuple[str, ...]
    readiness_checks: tuple[str, ...]
    steps: tuple[IdentityRolloutPlanStep, ...]
    risk_gates: tuple[str, ...]
    warnings: tuple[str, ...]

    @property
    def ok(self) -> bool:
        return not self.warnings

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "mode": "plan",
            "applies_changes": False,
            "key_vault_name": self.key_vault_name,
            "api_app_name": self.api_app_name,
            "flutter_app_name": self.flutter_app_name,
            "api_app_id_uri": self.api_app_id_uri,
            "required_scopes": list(self.required_scopes),
            "base_url": self.base_url,
            "key_vault_secret_names": list(self.key_vault_secret_names),
            "readiness_checks": list(self.readiness_checks),
            "steps": [step.to_dict() for step in self.steps],
            "risk_gates": list(self.risk_gates),
            "warnings": list(self.warnings),
        }


def build_identity_rollout_plan(
    *,
    key_vault_name: str = DEFAULT_KEY_VAULT_NAME,
    api_app_name: str = DEFAULT_API_APP_NAME,
    flutter_app_name: str = DEFAULT_FLUTTER_APP_NAME,
    api_app_id_uri: str = DEFAULT_API_APP_ID_URI,
    required_scopes: tuple[str, ...] = DEFAULT_REQUIRED_SCOPES,
    base_url: str = DEFAULT_BASE_URL,
) -> IdentityRolloutPlan:
    base_url = base_url.rstrip("/")
    warnings = _validate_inputs(
        key_vault_name=key_vault_name,
        api_app_name=api_app_name,
        flutter_app_name=flutter_app_name,
        api_app_id_uri=api_app_id_uri,
        required_scopes=required_scopes,
    )
    command_key_vault_name = (
        key_vault_name
        if key_vault_name == DEFAULT_KEY_VAULT_NAME and "onmu" not in key_vault_name.lower()
        else DEFAULT_KEY_VAULT_NAME
    )
    scope_list = " ".join(required_scopes)
    scope_csv = ",".join(required_scopes)
    steps = (
        IdentityRolloutPlanStep(
            order=1,
            title="Confirm current static-auth transition state",
            command=_cmd(
                "scripts/unix/smoke_api.sh",
                "--base-url",
                base_url,
            ),
            approval_required=False,
            notes=(
                "Read-only. Confirms /readyz and authenticated /api/v1/* still work before identity changes.",
            ),
        ),
        IdentityRolloutPlanStep(
            order=2,
            title="Create approved Entra API app registration",
            command=_cmd(
                "az",
                "ad",
                "app",
                "create",
                "--display-name",
                api_app_name,
                "--identifier-uris",
                api_app_id_uri,
                "--sign-in-audience",
                "AzureADMyOrg",
            ),
            approval_required=True,
            notes=(
                "Creates an app registration only after owner approval.",
                "Record the returned appId as oauth-audience if the team chooses client-id audiences.",
            ),
        ),
        IdentityRolloutPlanStep(
            order=3,
            title="Expose delegated API scopes",
            command=(
                "manual: Entra App registrations > "
                f"{api_app_name} > Expose an API > add scopes: {scope_list}"
            ),
            approval_required=True,
            notes=(
                "Keep scope names stable; Flutter and API rollout docs should use the same list.",
                "Do not add admin-consent-only permissions unless the team approves them.",
            ),
        ),
        IdentityRolloutPlanStep(
            order=4,
            title="Create approved Flutter public client app registration",
            command=_cmd(
                "az",
                "ad",
                "app",
                "create",
                "--display-name",
                flutter_app_name,
                "--sign-in-audience",
                "AzureADMyOrg",
            ),
            approval_required=True,
            notes=(
                "Configure platform redirect URIs separately for Flutter Web, iOS, Android, and macOS.",
                "Do not create or store a client secret for the public Flutter client.",
            ),
        ),
        IdentityRolloutPlanStep(
            order=5,
            title="Grant Flutter app delegated access to the API app",
            command=(
                "manual: Entra App registrations > "
                f"{flutter_app_name} > API permissions > add {api_app_name}/{scope_list}"
            ),
            approval_required=True,
            notes=("Grant consent only after the requested scopes are reviewed.",),
        ),
        IdentityRolloutPlanStep(
            order=6,
            title="Register OAuth configuration in the LALA-next Key Vault",
            command="\n".join(
                (
                    _cmd(
                        "az",
                        "keyvault",
                        "secret",
                        "set",
                        "--vault-name",
                        command_key_vault_name,
                        "--name",
                        "oauth-issuer",
                        "--value",
                        "https://login.microsoftonline.com/<tenant-id>/v2.0",
                    ),
                    _cmd(
                        "az",
                        "keyvault",
                        "secret",
                        "set",
                        "--vault-name",
                        command_key_vault_name,
                        "--name",
                        "oauth-audience",
                        "--value",
                        api_app_id_uri,
                    ),
                    _cmd(
                        "az",
                        "keyvault",
                        "secret",
                        "set",
                        "--vault-name",
                        command_key_vault_name,
                        "--name",
                        "oauth-jwks-url",
                        "--value",
                        "https://login.microsoftonline.com/<tenant-id>/discovery/v2.0/keys",
                    ),
                    _cmd(
                        "az",
                        "keyvault",
                        "secret",
                        "set",
                        "--vault-name",
                        command_key_vault_name,
                        "--name",
                        "oauth-client-id",
                        "--value",
                        "<flutter-public-client-id>",
                    ),
                    _cmd(
                        "az",
                        "keyvault",
                        "secret",
                        "set",
                        "--vault-name",
                        command_key_vault_name,
                        "--name",
                        "oauth-required-scopes",
                        "--value",
                        scope_csv,
                    ),
                )
            ),
            approval_required=True,
            notes=(
                "Stores configuration names only; do not store Flutter public-client secrets.",
                "Use the LALA-next vault, never the ONMU vault.",
            ),
        ),
        IdentityRolloutPlanStep(
            order=7,
            title="Start API in static-plus-OAuth transition mode",
            command=_cmd(
                "scripts/unix/start_api.sh",
                "--key-vault-url",
                KEY_VAULT_URL_PLACEHOLDER,
            ),
            approval_required=False,
            notes=(
                "Readiness should report client_identity=transition while static bearer/API-key auth still protects /api/v1/*.",
                "Resolve <KEY_VAULT_URL> from a private runbook or environment variable, not tracked docs.",
            ),
        ),
        IdentityRolloutPlanStep(
            order=8,
            title="Verify identity readiness and JWT enforcement path",
            command=_cmd(
                "scripts/unix/smoke_api.sh",
                "--base-url",
                base_url,
                "--key-vault-url",
                KEY_VAULT_URL_PLACEHOLDER,
            ),
            approval_required=False,
            notes=(
                "Read-only smoke. /readyz should show jwt_validation=configured when OAuth validation settings are complete.",
                "Use a separately approved Entra test token for an end-to-end JWT smoke; this plan does not mint tokens.",
            ),
        ),
        IdentityRolloutPlanStep(
            order=9,
            title="Retire static auth only after Flutter token acquisition is verified",
            command=(
                "manual: remove ios-api-key/api-bearer-token from the active environment "
                "only after signed JWT validation, Flutter token acquisition, and rollback are approved"
            ),
            approval_required=True,
            notes=(
                "API-side signed JWT validation is implemented for configured OAuth/Entra issuers.",
                "Keep IOS_API_KEY or API_BEARER_TOKEN during the transition window.",
            ),
        ),
    )

    return IdentityRolloutPlan(
        key_vault_name=key_vault_name,
        api_app_name=api_app_name,
        flutter_app_name=flutter_app_name,
        api_app_id_uri=api_app_id_uri,
        required_scopes=required_scopes,
        base_url=base_url,
        key_vault_secret_names=OAUTH_KEY_VAULT_SECRET_NAMES,
        readiness_checks=(
            "client_identity",
            "jwt_validation",
            "oauth_issuer",
            "oauth_audience",
            "oauth_jwks_url",
            "oauth_client_id",
            "oauth_required_scopes",
        ),
        steps=steps,
        risk_gates=(
            "This plan does not create Entra apps, Key Vault secrets, or Flutter tokens by itself.",
            "OAuth configuration belongs in the LALA-next Key Vault; do not use ONMU vaults.",
            "Do not remove IOS_API_KEY or API_BEARER_TOKEN until API JWT validation and Flutter token acquisition are verified together.",
            "Do not commit tenant ids, client ids tied to private environments, tokens, or screenshots with credentials.",
            "Flutter public clients must not use client secrets.",
        ),
        warnings=tuple(warnings),
    )


def _cmd(*parts: str) -> str:
    return " ".join(shlex.quote(part) for part in parts)


def _validate_inputs(
    *,
    key_vault_name: str,
    api_app_name: str,
    flutter_app_name: str,
    api_app_id_uri: str,
    required_scopes: tuple[str, ...],
) -> list[str]:
    warnings: list[str] = []
    if key_vault_name != DEFAULT_KEY_VAULT_NAME:
        warnings.append("Identity rollout must target the LALA-next Key Vault by default.")
    if "onmu" in key_vault_name.lower():
        warnings.append("ONMU Key Vault must not be used for LALA-next identity rollout.")
    if not _AZURE_NAME_RE.fullmatch(api_app_name):
        warnings.append("API app registration display name contains unsupported characters.")
    if not _AZURE_NAME_RE.fullmatch(flutter_app_name):
        warnings.append("Flutter app registration display name contains unsupported characters.")
    if not api_app_id_uri.startswith("api://"):
        warnings.append("API app id URI should use the api:// scheme.")
    if not required_scopes:
        warnings.append("At least one delegated OAuth scope must be planned.")
    for scope in required_scopes:
        if not _SCOPE_RE.fullmatch(scope):
            warnings.append(f"OAuth scope name is invalid: {scope}")
    return warnings
