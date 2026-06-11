from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from apps.api.app.main import create_app


@pytest.fixture()
def client() -> TestClient:
    return TestClient(create_app())


@pytest.fixture(autouse=True)
def isolate_db_env(monkeypatch) -> None:
    monkeypatch.delenv("DB_DSN", raising=False)
    for name in (
        "LALA_ENABLE_LIVE_AI",
        "AZURE_OPENAI_ENDPOINT",
        "AZURE_OPENAI_KEY",
        "AZURE_OPENAI_DEPLOYMENT",
        "AZURE_OPENAI_API_VERSION",
        "LALA_ENABLE_LIVE_SPEECH",
        "AZURE_SPEECH_REGION",
        "AZURE_SPEECH_KEY",
        "AZURE_SPEECH_ENDPOINT",
    ):
        monkeypatch.delenv(name, raising=False)


@pytest.fixture()
def api_key(monkeypatch) -> str:
    key = "test-client-key"
    monkeypatch.setenv("IOS_API_KEY", key)
    return key


@pytest.fixture()
def auth_headers(api_key: str) -> dict[str, str]:
    return {"X-API-Key": api_key}
