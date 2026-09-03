from __future__ import annotations

import json

import pytest

from apps.api.app.core import aws_secrets, runtime_secrets
from apps.api.app.core.config import Settings
from apps.api.app.core.runtime_secrets import RuntimeSecretContractError


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
    monkeypatch.setattr(
        aws_secrets,
        "get_aws_sm_secret_structured",
        lambda *args, **kwargs: pytest.fail("AWS called for a supplied placeholder"),
    )

    with pytest.raises(runtime_secrets.RuntimeSecretContractError) as exc_info:
        runtime_secrets.validate_secret_contract("api", values)

    assert "DB_DSN" in str(exc_info.value)
    assert "<secret>" not in str(exc_info.value)


def test_api_settings_fail_closed_without_required_aws_contract(monkeypatch):
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")
    monkeypatch.delenv("LALA_GUEST_ACCESS", raising=False)
    monkeypatch.delenv("LALA_PUBLIC_CONTEST_ACCESS", raising=False)
    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret", lambda *args, **kwargs: "")
    monkeypatch.setattr(
        aws_secrets,
        "get_aws_sm_secret_structured",
        lambda secret_id: aws_secrets.AwsSecretLookupResult(
            outcome="missing", logical_name=secret_id
        ),
    )

    with pytest.raises(runtime_secrets.RuntimeSecretContractError) as exc_info:
        Settings.from_env()

    message = str(exc_info.value)
    assert "DB_DSN" in message
    assert "API_BEARER_TOKEN" in message
    assert "<secret>" not in message


def test_runtime_status_is_safe_metadata_only():
    status = runtime_secrets.SecretContractStatus(
        "api", "error", ("DB_DSN",), (), ("DB_DSN",), (), (), ()
    )
    encoded = json.dumps(status.to_dict())

    assert set(status.to_dict()) == {
        "profile",
        "status",
        "required_names",
        "configured_names",
        "missing_names",
        "denied_names",
        "unavailable_names",
        "invalid_names",
    }
    assert "value" not in encoded.lower()


def test_api_profile_does_not_load_dotenv(monkeypatch):
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")
    called = []
    monkeypatch.setattr("dotenv.load_dotenv", lambda *args, **kwargs: called.append(True))

    runtime_secrets.load_runtime_environment()

    assert called == []


def test_validate_contract_classifies_missing_secrets(monkeypatch):
    """Missing secrets (ResourceNotFound) are classified separately."""
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")

    # Simulate missing secret in AWS
    def mock_structured_lookup(secret_id):
        return aws_secrets.AwsSecretLookupResult(outcome="missing", logical_name=secret_id)

    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret_structured", mock_structured_lookup)

    values = {"db_dsn": "", "ios_api_key": "valid-key"}  # pragma: allowlist secret
    with pytest.raises(RuntimeSecretContractError) as exc_info:
        runtime_secrets.validate_secret_contract("api", values)

    message = str(exc_info.value)
    assert "missing" in message.lower()
    assert "DB_DSN" in message


def test_validate_contract_classifies_denied_secrets(monkeypatch):
    """Denied secrets (AccessDenied) are classified separately."""
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")

    # Simulate denied secret in AWS
    def mock_structured_lookup(secret_id):
        return aws_secrets.AwsSecretLookupResult(outcome="denied", logical_name=secret_id)

    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret_structured", mock_structured_lookup)

    values = {"db_dsn": "", "ios_api_key": "valid-key"}  # pragma: allowlist secret
    with pytest.raises(RuntimeSecretContractError) as exc_info:
        runtime_secrets.validate_secret_contract("api", values)

    message = str(exc_info.value)
    assert "denied" in message.lower()
    assert "DB_DSN" in message


def test_validate_contract_classifies_unavailable_secrets(monkeypatch):
    """Unavailable secrets (transient failures) are classified separately."""
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")

    # Simulate unavailable secret in AWS
    def mock_structured_lookup(secret_id):
        return aws_secrets.AwsSecretLookupResult(outcome="unavailable", logical_name=secret_id)

    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret_structured", mock_structured_lookup)

    values = {"db_dsn": "", "ios_api_key": "valid-key"}  # pragma: allowlist secret
    with pytest.raises(RuntimeSecretContractError) as exc_info:
        runtime_secrets.validate_secret_contract("api", values)

    message = str(exc_info.value)
    assert "unavailable" in message.lower()
    assert "DB_DSN" in message


def test_validate_contract_classifies_invalid_secrets(monkeypatch):
    """Invalid secrets (empty/binary) are classified separately."""
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")

    # Simulate invalid secret in AWS
    def mock_structured_lookup(secret_id):
        return aws_secrets.AwsSecretLookupResult(outcome="invalid", logical_name=secret_id)

    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret_structured", mock_structured_lookup)

    values = {"db_dsn": "", "ios_api_key": "valid-key"}  # pragma: allowlist secret
    with pytest.raises(RuntimeSecretContractError) as exc_info:
        runtime_secrets.validate_secret_contract("api", values)

    message = str(exc_info.value)
    assert "invalid" in message.lower()
    assert "DB_DSN" in message


def test_validate_contract_allows_found_secrets(monkeypatch):
    """Found secrets pass validation."""
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")

    # Simulate found secret in AWS
    def mock_structured_lookup(secret_id):
        return aws_secrets.AwsSecretLookupResult(
            outcome="found",
            logical_name=secret_id,
            value="actual-secret",  # pragma: allowlist secret
        )

    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret_structured", mock_structured_lookup)

    values = {"db_dsn": "actual-secret", "ios_api_key": "valid-key"}  # pragma: allowlist secret
    status = runtime_secrets.validate_secret_contract("api", values)

    assert status.status == "ok"
    assert "DB_DSN" in status.configured_names


def test_validate_contract_mixed_outcome_classification(monkeypatch):
    """Multiple secrets with different outcomes are all classified."""
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")

    def mock_structured_lookup(secret_id):
        outcomes = {
            "db-dsn": "missing",
            "openai-api-key": "denied",
            "azure-speech-key": "unavailable",
            "azure-speech-region": "invalid",
        }
        return aws_secrets.AwsSecretLookupResult(
            outcome=outcomes.get(secret_id, "found"),
            logical_name=secret_id,
        )

    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret_structured", mock_structured_lookup)

    values = {
        "db_dsn": "",
        "openai_api_key": "",
        "azure_speech_key": "",
        "azure_speech_region": "",
        "enable_live_ai": True,
        "enable_live_speech": True,
        "ios_api_key": "valid-key",  # pragma: allowlist secret
    }

    with pytest.raises(RuntimeSecretContractError) as exc_info:
        runtime_secrets.validate_secret_contract("api", values)

    message = str(exc_info.value)
    assert "missing" in message
    assert "denied" in message
    assert "unavailable" in message
    assert "invalid" in message


def test_validate_contract_status_includes_all_outcome_categories(monkeypatch):
    """SecretContractStatus includes denied, unavailable, and invalid categories."""
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")

    def mock_structured_lookup(secret_id):
        return aws_secrets.AwsSecretLookupResult(
            outcome="found",
            logical_name=secret_id,
            value="secret-value",  # pragma: allowlist secret
        )

    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret_structured", mock_structured_lookup)

    values = {"db_dsn": "secret-value", "ios_api_key": "valid-key"}  # pragma: allowlist secret
    status = runtime_secrets.validate_secret_contract("api", values)

    status_dict = status.to_dict()
    assert "denied_names" in status_dict
    assert "unavailable_names" in status_dict
    assert "invalid_names" in status_dict
    assert status_dict["denied_names"] == []
    assert status_dict["unavailable_names"] == []
    assert status_dict["invalid_names"] == []


def test_validate_contract_local_profile_returns_not_required(monkeypatch):
    """Local profile returns not_required status without AWS checks."""
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "local")

    values = {"db_dsn": "", "ios_api_key": ""}
    status = runtime_secrets.validate_secret_contract("local", values)

    assert status.status == "not_required"
    assert status.profile == "local"


def test_validate_contract_ci_profile_returns_not_required(monkeypatch):
    """CI profile returns not_required status without AWS checks."""
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "ci")

    values = {"db_dsn": "", "ios_api_key": ""}
    status = runtime_secrets.validate_secret_contract("ci", values)

    assert status.status == "not_required"
    assert status.profile == "ci"


def test_validate_contract_worker_profile_includes_job_specific_secrets(monkeypatch):
    """Worker profile includes job-specific required secrets."""
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "worker")

    def mock_structured_lookup(secret_id):
        if secret_id == "public-data-service-key":
            return aws_secrets.AwsSecretLookupResult(
                outcome="found",
                logical_name=secret_id,
                value="api-key",  # pragma: allowlist secret
            )
        return aws_secrets.AwsSecretLookupResult(
            outcome="found",
            logical_name=secret_id,
            value="secret-value",  # pragma: allowlist secret
        )

    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret_structured", mock_structured_lookup)

    values = {
        "db_dsn": "secret-value",  # pragma: allowlist secret
        "public_data_service_key": "api-key",  # pragma: allowlist secret
    }

    status = runtime_secrets.validate_secret_contract(
        "worker", values, worker_job_id="weather-refresh"
    )

    assert status.status == "ok"
    assert "DB_DSN" in status.required_names
    assert "PUBLIC_DATA_SERVICE_KEY" in status.required_names


def test_validate_contract_secret_safe_status_dict(monkeypatch):
    """Status dict never exposes secret values or provider details."""
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "api")

    def mock_structured_lookup(secret_id):
        return aws_secrets.AwsSecretLookupResult(
            outcome="found",
            logical_name=secret_id,
            value="super-secret-value",  # pragma: allowlist secret
        )

    monkeypatch.setattr(aws_secrets, "get_aws_sm_secret_structured", mock_structured_lookup)

    values = {
        "db_dsn": "super-secret-value",  # pragma: allowlist secret
        "ios_api_key": "valid-key",  # pragma: allowlist secret
    }
    status = runtime_secrets.validate_secret_contract("api", values)

    encoded = json.dumps(status.to_dict())
    assert "super-secret-value" not in encoded
    assert "arn:" not in encoded.lower()
    assert "provider" not in encoded.lower()
    # But safe metadata should be present
    assert "DB_DSN" in encoded
    assert "ok" in encoded
