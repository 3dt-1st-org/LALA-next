from urllib.parse import urlsplit

import pytest

from scripts import local_dev


def test_local_runner_ignores_inherited_cloud_and_database_settings(monkeypatch, tmp_path):
    monkeypatch.setenv("DB_DSN", "postgresql://invalid@remote.invalid/production")
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "not-a-real-key")
    monkeypatch.setenv("LALA_LOCAL_USE_AWS_SECRETS", "true")  # pragma: allowlist secret
    monkeypatch.setenv("LALA_ENABLE_LIVE_AI", "true")
    monkeypatch.setenv("KEY_VAULT_URL", "https://invalid.example")
    monkeypatch.setattr(local_dev, "STATE", tmp_path)
    monkeypatch.setattr(local_dev, "CONFIG", tmp_path / "database.json")
    env = local_dev.database_env(create=True)
    assert urlsplit(env["DB_DSN"]).hostname == "127.0.0.1"
    assert urlsplit(env["DB_DSN"]).port == 55433
    assert "AWS_ACCESS_KEY_ID" not in env
    assert "KEY_VAULT_URL" not in env
    assert env["LALA_LOCAL_USE_AWS_SECRETS"] == "false"  # pragma: allowlist secret
    assert env["LALA_ENABLE_LIVE_AI"] == "false"
    assert local_dev.database_env()["DB_DSN"] == env["DB_DSN"]


def test_local_runner_rejects_tampered_credentials_before_starting(monkeypatch, tmp_path):
    monkeypatch.setattr(local_dev, "STATE", tmp_path)
    monkeypatch.setattr(local_dev, "CONFIG", tmp_path / "database.json")
    local_dev.CONFIG.write_text('{"password": "@remote.invalid/production"}', encoding="utf-8")
    with pytest.raises(RuntimeError, match="Invalid local credential"):
        local_dev.database_env()
