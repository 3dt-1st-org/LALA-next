#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
JSON_STATUS="false"
LOG_PATH=""
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
    --request-id|--route-path|--limit)
      EXTRA_ARGS+=("$1" "${2:-}")
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/inspect_access_log.sh PATH [--request-id ID] [--route-path PATH] [--limit N] [--json] [--python PATH]"
      exit 0
      ;;
    *)
      if [[ -z "$LOG_PATH" ]]; then
        LOG_PATH="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$LOG_PATH" ]]; then
  echo "Access log path is required." >&2
  exit 2
fi

ROOT="$(repo_root)"
PYTHON="$(select_python "$PYTHON_ARG")"
cd "$ROOT"

if [[ "$JSON_STATUS" != "true" ]]; then
  echo "Inspecting a local LALA-next JSONL access log."
  echo "This script is read-only and prints only bounded access-log fields."
fi

ARGS=(-m apps.api.app.tools.inspect_access_log "$LOG_PATH")
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
ARGS+=("${EXTRA_ARGS[@]}")
"$PYTHON" "${ARGS[@]}"
