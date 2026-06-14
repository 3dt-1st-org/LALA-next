#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
JSON_STATUS="false"
BASE_URL="http://127.0.0.1:8080"
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
    --base-url)
      BASE_URL="${2:-}"
      shift 2
      ;;
    --key-vault-name|--api-app-name|--flutter-app-name|--api-app-id-uri|--required-scope)
      EXTRA_ARGS+=("$1" "${2:-}")
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/plan_identity_rollout.sh [--base-url URL] [--json] [--python PATH] [plan options]"
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
  echo "Planning LALA-next OAuth/Entra identity rollout."
  echo "This script does not create Entra apps, Key Vault secrets, token validators, or print secrets."
fi

ARGS=(-m apps.api.app.tools.plan_identity_rollout --base-url "$BASE_URL")
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
ARGS+=("${EXTRA_ARGS[@]}")
"$PYTHON" "${ARGS[@]}"
