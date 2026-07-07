#!/usr/bin/env bash
# 월간 카드 소비 데이터 적재. 최신 카드 zip 파일을 자동 탐색.
# systemd timer(lala-next-pipeline-card.timer, 매월 1일 KST 02:00)에서 호출.
# ALLOW_CARD_SPENDING_FILE_INGEST_APPLY=1 은 systemd unit에서 주입.
# 카드 파일이 없으면 안전하게 종료 (해당 월 데이터 미공개일 수 있음).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$(dirname "$SCRIPT_DIR")"

LOG_DIR="${LALA_LOG_DIR:-runtime/logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/monthly-card-$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "$LOG_FILE") 2>&1

CARD_DIR="${LALA_CARD_DIR:-artifacts/tmp/raw/gyeonggi-card}"
LATEST_ZIP=$(ls -t "${CARD_DIR}/"카드소비\ 데이터_*.zip 2>/dev/null | head -1 || true)

echo "=== Monthly card ingest started at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
if [[ -z "$LATEST_ZIP" ]]; then
  echo "WARN: no card spending zip found in $CARD_DIR — skipping (data not yet published?)."
  exit 0
fi

echo "Using card file: $LATEST_ZIP"
bash "$SCRIPT_DIR/plan_card_spending_file_ingest.sh" --apply --confirm APPLY_CARD_SPENDING_FILE_INGEST --file-path "$LATEST_ZIP"
echo "=== Monthly card ingest completed at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
