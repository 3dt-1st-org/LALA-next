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
YEAR=""
ROWS="500"
PAGE_SIZE="1000"
CONNECT_TIMEOUT="10"
API_URL=""
SOURCE_NAME="fair_trade_commission"
DATASET_NAME="공정거래위원회_가맹정보_브랜드별 가맹점 현황 제공 서비스"

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
    --year)
      YEAR="${2:-}"
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
    --connect-timeout)
      CONNECT_TIMEOUT="${2:-}"
      shift 2
      ;;
    --api-url)
      API_URL="${2:-}"
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
    --python)
      PYTHON_ARG="${2:-}"
      shift 2
      ;;
    --json)
      JSON_STATUS="true"
      shift
      ;;
    -h|--help)
      echo "Usage: scripts/unix/plan_franchise_reference_ingest.sh [--preview|--apply --confirm APPLY_FRANCHISE_REFERENCE_INGEST] [--year YYYY] [--rows N] [--key-vault-url URL] [--json] [--python PATH]"
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
  echo "Planning LALA-next franchise reference ingestion."
  echo "Default mode is dry-run plan only."
  echo "Preview mode calls the Fair Trade Commission public-data API but does not mutate DB."
  echo "Apply mode requires ALLOW_FRANCHISE_REFERENCE_INGEST_APPLY=1."
  echo "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script."
fi

ARGS=(
  -m apps.api.app.tools.run_franchise_reference_ingest
  --rows "$ROWS"
  --page-size "$PAGE_SIZE"
  --connect-timeout "$CONNECT_TIMEOUT"
  --source-name "$SOURCE_NAME"
  --dataset-name "$DATASET_NAME"
)
if [[ -n "$YEAR" ]]; then
  ARGS+=(--year "$YEAR")
fi
if [[ -n "$API_URL" ]]; then
  ARGS+=(--api-url "$API_URL")
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
