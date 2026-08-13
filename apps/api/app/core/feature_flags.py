"""Central registry for clean-room rollout flags.

The registry is deliberately additive: resolving the registry does not enable a
new behavior. Feature consumers can opt into a named flag in a later slice,
while an absent environment variable keeps today's behavior.
"""

from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass

FeatureFlagValue = bool | int | str


@dataclass(frozen=True)
class FeatureFlag:
    """A non-secret, typed rollout control and its current fallback contract."""

    key: str
    env_name: str
    default: FeatureFlagValue
    current_behavior: str
    owner_slice: str
    description: str
    allowed_values: tuple[str, ...] | None = None


def _flag(
    key: str,
    default: FeatureFlagValue,
    current_behavior: str,
    owner_slice: str,
    description: str,
    *,
    env_name: str | None = None,
    allowed_values: tuple[str, ...] | None = None,
) -> FeatureFlag:
    return FeatureFlag(
        key=key,
        env_name=env_name or f"LALA_{key}",
        default=default,
        current_behavior=current_behavior,
        owner_slice=owner_slice,
        description=description,
        allowed_values=allowed_values,
    )


# This list is the single namespace for the flags named by §5.x of the
# execution program. Keep a new flag here before a wave consumer is added.
FEATURE_FLAG_REGISTRY: tuple[FeatureFlag, ...] = (
    _flag(
        "REGION_SIGUN_RESOLUTION",
        False,
        "province-level resolution",
        "W1-a",
        "Resolve a region to province plus city/county.",
    ),
    _flag(
        "WEATHER_EXPLICIT_FLAGS",
        False,
        "legacy weather summary",
        "W1-b",
        "Emit the explicit weather alert-vector fields.",
    ),
    _flag(
        "WEATHER_OPEN_METEO_FALLBACK",
        False,
        "current weather source chain",
        "W1-c",
        "Allow Open-Meteo as the documented fallback tier.",
    ),
    _flag(
        "PLACE_OPEN_HOURS",
        False,
        "legacy operating-state behavior",
        "W1-d",
        "Use place operating-hours predicates for slot eligibility.",
    ),
    _flag(
        "PLACE_INDOOR_CLASSIFY",
        False,
        "current place enrichment",
        "W1-e",
        "Enable provenance-aware indoor/outdoor classification.",
    ),
    _flag(
        "REVIEW_QUARANTINE",
        False,
        "current governed review path",
        "W2-c",
        "Enable quarantine replay behavior for ambiguous review signals.",
    ),
    _flag(
        "REVIEW_AI_CLASSIFIER",
        False,
        "deterministic review classification",
        "W2-d",
        "Enable the bulk-lane AI ad classifier and attribute mirror.",
    ),
    _flag(
        "REVIEW_RECHECK",
        False,
        "current review path without selective recheck",
        "W2-e",
        "Enable selective mini rechecks for low-confidence review signals.",
    ),
    _flag(
        "LALA_ENABLE_LIVE_AI",
        False,
        "offline AI and deterministic fixtures",
        "W2-d",
        "Permit existing standard-OpenAI callers to make live AI requests.",
        env_name="LALA_ENABLE_LIVE_AI",
    ),
    _flag(
        "rag_embedding_method",
        "local-hash",
        "deterministic local-hash embeddings",
        "W3-a",
        "Select the configured serving embedding method.",
        env_name="LALA_RAG_EMBEDDING_METHOD",
        allowed_values=("local-hash", "openai"),
    ),
    _flag(
        "rag_embedding_generation",
        1,
        "embedding generation 1",
        "W3-a",
        "Identify the active embedding-generation contract.",
        env_name="LALA_RAG_EMBEDDING_GENERATION",
    ),
    _flag(
        "rag_retrieval_mode",
        "legacy",
        "legacy retrieval mode",
        "W3-b",
        "Select legacy or future hybrid retrieval behavior.",
        env_name="LALA_RAG_RETRIEVAL_MODE",
        allowed_values=("legacy", "hybrid"),
    ),
    _flag(
        "docent_inline_guards",
        False,
        "current docent response path",
        "W3-c",
        "Enable inline language, leakage, length, and filler guards.",
        env_name="LALA_DOCENT_INLINE_GUARDS",
    ),
    _flag(
        "docent_reason_enabled",
        False,
        "no on-demand docent reason route",
        "W3-d",
        "Enable the additive on-demand grounded reason contract.",
        env_name="LALA_DOCENT_REASON_ENABLED",
    ),
    _flag(
        "docent_audio_cache",
        False,
        "current docent audio path",
        "W3-e",
        "Enable the additive docent audio-cache contract.",
        env_name="LALA_DOCENT_AUDIO_CACHE",
    ),
    _flag(
        "LALA_ENABLE_LIVE_SPEECH",
        False,
        "no live Azure Speech requests",
        "W3-e",
        "Permit the existing optional Azure Speech TTS path.",
        env_name="LALA_ENABLE_LIVE_SPEECH",
    ),
    _flag(
        "docent_qa_judge",
        False,
        "deterministic docent QA precheck",
        "W3-f",
        "Reserve the rollout control for the future mini LLM QA judge.",
        env_name="LALA_DOCENT_QA_JUDGE",
    ),
    _flag(
        "PLAN_FULL_SLOTS",
        False,
        "current planner slot count",
        "W4-a",
        "Enable the full timed-slot planner.",
    ),
    _flag(
        "PLAN_WEATHER_SUBSTITUTE",
        False,
        "current planner without weather substitution",
        "W4-b",
        "Enable indoor/outdoor weather-aware substitutions.",
    ),
    _flag(
        "PLACES_VIEWPORT_BOUNDS",
        False,
        "circle-based places query",
        "W5-a",
        "Enable optional viewport-bounds place queries.",
    ),
    _flag(
        "PLACE_FACETS",
        False,
        "current place filters",
        "W5-c",
        "Enable cuisine, meal, diet, and indoor facets.",
    ),
    _flag(
        "LOCAL_TOUR",
        False,
        "no local restaurant tour surface",
        "W5-d",
        "Enable the local restaurant tour surface.",
    ),
    _flag(
        "PLACE_CONFIDENCE_SURFACE",
        False,
        "current place response metadata",
        "W5-e",
        "Expose honest place confidence and missing-signal metadata.",
    ),
    _flag(
        "RECOMMENDATION_FEEDBACK",
        False,
        "no recommendation feedback writes",
        "W5-f",
        "Enable aggregate-only anonymous recommendation feedback.",
    ),
    _flag(
        "MAP_FUNNEL_METRICS",
        False,
        "current metrics surface",
        "W6-c",
        "Enable privacy-safe region-level funnel metrics.",
    ),
    _flag(
        "LOCAL_SIGNALS_READ",
        False,
        "no Local Signals read surface",
        "LS-2",
        "Enable the published, approved, public Local Signals read API.",
    ),
    _flag(
        "LOCAL_SIGNALS_WRITE",
        False,
        "no Local Signals write surface",
        "LS-2",
        "Enable the Logto-authenticated Local Signals draft and policy write API.",
    ),
    _flag(
        "LALA_ENABLE_LIVE_ROUTING",
        False,
        "Haversine walk-time estimate only",
        "V5-C",
        "Permit the routing seam; real Kakao/Naver Directions remain BLOCKED_EXTERNAL/V7.",
        env_name="LALA_ENABLE_LIVE_ROUTING",
    ),
)


def _registry_by_key() -> dict[str, FeatureFlag]:
    return {flag.key: flag for flag in FEATURE_FLAG_REGISTRY}


def _parse_value(flag: FeatureFlag, raw_value: str) -> FeatureFlagValue:
    raw = raw_value.strip()
    if isinstance(flag.default, bool):
        normalized = raw.lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off"}:
            return False
        raise ValueError(f"Invalid boolean feature flag value for {flag.env_name}.")
    if isinstance(flag.default, int):
        try:
            parsed = int(raw)
        except ValueError as exc:
            raise ValueError(f"Invalid integer feature flag value for {flag.env_name}.") from exc
        if parsed < 0:
            raise ValueError(f"Feature flag value for {flag.env_name} must be non-negative.")
        return parsed
    normalized = raw.lower()
    if flag.allowed_values is not None and normalized not in flag.allowed_values:
        allowed = ", ".join(flag.allowed_values)
        raise ValueError(f"Invalid value for {flag.env_name}; expected one of: {allowed}.")
    return normalized


def default_feature_flag_values() -> dict[str, FeatureFlagValue]:
    """Return a copy of the no-op values for every registered flag."""

    return {flag.key: flag.default for flag in FEATURE_FLAG_REGISTRY}


def resolve_feature_flags(
    environ: Mapping[str, str] | None = None,
) -> dict[str, FeatureFlagValue]:
    """Resolve only registered, non-secret flag inputs.

    The function is deterministic with an empty mapping and never creates a
    provider client or performs an external request.
    """

    source = os.environ if environ is None else environ
    return {
        flag.key: (
            _parse_value(flag, raw_value)
            if (raw_value := source.get(flag.env_name)) not in (None, "")
            else flag.default
        )
        for flag in FEATURE_FLAG_REGISTRY
    }


FeatureFlagMetadataValue = FeatureFlagValue | tuple[str, ...] | None


def feature_flag_metadata() -> tuple[dict[str, FeatureFlagMetadataValue], ...]:
    """Return safe registry metadata for diagnostics and future readiness use."""

    return tuple(
        {
            "key": flag.key,
            "env_name": flag.env_name,
            "default": flag.default,
            "current_behavior": flag.current_behavior,
            "owner_slice": flag.owner_slice,
            "description": flag.description,
            "allowed_values": flag.allowed_values,
        }
        for flag in FEATURE_FLAG_REGISTRY
    )


def feature_flag(key: str) -> FeatureFlag:
    """Look up one registered flag without exposing environment values."""

    try:
        return _registry_by_key()[key]
    except KeyError as exc:
        raise KeyError(f"Unknown feature flag: {key}") from exc
