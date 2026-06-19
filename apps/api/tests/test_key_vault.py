from __future__ import annotations

import logging

from apps.api.app.core import key_vault


def test_key_vault_does_not_cache_empty_secret(monkeypatch):
    vault_url = "https://example-lala-vault.vault.azure.net/"
    values = iter(("", "public-data-secret"))

    key_vault._get_cached_non_empty_secret.cache_clear()
    monkeypatch.setattr(key_vault, "_get_secret_with_sdk", lambda *_args: next(values))
    monkeypatch.setattr(key_vault, "_get_secret_with_azure_cli", lambda *_args: "")

    assert key_vault.get_secret_if_configured(vault_url, "public-data-service-key") == ""
    assert (
        key_vault.get_secret_if_configured(vault_url, "public-data-service-key")
        == "public-data-secret"
    )


def test_key_vault_caches_non_empty_secret(monkeypatch):
    vault_url = "https://example-lala-vault.vault.azure.net/"
    calls = {"sdk": 0}

    def fake_sdk(*_args: object) -> str:
        calls["sdk"] += 1
        return "cached-secret"

    key_vault._get_cached_non_empty_secret.cache_clear()
    monkeypatch.setattr(key_vault, "_get_secret_with_sdk", fake_sdk)
    monkeypatch.setattr(key_vault, "_get_secret_with_azure_cli", lambda *_args: "")

    assert key_vault.get_secret_if_configured(vault_url, "db-dsn") == "cached-secret"
    assert key_vault.get_secret_if_configured(vault_url, "db-dsn") == "cached-secret"
    assert calls["sdk"] == 1


def test_key_vault_suppresses_azure_sdk_request_logging():
    http_logger = logging.getLogger("azure.core.pipeline.policies.http_logging_policy")
    identity_logger = logging.getLogger("azure.identity")
    previous_http_level = http_logger.level
    previous_identity_level = identity_logger.level
    try:
        http_logger.setLevel(logging.NOTSET)
        identity_logger.setLevel(logging.NOTSET)

        key_vault._suppress_azure_sdk_request_logging()

        assert http_logger.level == logging.WARNING
        assert identity_logger.level == logging.WARNING
    finally:
        http_logger.setLevel(previous_http_level)
        identity_logger.setLevel(previous_identity_level)
