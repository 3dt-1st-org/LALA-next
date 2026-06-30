#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

LABEL="cloud.lala-next.docker-autostart"
INTERVAL_SECONDS="300"
APPLY="false"
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval-seconds) INTERVAL_SECONDS="${2:-}"; shift 2 ;;
    --apply) APPLY="true"; shift ;;
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/install_onprem_docker_autostart_launchd_macos.sh [--interval-seconds 300] --apply --confirm INSTALL_DOCKER_AUTOSTART_LAUNCHD"
      echo "Installs a macOS LaunchAgent that keeps Docker Desktop running for the on-prem runtime."
      echo "Idempotent: launches Docker only when the daemon is not reachable."
      echo "Fires at login (RunAtLoad) and every --interval-seconds (default 300)."
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

case "$INTERVAL_SECONDS" in ''|*[!0-9]*)
  echo "--interval-seconds must be a positive integer." >&2
  exit 2
;; esac

PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"

# Only call `open -a Docker` when the daemon is not reachable, so a healthy
# Docker is never disturbed and no GUI focus is stolen. `docker info` failing
# for any reason (daemon down, CLI missing) falls through to launching Docker.
ENSURE_COMMAND='docker info >/dev/null 2>&1 || open -a Docker'

echo "LALA macOS on-premises Docker autostart LaunchAgent installer"
echo "label=$LABEL"
echo "repo_root=$ROOT"
echo "interval_seconds=$INTERVAL_SECONDS"
echo "run_at_load=true"
echo "ensure_command=$ENSURE_COMMAND"
echo "secret_printing=false"

if [[ "$APPLY" != "true" || "$CONFIRM" != "INSTALL_DOCKER_AUTOSTART_LAUNCHD" ]]; then
  echo "mode=plan"
  echo "To execute: add --apply --confirm INSTALL_DOCKER_AUTOSTART_LAUNCHD"
  exit 0
fi

mkdir -p "$PLIST_DIR" "$ROOT/runtime/logs"

LABEL="$LABEL" \
ROOT="$ROOT" \
INTERVAL_SECONDS="$INTERVAL_SECONDS" \
ENSURE_COMMAND="$ENSURE_COMMAND" \
PLIST_PATH="$PLIST_PATH" \
python3 - <<'PY'
import os
import plistlib
from pathlib import Path

label = os.environ["LABEL"]
root = os.environ["ROOT"]
interval_seconds = int(os.environ["INTERVAL_SECONDS"])
ensure_command = os.environ["ENSURE_COMMAND"]
plist_path = Path(os.environ["PLIST_PATH"])

plist = {
    "Label": label,
    "ProgramArguments": ["/bin/zsh", "-lc", ensure_command],
    "WorkingDirectory": root,
    "RunAtLoad": True,
    "StartInterval": interval_seconds,
    "StandardOutPath": str(Path(root) / "runtime/logs/lala-onprem-docker-autostart.launchd.out"),
    "StandardErrorPath": str(Path(root) / "runtime/logs/lala-onprem-docker-autostart.launchd.err"),
    "ProcessType": "Background",
}

with plist_path.open("wb") as handle:
    plistlib.dump(plist, handle, sort_keys=False)
PY

launchctl bootout "gui/$UID" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$PLIST_PATH"

echo "docker_autostart_launchd_install=ok"
