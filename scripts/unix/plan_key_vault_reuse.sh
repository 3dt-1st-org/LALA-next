#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
JSON_STATUS="false"
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --python)
      PYTHON_ARG="${2:-}"
      shift 2
      ;;
    --json)
      JSON_STATUS="true"
      shift
      ;;
    --source-vault-name|--target-vault-name)
      EXTRA_ARGS+=("$1" "${2:-}")
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/plan_key_vault_reuse.sh [--json] [--python PATH] [--source-vault-name NAME] [--target-vault-name NAME]"
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
  echo "Planning safe ONMU Key Vault reuse for LALA-next."
  echo "This script does not read or print secret values, copy secrets, set secrets, or change Azure resources."
fi

ARGS=(-m apps.api.app.tools.plan_key_vault_reuse)
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
ARGS+=("${EXTRA_ARGS[@]}")
"$PYTHON" "${ARGS[@]}"
