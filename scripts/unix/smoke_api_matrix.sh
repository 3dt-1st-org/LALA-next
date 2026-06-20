#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

BASE_URL="http://127.0.0.1:8080"
KEY_VAULT_URL_ARG=""
PYTHON_ARG=""
JSON_STATUS="false"
TIMEOUT="20"
PROFILE="full"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      BASE_URL="${2:-}"
      shift 2
      ;;
    --key-vault-url)
      KEY_VAULT_URL_ARG="${2:-}"
      shift 2
      ;;
    --python)
      PYTHON_ARG="${2:-}"
      shift 2
      ;;
    --timeout)
      TIMEOUT="${2:-}"
      shift 2
      ;;
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --json)
      JSON_STATUS="true"
      shift
      ;;
    -h|--help)
      echo "Usage: scripts/unix/smoke_api_matrix.sh [--base-url URL] [--key-vault-url URL] [--timeout SEC] [--profile deploy|full] [--json] [--python PATH]"
      echo "Runs a bounded deploy or wider live API matrix without printing client tokens or Key Vault secret values."
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

load_env_file "$ROOT/.env"
load_lala_key_vault_secrets

ARGS=(-m apps.api.app.tools.smoke_api_matrix --base-url "$BASE_URL" --timeout "$TIMEOUT" --profile "$PROFILE")
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi

"$PYTHON" "${ARGS[@]}"
