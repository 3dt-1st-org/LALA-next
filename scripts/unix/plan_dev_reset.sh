#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
JSON_STATUS="false"
APPLY="false"
CONFIRM=""
KEY_VAULT_URL_ARG=""
CONNECT_TIMEOUT="5"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY="true"
      shift
      ;;
    --confirm)
      CONFIRM="${2:-}"
      shift 2
      ;;
    --key-vault-url)
      KEY_VAULT_URL_ARG="${2:-}"
      shift 2
      ;;
    --connect-timeout)
      CONNECT_TIMEOUT="${2:-}"
      shift 2
      ;;
    --python)
      PYTHON_ARG="${2:-}"
      shift 2
      ;;
    --json)
      JSON_STATUS="true"
      shift
      ;;
    -h|--help)
      echo "Usage: scripts/unix/plan_dev_reset.sh [--apply --confirm APPLY_DEV_RESET_SQL] [--key-vault-url URL] [--json] [--connect-timeout SECONDS] [--python PATH]"
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
else
  load_env_names_from_file "$ROOT/.env" KEY_VAULT_URL LALA_ALLOWED_KEY_VAULT_HOSTS
fi
if [[ "$APPLY" == "true" ]]; then
  load_lala_key_vault_secrets
fi

if [[ "$JSON_STATUS" != "true" ]]; then
  echo "Planning LALA-next local-only dev seed/reset SQL."
  echo "Default mode is dry-run plan only."
  echo "Apply mode is localhost-only and requires ALLOW_DEV_RESET_APPLY=1."
  echo "DB_DSN value is never printed by this script."
fi

ARGS=(-m apps.api.app.tools.plan_dev_reset --connect-timeout "$CONNECT_TIMEOUT")
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
if [[ "$APPLY" == "true" ]]; then
  ARGS+=(--apply --confirm "$CONFIRM")
fi
"$PYTHON" "${ARGS[@]}"
