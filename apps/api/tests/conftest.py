from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from apps.api.app.main import create_app


@pytest.fixture()
def client() -> TestClient:
    return TestClient(create_app())


@pytest.fixture()
def api_key(monkeypatch) -> str:
    key = "test-client-key"
    monkeypatch.setenv("IOS_API_KEY", key)
    return key


@pytest.fixture()
def auth_headers(api_key: str) -> dict[str, str]:
    return {"X-API-Key": api_key}

