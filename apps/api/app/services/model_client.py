"""Pure model-role resolution for the standard OpenAI lanes.

This module deliberately contains no OpenAI SDK import and never constructs a
provider client.  Callers use the returned metadata to build a client only at
the live-call boundary.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, Literal

from apps.api.app.core.config import get_settings, resolve_openai_base_url_host

ModelRole = Literal[
    "review_bulk",
    "review_recheck",
    "docent",
    "docent_qa",
    "place_enrichment",
    "embedding",
]

MODEL_ROLES: tuple[ModelRole, ...] = (
    "review_bulk",
    "review_recheck",
    "docent",
    "docent_qa",
    "place_enrichment",
    "embedding",
)

MODEL_ROLE_DEFAULTS: dict[ModelRole, str] = {
    "review_bulk": "gpt-5.4-nano",
    "review_recheck": "gpt-5.4-mini",
    "docent": "gpt-5.4-mini",
    "docent_qa": "gpt-5.4-mini",
    "place_enrichment": "gpt-5.4-mini",
    "embedding": "text-embedding-3-small",
}

_LEGACY_ROLE_ALIASES: dict[str, ModelRole] = {
    "review_extract": "review_bulk",
    "recheck_low_conf": "review_recheck",
    "docent_generate": "docent",
    "embed": "embedding",
}

_LEGACY_SETTINGS_FIELDS: dict[ModelRole, str] = {
    "review_bulk": "openai_review_batch_model",
    "review_recheck": "openai_review_recheck_model",
    "docent": "openai_docent_model",
    "docent_qa": "openai_docent_model",
    "place_enrichment": "openai_place_enrichment_model",
    "embedding": "openai_embedding_model",
}


@dataclass(frozen=True)
class ResolvedModel:
    """Safe model metadata; ``client`` is a kind label, not an SDK instance."""

    role: ModelRole
    provider: Literal["openai"]
    model_id: str
    client: Literal["OpenAI"] = "OpenAI"

    def as_metadata(self) -> dict[str, str]:
        return {
            "role": self.role,
            "provider": self.provider,
            "model_id": self.model_id,
            "client": self.client,
        }


def resolve(role: str, settings: Any | None = None) -> ResolvedModel:
    """Resolve a logical role without creating a provider client or making a call.

    ``LALA_MODEL_ROLE_<ROLE>`` is the highest-precedence, non-secret override.
    Existing ``OPENAI_*_MODEL`` settings remain the compatibility layer before
    the policy defaults.  Azure OpenAI base URLs are rejected for every role,
    including offline resolution, so a caller cannot accidentally hide a bad
    route behind ``LALA_ENABLE_LIVE_AI=false``.
    """

    canonical_role = _canonical_role(role)
    settings = settings or get_settings()
    resolve_openai_base_url_host(getattr(settings, "openai_base_url", ""))
    model_id = _override_from_env(canonical_role)
    if not model_id:
        model_id = _override_from_settings(canonical_role, settings)
    if not model_id:
        model_id = MODEL_ROLE_DEFAULTS[canonical_role]
    return ResolvedModel(
        role=canonical_role,
        provider="openai",
        model_id=model_id,
    )


def resolve_all(settings: Any | None = None) -> tuple[ResolvedModel, ...]:
    """Resolve every supported role for safe readiness/operator metadata."""

    return tuple(resolve(role, settings) for role in MODEL_ROLES)


def _canonical_role(role: str) -> ModelRole:
    normalized = str(role or "").strip().lower()
    normalized = _LEGACY_ROLE_ALIASES.get(normalized, normalized)
    if normalized not in MODEL_ROLES:
        expected = ", ".join(MODEL_ROLES)
        raise ValueError(f"Unsupported model role {role!r}; expected one of {expected}.")
    return normalized  # type: ignore[return-value]


def _override_from_env(role: ModelRole) -> str:
    value = (os.getenv(f"LALA_MODEL_ROLE_{role.upper()}") or "").strip()
    if value:
        return value
    # Keep the role names used in the planning contract as harmless aliases.
    for alias, canonical in _LEGACY_ROLE_ALIASES.items():
        if canonical == role:
            value = (os.getenv(f"LALA_MODEL_ROLE_{alias.upper()}") or "").strip()
            if value:
                return value
    return ""


def _override_from_settings(role: ModelRole, settings: Any) -> str:
    overrides = getattr(settings, "model_role_overrides", None)
    if isinstance(overrides, dict):
        for key in (role, *_aliases_for(role)):
            value = str(overrides.get(key) or "").strip()
            if value:
                return value
    legacy_field = _LEGACY_SETTINGS_FIELDS[role]
    return str(getattr(settings, legacy_field, "") or "").strip()


def _aliases_for(role: ModelRole) -> tuple[str, ...]:
    return tuple(alias for alias, canonical in _LEGACY_ROLE_ALIASES.items() if canonical == role)
