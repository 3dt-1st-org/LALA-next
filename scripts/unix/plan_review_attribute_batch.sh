#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
JSON_STATUS="false"
PREVIEW="false"
DRY_RUN_AI="false"
APPLY="false"
CONFIRM=""
KEY_VAULT_URL_ARG=""
CATEGORY="all"
LIMIT="50"
MIN_ORGANIC="3"
BATCH_SIZE="10"
RETRY_ATTEMPTS="3"
RETRY_DELAY_SEC="5.0"
CONNECT_TIMEOUT="5"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preview)
      PREVIEW="true"
      shift
      ;;
    --dry-run-ai)
      DRY_RUN_AI="true"
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
    --category)
      CATEGORY="${2:-}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    --min-organic)
      MIN_ORGANIC="${2:-}"
      shift 2
      ;;
    --batch-size)
      BATCH_SIZE="${2:-}"
      shift 2
      ;;
    --retry-attempts)
      RETRY_ATTEMPTS="${2:-}"
      shift 2
      ;;
    --retry-delay-sec)
      RETRY_DELAY_SEC="${2:-}"
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
      echo "Usage: scripts/unix/plan_review_attribute_batch.sh [--preview|--dry-run-ai|--apply --confirm APPLY_REVIEW_ATTRIBUTE_BATCH] [--category NAME] [--limit N] [--min-organic N] [--key-vault-url URL] [--json] [--python PATH]"
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
if [[ "$PREVIEW" == "true" || "$DRY_RUN_AI" == "true" || "$APPLY" == "true" ]]; then
  load_lala_key_vault_secrets
fi

if [[ "$JSON_STATUS" != "true" ]]; then
  echo "Planning LALA-next review attribute batch."
  echo "Default mode is dry-run plan only."
  echo "Preview mode reads review mentions and computes deterministic attributes without mutating DB."
  echo "Dry-run AI mode calls Azure OpenAI but does not mutate DB."
  echo "Apply mode requires ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY=1."
  echo "AZURE_OPENAI_KEY and DB_DSN values are never printed by this script."
fi

ARGS=(
  -m apps.api.app.tools.run_review_attribute_batch
  --category "$CATEGORY"
  --limit "$LIMIT"
  --min-organic "$MIN_ORGANIC"
  --batch-size "$BATCH_SIZE"
  --retry-attempts "$RETRY_ATTEMPTS"
  --retry-delay-sec "$RETRY_DELAY_SEC"
  --connect-timeout "$CONNECT_TIMEOUT"
)
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
if [[ "$PREVIEW" == "true" ]]; then
  ARGS+=(--preview)
fi
if [[ "$DRY_RUN_AI" == "true" ]]; then
  ARGS+=(--dry-run-ai)
fi
if [[ "$APPLY" == "true" ]]; then
  ARGS+=(--apply --confirm "$CONFIRM")
fi
"$PYTHON" "${ARGS[@]}"
