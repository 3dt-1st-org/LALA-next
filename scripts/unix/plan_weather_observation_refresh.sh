#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
JSON_STATUS="false"
PREVIEW="false"
APPLY="false"
CONFIRM=""
KEY_VAULT_URL_ARG=""
LIMIT="20"
CONNECT_TIMEOUT="5"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preview)
      PREVIEW="true"
      shift
      ;;
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
    --limit)
      LIMIT="${2:-}"
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
      echo "Usage: scripts/unix/plan_weather_observation_refresh.sh [--preview|--apply --confirm APPLY_WEATHER_OBSERVATION_REFRESH] [--limit N] [--key-vault-url URL] [--json] [--connect-timeout SECONDS] [--python PATH]"
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

if [[ "$PREVIEW" == "true" || "$APPLY" == "true" ]]; then
  load_lala_key_vault_secrets
fi

if [[ "$JSON_STATUS" != "true" ]]; then
  echo "Planning LALA-next weather observation refresh."
  echo "Default mode is dry-run plan only."
  echo "Preview mode reads DB targets and calls KMA/AirKorea but does not mutate DB."
  echo "Apply mode requires ALLOW_WEATHER_OBSERVATION_REFRESH_APPLY=1."
  echo "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script."
fi

ARGS=(
  -m apps.api.app.tools.run_weather_observation_refresh
  --limit "$LIMIT"
  --connect-timeout "$CONNECT_TIMEOUT"
)
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
if [[ "$PREVIEW" == "true" ]]; then
  ARGS+=(--preview)
fi
if [[ "$APPLY" == "true" ]]; then
  ARGS+=(--apply --confirm "$CONFIRM")
fi
"$PYTHON" "${ARGS[@]}"
