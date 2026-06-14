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
STDATE=""
EDDATE=""
SIGNGUCODE="41"
SIGNGUCODESUB=""
PRFSTATE=""
ROWS="20"
PAGE_SIZE="10"
TIMEOUT="10"
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
    --stdate)
      STDATE="${2:-}"
      shift 2
      ;;
    --eddate)
      EDDATE="${2:-}"
      shift 2
      ;;
    --signgucode)
      SIGNGUCODE="${2:-}"
      shift 2
      ;;
    --signgucodesub)
      SIGNGUCODESUB="${2:-}"
      shift 2
      ;;
    --prfstate)
      PRFSTATE="${2:-}"
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
      echo "Usage: scripts/unix/plan_kopis_ingest.sh [--preview|--apply --confirm APPLY_KOPIS_INGEST] [--stdate YYYYMMDD] [--eddate YYYYMMDD] [--signgucode 41] [--signgucodesub CODE] [--prfstate CODE] [--rows N] [--key-vault-url URL] [--json] [--python PATH]"
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
  echo "Planning LALA-next KOPIS performance ingestion."
  echo "Default mode is dry-run plan only."
  echo "Preview mode calls KOPIS but does not mutate DB."
  echo "Apply mode requires ALLOW_KOPIS_INGEST_APPLY=1."
  echo "KOPIS_API_KEY and DB_DSN values are never printed by this script."
fi

ARGS=(
  -m apps.api.app.tools.run_kopis_ingest
  --signgucode "$SIGNGUCODE"
  --signgucodesub "$SIGNGUCODESUB"
  --prfstate "$PRFSTATE"
  --rows "$ROWS"
  --page-size "$PAGE_SIZE"
  --timeout "$TIMEOUT"
  --connect-timeout "$CONNECT_TIMEOUT"
)
if [[ -n "$STDATE" ]]; then
  ARGS+=(--stdate "$STDATE")
fi
if [[ -n "$EDDATE" ]]; then
  ARGS+=(--eddate "$EDDATE")
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
