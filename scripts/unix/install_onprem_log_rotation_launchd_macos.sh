#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

ROTATION_LABEL="cloud.lala-next.log-rotation"
LOG_DIR=""
MAX_BYTES="10485760"
RETENTION_DAYS="14"
HOUR="4"
MINUTE="0"
APPLY="false"
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-dir) LOG_DIR="${2:-}"; shift 2 ;;
    --max-bytes) MAX_BYTES="${2:-}"; shift 2 ;;
    --retention-days) RETENTION_DAYS="${2:-}"; shift 2 ;;
    --hour) HOUR="${2:-}"; shift 2 ;;
    --minute) MINUTE="${2:-}"; shift 2 ;;
    --apply) APPLY="true"; shift ;;
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/install_onprem_log_rotation_launchd_macos.sh --apply --confirm INSTALL_LOG_ROTATION_LAUNCHD"
      echo "Installs a daily macOS LaunchAgent for ignored runtime log rotation."
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
if [[ -z "$LOG_DIR" ]]; then
  LOG_DIR="$ROOT/runtime/logs"
fi

PLIST_DIR="$HOME/Library/LaunchAgents"
ROTATION_PLIST="$PLIST_DIR/$ROTATION_LABEL.plist"

echo "LALA macOS on-premises log rotation LaunchAgent installer"
echo "rotation_label=$ROTATION_LABEL"
echo "repo_root=$ROOT"
echo "log_dir=$LOG_DIR"
echo "max_bytes=$MAX_BYTES"
echo "retention_days=$RETENTION_DAYS"
echo "schedule=$HOUR:$MINUTE"
echo "secret_printing=false"

if [[ "$APPLY" != "true" || "$CONFIRM" != "INSTALL_LOG_ROTATION_LAUNCHD" ]]; then
  echo "mode=plan"
  echo "To execute: add --apply --confirm INSTALL_LOG_ROTATION_LAUNCHD"
  exit 0
fi

mkdir -p "$PLIST_DIR" "$LOG_DIR"

ROTATION_LABEL="$ROTATION_LABEL" \
ROOT="$ROOT" \
LOG_DIR="$LOG_DIR" \
MAX_BYTES="$MAX_BYTES" \
RETENTION_DAYS="$RETENTION_DAYS" \
HOUR="$HOUR" \
MINUTE="$MINUTE" \
ROTATION_PLIST="$ROTATION_PLIST" \
python3 - <<'PY'
import os
import plistlib
import shlex
from pathlib import Path

root = os.environ["ROOT"]
command = (
    f"cd {shlex.quote(root)} && "
    "scripts/unix/rotate_onprem_logs.sh "
    f"--log-dir {shlex.quote(os.environ['LOG_DIR'])} "
    f"--max-bytes {shlex.quote(os.environ['MAX_BYTES'])} "
    f"--retention-days {shlex.quote(os.environ['RETENTION_DAYS'])} "
    "--apply --confirm ROTATE_ONPREM_LOGS"
)
plist = {
    "Label": os.environ["ROTATION_LABEL"],
    "ProgramArguments": ["/bin/zsh", "-lc", command],
    "WorkingDirectory": root,
    "RunAtLoad": False,
    "StartCalendarInterval": {
        "Hour": int(os.environ["HOUR"]),
        "Minute": int(os.environ["MINUTE"]),
    },
    "StandardOutPath": str(Path(root) / "runtime/logs/lala-onprem-log-rotation.launchd.out"),
    "StandardErrorPath": str(Path(root) / "runtime/logs/lala-onprem-log-rotation.launchd.err"),
    "ProcessType": "Background",
}
path = Path(os.environ["ROTATION_PLIST"])
with path.open("wb") as handle:
    plistlib.dump(plist, handle, sort_keys=False)
PY

launchctl bootout "gui/$UID" "$ROTATION_PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$ROTATION_PLIST"

echo "log_rotation_launchd_install=ok"
