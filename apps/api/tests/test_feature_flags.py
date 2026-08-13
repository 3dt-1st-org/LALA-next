from __future__ import annotations

import pytest

from apps.api.app.core.config import Settings
from apps.api.app.core.feature_flags import (
    FEATURE_FLAG_REGISTRY,
    default_feature_flag_values,
    feature_flag,
    feature_flag_metadata,
    resolve_feature_flags,
)

EXPECTED_KEYS = {
    "REGION_SIGUN_RESOLUTION",
    "WEATHER_EXPLICIT_FLAGS",
    "WEATHER_OPEN_METEO_FALLBACK",
    "PLACE_OPEN_HOURS",
    "PLACE_INDOOR_CLASSIFY",
    "REVIEW_QUARANTINE",
    "REVIEW_AI_CLASSIFIER",
    "REVIEW_RECHECK",
    "LALA_ENABLE_LIVE_AI",
    "rag_embedding_method",
    "rag_embedding_generation",
    "rag_retrieval_mode",
    "docent_inline_guards",
    "docent_reason_enabled",
    "docent_audio_cache",
    "LALA_ENABLE_LIVE_SPEECH",
    "LALA_ENABLE_LIVE_ROUTING",
    "docent_qa_judge",
    "PLAN_FULL_SLOTS",
    "PLAN_WEATHER_SUBSTITUTE",
    "PLACES_VIEWPORT_BOUNDS",
    "PLACE_FACETS",
    "LOCAL_TOUR",
    "PLACE_CONFIDENCE_SURFACE",
    "RECOMMENDATION_FEEDBACK",
    "MAP_FUNNEL_METRICS",
    "LOCAL_SIGNALS_READ",
    "LOCAL_SIGNALS_WRITE",
}


def test_registry_has_one_documented_namespace_for_every_program_flag():
    keys = {flag.key for flag in FEATURE_FLAG_REGISTRY}
    env_names = [flag.env_name for flag in FEATURE_FLAG_REGISTRY]

    assert keys == EXPECTED_KEYS
    assert len(env_names) == len(set(env_names))
    assert all(flag.default is not None for flag in FEATURE_FLAG_REGISTRY)

    metadata = feature_flag_metadata()
    assert {item["key"] for item in metadata} == EXPECTED_KEYS
    assert all(item["env_name"].startswith("LALA_") for item in metadata)
    assert feature_flag("rag_embedding_method").allowed_values == ("local-hash", "openai")
    assert feature_flag("rag_retrieval_mode").allowed_values == ("legacy", "hybrid")


def test_empty_environment_is_a_noop_default_contract():
    resolved = resolve_feature_flags({})

    assert resolved == default_feature_flag_values()
    assert resolved["LALA_ENABLE_LIVE_AI"] is False
    assert resolved["LALA_ENABLE_LIVE_SPEECH"] is False
    assert resolved["LOCAL_SIGNALS_READ"] is False
    assert resolved["LOCAL_SIGNALS_WRITE"] is False
    assert resolved["rag_embedding_method"] == "local-hash"
    assert resolved["rag_retrieval_mode"] == "legacy"
    assert Settings(feature_flags=resolved).feature_flags == resolved


@pytest.mark.parametrize("flag", FEATURE_FLAG_REGISTRY)
def test_every_registered_flag_accepts_only_its_canonical_env_input(flag):
    if isinstance(flag.default, bool):
        raw_value = "true"
        expected = True
    elif isinstance(flag.default, int):
        raw_value = str(flag.default + 1)
        expected = flag.default + 1
    else:
        raw_value = flag.allowed_values[0] if flag.allowed_values else "registry-test"
        expected = raw_value

    resolved = resolve_feature_flags({flag.env_name: raw_value})

    assert resolved[flag.key] == expected


@pytest.mark.parametrize(
    ("key", "raw_value", "expected"),
    [
        ("REGION_SIGUN_RESOLUTION", "true", True),
        ("WEATHER_EXPLICIT_FLAGS", "1", True),
        ("PLACE_OPEN_HOURS", "off", False),
        ("LALA_ENABLE_LIVE_AI", "yes", True),
        ("rag_embedding_method", "OPENAI", "openai"),
        ("rag_embedding_generation", "7", 7),
        ("rag_retrieval_mode", "HYBRID", "hybrid"),
        ("docent_qa_judge", "true", True),
        ("MAP_FUNNEL_METRICS", "on", True),
        ("LOCAL_SIGNALS_READ", "true", True),
        ("LOCAL_SIGNALS_WRITE", "1", True),
    ],
)
def test_registered_env_override_is_typed_and_scoped(key, raw_value, expected):
    flag = feature_flag(key)

    resolved = resolve_feature_flags({flag.env_name: raw_value})

    assert resolved[key] == expected
    for other_key, default in default_feature_flag_values().items():
        if other_key != key:
            assert resolved[other_key] == default


@pytest.mark.parametrize(
    ("key", "raw_value"),
    [
        ("REGION_SIGUN_RESOLUTION", "sometimes"),
        ("rag_embedding_generation", "not-an-int"),
        ("rag_embedding_generation", "-1"),
    ],
)
def test_invalid_registered_env_override_fails_closed(key, raw_value):
    flag = feature_flag(key)

    with pytest.raises(ValueError, match=flag.env_name):
        resolve_feature_flags({flag.env_name: raw_value})


@pytest.mark.parametrize(
    ("key", "raw_value"),
    [
        ("rag_embedding_method", "sentence-transformers"),
        ("rag_retrieval_mode", "semantic"),
    ],
)
def test_unknown_string_enum_fails_closed_with_env_name(key, raw_value):
    flag = feature_flag(key)

    with pytest.raises(ValueError, match=flag.env_name):
        resolve_feature_flags({flag.env_name: raw_value})


@pytest.mark.parametrize(
    ("key", "raw_value", "expected"),
    [
        ("rag_embedding_method", "LoCaL-HaSh", "local-hash"),
        ("rag_retrieval_mode", "HyBrId", "hybrid"),
    ],
)
def test_string_enum_normalizes_before_validation(key, raw_value, expected):
    flag = feature_flag(key)

    assert resolve_feature_flags({flag.env_name: raw_value})[key] == expected


def test_settings_reads_registry_without_changing_existing_defaults(monkeypatch):
    monkeypatch.delenv("LALA_ENABLE_LIVE_AI", raising=False)
    monkeypatch.delenv("LALA_ENABLE_LIVE_SPEECH", raising=False)
    monkeypatch.delenv("LALA_RAG_EMBEDDING_METHOD", raising=False)
    monkeypatch.delenv("LALA_RAG_RETRIEVAL_MODE", raising=False)

    settings = Settings.from_env()

    assert settings.enable_live_ai is False
    assert settings.enable_live_speech is False
    assert settings.rag_embedding_method == "local-hash"
    assert settings.rag_retrieval_mode == "legacy"
    assert settings.feature_flags == default_feature_flag_values()


def test_registry_table_is_present_in_execution_program():
    from pathlib import Path

    root = Path(__file__).resolve().parents[3]
    text = (root / "docs/planning/cleanroom-reimplementation-execution-program.md").read_text(
        encoding="utf-8"
    )

    for flag in FEATURE_FLAG_REGISTRY:
        assert f"`{flag.key}`" in text
        assert f"`{flag.env_name}`" in text
