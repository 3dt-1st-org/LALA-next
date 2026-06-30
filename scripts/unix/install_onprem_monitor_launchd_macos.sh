#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

MONITOR_LABEL="cloud.lala-next.monitor"
PUBLIC_URL="https://api.lala-next.cloud"
LOCAL_URL="http://127.0.0.1:8080"
INTERVAL_SECONDS="300"
MIN_DISK_GB="10"
LOG_JSONL=""
ENV_FILE=""
REQUIRE_LIVE_AI="true"
REQUIRE_LIVE_SPEECH="true"
REQUIRE_DATA_FRESHNESS="false"
ALERT="local"
WEBHOOK_ENV_NAME=""
APPLY="false"
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-url) PUBLIC_URL="${2:-}"; shift 2 ;;
    --local-url) LOCAL_URL="${2:-}"; shift 2 ;;
    --interval-seconds) INTERVAL_SECONDS="${2:-}"; shift 2 ;;
    --min-disk-gb) MIN_DISK_GB="${2:-}"; shift 2 ;;
    --log-jsonl) LOG_JSONL="${2:-}"; shift 2 ;;
    --env-file) ENV_FILE="${2:-}"; shift 2 ;;
    --no-require-live-ai) REQUIRE_LIVE_AI="false"; shift ;;
    --no-require-live-speech) REQUIRE_LIVE_SPEECH="false"; shift ;;
    --require-data-freshness) REQUIRE_DATA_FRESHNESS="true"; shift ;;
    --alert) ALERT="${2:-}"; shift 2 ;;
    --webhook-env-name) WEBHOOK_ENV_NAME="${2:-}"; shift 2 ;;
    --apply) APPLY="true"; shift ;;
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/install_onprem_monitor_launchd_macos.sh --apply --confirm INSTALL_MONITOR_LAUNCHD"
      echo "Installs a macOS LaunchAgent that writes periodic on-prem runtime checks to JSONL."
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
if [[ -z "$ENV_FILE" && -f "$ROOT/runtime/onprem-api.env" ]]; then
  ENV_FILE="$ROOT/runtime/onprem-api.env"
fi

PLIST_DIR="$HOME/Library/LaunchAgents"
MONITOR_PLIST="$PLIST_DIR/$MONITOR_LABEL.plist"

echo "LALA macOS on-premises monitor LaunchAgent installer"
echo "monitor_label=$MONITOR_LABEL"
echo "repo_root=$ROOT"
echo "public_url=$PUBLIC_URL"
echo "local_url=$LOCAL_URL"
echo "interval_seconds=$INTERVAL_SECONDS"
echo "min_disk_gb=$MIN_DISK_GB"
echo "log_jsonl=$LOG_JSONL"
echo "env_file=${ENV_FILE:-disabled}"
echo "require_live_ai=$REQUIRE_LIVE_AI"
echo "require_live_speech=$REQUIRE_LIVE_SPEECH"
echo "require_data_freshness=$REQUIRE_DATA_FRESHNESS"
echo "alert=$ALERT"
echo "webhook_env_name=${WEBHOOK_ENV_NAME:-disabled}"
echo "secret_printing=false"

if [[ "$APPLY" != "true" || "$CONFIRM" != "INSTALL_MONITOR_LAUNCHD" ]]; then
  echo "mode=plan"
  echo "To execute: add --apply --confirm INSTALL_MONITOR_LAUNCHD"
  exit 0
fi

mkdir -p "$PLIST_DIR" "$ROOT/runtime/logs"

MONITOR_LABEL="$MONITOR_LABEL" \
ROOT="$ROOT" \
PUBLIC_URL="$PUBLIC_URL" \
LOCAL_URL="$LOCAL_URL" \
INTERVAL_SECONDS="$INTERVAL_SECONDS" \
MIN_DISK_GB="$MIN_DISK_GB" \
LOG_JSONL="$LOG_JSONL" \
ENV_FILE="$ENV_FILE" \
REQUIRE_LIVE_AI="$REQUIRE_LIVE_AI" \
REQUIRE_LIVE_SPEECH="$REQUIRE_LIVE_SPEECH" \
REQUIRE_DATA_FRESHNESS="$REQUIRE_DATA_FRESHNESS" \
ALERT="$ALERT" \
WEBHOOK_ENV_NAME="$WEBHOOK_ENV_NAME" \
MONITOR_PLIST="$MONITOR_PLIST" \
python3 - <<'PY'
import os
import plistlib
import shlex
from pathlib import Path

root = os.environ["ROOT"]
public_url = os.environ["PUBLIC_URL"]
local_url = os.environ["LOCAL_URL"]
min_disk_gb = os.environ["MIN_DISK_GB"]
log_jsonl = os.environ["LOG_JSONL"]
env_file = os.environ["ENV_FILE"]
require_live_ai = os.environ["REQUIRE_LIVE_AI"].lower() == "true"
require_live_speech = os.environ["REQUIRE_LIVE_SPEECH"].lower() == "true"
require_data_freshness = os.environ["REQUIRE_DATA_FRESHNESS"].lower() == "true"
alert = os.environ["ALERT"]
webhook_env_name = os.environ["WEBHOOK_ENV_NAME"]

args = [
    "scripts/unix/onprem_monitor_tick.sh",
    "--public-url",
    public_url,
    "--local-url",
    local_url,
    "--log-jsonl",
    log_jsonl,
    "--min-disk-gb",
    min_disk_gb,
    "--alert",
    alert,
]
if webhook_env_name:
    args.extend(["--webhook-env-name", webhook_env_name])
if require_live_ai:
    args.append("--require-live-ai")
if require_live_speech:
    args.append("--require-live-speech")
if require_data_freshness:
    args.append("--require-data-freshness")

env_prefix = (
    f"set -a && source {shlex.quote(env_file)} && set +a && "
    if env_file
    else ""
)
command = (
    f"cd {shlex.quote(root)} && "
    "mkdir -p runtime/logs && "
    f"{env_prefix}"
    f"{' '.join(shlex.quote(part) for part in args)}"
)

plist = {
    "Label": os.environ["MONITOR_LABEL"],
    "ProgramArguments": ["/bin/zsh", "-lc", command],
    "WorkingDirectory": root,
    "RunAtLoad": True,
    "StartInterval": int(os.environ["INTERVAL_SECONDS"]),
    "StandardOutPath": str(Path(root) / "runtime/logs/lala-onprem-monitor.launchd.out"),
    "StandardErrorPath": str(Path(root) / "runtime/logs/lala-onprem-monitor.launchd.err"),
    "ProcessType": "Background",
}

path = Path(os.environ["MONITOR_PLIST"])
with path.open("wb") as handle:
    plistlib.dump(plist, handle, sort_keys=False)
PY

launchctl bootout "gui/$UID" "$MONITOR_PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$MONITOR_PLIST"
launchctl kickstart -k "gui/$UID/$MONITOR_LABEL"

echo "monitor_launchd_install=ok"
