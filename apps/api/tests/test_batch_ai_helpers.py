from __future__ import annotations

from datetime import UTC, datetime
from types import SimpleNamespace

from apps.api.app.services import batch_ai, weather_observation_refresh
from apps.api.app.tools import batch_helpers


def test_batch_ai_retry_uses_status_code_and_backoff():
    calls = {"count": 0}
    sleeps: list[float] = []

    class RetryableError(Exception):
        status_code = 503

    class FakeCompletions:
        def create(self, **kwargs):
            calls["count"] += 1
            if calls["count"] == 1:
                raise RetryableError("temporarily unavailable")
            return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content="{}"))])

    client = SimpleNamespace(chat=SimpleNamespace(completions=FakeCompletions()))

    response = batch_ai.create_chat_completion_with_retry(
        client=client,
        model="test-model",
        messages=[],
        retry_attempts=2,
        retry_delay_sec=0.25,
        sleep=sleeps.append,
    )

    assert response.choices[0].message.content == "{}"
    assert calls["count"] == 2
    assert sleeps == [0.25]


def test_batch_ai_non_retryable_error_raises_without_sleep():
    sleeps: list[float] = []

    class FakeCompletions:
        def create(self, **kwargs):
            raise RuntimeError("bad request")

    client = SimpleNamespace(chat=SimpleNamespace(completions=FakeCompletions()))

    try:
        batch_ai.create_chat_completion_with_retry(
            client=client,
            model="test-model",
            messages=[],
            retry_attempts=3,
            retry_delay_sec=1,
            sleep=sleeps.append,
        )
    except RuntimeError as exc:
        assert str(exc) == "bad request"
    else:
        raise AssertionError("expected RuntimeError")

    assert sleeps == []


def test_apply_guard_error_uses_explicit_confirm_and_allow_env(monkeypatch):
    args = SimpleNamespace(confirm="GO")
    monkeypatch.delenv("ALLOW_TEST_APPLY", raising=False)

    assert (
        batch_helpers.apply_guard_error(
            args,
            confirm_text="GO",
            allow_env="ALLOW_TEST_APPLY",
        )
        == "--apply requires ALLOW_TEST_APPLY=1 in the process environment."
    )

    args.confirm = "STOP"
    monkeypatch.setenv("ALLOW_TEST_APPLY", "1")
    assert (
        batch_helpers.apply_guard_error(
            args,
            confirm_text="GO",
            allow_env="ALLOW_TEST_APPLY",
        )
        == "--apply requires --confirm GO."
    )


def test_env_or_secret_preserves_runtime_profile_and_key_vault_loader(monkeypatch):
    calls: list[tuple] = []

    monkeypatch.setenv("KEY_VAULT_URL", " https://kv.example ")
    monkeypatch.setattr(batch_helpers, "get_runtime_profile", lambda: "worker")

    def fake_resolve_runtime_secret(env_name, secret_name, *, key_vault_loader, required):
        calls.append((env_name, secret_name, required))
        return key_vault_loader("ignored", secret_name)

    def fake_get_secret_if_configured(key_vault_url, name):
        calls.append((key_vault_url, name))
        return "secret-value"

    monkeypatch.setattr(batch_helpers, "resolve_runtime_secret", fake_resolve_runtime_secret)
    monkeypatch.setattr(batch_helpers, "get_secret_if_configured", fake_get_secret_if_configured)

    assert batch_helpers.env_or_secret("DB_DSN", "db-dsn") == "secret-value"
    assert calls == [
        ("DB_DSN", "db-dsn", True),
        ("https://kv.example", "db-dsn"),
    ]


def test_weather_record_job_run_delegates_to_shared_job_runs(monkeypatch):
    recorded: list[dict] = []
    started_at = datetime(2026, 9, 16, 1, 2, tzinfo=UTC)
    finished_at = datetime(2026, 9, 16, 1, 3, tzinfo=UTC)

    monkeypatch.setattr(
        weather_observation_refresh, "_record_job_run", lambda **kw: recorded.append(kw)
    )

    weather_observation_refresh.record_job_run(
        dsn="postgresql://example",
        job_name="weather-refresh",
        status="succeeded",
        started_at=started_at,
        finished_at=finished_at,
        duration_ms=60000,
        error_message=None,
        connect_timeout=5,
    )

    assert recorded == [
        {
            "dsn": "postgresql://example",
            "job_name": "weather-refresh",
            "status": "succeeded",
            "started_at": started_at,
            "finished_at": finished_at,
            "duration_ms": 60000,
            "error_message": None,
            "connect_timeout": 5,
        }
    ]
