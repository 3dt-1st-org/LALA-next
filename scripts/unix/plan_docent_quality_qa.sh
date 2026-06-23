#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
JSON_STATUS="false"
PREVIEW="false"
WRITE="false"
KEY_VAULT_URL_ARG=""
CATEGORY="all"
LANGUAGE="ko"
MODE="brief"
LIMIT="40"
CONNECT_TIMEOUT="5"
OUTPUT_DIR="output/local/docent-qa"
LABEL="docent-quality-qa"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preview)
      PREVIEW="true"
      shift
      ;;
    --write)
      WRITE="true"
      shift
      ;;
    --key-vault-url)
      KEY_VAULT_URL_ARG="${2:-}"
      shift 2
      ;;
    --category)
      CATEGORY="${2:-}"
      shift 2
      ;;
    --language)
      LANGUAGE="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
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
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --label)
      LABEL="${2:-}"
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
      echo "Usage: scripts/unix/plan_docent_quality_qa.sh [--preview|--write] [--category all|attraction|restaurant|event|culture_venue] [--language ko|en] [--mode brief|detail] [--limit N] [--output-dir PATH] [--key-vault-url URL] [--json] [--connect-timeout SECONDS] [--python PATH]"
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
if [[ "$PREVIEW" == "true" || "$WRITE" == "true" ]]; then
  load_lala_key_vault_secrets
fi

if [[ "$JSON_STATUS" != "true" ]]; then
  echo "Planning LALA-next docent quality QA."
  echo "Default mode is dry-run plan only and does not read DB."
  echo "Preview mode reads DB and prints sanitized aggregate QA seed data."
  echo "Write mode creates local-only files under output/local."
  echo "DB_DSN value is never printed by this script."
fi

ARGS=(
  -m apps.api.app.tools.run_docent_quality_qa
  --category "$CATEGORY"
  --language "$LANGUAGE"
  --mode "$MODE"
  --limit "$LIMIT"
  --connect-timeout "$CONNECT_TIMEOUT"
  --output-dir "$OUTPUT_DIR"
  --label "$LABEL"
)
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
if [[ "$PREVIEW" == "true" ]]; then
  ARGS+=(--preview)
fi
if [[ "$WRITE" == "true" ]]; then
  ARGS+=(--write)
fi
"$PYTHON" "${ARGS[@]}"
