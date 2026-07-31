from __future__ import annotations

import json

import pytest

from apps.api.app.core import aws_secrets, runtime_secrets
from apps.api.app.core.config import Settings


def test_secret_registry_has_one_stable_mapping_per_runtime_secret():
    mapping = {item.env_name: item.secret_name for item in runtime_secrets.SECRET_REGISTRY}

    assert mapping["DB_DSN"] == "db-dsn"
    assert mapping["OPENAI_API_KEY"] == "openai-api-key"  # pragma: allowlist secret
    expected_management_secret = "logto-management-client-secret"  # pragma: allowlist secret
    assert mapping["LOGTO_MANAGEMENT_CLIENT_SECRET"] == expected_management_secret
    assert len(mapping) == len(runtime_secrets.SECRET_REGISTRY)


def test_ci_profile_reads_process_env_without_aws_or_dotenv(monkeypatch):
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "ci")
    monkeypatch.setenv("DB_DSN", "ci-fixture-dsn")
    monkeypatch.setattr(
        aws_secrets, "get_aws_sm_secret", lambda *args, **kwargs: pytest.fail("AWS called")
    )

    assert runtime_secrets.resolve_runtime_secret("DB_DSN", "db-dsn") == "ci-fixture-dsn"


def test_operational_profile_ignores_process_secret_and_requires_aws(monkeypatch):
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")
    monkeypatch.setenv("DB_DSN", "process-fixture-dsn")
    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret", lambda *args, **kwargs: "")

    with pytest.raises(runtime_secrets.RuntimeSecretLookupError) as exc_info:
        runtime_secrets.resolve_runtime_secret("DB_DSN", "db-dsn", required=True)

    assert "DB_DSN" not in str(exc_info.value)
    assert "db-dsn" in str(exc_info.value)
    assert "process-fixture-dsn" not in str(exc_info.value)


def test_operational_profile_rejects_placeholder_secret(monkeypatch):
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")
    values = {"db_dsn": "<secret>", "guest_access": True}

    with pytest.raises(runtime_secrets.RuntimeSecretContractError) as exc_info:
        runtime_secrets.validate_secret_contract("api", values)

    assert "DB_DSN" in str(exc_info.value)
    assert "<secret>" not in str(exc_info.value)


def test_api_settings_fail_closed_without_required_aws_contract(monkeypatch):
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")
    monkeypatch.delenv("LALA_GUEST_ACCESS", raising=False)
    monkeypatch.delenv("LALA_PUBLIC_CONTEST_ACCESS", raising=False)
    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret", lambda *args, **kwargs: "")

    with pytest.raises(runtime_secrets.RuntimeSecretContractError) as exc_info:
        Settings.from_env()

    message = str(exc_info.value)
    assert "DB_DSN" in message
    assert "API_BEARER_TOKEN" in message
    assert "<secret>" not in message


def test_runtime_status_is_safe_metadata_only():
    status = runtime_secrets.SecretContractStatus("api", "error", ("DB_DSN",), (), ("DB_DSN",))
    encoded = json.dumps(status.to_dict())

    assert set(status.to_dict()) == {
        "profile",
        "status",
        "required_names",
        "configured_names",
        "missing_names",
    }
    assert "value" not in encoded.lower()


def test_api_profile_does_not_load_dotenv(monkeypatch):
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")
    called = []
    monkeypatch.setattr("dotenv.load_dotenv", lambda *args, **kwargs: called.append(True))

    runtime_secrets.load_runtime_environment()

    assert called == []
