#!/usr/bin/env bash
# Redaction repair for legacy URL-shaped values in
# community.place_mentions_weekly.attributes (S2 companion to the S1 ingest
# redaction). Dry-run by default; apply requires the two-man rule:
#   ALLOW_PLACE_MENTION_REPAIR_APPLY=1 + --confirm APPLY_PLACE_MENTION_ATTRIBUTE_REPAIR
# DB_DSN value is never printed by this script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
JSON_STATUS="false"
DRY_RUN="false"
APPLY="false"
CONFIRM=""
LIMIT="10000"
CONNECT_TIMEOUT="5"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --apply)
      APPLY="true"
      shift
      ;;
    --confirm)
      CONFIRM="${2:-}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    --connect-timeout)
      CONNECT_TIMEOUT="${2:-}"
      shift 2
      ;;
    --python)
      PYTHON_ARG="${2:-}"
      shift 2
      ;;
    --json)
      JSON_STATUS="true"
      shift
      ;;
    -h|--help)
      echo "Usage: scripts/unix/repair_place_mention_attributes.sh [--dry-run|--apply --confirm APPLY_PLACE_MENTION_ATTRIBUTE_REPAIR] [--limit N] [--json] [--connect-timeout SECONDS] [--python PATH]"
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

load_env_names_from_file "$ROOT/.env" DB_DSN

if [[ "$JSON_STATUS" != "true" ]]; then
  echo "LALA-next place_mentions_weekly attribute redaction repair."
  echo "Default mode is plan only (counts, no DB reads)."
  echo "Dry-run scans and reports counts; no DB writes."
  echo "Apply mode requires ALLOW_PLACE_MENTION_REPAIR_APPLY=1."
  echo "DB_DSN value is never printed by this script."
fi

ARGS=(
  -m apps.api.app.tools.run_place_mention_attribute_repair
  --limit "$LIMIT"
  --connect-timeout "$CONNECT_TIMEOUT"
)
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
if [[ "$DRY_RUN" == "true" ]]; then
  ARGS+=(--dry-run)
fi
if [[ "$APPLY" == "true" ]]; then
  ARGS+=(--apply --confirm "$CONFIRM")
fi
"$PYTHON" "${ARGS[@]}"
