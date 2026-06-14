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
AREA_CODE="31"
ROWS="40"
PAGE_SIZE="20"
TIMEOUT="10"
CONNECT_TIMEOUT="5"
CONTENT_TYPE_ARGS=()

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
    --area-code)
      AREA_CODE="${2:-}"
      shift 2
      ;;
    --content-type-id)
      CONTENT_TYPE_ARGS+=(--content-type-id "${2:-}")
      shift 2
      ;;
    --rows)
      ROWS="${2:-}"
      shift 2
      ;;
    --page-size)
      PAGE_SIZE="${2:-}"
      shift 2
      ;;
    --timeout)
      TIMEOUT="${2:-}"
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
      echo "Usage: scripts/unix/plan_tour_api_ingest.sh [--preview|--apply --confirm APPLY_TOUR_API_INGEST] [--area-code CODE] [--content-type-id ID] [--rows N] [--key-vault-url URL] [--json] [--python PATH]"
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
  echo "Planning LALA-next TourAPI place ingestion."
  echo "Default mode is dry-run plan only."
  echo "Preview mode calls TourAPI but does not mutate DB."
  echo "Apply mode requires ALLOW_TOUR_API_INGEST_APPLY=1."
  echo "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script."
fi

ARGS=(
  -m apps.api.app.tools.run_tour_api_ingest
  --area-code "$AREA_CODE"
  --rows "$ROWS"
  --page-size "$PAGE_SIZE"
  --timeout "$TIMEOUT"
  --connect-timeout "$CONNECT_TIMEOUT"
)
if [[ ${#CONTENT_TYPE_ARGS[@]} -gt 0 ]]; then
  ARGS+=("${CONTENT_TYPE_ARGS[@]}")
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
