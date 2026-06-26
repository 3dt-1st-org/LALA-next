#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

API_LABEL="cloud.lala-next.api"
CLOUDFLARED_LABEL="cloud.lala-next.cloudflared"
ENV_FILE=""
API_HOST="127.0.0.1"
API_PORT="8080"
ACCESS_LOG_PATH=""
CLOUDFLARED_CONFIG=""
CLOUDFLARED_BIN=""
TUNNEL_NAME="lala-next-onprem-api"
PUBLIC_CONTEST_ACCESS="true"
GRACEFUL_TIMEOUT="20"
EXIT_TIMEOUT="30"
APPLY="false"
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="${2:-}"; shift 2 ;;
    --api-host) API_HOST="${2:-}"; shift 2 ;;
    --api-port) API_PORT="${2:-}"; shift 2 ;;
    --access-log-path) ACCESS_LOG_PATH="${2:-}"; shift 2 ;;
    --cloudflared-config) CLOUDFLARED_CONFIG="${2:-}"; shift 2 ;;
    --cloudflared-bin) CLOUDFLARED_BIN="${2:-}"; shift 2 ;;
    --tunnel-name) TUNNEL_NAME="${2:-}"; shift 2 ;;
    --public-contest-access) PUBLIC_CONTEST_ACCESS="${2:-}"; shift 2 ;;
    --graceful-timeout) GRACEFUL_TIMEOUT="${2:-}"; shift 2 ;;
    --exit-timeout) EXIT_TIMEOUT="${2:-}"; shift 2 ;;
    --apply) APPLY="true"; shift ;;
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/install_onprem_launchd_macos.sh [--env-file PATH] [--cloudflared-config PATH] --apply --confirm INSTALL_LAUNCHD"
      echo "Installs macOS LaunchAgents for the on-premises API and Cloudflare Tunnel."
      echo "Secret values are read only from ignored runtime env/config files and are never printed."
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
if [[ -z "$ACCESS_LOG_PATH" ]]; then
  ACCESS_LOG_PATH="$ROOT/runtime/logs/onprem-api-access.jsonl"
fi
if [[ -z "$CLOUDFLARED_CONFIG" ]]; then
  CLOUDFLARED_CONFIG="$ROOT/runtime/cloudflared/lala-next-onprem-api.yml"
fi
if [[ -z "$CLOUDFLARED_BIN" ]]; then
  CLOUDFLARED_BIN="$(command -v cloudflared || true)"
fi
if [[ -z "$CLOUDFLARED_BIN" && -x /opt/homebrew/bin/cloudflared ]]; then
  CLOUDFLARED_BIN="/opt/homebrew/bin/cloudflared"
fi

PLIST_DIR="$HOME/Library/LaunchAgents"
API_PLIST="$PLIST_DIR/$API_LABEL.plist"
CLOUDFLARED_PLIST="$PLIST_DIR/$CLOUDFLARED_LABEL.plist"

echo "LALA macOS on-premises LaunchAgent installer"
echo "api_label=$API_LABEL"
echo "cloudflared_label=$CLOUDFLARED_LABEL"
echo "repo_root=$ROOT"
echo "env_file=$ENV_FILE"
echo "cloudflared_config=$CLOUDFLARED_CONFIG"
echo "graceful_timeout=$GRACEFUL_TIMEOUT"
echo "exit_timeout=$EXIT_TIMEOUT"
echo "secret_printing=false"

if [[ "$APPLY" != "true" || "$CONFIRM" != "INSTALL_LAUNCHD" ]]; then
  echo "mode=plan"
  echo "To execute: add --apply --confirm INSTALL_LAUNCHD"
  exit 0
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Env file is missing: $ENV_FILE" >&2
  exit 1
fi
if [[ ! -f "$CLOUDFLARED_CONFIG" ]]; then
  echo "Cloudflared config is missing: $CLOUDFLARED_CONFIG" >&2
  exit 1
fi
if [[ -z "$CLOUDFLARED_BIN" || ! -x "$CLOUDFLARED_BIN" ]]; then
  echo "cloudflared binary is missing. Install cloudflared or pass --cloudflared-bin." >&2
  exit 1
fi

mkdir -p "$PLIST_DIR" "$ROOT/runtime/logs"

API_LABEL="$API_LABEL" \
CLOUDFLARED_LABEL="$CLOUDFLARED_LABEL" \
ROOT="$ROOT" \
ENV_FILE="$ENV_FILE" \
API_HOST="$API_HOST" \
API_PORT="$API_PORT" \
ACCESS_LOG_PATH="$ACCESS_LOG_PATH" \
CLOUDFLARED_CONFIG="$CLOUDFLARED_CONFIG" \
CLOUDFLARED_BIN="$CLOUDFLARED_BIN" \
TUNNEL_NAME="$TUNNEL_NAME" \
PUBLIC_CONTEST_ACCESS="$PUBLIC_CONTEST_ACCESS" \
GRACEFUL_TIMEOUT="$GRACEFUL_TIMEOUT" \
EXIT_TIMEOUT="$EXIT_TIMEOUT" \
API_PLIST="$API_PLIST" \
CLOUDFLARED_PLIST="$CLOUDFLARED_PLIST" \
python3 - <<'PY'
import os
import plistlib
import shlex
from pathlib import Path

root = os.environ["ROOT"]
env_file = os.environ["ENV_FILE"]
api_host = os.environ["API_HOST"]
api_port = os.environ["API_PORT"]
access_log_path = os.environ["ACCESS_LOG_PATH"]
public_contest_access = os.environ["PUBLIC_CONTEST_ACCESS"]
graceful_timeout = os.environ["GRACEFUL_TIMEOUT"]
exit_timeout = int(os.environ["EXIT_TIMEOUT"])
cloudflared_bin = os.environ["CLOUDFLARED_BIN"]
cloudflared_config = os.environ["CLOUDFLARED_CONFIG"]
tunnel_name = os.environ["TUNNEL_NAME"]

api_command = (
    f"cd {shlex.quote(root)} && "
    f"set -a && source {shlex.quote(env_file)} && set +a && "
    "export KEY_VAULT_URL= && "
    "export LALA_ALLOWED_KEY_VAULT_HOSTS= && "
    "export LALA_STATIC_SNAPSHOT_FALLBACK=false && "
    f"export LALA_PUBLIC_CONTEST_ACCESS={shlex.quote(public_contest_access)} && "
    f"exec scripts/unix/start_api.sh --host-name {shlex.quote(api_host)} --port {shlex.quote(api_port)} "
    f"--access-log-path {shlex.quote(access_log_path)} "
    f"--graceful-timeout {shlex.quote(graceful_timeout)}"
)

api_plist = {
    "Label": os.environ["API_LABEL"],
    "ProgramArguments": ["/bin/zsh", "-lc", api_command],
    "WorkingDirectory": root,
    "RunAtLoad": True,
    "KeepAlive": True,
    "StandardOutPath": str(Path(root) / "runtime/logs/lala-onprem-api.launchd.out"),
    "StandardErrorPath": str(Path(root) / "runtime/logs/lala-onprem-api.launchd.err"),
    "ProcessType": "Background",
    "ExitTimeOut": exit_timeout,
}
cloudflared_plist = {
    "Label": os.environ["CLOUDFLARED_LABEL"],
    "ProgramArguments": [
        cloudflared_bin,
        "tunnel",
        "--config",
        cloudflared_config,
        "run",
        tunnel_name,
    ],
    "WorkingDirectory": root,
    "RunAtLoad": True,
    "KeepAlive": True,
    "StandardOutPath": str(Path(root) / "runtime/logs/lala-next-cloudflared.out.log"),
    "StandardErrorPath": str(Path(root) / "runtime/logs/lala-next-cloudflared.err.log"),
}

for path_name, payload in (
    ("API_PLIST", api_plist),
    ("CLOUDFLARED_PLIST", cloudflared_plist),
):
    path = Path(os.environ[path_name])
    with path.open("wb") as handle:
        plistlib.dump(payload, handle, sort_keys=False)
PY

launchctl bootout "gui/$UID" "$API_PLIST" >/dev/null 2>&1 || true
launchctl bootout "gui/$UID" "$CLOUDFLARED_PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$API_PLIST"
launchctl bootstrap "gui/$UID" "$CLOUDFLARED_PLIST"
launchctl kickstart -k "gui/$UID/$API_LABEL"
launchctl kickstart -k "gui/$UID/$CLOUDFLARED_LABEL"

echo "launchd_install=ok"
