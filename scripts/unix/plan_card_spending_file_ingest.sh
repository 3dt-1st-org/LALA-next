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
FILE_PATH=""
REGION_MAP=""
SOURCE_NAME="data_portal"
DATASET_NAME="경기도_카드 소비 데이터"
VISITOR_TYPE="domestic"
ROW_LIMIT="0"
SKIP_DEMOGRAPHICS="false"
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
    --file-path|--csv-path)
      FILE_PATH="${2:-}"
      shift 2
      ;;
    --region-map)
      REGION_MAP="${2:-}"
      shift 2
      ;;
    --source-name)
      SOURCE_NAME="${2:-}"
      shift 2
      ;;
    --dataset-name)
      DATASET_NAME="${2:-}"
      shift 2
      ;;
    --visitor-type)
      VISITOR_TYPE="${2:-}"
      shift 2
      ;;
    --row-limit)
      ROW_LIMIT="${2:-}"
      shift 2
      ;;
    --skip-demographics)
      SKIP_DEMOGRAPHICS="true"
      shift
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
      echo "Usage: scripts/unix/plan_card_spending_file_ingest.sh [--preview|--apply --confirm APPLY_CARD_SPENDING_FILE_INGEST] [--file-path PATH] [--region-map PATH] [--dataset-name NAME] [--row-limit N] [--skip-demographics] [--json] [--python PATH]"
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
  echo "Planning LALA-next card spending file ingestion."
  echo "Default mode is dry-run plan only."
  echo "Preview mode parses a local CSV/XLSX file but does not mutate DB."
  echo "Apply mode requires ALLOW_CARD_SPENDING_FILE_INGEST_APPLY=1."
  echo "DB_DSN value is never printed by this script."
fi

ARGS=(
  -m apps.api.app.tools.run_card_spending_file_ingest
  --source-name "$SOURCE_NAME"
  --dataset-name "$DATASET_NAME"
  --visitor-type "$VISITOR_TYPE"
  --row-limit "$ROW_LIMIT"
  --connect-timeout "$CONNECT_TIMEOUT"
)
if [[ -n "$FILE_PATH" ]]; then
  ARGS+=(--file-path "$FILE_PATH")
fi
if [[ -n "$REGION_MAP" ]]; then
  ARGS+=(--region-map "$REGION_MAP")
fi
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
if [[ "$SKIP_DEMOGRAPHICS" == "true" ]]; then
  ARGS+=(--skip-demographics)
fi
if [[ "$PREVIEW" == "true" ]]; then
  ARGS+=(--preview)
fi
if [[ "$APPLY" == "true" ]]; then
  ARGS+=(--apply --confirm "$CONFIRM")
fi
"$PYTHON" "${ARGS[@]}"
