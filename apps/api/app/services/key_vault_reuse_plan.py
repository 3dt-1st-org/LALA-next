from __future__ import annotations

import shlex
from dataclasses import dataclass
from typing import Any

DEFAULT_SOURCE_VAULT_NAME = "onmu-dev-kv-27db5e"
DEFAULT_TARGET_VAULT_NAME = "lala-next-kv-27db5e"


@dataclass(frozen=True)
class KeyVaultReuseCandidate:
    source_secret_name: str
    target_secret_name: str
    action: str
    approval_required: bool
    secret_sensitive: bool
    validation: str
    notes: tuple[str, ...] = ()

    def to_dict(self) -> dict[str, Any]:
        return {
            "source_secret_name": self.source_secret_name,
            "target_secret_name": self.target_secret_name,
            "action": self.action,
            "approval_required": self.approval_required,
            "secret_sensitive": self.secret_sensitive,
            "validation": self.validation,
            "notes": list(self.notes),
        }


@dataclass(frozen=True)
class RejectedSecretPattern:
    pattern: str
    reason: str

    def to_dict(self) -> dict[str, str]:
        return {
            "pattern": self.pattern,
            "reason": self.reason,
        }


@dataclass(frozen=True)
class KeyVaultReusePlan:
    source_vault_name: str
    target_vault_name: str
    candidate_secret_mappings: tuple[KeyVaultReuseCandidate, ...]
    rejected_secret_patterns: tuple[RejectedSecretPattern, ...]
    verification_commands: tuple[str, ...]
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
            "source_vault_name": self.source_vault_name,
            "target_vault_name": self.target_vault_name,
            "candidate_secret_mappings": [
                candidate.to_dict() for candidate in self.candidate_secret_mappings
            ],
            "rejected_secret_patterns": [
                pattern.to_dict() for pattern in self.rejected_secret_patterns
            ],
            "verification_commands": list(self.verification_commands),
            "risk_gates": list(self.risk_gates),
            "warnings": list(self.warnings),
        }


def build_key_vault_reuse_plan(
    *,
    source_vault_name: str = DEFAULT_SOURCE_VAULT_NAME,
    target_vault_name: str = DEFAULT_TARGET_VAULT_NAME,
) -> KeyVaultReusePlan:
    warnings = _validate_vault_names(
        source_vault_name=source_vault_name,
        target_vault_name=target_vault_name,
    )
    command_source_vault_name = source_vault_name or DEFAULT_SOURCE_VAULT_NAME
    command_target_vault_name = (
        target_vault_name
        if target_vault_name == DEFAULT_TARGET_VAULT_NAME and "onmu" not in target_vault_name.lower()
        else DEFAULT_TARGET_VAULT_NAME
    )

    return KeyVaultReusePlan(
        source_vault_name=source_vault_name,
        target_vault_name=target_vault_name,
        candidate_secret_mappings=(
            KeyVaultReuseCandidate(
                source_secret_name="int-cors-origins",
                target_secret_name="cors-allow-origins",
                action="copy_after_owner_approval",
                approval_required=True,
                secret_sensitive=True,
                validation="Compare hashes or rerun browser CORS smoke without printing the value.",
                notes=(
                    "This is the only current ONMU-to-LALA reuse candidate.",
                    "It is environment configuration for browser CORS, not a credential for DB, OAuth, storage, or upstream APIs.",
                    "The copied value must live in the LALA-next vault; LALA runtime must not point at the ONMU vault.",
                ),
            ),
        ),
        rejected_secret_patterns=(
            RejectedSecretPattern(
                pattern="db, database, postgres, dsn",
                reason="ONMU database targets and schemas are not LALA canonical DB rollout inputs.",
            ),
            RejectedSecretPattern(
                pattern="oauth, oidc, client-secret, social-provider",
                reason="LALA identity rollout needs its own approved Entra/OAuth configuration and Flutter public client.",
            ),
            RejectedSecretPattern(
                pattern="minio, storage, blob, redis, cache",
                reason="These belong to ONMU runtime ownership and should not be cross-wired into LALA-next.",
            ),
            RejectedSecretPattern(
                pattern="api-key, bearer-token, webhook, shared-access-key",
                reason="Client and integration credentials must be issued for LALA-next, not borrowed from ONMU.",
            ),
            RejectedSecretPattern(
                pattern="azure-openai, speech, cognitive-services",
                reason="LALA-next already has dedicated Azure OpenAI and Speech resources.",
            ),
        ),
        verification_commands=(
            _cmd(
                "az",
                "keyvault",
                "secret",
                "list",
                "--vault-name",
                command_source_vault_name,
                "--query",
                "[].name",
                "-o",
                "table",
            ),
            "manual: after approval, copy int-cors-origins to cors-allow-origins without printing the value",
            _cmd("scripts/unix/verify_azure_resources.sh"),
            _cmd(
                "scripts/unix/smoke_api.sh",
                "--base-url",
                "http://127.0.0.1:8080",
                "--cors-origin",
                "http://localhost:3000",
            ),
        ),
        risk_gates=(
            f"Target vault must stay {DEFAULT_TARGET_VAULT_NAME}; do not set KEY_VAULT_URL to the ONMU vault.",
            "This plan does not read, print, copy, or set any secret values.",
            "Copy only the approved CORS origin list unless a new owner-approved mapping is added with tests and docs.",
            "Do not reuse ONMU DB, OAuth, social-provider, storage, Redis, API token, OpenAI, or Speech secrets.",
            "After copying any value, verify by secret-name presence, hash comparison, or runtime smoke without exposing the value.",
        ),
        warnings=tuple(warnings),
    )


def _cmd(*parts: str) -> str:
    return " ".join(shlex.quote(part) for part in parts)


def _validate_vault_names(*, source_vault_name: str, target_vault_name: str) -> list[str]:
    warnings: list[str] = []
    if not source_vault_name:
        warnings.append("Source vault name is required for the reuse review.")
    if source_vault_name and "onmu" not in source_vault_name.lower():
        warnings.append("Source vault is expected to be the ONMU vault for this review.")
    if target_vault_name != DEFAULT_TARGET_VAULT_NAME:
        warnings.append("Target vault must be the LALA-next Key Vault by default.")
    if "onmu" in target_vault_name.lower():
        warnings.append("ONMU Key Vault must not be the LALA-next runtime target.")
    if source_vault_name and source_vault_name == target_vault_name:
        warnings.append("Source and target vault names must be different.")
    return warnings
