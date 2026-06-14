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
    --subscription-id|--resource-group|--location|--key-vault-name|--postgres-server-name|--database-name|--admin-user|--sku-name|--tier|--storage-size-gb|--public-access)
      EXTRA_ARGS+=("$1" "${2:-}")
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/plan_db_rollout.sh [--json] [--python PATH] [plan options]"
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
  echo "Planning LALA-next PostgreSQL rollout."
  echo "This script does not create Azure resources, apply SQL, or print secrets."
fi

ARGS=(-m apps.api.app.tools.plan_db_rollout)
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
ARGS+=("${EXTRA_ARGS[@]}")
"$PYTHON" "${ARGS[@]}"
