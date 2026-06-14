#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

JOB_ID=""
PYTHON_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --job-id)
      JOB_ID="${2:-}"
      shift 2
      ;;
    --python)
      PYTHON_ARG="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/smoke_workers.sh [--job-id JOB_ID] [--python PATH]"
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

echo "Listing LALA-next worker contracts..."
LIST_OUTPUT="$("$PYTHON" -m apps.workers.app.cli list --json)"

echo "Evaluating worker live preflight..."
PREFLIGHT_ARGS=(-m apps.workers.app.cli preflight --json)
if [[ -n "$JOB_ID" ]]; then
  PREFLIGHT_ARGS+=(--job-id "$JOB_ID")
fi
PREFLIGHT_OUTPUT="$("$PYTHON" "${PREFLIGHT_ARGS[@]}")"
JSON_PAYLOAD="$PREFLIGHT_OUTPUT" "$PYTHON" <<'PY'
import json
import os

payload = json.loads(os.environ["JSON_PAYLOAD"])
if not payload.get("ok") or payload.get("mode") != "live_preflight":
    raise SystemExit("Worker preflight returned an unexpected payload.")
if payload.get("ready") is not False:
    raise SystemExit("Worker live preflight should remain blocked in Wave 1.")
PY

if [[ -n "$JOB_ID" ]]; then
  JOB_IDS=("$JOB_ID")
else
  mapfile -t JOB_IDS < <(JSON_PAYLOAD="$LIST_OUTPUT" "$PYTHON" - <<'PY' | tr -d '\r'
import json
import os

payload = json.loads(os.environ["JSON_PAYLOAD"])
for job in payload.get("jobs", []):
    print(job["job_id"])
PY
)
fi

for id in "${JOB_IDS[@]}"; do
  echo "Dry-run worker job $id"
  RUN_OUTPUT="$("$PYTHON" -m apps.workers.app.cli run "$id" --dry-run --json)"
  JSON_PAYLOAD="$RUN_OUTPUT" "$PYTHON" - "$id" <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["JSON_PAYLOAD"])
if not payload.get("ok") or payload.get("mode") != "dry_run":
    raise SystemExit(f"Worker dry-run returned an unexpected payload for {sys.argv[1]}.")
PY
done

echo "LALA-next worker smoke completed."
echo "Worker smoke uses dry-run only and never prints secret values."
