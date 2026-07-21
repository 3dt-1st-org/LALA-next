from __future__ import annotations

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
    monkeypatch.delenv("LOGTO_ENDPOINT", raising=False)

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
    monkeypatch.delenv("OAUTH_CLIENT_ID", raising=False)
    monkeypatch.setattr("apps.api.app.core.aws_secrets.get_aws_sm_secret", lambda sid: "")
    monkeypatch.setattr(config, "get_secret_if_configured", lambda url, name: "from-azure-kv")

    result = config._env_or_secret(
        "OAUTH_CLIENT_ID", "oauth-client-id", "https://kv.vault.azure.net"
    )
    assert result == "from-azure-kv"
