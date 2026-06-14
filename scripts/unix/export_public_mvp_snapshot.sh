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
      echo "Usage: scripts/unix/export_public_mvp_snapshot.sh [tool args...] [--python PATH]"
      echo "Tool args include --preview, --write, --confirm WRITE_PUBLIC_MVP_SNAPSHOT, --output PATH, --json."
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
  echo "Planning LALA-next public MVP snapshot export."
  echo "Default mode is dry-run plan only."
  echo "Write mode requires ALLOW_PUBLIC_MVP_SNAPSHOT_WRITE=1."
  echo "DB_DSN value is never printed by this script."
fi

"$PYTHON" -m apps.api.app.tools.export_public_mvp_snapshot "${ARGS[@]}"
