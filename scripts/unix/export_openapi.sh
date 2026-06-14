#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

BASE_URL="http://127.0.0.1:8080"
OUTPUT_PATH="artifacts/openapi/lala-next-openapi.json"
IN_PROCESS="false"
JSON_STATUS="false"
PYTHON_ARG=""
CHECK_COMPAT_BASELINE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      BASE_URL="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --in-process)
      IN_PROCESS="true"
      shift
      ;;
    --json)
      JSON_STATUS="true"
      shift
      ;;
    --check-compat)
      CHECK_COMPAT_BASELINE="${2:-}"
      shift 2
      ;;
    --python)
      PYTHON_ARG="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/export_openapi.sh [--in-process] [--base-url URL] [--output PATH] [--json] [--python PATH]"
      echo "       scripts/unix/export_openapi.sh --check-compat BASELINE_JSON [--python PATH]"
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

if [[ -n "$CHECK_COMPAT_BASELINE" ]]; then
  ARGS=(-m apps.api.app.tools.check_openapi_compat "$CHECK_COMPAT_BASELINE")
  if [[ "$JSON_STATUS" == "true" ]]; then
    ARGS+=(--json)
  fi
  "$PYTHON" "${ARGS[@]}"
  exit 0
fi

case "$OUTPUT_PATH" in
  /*) RESOLVED_OUTPUT="$OUTPUT_PATH" ;;
  *) RESOLVED_OUTPUT="$ROOT/$OUTPUT_PATH" ;;
esac
mkdir -p "$(dirname "$RESOLVED_OUTPUT")"

if [[ "$IN_PROCESS" == "true" ]]; then
  echo "Exporting OpenAPI schema in-process"
  ARGS=(-m apps.api.app.tools.export_openapi --output "$RESOLVED_OUTPUT")
  if [[ "$JSON_STATUS" == "true" ]]; then
    ARGS+=(--json)
  fi
  "$PYTHON" "${ARGS[@]}"
  exit 0
fi

SCHEMA_URL="${BASE_URL%/}/openapi.json"
echo "Exporting OpenAPI schema from $SCHEMA_URL"
SCHEMA_URL="$SCHEMA_URL" RESOLVED_OUTPUT="$RESOLVED_OUTPUT" "$PYTHON" - <<'PY'
import json
import os
from pathlib import Path
from urllib.request import urlopen

schema_url = os.environ["SCHEMA_URL"]
output = Path(os.environ["RESOLVED_OUTPUT"])
with urlopen(schema_url, timeout=10) as response:
    schema = json.loads(response.read().decode("utf-8"))
output.write_text(json.dumps(schema, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
echo "OpenAPI schema written to $RESOLVED_OUTPUT"
