#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

BACKUP_LABEL="cloud.lala-next.backup"
ENV_FILE=""
BACKUP_DIR=""
OFFSITE_DIR=""
RETENTION_DAYS="14"
HOUR="3"
MINUTE="30"
APPLY="false"
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="${2:-}"; shift 2 ;;
    --backup-dir) BACKUP_DIR="${2:-}"; shift 2 ;;
    --offsite-dir) OFFSITE_DIR="${2:-}"; shift 2 ;;
    --retention-days) RETENTION_DAYS="${2:-}"; shift 2 ;;
    --hour) HOUR="${2:-}"; shift 2 ;;
    --minute) MINUTE="${2:-}"; shift 2 ;;
    --apply) APPLY="true"; shift ;;
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/install_onprem_backup_launchd_macos.sh [--hour 3 --minute 30] --apply --confirm INSTALL_BACKUP_LAUNCHD"
      echo "Installs a daily macOS LaunchAgent for Docker PostgreSQL backups."
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

if [[ -z "$ENV_FILE" ]]; then
  if [[ -f "$ROOT/runtime/onprem-api.env" ]]; then
    ENV_FILE="$ROOT/runtime/onprem-api.env"
  else
    ENV_FILE="$ROOT/runtime/local-postgres.env"
  fi
fi
if [[ -z "$BACKUP_DIR" ]]; then
  BACKUP_DIR="$ROOT/runtime/backups"
fi

PLIST_DIR="$HOME/Library/LaunchAgents"
BACKUP_PLIST="$PLIST_DIR/$BACKUP_LABEL.plist"

echo "LALA macOS on-premises backup LaunchAgent installer"
echo "backup_label=$BACKUP_LABEL"
echo "repo_root=$ROOT"
echo "env_file=$ENV_FILE"
echo "backup_dir=$BACKUP_DIR"
echo "offsite_dir=${OFFSITE_DIR:-disabled}"
echo "retention_days=$RETENTION_DAYS"
echo "schedule=$HOUR:$MINUTE"
echo "secret_printing=false"

if [[ "$APPLY" != "true" || "$CONFIRM" != "INSTALL_BACKUP_LAUNCHD" ]]; then
  echo "mode=plan"
  echo "To execute: add --apply --confirm INSTALL_BACKUP_LAUNCHD"
  exit 0
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Env file is missing: $ENV_FILE" >&2
  exit 1
fi

mkdir -p "$PLIST_DIR" "$ROOT/runtime/logs" "$BACKUP_DIR"

BACKUP_LABEL="$BACKUP_LABEL" \
ROOT="$ROOT" \
ENV_FILE="$ENV_FILE" \
BACKUP_DIR="$BACKUP_DIR" \
OFFSITE_DIR="$OFFSITE_DIR" \
RETENTION_DAYS="$RETENTION_DAYS" \
HOUR="$HOUR" \
MINUTE="$MINUTE" \
BACKUP_PLIST="$BACKUP_PLIST" \
python3 - <<'PY'
import os
import plistlib
import shlex
from pathlib import Path

root = os.environ["ROOT"]
env_file = os.environ["ENV_FILE"]
backup_dir = os.environ["BACKUP_DIR"]
offsite_dir = os.environ["OFFSITE_DIR"]
retention_days = os.environ["RETENTION_DAYS"]

command = (
    f"cd {shlex.quote(root)} && "
    "scripts/unix/backup_docker_postgres.sh "
    f"--env-file {shlex.quote(env_file)} "
    f"--backup-dir {shlex.quote(backup_dir)} "
    f"--retention-days {shlex.quote(retention_days)} "
)
if offsite_dir:
    command += f"--offsite-dir {shlex.quote(offsite_dir)} "
command += "--apply --confirm BACKUP_DOCKER_POSTGRES"

plist = {
    "Label": os.environ["BACKUP_LABEL"],
    "ProgramArguments": ["/bin/zsh", "-lc", command],
    "WorkingDirectory": root,
    "RunAtLoad": False,
    "StartCalendarInterval": {
        "Hour": int(os.environ["HOUR"]),
        "Minute": int(os.environ["MINUTE"]),
    },
    "StandardOutPath": str(Path(root) / "runtime/logs/lala-onprem-backup.launchd.out"),
    "StandardErrorPath": str(Path(root) / "runtime/logs/lala-onprem-backup.launchd.err"),
    "ProcessType": "Background",
}

path = Path(os.environ["BACKUP_PLIST"])
with path.open("wb") as handle:
    plistlib.dump(plist, handle, sort_keys=False)
PY

launchctl bootout "gui/$UID" "$BACKUP_PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$BACKUP_PLIST"

echo "backup_launchd_install=ok"
