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
DB_REGIONS="false"
LIMIT="50"
CONNECT_TIMEOUT="5"
FORCE="false"
TARGETS=()

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
    --target)
      TARGETS+=("${2:-}")
      shift 2
      ;;
    --db-regions)
      DB_REGIONS="true"
      shift
      ;;
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    --connect-timeout)
      CONNECT_TIMEOUT="${2:-}"
      shift 2
      ;;
    --force)
      FORCE="true"
      shift
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
      echo "Usage: scripts/unix/plan_weather_observation_refresh.sh [--preview|--apply --confirm APPLY_WEATHER_OBSERVATION_REFRESH] [--target NAME=LAT,LNG] [--db-regions] [--limit N] [--key-vault-url URL] [--json] [--python PATH]"
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

if [[ "$JSON_STATUS" != "true" ]]; then
  echo "Planning LALA-next weather observation refresh."
  echo "Default mode is dry-run plan only."
  echo "Preview mode calls KMA/AirKorea but does not mutate DB."
  echo "Apply mode requires ALLOW_WEATHER_OBSERVATION_REFRESH_APPLY=1."
  echo "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script."
fi

ARGS=(
  -m apps.api.app.tools.run_weather_observation_refresh
  --limit "$LIMIT"
  --connect-timeout "$CONNECT_TIMEOUT"
)
for target in "${TARGETS[@]}"; do
  ARGS+=(--target "$target")
done
if [[ "$DB_REGIONS" == "true" ]]; then
  ARGS+=(--db-regions)
fi
if [[ "$FORCE" == "true" ]]; then
  ARGS+=(--force)
fi
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
