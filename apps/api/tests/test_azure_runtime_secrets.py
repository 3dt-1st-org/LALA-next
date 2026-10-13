from __future__ import annotations

from types import SimpleNamespace

import pytest

from apps.api.app.core import aws_secrets, azure_runtime_secrets, runtime_secrets


@pytest.fixture(autouse=True)
def isolate_azure_cache():
    azure_runtime_secrets._cache.clear()
    clear_client_cache = azure_runtime_secrets._client.cache_clear
    clear_client_cache()
    yield
    azure_runtime_secrets._cache.clear()
    clear_client_cache()


def azure_env():
    return {
        "LALA_RUNTIME_PROFILE": "api",
        "LALA_SECRET_BACKEND": "azure",  # pragma: allowlist secret (provider selector)
        "KEY_VAULT_URL": "https://lala-fixture.vault.azure.net",
        "LALA_ALLOWED_KEY_VAULT_HOSTS": "lala-fixture.vault.azure.net",
    }


def test_backend_defaults_to_aws_and_rejects_unknown_value():
    assert runtime_secrets.get_runtime_secret_backend({}) == "aws"
    with pytest.raises(runtime_secrets.RuntimeSecretContractError):
        runtime_secrets.get_runtime_secret_backend(
            {"LALA_SECRET_BACKEND": "unknown"}  # pragma: allowlist secret (provider selector)
        )


@pytest.mark.parametrize("profile", ["api", "worker"])
def test_azure_uses_only_selected_backend_and_ignores_process_value(monkeypatch, profile):
    env = azure_env() | {"DB_DSN": "process-value", "LALA_RUNTIME_PROFILE": profile}
    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret", lambda *a, **k: pytest.fail("AWS"))
    monkeypatch.setattr(
        azure_runtime_secrets,
        "_client",
        lambda *a: SimpleNamespace(get_secret=lambda *a, **k: SimpleNamespace(value="fixture")),
    )
    assert runtime_secrets.resolve_runtime_secret("DB_DSN", "db-dsn", environ=env) == "fixture"


@pytest.mark.parametrize(
    "status,outcome",
    [
        (404, "missing"),
        (403, "denied"),
        (401, "denied"),
        (429, "unavailable"),
        (500, "unavailable"),
    ],
)
def test_azure_failure_is_classified_without_value_or_provider_error(monkeypatch, status, outcome):
    class ProviderError(Exception):
        status_code = status

    def fail(*a, **k):
        raise ProviderError("sensitive-provider-error")

    monkeypatch.setattr(
        azure_runtime_secrets, "_client", lambda *a: SimpleNamespace(get_secret=fail)
    )
    result = azure_runtime_secrets.get_azure_runtime_secret_structured(
        "db-dsn", environ=azure_env()
    )
    assert result.outcome == outcome
    assert "sensitive" not in repr(result)
    with pytest.raises(runtime_secrets.RuntimeSecretLookupError) as exc:
        runtime_secrets.resolve_runtime_secret(
            "DB_DSN", "db-dsn", environ=azure_env(), required=True
        )
    assert "sensitive" not in str(exc.value)


@pytest.mark.parametrize(
    "url",
    [
        "http://lala-fixture.vault.azure.net",
        "https://onmu-fixture.vault.azure.net",
        "https://lala-fixture.vault.azure.net/path",
        "https://lala-fixture.vault.azure.net?x=1",
        "https://lala-fixture.vault.azure.net#x",
        "https://user@lala-fixture.vault.azure.net",
        "https://lala-fixture.vault.azure.net:443",
        "https://other.vault.azure.net",
        "https://lala-fixture.vault.azure.net:bad",
    ],
)
def test_azure_rejects_disallowed_urls_before_client_creation(monkeypatch, url):
    monkeypatch.setattr(azure_runtime_secrets, "_client", lambda *a: pytest.fail("client created"))
    result = azure_runtime_secrets.get_azure_runtime_secret_structured(
        "db-dsn", environ=azure_env() | {"KEY_VAULT_URL": url}
    )
    assert result.outcome == "invalid"


def test_missing_allowlist_is_invalid(monkeypatch):
    env = azure_env()
    env.pop("LALA_ALLOWED_KEY_VAULT_HOSTS")
    monkeypatch.setattr(azure_runtime_secrets, "_client", lambda *a: pytest.fail("client created"))
    assert (
        azure_runtime_secrets.get_azure_runtime_secret_structured("db-dsn", environ=env).outcome
        == "invalid"
    )


@pytest.mark.parametrize("value", ["", " ", None, b"binary"])
def test_invalid_secret_values(monkeypatch, value):
    monkeypatch.setattr(
        azure_runtime_secrets,
        "_client",
        lambda *a: SimpleNamespace(get_secret=lambda *a, **k: SimpleNamespace(value=value)),
    )
    assert (
        azure_runtime_secrets.get_azure_runtime_secret_structured(
            "db-dsn", environ=azure_env()
        ).outcome
        == "invalid"
    )


def test_contract_failure_uses_azure_classification_without_aws(monkeypatch):
    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret_structured", lambda *a: pytest.fail("AWS"))
    monkeypatch.setattr(
        azure_runtime_secrets,
        "get_azure_runtime_secret_structured",
        lambda name, **k: azure_runtime_secrets.AzureSecretLookupResult("denied", name),
    )
    with pytest.raises(runtime_secrets.RuntimeSecretContractError, match="denied: DB_DSN"):
        runtime_secrets.validate_secret_contract("api", {"guest_access": True}, environ=azure_env())


def test_secret_repr_and_dict_exclude_values():
    result = azure_runtime_secrets.AzureSecretLookupResult("found", "db-dsn", "private-fixture")
    assert "private-fixture" not in repr(result)
    assert "private-fixture" not in str(result.to_dict())


def test_ci_profile_does_not_call_azure(monkeypatch):
    monkeypatch.setattr(azure_runtime_secrets, "_client", lambda *a: pytest.fail("Azure"))
    env = azure_env() | {"LALA_RUNTIME_PROFILE": "ci", "DB_DSN": "ci-fixture"}
    assert runtime_secrets.resolve_runtime_secret("DB_DSN", "db-dsn", environ=env) == "ci-fixture"


@pytest.mark.parametrize("profile", ["api", "worker"])
def test_azure_failure_never_falls_back_to_aws_env_or_local_loader(monkeypatch, profile):
    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret", lambda *a, **k: pytest.fail("AWS"))
    monkeypatch.setattr(
        azure_runtime_secrets,
        "_lookup",
        lambda *a: azure_runtime_secrets.AzureSecretLookupResult("denied", "db-dsn"),
    )
    env = azure_env() | {"LALA_RUNTIME_PROFILE": profile, "DB_DSN": "process-private-value"}
    with pytest.raises(runtime_secrets.RuntimeSecretLookupError):
        runtime_secrets.resolve_runtime_secret(
            "DB_DSN",
            "db-dsn",
            environ=env,
            required=True,
            key_vault_loader=lambda *a: pytest.fail("local loader"),
        )


def test_cache_expires_and_never_serves_stale_success_after_failure(monkeypatch):
    clock = [100.0]
    calls = []
    responses = [
        azure_runtime_secrets.AzureSecretLookupResult("found", "db-dsn", "first-value"),
        azure_runtime_secrets.AzureSecretLookupResult("denied", "db-dsn"),
        azure_runtime_secrets.AzureSecretLookupResult("found", "db-dsn", "rotated-value"),
    ]

    def lookup(*args):
        calls.append(args)
        return responses.pop(0)

    monkeypatch.setattr(azure_runtime_secrets, "monotonic", lambda: clock[0])
    monkeypatch.setattr(azure_runtime_secrets, "_lookup", lookup)

    def get():
        return azure_runtime_secrets.get_azure_runtime_secret_structured(
            "db-dsn", environ=azure_env()
        )

    assert get().value == "first-value"
    assert get().value == "first-value"
    assert len(calls) == 1
    clock[0] += 301
    assert get().outcome == "denied"
    assert get().value == ""
    assert len(calls) == 2
    clock[0] += 16
    assert get().value == "rotated-value"


def test_cache_isolates_vault_identity_and_secret(monkeypatch):
    calls = []

    def lookup(*args):
        calls.append(args)
        return azure_runtime_secrets.AzureSecretLookupResult("found", args[2], "fixture")

    monkeypatch.setattr(azure_runtime_secrets, "_lookup", lookup)
    env = azure_env()
    for overrides, name in [
        ({}, "db-dsn"),
        ({"AZURE_CLIENT_ID": "other-identity"}, "db-dsn"),
        (
            {
                "KEY_VAULT_URL": "https://lala-second.vault.azure.net",
                "LALA_ALLOWED_KEY_VAULT_HOSTS": "lala-second.vault.azure.net",
            },
            "db-dsn",
        ),
        ({}, "oauth-issuer"),
    ]:
        azure_runtime_secrets.get_azure_runtime_secret_structured(name, environ=env | overrides)
    assert len(calls) == 4
    env["LALA_ALLOWED_KEY_VAULT_HOSTS"] = ""
    assert (
        azure_runtime_secrets.get_azure_runtime_secret_structured("db-dsn", environ=env).outcome
        == "invalid"
    )
    assert len(calls) == 4


def test_managed_identity_client_does_not_use_developer_credential_chain(monkeypatch):
    import azure.identity
    import azure.keyvault.secrets

    calls = []
    monkeypatch.setattr(
        azure.identity, "DefaultAzureCredential", lambda **k: pytest.fail("developer chain")
    )
    monkeypatch.setattr(
        azure.identity, "ManagedIdentityCredential", lambda **k: calls.append(k) or "credential"
    )
    monkeypatch.setattr(
        azure.keyvault.secrets, "SecretClient", lambda **k: calls.append(k) or "client"
    )
    assert (
        azure_runtime_secrets._client("https://fixture.vault.azure.net", "identity-id") == "client"
    )
    assert calls[0]["client_id"] == "identity-id"
    assert calls[1]["credential"] == "credential"
    assert calls[1]["logging_enable"] is False
    assert calls[1]["retry_total"] == 1


def test_full_settings_load_azure_auth_contract_and_cache_optional_misses(monkeypatch):
    from apps.api.app.core.config import Settings

    for name, value in azure_env().items():
        monkeypatch.setenv(name, value)
    monkeypatch.setenv("DB_DSN", "ignored-process-dsn")
    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret", lambda *a, **k: pytest.fail("AWS"))
    monkeypatch.setattr("dotenv.load_dotenv", lambda **k: pytest.fail("dotenv"))
    fixtures = {
        "db-dsn": "fixture-dsn",
        "oauth-issuer": "https://auth.example.test",
        "oauth-audience": "https://api.example.test",
        "oauth-jwks-url": "https://auth.example.test/jwks",
    }
    calls = []

    def lookup(vault, identity, name):
        calls.append(name)
        value = fixtures.get(name, "")
        return azure_runtime_secrets.AzureSecretLookupResult(
            "found" if value else "missing", name, value
        )

    monkeypatch.setattr(azure_runtime_secrets, "_lookup", lookup)
    settings = Settings.from_env()
    count = len(calls)
    assert settings.secret_contract.status == "ok"
    assert settings.db_dsn == "fixture-dsn"
    assert settings.oauth_issuer == fixtures["oauth-issuer"]
    assert not settings.enable_live_ai
    assert not settings.enable_live_speech
    Settings.from_env()
    assert len(calls) == count


def test_placeholder_returned_by_provider_fails_contract(monkeypatch):
    monkeypatch.setattr(
        azure_runtime_secrets,
        "_lookup",
        lambda *a: azure_runtime_secrets.AzureSecretLookupResult("found", "db-dsn", "placeholder"),
    )
    with pytest.raises(runtime_secrets.RuntimeSecretContractError, match="invalid: DB_DSN"):
        runtime_secrets.validate_secret_contract("api", {"guest_access": True}, environ=azure_env())
