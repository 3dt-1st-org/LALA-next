#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

LOG_DIR=""
MAX_BYTES="10485760"
RETENTION_DAYS="14"
APPLY="false"
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-dir) LOG_DIR="${2:-}"; shift 2 ;;
    --max-bytes) MAX_BYTES="${2:-}"; shift 2 ;;
    --retention-days) RETENTION_DAYS="${2:-}"; shift 2 ;;
    --apply) APPLY="true"; shift ;;
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/rotate_onprem_logs.sh [--log-dir PATH] [--max-bytes BYTES] [--retention-days DAYS] --apply --confirm ROTATE_ONPREM_LOGS"
      echo "Rotates ignored on-prem runtime logs without reading or printing secret values."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ROOT="$(repo_root)"
cd "$ROOT"
if [[ -z "$LOG_DIR" ]]; then
  LOG_DIR="$ROOT/runtime/logs"
fi

case "$MAX_BYTES" in ''|*[!0-9]*) echo "--max-bytes must be a positive integer." >&2; exit 2 ;; esac
case "$RETENTION_DAYS" in ''|*[!0-9]*) echo "--retention-days must be a non-negative integer." >&2; exit 2 ;; esac

echo "LALA on-prem log rotation"
echo "log_dir=$LOG_DIR"
echo "max_bytes=$MAX_BYTES"
echo "retention_days=$RETENTION_DAYS"
echo "secret_printing=false"

if [[ "$APPLY" != "true" || "$CONFIRM" != "ROTATE_ONPREM_LOGS" ]]; then
  echo "mode=plan"
  echo "To execute: add --apply --confirm ROTATE_ONPREM_LOGS"
  exit 0
fi

mkdir -p "$LOG_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
patterns=(
  "*.log"
  "*.err"
  "*.out"
  "*.jsonl"
)

rotated_count=0
for pattern in "${patterns[@]}"; do
  while IFS= read -r path; do
    [[ -f "$path" ]] || continue
    size="$(wc -c < "$path" | tr -d '[:space:]')"
    if (( size < MAX_BYTES )); then
      continue
    fi
    rotated="$path.$timestamp"
    mv "$path" "$rotated"
    : > "$path"
    if command -v gzip >/dev/null 2>&1; then
      gzip -f "$rotated"
      echo "rotated=$(basename "$rotated").gz bytes=$size"
    else
      echo "rotated=$(basename "$rotated") bytes=$size"
    fi
    rotated_count=$((rotated_count + 1))
  done < <(find "$LOG_DIR" -maxdepth 1 -type f -name "$pattern" -print)
done

find "$LOG_DIR" -maxdepth 1 -type f \( -name '*.gz' -o -name '*.log.*' -o -name '*.err.*' -o -name '*.out.*' -o -name '*.jsonl.*' \) -mtime +"$RETENTION_DAYS" -print -delete

echo "rotated_count=$rotated_count"
echo "onprem_log_rotation=ok"
