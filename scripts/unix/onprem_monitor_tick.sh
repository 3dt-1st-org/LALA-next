#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PUBLIC_URL="https://api.lala-next.cloud"
LOCAL_URL="http://127.0.0.1:8080"
LOG_JSONL=""
MIN_DISK_GB="10"
REQUIRE_LIVE_AI="false"
REQUIRE_LIVE_SPEECH="false"
REQUIRE_DATA_FRESHNESS="false"
ALERT="local"
WEBHOOK_ENV_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-url) PUBLIC_URL="${2:-}"; shift 2 ;;
    --local-url) LOCAL_URL="${2:-}"; shift 2 ;;
    --log-jsonl) LOG_JSONL="${2:-}"; shift 2 ;;
    --min-disk-gb) MIN_DISK_GB="${2:-}"; shift 2 ;;
    --require-live-ai) REQUIRE_LIVE_AI="true"; shift ;;
    --require-live-speech) REQUIRE_LIVE_SPEECH="true"; shift ;;
    --require-data-freshness) REQUIRE_DATA_FRESHNESS="true"; shift ;;
    --alert) ALERT="${2:-}"; shift 2 ;;
    --webhook-env-name) WEBHOOK_ENV_NAME="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/onprem_monitor_tick.sh [--log-jsonl PATH] [--alert local|none]"
      echo "Runs one JSON on-prem runtime check, appends it to JSONL, and optionally emits a local macOS alert on failure."
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
cd "$ROOT"

if [[ -z "$LOG_JSONL" ]]; then
  LOG_JSONL="$ROOT/runtime/logs/onprem-health.jsonl"
fi

mkdir -p "$(dirname "$LOG_JSONL")"

tmp_json="$(mktemp "$ROOT/runtime/logs/onprem-health.XXXXXX.json")"
trap 'rm -f "$tmp_json"' EXIT

args=(
  --json
  --public-url "$PUBLIC_URL"
  --local-url "$LOCAL_URL"
  --min-disk-gb "$MIN_DISK_GB"
)
if [[ "$REQUIRE_LIVE_AI" == "true" ]]; then
  args+=(--require-live-ai)
fi
if [[ "$REQUIRE_LIVE_SPEECH" == "true" ]]; then
  args+=(--require-live-speech)
fi
if [[ "$REQUIRE_DATA_FRESHNESS" == "true" ]]; then
  args+=(--require-data-freshness)
fi

set +e
scripts/unix/check_onprem_runtime.sh "${args[@]}" > "$tmp_json"
check_exit=$?
set -e

tr -d '\n' < "$tmp_json" >> "$LOG_JSONL"
printf '\n' >> "$LOG_JSONL"

if [[ "$check_exit" -ne 0 ]]; then
  echo "onprem_runtime_check=failed log_jsonl=$LOG_JSONL" >&2
  if [[ "$ALERT" == "local" ]] && command -v osascript >/dev/null 2>&1; then
      osascript -e 'display notification "api.lala-next.cloud runtime check failed. Check runtime/logs/onprem-health.jsonl." with title "LALA on-prem alert"' >/dev/null 2>&1 || true
  fi
  if [[ -n "$WEBHOOK_ENV_NAME" && -n "${!WEBHOOK_ENV_NAME:-}" ]]; then
    WEBHOOK_URL="${!WEBHOOK_ENV_NAME}" python3 - <<'PY' "$tmp_json" >/dev/null 2>&1 || true
from __future__ import annotations

import json
import os
import sys
from urllib import request

payload_path = sys.argv[1]
webhook_url = os.environ.get("WEBHOOK_URL", "").strip()
if not webhook_url:
    raise SystemExit(0)
with open(payload_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
body = json.dumps(
    {
        "service": "lala-next-onprem",
        "severity": "critical",
        "summary": "api.lala-next.cloud runtime check failed",
        "payload": payload,
    },
    ensure_ascii=False,
).encode("utf-8")
req = request.Request(
    webhook_url,
    data=body,
    headers={
        "Content-Type": "application/json",
        "User-Agent": "LALA-next-onprem-monitor/1.0",
    },
    method="POST",
)
with request.urlopen(req, timeout=8) as response:
    response.read()
PY
  fi
fi

exit "$check_exit"
