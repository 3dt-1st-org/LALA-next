#!/usr/bin/env bash
# 일일 날씨 갱신 (24h freshness 제약 — 방치하면 data_freshness degraded로 전락).
# systemd timer(lala-next-pipeline-daily.timer, KST 03:00)에서 호출.
# ALLOW_WEATHER_OBSERVATION_REFRESH_APPLY=1 은 systemd unit에서 주입.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$(dirname "$SCRIPT_DIR")"

LOG_DIR="${LALA_LOG_DIR:-runtime/logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/daily-weather-$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Daily weather refresh started at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
bash "$SCRIPT_DIR/plan_weather_observation_refresh.sh" --apply --confirm APPLY_WEATHER_OBSERVATION_REFRESH --limit 20
echo "=== Daily weather refresh completed at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
