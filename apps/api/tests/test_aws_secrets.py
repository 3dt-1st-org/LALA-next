from __future__ import annotations

import json

import pytest

from apps.api.app.core import aws_secrets, config


def test_get_aws_sm_secret_returns_value(monkeypatch):
    """boto3 client가 정상 응답하면 secret 문자열을 반환."""
    calls = {}

    class FakeClient:
        def get_secret_value(self, SecretId):
            calls["SecretId"] = SecretId
            return {"SecretString": "super-secret-value"}

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())
    aws_secrets.get_aws_sm_secret.cache_clear() if hasattr(
        aws_secrets.get_aws_sm_secret, "cache_clear"
    ) else None

    # 접두사 자동 부착 확인
    value = aws_secrets.get_aws_sm_secret("logto-management-client-secret")
    assert value == "super-secret-value"
    assert calls["SecretId"] == "lala-next/logto-management-client-secret"


def test_get_aws_sm_secret_returns_empty_when_no_client(monkeypatch):
    """boto3 미설치/권한 부족(_client가 None)이면 빈 문자열."""
    monkeypatch.setattr(aws_secrets, "_client", lambda: None)
    assert aws_secrets.get_aws_sm_secret("anything") == ""


def test_get_aws_sm_secret_returns_empty_on_exception(monkeypatch):
    """get_secret_value 예외(AccessDenied/ResourceNotFound) 시 빈 문자열."""

    class FakeClient:
        def get_secret_value(self, SecretId):
            raise Exception("AccessDenied")

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())
    assert aws_secrets.get_aws_sm_secret("missing") == ""


def test_get_aws_sm_secret_required_fails_closed_without_exposing_provider_error(monkeypatch):
    class FakeClient:
        def get_secret_value(self, SecretId):
            raise Exception("provider detail must not escape")

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())

    with pytest.raises(aws_secrets.AwsSecretLookupError) as exc_info:
        aws_secrets.get_aws_sm_secret("db-dsn", required=True)

    assert "db-dsn" in str(exc_info.value)
    assert "provider detail" not in str(exc_info.value)


def test_get_aws_sm_secret_respects_already_prefixed(monkeypatch):
    """'/' 가 포함된 secret_id는 접두사를 붙이지 않음."""
    captured = {}

    class FakeClient:
        def get_secret_value(self, SecretId):
            captured["id"] = SecretId
            return {"SecretString": "v"}

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())
    aws_secrets.get_aws_sm_secret("custom/prefix/secret")
    assert captured["id"] == "custom/prefix/secret"


def test_env_or_secret_prefers_aws_sm_over_key_vault(monkeypatch):
    """env 값이 없으면 AWS SM을 먼저 조회 (Azure Key Vault보다 우선)."""
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "local")
    monkeypatch.delenv("LOGTO_ENDPOINT", raising=False)
    monkeypatch.setenv("LALA_LOCAL_USE_AWS_SECRETS", "1")

    seen = {}

    def fake_aws(secret_id):
        seen["aws"] = secret_id
        return "from-aws-sm"

    monkeypatch.setattr(config, "get_secret_if_configured", lambda *a, **k: "from-azure-kv")
    monkeypatch.setattr("apps.api.app.core.aws_secrets.get_aws_sm_secret", fake_aws)

    result = config._env_or_secret("LOGTO_ENDPOINT", "logto-endpoint", "https://kv.vault.azure.net")
    assert result == "from-aws-sm"
    assert seen["aws"] == "logto-endpoint"


def test_env_or_secret_falls_back_to_key_vault_when_sm_empty(monkeypatch):
    """AWS SM이 빈 값을 주면 Azure Key Vault로 폴백."""
    monkeypatch.setenv("LALA_RUNTIME_PROFILE", "local")
    monkeypatch.delenv("OAUTH_CLIENT_ID", raising=False)
    monkeypatch.setenv("LALA_LOCAL_USE_AWS_SECRETS", "1")
    monkeypatch.setattr("apps.api.app.core.aws_secrets.get_aws_sm_secret", lambda sid: "")
    monkeypatch.setattr(config, "get_secret_if_configured", lambda url, name: "from-azure-kv")

    result = config._env_or_secret(
        "OAUTH_CLIENT_ID", "oauth-client-id", "https://kv.vault.azure.net"
    )
    assert result == "from-azure-kv"


def test_structured_lookup_returns_found_for_valid_secret(monkeypatch):
    """Valid secret string returns found outcome with value."""

    class FakeClient:
        def get_secret_value(self, SecretId):
            return {"SecretString": "actual-secret-value"}  # pragma: allowlist secret

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())
    result = aws_secrets.get_aws_sm_secret_structured("valid-secret")

    assert result.outcome == "found"
    assert result.logical_name == "valid-secret"
    assert result.value == "actual-secret-value"


def test_structured_lookup_classifies_resource_not_found_as_missing(monkeypatch):
    """ResourceNotFoundException classified as missing outcome."""

    class ResourceNotFoundException(Exception):
        pass

    class FakeClient:
        def get_secret_value(self, SecretId):
            raise ResourceNotFoundException("ResourceNotFoundException")

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())
    result = aws_secrets.get_aws_sm_secret_structured("missing-secret")

    assert result.outcome == "missing"
    assert result.logical_name == "missing-secret"
    assert result.value == ""


def test_structured_lookup_classifies_not_found_as_missing(monkeypatch):
    """Generic 'not found' error classified as missing outcome."""

    class FakeClient:
        def get_secret_value(self, SecretId):
            raise Exception("Secret not found in secretsmanager")

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())
    result = aws_secrets.get_aws_sm_secret_structured("not-found-secret")

    assert result.outcome == "missing"


def test_structured_lookup_classifies_access_denied_as_denied(monkeypatch):
    """AccessDeniedException classified as denied outcome."""

    class AccessDeniedException(Exception):
        pass

    class FakeClient:
        def get_secret_value(self, SecretId):
            raise AccessDeniedException("AccessDenied")

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())
    result = aws_secrets.get_aws_sm_secret_structured("denied-secret")

    assert result.outcome == "denied"
    assert result.logical_name == "denied-secret"
    assert result.value == ""


def test_structured_lookup_classifies_access_denied_text_as_denied(monkeypatch):
    """Generic 'access denied' error classified as denied outcome."""

    class FakeClient:
        def get_secret_value(self, SecretId):
            raise Exception("User is not authorized to access this secret")

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())
    result = aws_secrets.get_aws_sm_secret_structured("unauthorized-secret")

    assert result.outcome == "denied"


def test_structured_lookup_classifies_unavailable_as_unavailable(monkeypatch):
    """Client unavailable classified as unavailable outcome."""
    monkeypatch.setattr(aws_secrets, "_client", lambda: None)
    result = aws_secrets.get_aws_sm_secret_structured("unavailable-secret")

    assert result.outcome == "unavailable"
    assert result.logical_name == "unavailable-secret"
    assert result.value == ""


def test_structured_lookup_classifies_transient_error_as_unavailable(monkeypatch):
    """Generic exceptions classified as unavailable outcome."""

    class FakeClient:
        def get_secret_value(self, SecretId):
            raise Exception("InternalFailure")

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())
    result = aws_secrets.get_aws_sm_secret_structured("transient-error-secret")

    assert result.outcome == "unavailable"


def test_structured_lookup_classifies_binary_secret_as_invalid(monkeypatch):
    """Binary secret (no SecretString) classified as invalid outcome."""

    class FakeClient:
        def get_secret_value(self, SecretId):
            return {"SecretBinary": b"binary-data"}

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())
    result = aws_secrets.get_aws_sm_secret_structured("binary-secret")

    assert result.outcome == "invalid"
    assert result.logical_name == "binary-secret"
    assert result.value == ""


def test_structured_lookup_classifies_empty_secret_as_invalid(monkeypatch):
    """Empty or whitespace-only secret classified as invalid outcome."""

    class FakeClient:
        def get_secret_value(self, SecretId):
            return {"SecretString": "   "}

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())
    result = aws_secrets.get_aws_sm_secret_structured("empty-secret")

    assert result.outcome == "invalid"
    assert result.logical_name == "empty-secret"


def test_structured_lookup_result_is_secret_safe():
    """Structured result never exposes provider text, ARNs, or resource identifiers."""
    result = aws_secrets.AwsSecretLookupResult(
        outcome="found", logical_name="db-dsn", value="secret-value"
    )

    encoded = json.dumps(result.to_dict() if hasattr(result, "to_dict") else result.__dict__)
    assert "arn:" not in encoded.lower()
    assert "account" not in encoded.lower()
    assert "resource" not in encoded.lower()
    assert "provider" not in encoded.lower()
    # But logical name and safe outcome should be present
    assert "db-dsn" in encoded
    assert "found" in encoded


def test_get_aws_sm_secret_required_raises_structured_error(monkeypatch):
    """required=True raises AwsSecretLookupError with safe message based on outcome."""

    class FakeClient:
        def get_secret_value(self, SecretId):
            raise Exception("AccessDenied")

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())

    with pytest.raises(aws_secrets.AwsSecretLookupError) as exc_info:
        aws_secrets.get_aws_sm_secret("db-dsn", required=True)

    assert "db-dsn" in str(exc_info.value)
    assert "AccessDenied" not in str(exc_info.value)
    assert "provider" not in str(exc_info.value).lower()


def test_get_aws_sm_secret_required_missing_raises_structured_error(monkeypatch):
    """required=True with ResourceNotFound raises safe missing error."""

    class ResourceNotFoundException(Exception):
        pass

    class FakeClient:
        def get_secret_value(self, SecretId):
            raise ResourceNotFoundException("ResourceNotFoundException")

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())

    with pytest.raises(aws_secrets.AwsSecretLookupError) as exc_info:
        aws_secrets.get_aws_sm_secret("openai-api-key", required=True)

    assert "openai-api-key" in str(exc_info.value)
    assert "not found" in str(exc_info.value).lower()
    assert "ResourceNotFoundException" not in str(exc_info.value)


def test_get_aws_sm_secret_required_unavailable_raises_structured_error(monkeypatch):
    """required=True with unavailable client raises safe unavailable error."""
    monkeypatch.setattr(aws_secrets, "_client", lambda: None)

    with pytest.raises(aws_secrets.AwsSecretLookupError) as exc_info:
        aws_secrets.get_aws_sm_secret("db-dsn", required=True)

    assert "db-dsn" in str(exc_info.value)
    assert "unavailable" in str(exc_info.value).lower()


def test_get_aws_sm_secret_required_invalid_raises_structured_error(monkeypatch):
    """required=True with invalid secret raises safe invalid error."""

    class FakeClient:
        def get_secret_value(self, SecretId):
            return {"SecretString": ""}

    monkeypatch.setattr(aws_secrets, "_client", lambda: FakeClient())

    with pytest.raises(aws_secrets.AwsSecretLookupError) as exc_info:
        aws_secrets.get_aws_sm_secret("db-dsn", required=True)

    assert "db-dsn" in str(exc_info.value)
    assert "invalid" in str(exc_info.value).lower()
