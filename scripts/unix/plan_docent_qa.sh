#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
JSON_STATUS="false"
PREVIEW="false"
CATEGORY="all"
LIMIT="40"
CONNECT_TIMEOUT="5"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preview)
      PREVIEW="true"
      shift
      ;;
    --category)
      CATEGORY="${2:-}"
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
      echo "Usage: scripts/unix/plan_docent_qa.sh [--preview] [--category all] [--limit 30..50] [--json] [--python PATH]"
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

if [[ "$JSON_STATUS" != "true" ]]; then
  echo "Planning LALA-next representative docent manual QA."
  echo "Default mode is dry-run plan only."
  echo "Preview mode reads DB/RAG signals but does not mutate DB or generate scripts."
  echo "DB_DSN value is never printed by this script."
fi

ARGS=(
  -m apps.api.app.tools.plan_docent_qa
  --category "$CATEGORY"
  --limit "$LIMIT"
  --connect-timeout "$CONNECT_TIMEOUT"
)
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
if [[ "$PREVIEW" == "true" ]]; then
  ARGS+=(--preview)
fi
"$PYTHON" "${ARGS[@]}"
