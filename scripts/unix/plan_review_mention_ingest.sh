#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
JSON_STATUS="false"
PREVIEW="false"
APPLY="false"
CONFIRM=""
CATEGORY="all"
LIMIT="10"
ITEMS_PER_PLACE="10"
PROVIDER="naver_blog"
WEEK_START=""
TIMEOUT="10"
CONNECT_TIMEOUT="5"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preview)
      PREVIEW="true"
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
    --category)
      CATEGORY="${2:-}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    --items-per-place)
      ITEMS_PER_PLACE="${2:-}"
      shift 2
      ;;
    --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    --week-start)
      WEEK_START="${2:-}"
      shift 2
      ;;
    --timeout)
      TIMEOUT="${2:-}"
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
      echo "Usage: scripts/unix/plan_review_mention_ingest.sh [--preview|--apply --confirm APPLY_REVIEW_MENTION_INGEST] [--category all] [--limit N] [--items-per-place N] [--week-start YYYY-MM-DD] [--json] [--python PATH]"
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
  echo "Planning LALA-next review/mention preprocessing."
  echo "Default mode is dry-run plan only."
  echo "Preview mode calls Naver Blog Search but does not mutate DB."
  echo "Apply mode requires ALLOW_REVIEW_MENTION_INGEST_APPLY=1."
  echo "DB_DSN, NAVER_CLIENT_ID, and NAVER_CLIENT_SECRET values are never printed by this script."
fi

ARGS=(
  -m apps.api.app.tools.run_review_mention_ingest
  --category "$CATEGORY"
  --limit "$LIMIT"
  --items-per-place "$ITEMS_PER_PLACE"
  --provider "$PROVIDER"
  --timeout "$TIMEOUT"
  --connect-timeout "$CONNECT_TIMEOUT"
)
if [[ -n "$WEEK_START" ]]; then
  ARGS+=(--week-start "$WEEK_START")
fi
if [[ "$JSON_STATUS" == "true" ]]; then
  ARGS+=(--json)
fi
if [[ "$PREVIEW" == "true" ]]; then
  ARGS+=(--preview)
fi
if [[ "$APPLY" == "true" ]]; then
  ARGS+=(--apply --confirm "$CONFIRM")
fi
"$PYTHON" "${ARGS[@]}"
