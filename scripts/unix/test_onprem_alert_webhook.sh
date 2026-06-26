#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

ENV_FILE=""
WEBHOOK_ENV_NAME="LALA_ONPREM_ALERT_WEBHOOK_URL"
APPLY="false"
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="${2:-}"; shift 2 ;;
    --webhook-env-name) WEBHOOK_ENV_NAME="${2:-}"; shift 2 ;;
    --apply) APPLY="true"; shift ;;
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/test_onprem_alert_webhook.sh [--env-file PATH] [--webhook-env-name NAME] --apply --confirm TEST_ONPREM_ALERT_WEBHOOK"
      echo "Sends a safe test alert to the configured webhook without printing its URL."
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

if [[ -z "$ENV_FILE" && -f "$ROOT/runtime/onprem-api.env" ]]; then
  ENV_FILE="$ROOT/runtime/onprem-api.env"
fi
if [[ -n "$ENV_FILE" ]]; then
  load_env_names_from_file "$ENV_FILE" "$WEBHOOK_ENV_NAME"
fi

echo "LALA on-prem alert webhook test"
echo "env_file=${ENV_FILE:-disabled}"
echo "webhook_env_name=$WEBHOOK_ENV_NAME"
echo "webhook_configured=$([[ -n "${!WEBHOOK_ENV_NAME:-}" ]] && echo true || echo false)"
echo "secret_printing=false"

if [[ "$APPLY" != "true" || "$CONFIRM" != "TEST_ONPREM_ALERT_WEBHOOK" ]]; then
  echo "mode=plan"
  echo "To execute: add --apply --confirm TEST_ONPREM_ALERT_WEBHOOK"
  exit 0
fi

if [[ -z "${!WEBHOOK_ENV_NAME:-}" ]]; then
  echo "Webhook URL is not configured in env var: $WEBHOOK_ENV_NAME" >&2
  exit 2
fi

WEBHOOK_URL="${!WEBHOOK_ENV_NAME}" python3 - <<'PY'
from __future__ import annotations

import json
import os
from datetime import datetime, UTC
from urllib import request

webhook_url = os.environ.get("WEBHOOK_URL", "").strip()
if not webhook_url:
    raise SystemExit("WEBHOOK_URL is missing")

payload = {
    "service": "lala-next-onprem",
    "severity": "info",
    "summary": "LALA on-prem alert webhook test",
    "timestamp": datetime.now(UTC).isoformat(),
    "test": True,
}
body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
req = request.Request(
    webhook_url,
    data=body,
    headers={
        "Content-Type": "application/json",
        "User-Agent": "LALA-next-onprem-webhook-test/1.0",
    },
    method="POST",
)
with request.urlopen(req, timeout=8) as response:
    response.read()
    print(f"webhook_status={response.status}")
print("onprem_alert_webhook=ok")
PY
