from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from apps.workers.app.contracts import (
    WorkerExecutionError,
    get_worker_job,
    list_worker_jobs,
    run_worker_job,
)

ROOT = Path(__file__).resolve().parents[3]


def test_worker_registry_defines_expected_boundaries():
    jobs = {job["job_id"]: job for job in list_worker_jobs()}

    assert set(jobs) == {
        "weather-refresh",
        "daangn-weekly-keywords",
        "daangn-community-ingest",
        "monitoring-rollup",
    }
    assert jobs["weather-refresh"]["writes"] == ["locallink.realtime_weather_conditions"]
    assert "Azure Event Hub" in jobs["daangn-community-ingest"]["source_systems"]


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
