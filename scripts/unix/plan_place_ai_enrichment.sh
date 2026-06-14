#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --python)
      PYTHON_ARG="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/plan_place_ai_enrichment.sh [tool args...] [--python PATH]"
      echo "Tool args include --dry-run-ai, --apply, --confirm APPLY_AI_PLACE_ENRICHMENT, --category NAME, --limit N, --retry-attempts N, --json."
      exit 0
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

ROOT="$(repo_root)"
PYTHON="$(select_python "$PYTHON_ARG")"
cd "$ROOT"

if [[ " ${ARGS[*]} " != *" --json "* ]]; then
  echo "Planning LALA-next place AI enrichment."
  echo "Default mode is plan only and does not call Azure OpenAI."
  echo "Dry-run AI mode reads DB and calls Azure OpenAI but does not update rows."
  echo "Apply mode requires ALLOW_AI_PLACE_ENRICHMENT_APPLY=1."
  echo "AZURE_OPENAI_KEY and DB_DSN values are never printed by this script."
fi

"$PYTHON" -m apps.api.app.tools.enrich_place_ai_columns "${ARGS[@]}"
