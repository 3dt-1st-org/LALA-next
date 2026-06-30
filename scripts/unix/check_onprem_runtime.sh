#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PUBLIC_URL="https://api.lala-next.cloud"
LOCAL_URL="http://127.0.0.1:8080"
CONTAINER_NAME="lala-next-postgres"
API_LABEL="cloud.lala-next.api"
CLOUDFLARED_LABEL="cloud.lala-next.cloudflared"
TIMEOUT="8"
MIN_DISK_GB="10"
REQUIRE_LIVE_AI="false"
REQUIRE_LIVE_SPEECH="false"
REQUIRE_DATA_FRESHNESS="false"
JSON_STATUS="false"
PYTHON_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-url) PUBLIC_URL="${2:-}"; shift 2 ;;
    --local-url) LOCAL_URL="${2:-}"; shift 2 ;;
    --container) CONTAINER_NAME="${2:-}"; shift 2 ;;
    --api-label) API_LABEL="${2:-}"; shift 2 ;;
    --cloudflared-label) CLOUDFLARED_LABEL="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --min-disk-gb) MIN_DISK_GB="${2:-}"; shift 2 ;;
    --require-live-ai) REQUIRE_LIVE_AI="true"; shift ;;
    --require-live-speech) REQUIRE_LIVE_SPEECH="true"; shift ;;
    --require-data-freshness) REQUIRE_DATA_FRESHNESS="true"; shift ;;
    --json) JSON_STATUS="true"; shift ;;
    --python) PYTHON_ARG="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/check_onprem_runtime.sh [--json] [--require-live-ai] [--require-live-speech]"
      echo "Checks LaunchAgents, Docker PostgreSQL, local/public readyz, and host disk headroom."
      echo "Secrets and DB_DSN values are never printed."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ROOT="$(repo_root)"
PYTHON="$(select_python "$PYTHON_ARG")"
cd "$ROOT"

ROOT="$ROOT" \
PUBLIC_URL="$PUBLIC_URL" \
LOCAL_URL="$LOCAL_URL" \
CONTAINER_NAME="$CONTAINER_NAME" \
API_LABEL="$API_LABEL" \
CLOUDFLARED_LABEL="$CLOUDFLARED_LABEL" \
TIMEOUT="$TIMEOUT" \
MIN_DISK_GB="$MIN_DISK_GB" \
REQUIRE_LIVE_AI="$REQUIRE_LIVE_AI" \
REQUIRE_LIVE_SPEECH="$REQUIRE_LIVE_SPEECH" \
REQUIRE_DATA_FRESHNESS="$REQUIRE_DATA_FRESHNESS" \
JSON_STATUS="$JSON_STATUS" \
"$PYTHON" - <<'PY'
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from typing import Any
from urllib import request


def env_bool(name: str) -> bool:
    return os.environ.get(name, "").lower() == "true"


def run_command(args: list[str], timeout: float = 8.0) -> tuple[bool, str]:
    try:
        completed = subprocess.run(
            args,
            check=False,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
    except Exception as exc:  # pragma: no cover - runtime diagnostics only
        return False, type(exc).__name__
    detail = (completed.stdout or completed.stderr or "").strip().splitlines()
    return completed.returncode == 0, detail[0] if detail else f"exit={completed.returncode}"


def fetch_json(url: str, timeout: float) -> tuple[bool, dict[str, Any] | None, str]:
    readyz_url = url.rstrip("/") + "/readyz"
    req = request.Request(
        readyz_url,
        headers={"User-Agent": "LALA-next-onprem-runtime-check/1.0"},
    )
    try:
        with request.urlopen(req, timeout=timeout) as response:
            body = response.read()
    except Exception as exc:
        return False, None, type(exc).__name__
    try:
        payload = json.loads(body.decode("utf-8"))
    except Exception as exc:
        return False, None, f"json:{type(exc).__name__}"
    return True, payload, "ok"


def readyz_data(payload: dict[str, Any]) -> dict[str, Any]:
    data = payload.get("data")
    if isinstance(data, dict):
        return data
    return payload


def evaluate_readyz(name: str, payload: dict[str, Any]) -> list[dict[str, Any]]:
    data = readyz_data(payload)
    mode = data.get("mode") or {}
    checks = data.get("checks") or {}
    rows: list[dict[str, Any]] = []

    def add(suffix: str, ok: bool, detail: str) -> None:
        rows.append({"name": f"{name}:{suffix}", "ok": ok, "detail": detail})

    status = data.get("status") or payload.get("status")
    add("status", status == "ok", str(status))
    add("data", mode.get("data") == "db-backed", str(mode.get("data")))
    add("db", checks.get("db") == "configured", str(checks.get("db")))
    add(
        "postgis",
        checks.get("postgis") == "configured",
        str(checks.get("postgis")),
    )
    add(
        "snapshot_fallback",
        checks.get("static_snapshot_fallback") == "disabled",
        str(checks.get("static_snapshot_fallback")),
    )
    if env_bool("REQUIRE_LIVE_AI"):
        add("live_ai", checks.get("live_ai") == "enabled", str(checks.get("live_ai")))
    if env_bool("REQUIRE_LIVE_SPEECH"):
        add(
            "live_speech",
            checks.get("live_speech") == "enabled",
            str(checks.get("live_speech")),
        )
    if env_bool("REQUIRE_DATA_FRESHNESS"):
        add(
            "data_freshness",
            checks.get("data_freshness") == "configured",
            str(checks.get("data_freshness")),
        )
    return rows


def add_result(results: list[dict[str, Any]], name: str, ok: bool, detail: str) -> None:
    results.append({"name": name, "ok": ok, "detail": detail})


def main() -> int:
    timeout = float(os.environ["TIMEOUT"])
    root = os.environ["ROOT"]
    results: list[dict[str, Any]] = []

    if sys.platform == "darwin":
        for label_name, label in (
            ("launchd:api", os.environ["API_LABEL"]),
            ("launchd:cloudflared", os.environ["CLOUDFLARED_LABEL"]),
        ):
            ok, detail = run_command(["launchctl", "list", label], timeout=timeout)
            add_result(results, label_name, ok, "loaded" if ok else detail)
    else:
        add_result(results, "launchd", True, "skipped_non_darwin")

    docker_ok, docker_detail = run_command(
        [
            "docker",
            "inspect",
            "--format",
            "{{.State.Health.Status}}",
            os.environ["CONTAINER_NAME"],
        ],
        timeout=timeout,
    )
    add_result(
        results,
        "docker:postgres",
        docker_ok and docker_detail == "healthy",
        docker_detail,
    )

    for name, url in (
        ("readyz:local", os.environ["LOCAL_URL"]),
        ("readyz:public", os.environ["PUBLIC_URL"]),
    ):
        ok, payload, detail = fetch_json(url, timeout=timeout)
        add_result(results, name, ok, detail)
        if ok and payload:
            results.extend(evaluate_readyz(name, payload))

    min_disk_gb = float(os.environ["MIN_DISK_GB"])
    disk = shutil.disk_usage(root)
    free_gb = disk.free / (1024**3)
    add_result(results, "disk:free_gb", free_gb >= min_disk_gb, f"{free_gb:.1f}")

    ok = all(row["ok"] for row in results)
    payload = {
        "ok": ok,
        "mode": "onprem_runtime_check",
        "checked_at_epoch": int(time.time()),
        "results": results,
    }

    if env_bool("JSON_STATUS"):
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    else:
        print("LALA on-prem runtime check")
        print(f"ok={str(ok).lower()}")
        for row in results:
            marker = "ok" if row["ok"] else "fail"
            print(f"[{marker}] {row['name']} {row['detail']}")
    return 0 if ok else 1


raise SystemExit(main())
PY
