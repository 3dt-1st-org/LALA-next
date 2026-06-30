#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

TARGET_OS="macos"
STANDBY_HOST="${LALA_ONPREM_STANDBY_HOST:-<standby-host>}"
BACKUP_SOURCE="${LALA_ONPREM_OFFSITE_BACKUP_DIR:-<offsite-backup-dir>}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-os) TARGET_OS="${2:-}"; shift 2 ;;
    --standby-host) STANDBY_HOST="${2:-}"; shift 2 ;;
    --backup-source) BACKUP_SOURCE="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/unix/plan_onprem_standby.sh [--target-os macos|linux] [--standby-host HOST] [--backup-source PATH]"
      echo "Prints a secret-safe cold-standby plan for the on-premises runtime."
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

case "$TARGET_OS" in
  macos|linux) ;;
  *)
    echo "--target-os must be macos or linux." >&2
    exit 2
    ;;
esac

echo "LALA on-prem standby plan"
echo "mode=plan"
echo "target_os=$TARGET_OS"
echo "standby_host=$STANDBY_HOST"
echo "backup_source=$BACKUP_SOURCE"
echo "secret_printing=false"
echo "applies_changes=false"
echo "step=1 Prepare a second host with Docker, git, uv, cloudflared, and enough disk headroom."
echo "step=2 Clone the repo and check out the approved branch or release commit."
echo "step=3 Create ignored runtime env files from the team secret store; do not copy them through git."
echo "step=4 Restore the latest verified dump from the offsite backup source into Docker PostgreSQL."
echo "step=5 Run scripts/unix/drill_restore_docker_postgres_backup.sh on the standby host."
echo "step=6 Start API locally and verify /healthz, /readyz, PostGIS, data freshness, live AI, and live speech."
echo "step=7 Keep cloudflared disabled until failover, or run a separate standby tunnel hostname for rehearsal."
echo "step=8 During failover, stop the primary tunnel, start standby tunnel, then run public smoke tests."
echo "step=9 After primary recovery, reverse-sync only through database backup/restore or an approved replication design."
