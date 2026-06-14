#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
JSON_STATUS="false"
API_PORT="0"

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
    --api-port)
      API_PORT="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/smoke_oauth_jwt.sh [--api-port PORT] [--json] [--python PATH]"
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
  echo "Running local OAuth/JWT smoke."
  echo "This script creates only local test keys, a local JWKS server, and a temporary local API process."
fi

ARGS=(-m apps.api.app.tools.smoke_oauth_jwt --api-port "$API_PORT")
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
"$PYTHON" "${ARGS[@]}"
