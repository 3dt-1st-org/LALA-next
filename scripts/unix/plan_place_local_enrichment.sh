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
      echo "Usage: scripts/unix/plan_place_local_enrichment.sh [tool args...] [--python PATH]"
      echo "Tool args include --preview, --apply, --refresh-local, --confirm APPLY_LOCAL_PLACE_ENRICHMENT, --limit N, --json."
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
load_env_file "$ROOT/.env"

if [[ " ${ARGS[*]} " != *" --json "* ]]; then
  echo "Planning LALA-next local place enrichment."
  echo "Default mode is plan only and does not read or mutate DB."
  echo "Preview mode reads DB and shows local romanization candidates."
  echo "Apply mode requires ALLOW_LOCAL_PLACE_ENRICHMENT_APPLY=1."
  echo "DB_DSN value is never printed by this script."
fi

"$PYTHON" -m apps.api.app.tools.enrich_place_local_columns "${ARGS[@]}"
