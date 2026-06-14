from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from apps.workers.app.contracts import (
    WorkerExecutionError,
    evaluate_worker_live_preflight,
    get_worker_job,
    list_worker_jobs,
    run_worker_job,
)
from apps.workers.app.rollout_plan import build_worker_rollout_plan

ROOT = Path(__file__).resolve().parents[3]


def test_worker_registry_defines_expected_boundaries():
    jobs = {job["job_id"]: job for job in list_worker_jobs()}

    assert set(jobs) == {
        "weather-refresh",
        "community-keyword-watchlist",
        "community-post-ingest",
        "ops-rollup",
    }
    assert jobs["weather-refresh"]["writes"] == ["travel.weather_observations"]
    assert "Azure Event Hub" in jobs["community-post-ingest"]["source_systems"]
    assert jobs["weather-refresh"]["retry_policy"]["max_attempts"] == 3
    assert "observed_at" in jobs["weather-refresh"]["idempotency_policy"]["key"]
    assert "dead-letter" in jobs["community-post-ingest"]["poison_policy"]["destination"]


def test_worker_registry_documents_retry_idempotency_and_poison_policies():
    for job in list_worker_jobs():
        assert job["retry_policy"]["max_attempts"] > 0
        assert job["retry_policy"]["backoff"]
        assert job["retry_policy"]["retryable_errors"]
        assert job["idempotency_policy"]["key"]
        assert job["idempotency_policy"]["conflict_strategy"]
        assert job["idempotency_policy"]["duplicate_window"]
        assert job["poison_policy"]["threshold"] == job["retry_policy"]["max_attempts"]
        assert job["poison_policy"]["destination"]
        assert job["poison_policy"]["operator_action"]


def test_worker_unknown_job_fails_with_known_ids():
    with pytest.raises(WorkerExecutionError) as exc_info:
        get_worker_job("missing-job")

    assert exc_info.value.code == "unknown_job"
    assert "weather-refresh" in exc_info.value.message


def test_worker_dry_runs_do_not_require_external_services(monkeypatch):
    marker = "postgresql://worker:super-secret@localhost/lala"
    monkeypatch.setenv("DB_DSN", marker)

    for job in list_worker_jobs():
        result = run_worker_job(job["job_id"], dry_run=True)
        encoded = json.dumps(result, ensure_ascii=False)

        assert result["ok"] is True
        assert result["mode"] == "dry_run"
        assert result["would_write"] == job["writes"]
        assert result["job"]["retry_policy"] == job["retry_policy"]
        assert result["job"]["idempotency_policy"] == job["idempotency_policy"]
        assert result["job"]["poison_policy"] == job["poison_policy"]
        assert marker not in encoded


def test_worker_execute_is_blocked_without_mutation_guard(monkeypatch):
    monkeypatch.delenv("ALLOW_WORKER_MUTATION", raising=False)

    with pytest.raises(WorkerExecutionError) as exc_info:
        run_worker_job("weather-refresh", dry_run=False)

    assert exc_info.value.code == "mutation_disabled"
    assert "ALLOW_WORKER_MUTATION" in exc_info.value.message


def test_worker_execute_is_not_implemented_even_with_guard(monkeypatch):
    monkeypatch.setenv("ALLOW_WORKER_MUTATION", "1")

    with pytest.raises(WorkerExecutionError) as exc_info:
        run_worker_job("weather-refresh", dry_run=False)

    assert exc_info.value.code == "not_implemented"


def test_worker_live_preflight_is_secret_safe_and_blocked_until_implemented():
    marker = "postgresql://worker:super-secret@localhost/lala"
    env = {
        "ALLOW_WORKER_MUTATION": "1",
        "DB_DSN": marker,
        "KEY_VAULT_URL": "https://lala-next-kv-27db5e.vault.azure.net/",
        "EVENT_HUB_NAMESPACE": "lala-next-dev-eventhub",
    }

    payload = evaluate_worker_live_preflight(environ=env)
    encoded = json.dumps(payload, ensure_ascii=False)

    assert payload["ok"] is True
    assert payload["mode"] == "live_preflight"
    assert payload["ready"] is False
    assert payload["missing_dependencies"] == []
    assert payload["jobs"][0]["ready"] is False
    assert "live_implementation_missing" in payload["jobs"][0]["blockers"]
    assert marker not in encoded
    assert "super-secret" not in encoded


def test_worker_live_preflight_reports_missing_dependencies_without_values():
    payload = evaluate_worker_live_preflight(environ={})

    assert payload["ready"] is False
    assert "DB_DSN" in payload["missing_dependencies"]
    assert "KEY_VAULT_URL" in payload["missing_dependencies"]
    ingest = next(job for job in payload["jobs"] if job["job_id"] == "community-post-ingest")
    assert "missing_dependency:EVENT_HUB_NAMESPACE" in ingest["blockers"]


def test_worker_cli_list_and_run_json_are_secret_safe():
    marker = "postgresql://worker:super-secret@localhost/lala"
    env = os.environ.copy()
    env["DB_DSN"] = marker

    list_result = subprocess.run(
        [sys.executable, "-m", "apps.workers.app.cli", "list", "--json"],
        cwd=ROOT,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )
    list_payload = json.loads(list_result.stdout)
    assert list_payload["ok"] is True
    assert marker not in list_result.stdout

    run_result = subprocess.run(
        [
            sys.executable,
            "-m",
            "apps.workers.app.cli",
            "run",
            "weather-refresh",
            "--dry-run",
            "--json",
        ],
        cwd=ROOT,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )
    run_payload = json.loads(run_result.stdout)
    assert run_payload["ok"] is True
    assert run_payload["mode"] == "dry_run"
    assert marker not in run_result.stdout


def test_worker_cli_execute_returns_structured_error():
    env = os.environ.copy()
    env.pop("ALLOW_WORKER_MUTATION", None)

    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "apps.workers.app.cli",
            "run",
            "weather-refresh",
            "--execute",
            "--json",
        ],
        cwd=ROOT,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 2
    payload = json.loads(result.stdout)
    assert payload["ok"] is False
    assert payload["error"]["code"] == "mutation_disabled"


def test_worker_cli_preflight_json_is_secret_safe_and_does_not_enable_live_execution():
    marker = "postgresql://worker:super-secret@localhost/lala"
    env = os.environ.copy()
    env["ALLOW_WORKER_MUTATION"] = "1"
    env["DB_DSN"] = marker
    env["KEY_VAULT_URL"] = "https://lala-next-kv-27db5e.vault.azure.net/"
    env["EVENT_HUB_NAMESPACE"] = "lala-next-dev-eventhub"

    result = subprocess.run(
        [sys.executable, "-m", "apps.workers.app.cli", "preflight", "--json"],
        cwd=ROOT,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )

    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert payload["mode"] == "live_preflight"
    assert payload["ready"] is False
    assert marker not in result.stdout
    assert "live_implementation_missing" in result.stdout


def test_worker_rollout_plan_is_secret_safe_and_non_mutating():
    plan = build_worker_rollout_plan()
    payload = plan.to_dict()
    encoded = json.dumps(payload, ensure_ascii=False)

    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["applies_changes"] is False
    assert payload["key_vault_name"] == "lala-next-kv-27db5e"
    assert payload["function_app_name"] == "lala-next-workers-dev"
    assert payload["storage_account_name"] == "lalanextworker27db5e"
    assert "db-dsn" in payload["key_vault_secret_names"]
    assert len(payload["worker_jobs"]) == len(list_worker_jobs())
    assert any(step["approval_required"] for step in payload["steps"])
    assert any("smoke_workers.sh" in step["command"] for step in payload["steps"])
    assert any("verify_db_resources.sh" in step["command"] for step in payload["steps"])

    assert "onmu-dev-kv" not in encoded
    assert "postgresql://user:" not in encoded
    assert "password=" not in encoded.lower()
    assert "AccountKey=" not in encoded
    assert "Endpoint=sb://" not in encoded


def test_worker_rollout_plan_rejects_onmu_vault_and_bad_resource_names():
    plan = build_worker_rollout_plan(
        key_vault_name="onmu-dev-kv-27db5e",
        function_app_name="bad app!",
        storage_account_name="bad-storage-name",
        event_hub_namespace="bad namespace!",
        event_hub_name="bad event!",
    )

    assert plan.ok is False
    assert len(plan.warnings) >= 5
    assert any("ONMU" in warning for warning in plan.warnings)
    assert all("onmu-dev-kv" not in step.command for step in plan.steps)


def test_worker_cli_plan_rollout_json_is_secret_safe_and_non_mutating():
    result = subprocess.run(
        [sys.executable, "-m", "apps.workers.app.cli", "plan-rollout", "--json"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )

    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["applies_changes"] is False
    assert payload["worker_jobs"]
    assert "worker-storage-account" in result.stdout
    assert "onmu-dev-kv" not in result.stdout
    assert "postgresql://user:" not in result.stdout
    assert "password=" not in result.stdout.lower()
    assert "AccountKey=" not in result.stdout
