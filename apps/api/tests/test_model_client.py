from __future__ import annotations

from types import SimpleNamespace

import pytest

from apps.api.app.core.config import Settings
from apps.api.app.core.readiness import build_readiness
from apps.api.app.services import ai_service, model_client, rag_index, review_attribute_batch
from apps.api.app.tools import enrich_place_ai_columns


def _offline_settings(**overrides: object) -> SimpleNamespace:
    values = {
        "openai_api_key": "",
        "openai_base_url": "https://api.openai.com/v1",
        "enable_live_ai": False,
        "openai_review_batch_model": "",
        "openai_review_recheck_model": "",
        "openai_docent_model": "",
        "openai_place_enrichment_model": "",
        "openai_embedding_model": "",
        "model_role_overrides": {},
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def test_resolve_defaults_are_the_standard_openai_role_policy_without_a_key():
    settings = _offline_settings()

    resolved = {item.role: item for item in model_client.resolve_all(settings)}

    assert {role: item.model_id for role, item in resolved.items()} == {
        "review_bulk": "gpt-5.4-nano",
        "review_recheck": "gpt-5.4-mini",
        "docent": "gpt-5.4-mini",
        "docent_qa": "gpt-5.4-mini",
        "place_enrichment": "gpt-5.4-mini",
        "embedding": "text-embedding-3-small",
    }
    assert all(item.provider == "openai" and item.client == "OpenAI" for item in resolved.values())


def test_legacy_openai_model_fields_remain_compatible():
    settings = _offline_settings(
        openai_review_batch_model="legacy-bulk",
        openai_review_recheck_model="legacy-recheck",
        openai_docent_model="legacy-docent",
        openai_place_enrichment_model="legacy-place",
        openai_embedding_model="legacy-embedding",
    )

    assert model_client.resolve("review_bulk", settings).model_id == "legacy-bulk"
    assert model_client.resolve("review_recheck", settings).model_id == "legacy-recheck"
    assert model_client.resolve("docent", settings).model_id == "legacy-docent"
    assert model_client.resolve("docent_qa", settings).model_id == "legacy-docent"
    assert model_client.resolve("place_enrichment", settings).model_id == "legacy-place"
    assert model_client.resolve("embedding", settings).model_id == "legacy-embedding"


@pytest.mark.parametrize(
    ("role", "legacy_field"),
    [
        ("review_bulk", "openai_review_batch_model"),
        ("review_recheck", "openai_review_recheck_model"),
        ("docent", "openai_docent_model"),
        ("docent_qa", "openai_docent_model"),
        ("place_enrichment", "openai_place_enrichment_model"),
        ("embedding", "openai_embedding_model"),
    ],
)
def test_each_canonical_role_env_override_precedes_legacy_input(
    monkeypatch, role: str, legacy_field: str
):
    override = f"override-{role}"
    monkeypatch.setenv(f"LALA_MODEL_ROLE_{role.upper()}", override)
    settings = _offline_settings(**{legacy_field: f"legacy-{role}"})

    assert model_client.resolve(role, settings).model_id == override


def test_settings_capture_only_non_secret_role_overrides(monkeypatch):
    monkeypatch.setenv("LALA_MODEL_ROLE_DOCENT", "env-docent")
    monkeypatch.setenv("OPENAI_DOCENT_MODEL", "legacy-docent")

    settings = Settings.from_env()

    assert settings.model_role_overrides == {"docent": "env-docent"}
    assert model_client.resolve("docent", settings).model_id == "env-docent"


def test_planning_role_aliases_resolve_to_canonical_roles():
    settings = _offline_settings()

    assert model_client.resolve("review_extract", settings).role == "review_bulk"
    assert model_client.resolve("recheck_low_conf", settings).role == "review_recheck"
    assert model_client.resolve("docent_generate", settings).role == "docent"
    assert model_client.resolve("embed", settings).role == "embedding"


def test_resolve_rejects_azure_url_for_every_role_without_a_live_call():
    settings = _offline_settings(openai_base_url="https://tenant.openai.azure.com/openai/v1")

    for role in model_client.MODEL_ROLES:
        with pytest.raises(ValueError, match="Azure OpenAI base URLs are not supported"):
            model_client.resolve(role, settings)


def test_existing_model_selectors_are_thin_router_callers():
    settings = _offline_settings(
        model_role_overrides={
            "docent": "router-docent",
            "review_bulk": "router-bulk",
            "review_recheck": "router-recheck",
            "place_enrichment": "router-place",
            "embedding": "router-embedding",
        }
    )

    assert ai_service.selected_docent_model(settings) == "router-docent"
    assert review_attribute_batch.selected_review_batch_model(settings) == "router-bulk"
    assert review_attribute_batch.selected_review_recheck_model(settings) == "router-recheck"
    assert enrich_place_ai_columns.selected_place_enrichment_model(settings) == "router-place"
    assert model_client.resolve("embedding", settings).model_id == "router-embedding"
    assert (
        rag_index.settings_openai_embedding_model_name()
        == model_client.resolve("embedding").model_id
    )


def test_readiness_exposes_only_safe_model_role_metadata_offline():
    readiness = build_readiness(
        Settings(
            openai_api_key="",
            openai_base_url="https://api.openai.com/v1",
            enable_live_ai=False,
        )
    )

    roles = readiness["model_roles"]["roles"]
    assert readiness["model_roles"]["status"] == "configured"
    assert {item["role"] for item in roles} == set(model_client.MODEL_ROLES)
    assert all(item["provider"] == "openai" for item in roles)
    assert all(item["client"] == "OpenAI" for item in roles)


def test_readiness_marks_azure_model_route_invalid_without_echoing_the_url():
    readiness = build_readiness(
        Settings(
            openai_base_url="https://tenant.openai.azure.com/openai/v1",
            enable_live_ai=False,
        )
    )

    assert readiness["model_roles"]["status"] == "invalid"
    assert "Azure OpenAI base URLs are not supported" in readiness["model_roles"]["error"]
    assert "tenant.openai.azure.com" not in readiness["model_roles"]["error"]
