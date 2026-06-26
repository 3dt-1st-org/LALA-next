#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

OFFSITE_DIR="${LALA_ONPREM_OFFSITE_BACKUP_DIR:-}"
ALLOW_REPO_PATH="false"
ALLOW_SAME_FILESYSTEM="false"
APPLY="false"
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --offsite-dir) OFFSITE_DIR="${2:-}"; shift 2 ;;
    --allow-repo-path) ALLOW_REPO_PATH="true"; shift ;;
    --allow-same-filesystem) ALLOW_SAME_FILESYSTEM="true"; shift ;;
    --apply) APPLY="true"; shift ;;
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/verify_onprem_offsite_backup.sh --offsite-dir PATH --apply --confirm VERIFY_OFFSITE_BACKUP"
      echo "Verifies an off-host backup target is writable without printing secret values."
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

echo "LALA on-prem offsite backup target verification"
echo "offsite_dir=${OFFSITE_DIR:-missing}"
echo "allow_repo_path=$ALLOW_REPO_PATH"
echo "allow_same_filesystem=$ALLOW_SAME_FILESYSTEM"
echo "secret_printing=false"

if [[ -z "$OFFSITE_DIR" ]]; then
  echo "Offsite backup target is required. Pass --offsite-dir or set LALA_ONPREM_OFFSITE_BACKUP_DIR." >&2
  exit 2
fi

case "$OFFSITE_DIR" in
  "$ROOT"|"$ROOT"/*)
    if [[ "$ALLOW_REPO_PATH" != "true" ]]; then
      echo "Offsite backup target must not be inside the repository." >&2
      exit 2
    fi
    ;;
esac

if [[ "$APPLY" != "true" || "$CONFIRM" != "VERIFY_OFFSITE_BACKUP" ]]; then
  echo "mode=plan"
  echo "To execute: add --apply --confirm VERIFY_OFFSITE_BACKUP"
  exit 0
fi

mkdir -p "$OFFSITE_DIR"

repo_device="$(df -P "$ROOT" | awk 'NR==2 {print $1}')"
offsite_device="$(df -P "$OFFSITE_DIR" | awk 'NR==2 {print $1}')"
if [[ -n "$repo_device" && "$repo_device" == "$offsite_device" && "$ALLOW_SAME_FILESYSTEM" != "true" ]]; then
  echo "Offsite target appears to be on the same filesystem as the repository: $offsite_device" >&2
  echo "Use a mounted backup volume or rerun with --allow-same-filesystem only for temporary rehearsal." >&2
  exit 1
fi

test_file="$OFFSITE_DIR/.lala-offsite-write-test-$$"
trap 'rm -f "$test_file"' EXIT
printf 'lala-next offsite backup write test\n' >"$test_file"
test_bytes="$(wc -c < "$test_file" | tr -d '[:space:]')"
if [[ "$test_bytes" != "36" ]]; then
  echo "Offsite write verification produced an unexpected byte count." >&2
  exit 1
fi
rm -f "$test_file"
trap - EXIT

echo "repo_filesystem=$repo_device"
echo "offsite_filesystem=$offsite_device"
echo "offsite_backup_target=ok"
