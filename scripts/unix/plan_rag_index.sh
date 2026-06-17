#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
JSON_STATUS="false"
PREVIEW="false"
APPLY="false"
CONFIRM=""
QUERY=""
KEY_VAULT_URL_ARG=""
SOURCE="all"
EMBEDDING_METHOD="local-hash"
PLACE_ID=""
LIMIT="500"
TOP_K="5"
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
    --query)
      QUERY="${2:-}"
      shift 2
      ;;
    --key-vault-url)
      KEY_VAULT_URL_ARG="${2:-}"
      shift 2
      ;;
    --source)
      SOURCE="${2:-}"
      shift 2
      ;;
    --embedding-method)
      EMBEDDING_METHOD="${2:-}"
      shift 2
      ;;
    --place-id)
      PLACE_ID="${2:-}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    --top-k)
      TOP_K="${2:-}"
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
      echo "Usage: scripts/unix/plan_rag_index.sh [--preview|--apply --confirm APPLY_RAG_INDEX|--query TEXT] [--source all|static|dynamic] [--embedding-method local-hash|azure-openai] [--limit N] [--top-k N] [--json] [--connect-timeout SECONDS] [--python PATH]"
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
load_env_file "$ROOT/.env"

if [[ -n "$KEY_VAULT_URL_ARG" ]]; then
  export KEY_VAULT_URL="$KEY_VAULT_URL_ARG"
fi

if [[ "$JSON_STATUS" != "true" ]]; then
  echo "Planning LALA-next RAG knowledge index."
  echo "Default mode is dry-run plan only."
  echo "Apply mode requires ALLOW_RAG_INDEX_APPLY=1."
  echo "DB_DSN and AZURE_OPENAI_KEY values are never printed by this script."
fi

ARGS=(
  -m apps.api.app.tools.run_rag_index
  --source "$SOURCE"
  --embedding-method "$EMBEDDING_METHOD"
  --limit "$LIMIT"
  --top-k "$TOP_K"
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
if [[ -n "$QUERY" ]]; then
  ARGS+=(--query "$QUERY")
fi
if [[ -n "$PLACE_ID" ]]; then
  ARGS+=(--place-id "$PLACE_ID")
fi
"$PYTHON" "${ARGS[@]}"
