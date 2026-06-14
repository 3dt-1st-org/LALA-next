#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

KEY_VAULT_URL_ARG=""
JSON_STATUS="false"
PYTHON_ARG=""
CONNECT_TIMEOUT="5"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key-vault-url)
      KEY_VAULT_URL_ARG="${2:-}"
      shift 2
      ;;
    --json)
      JSON_STATUS="true"
      shift
      ;;
    --python)
      PYTHON_ARG="${2:-}"
      shift 2
      ;;
    --connect-timeout)
      CONNECT_TIMEOUT="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/verify_db_schema.sh [--key-vault-url URL] [--json] [--connect-timeout SECONDS] [--python PATH]"
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

if [[ -n "$KEY_VAULT_URL_ARG" ]]; then
  export KEY_VAULT_URL="$KEY_VAULT_URL_ARG"
fi

echo "Verifying LALA-next canonical DB schema."
echo "DB_DSN value is never printed by this script."

ARGS=(-m apps.api.app.tools.verify_db_schema --connect-timeout "$CONNECT_TIMEOUT")
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
"$PYTHON" "${ARGS[@]}"
