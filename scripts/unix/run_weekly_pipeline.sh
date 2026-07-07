#!/usr/bin/env bash
# 주간 데이터 파이프라인 실행 (DAG 순서).
# systemd timer(lala-next-pipeline.timer, KST 일요일 04:00)에서 호출.
# 환경변수 ALLOW_*_APPLY=1 은 systemd unit에서 주입. .env의 API 키는 plan_*.sh가 _common.sh로 자동 로드.
# RAG 임베딩(openai) 실행 시에만 LALA_ENABLE_LIVE_AI=true — FastAPI 런타임과 격리.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$(dirname "$SCRIPT_DIR")"

LOG_DIR="${LALA_LOG_DIR:-runtime/logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/weekly-pipeline-$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Weekly pipeline started at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

# Phase 1: 외부 소스 (경기+서울)
echo "--- Phase 1: external sources ---"
bash "$SCRIPT_DIR/plan_tour_api_ingest.sh" --apply --confirm APPLY_TOUR_API_INGEST --area-code 31 --rows 40   # 경기
bash "$SCRIPT_DIR/plan_tour_api_ingest.sh" --apply --confirm APPLY_TOUR_API_INGEST --area-code 1  --rows 40   # 서울
bash "$SCRIPT_DIR/plan_culture_info_ingest.sh" --apply --confirm APPLY_CULTURE_INFO_INGEST --sido 경기 --rows 20
bash "$SCRIPT_DIR/plan_kopis_ingest.sh" --apply --confirm APPLY_KOPIS_INGEST --signgucode 41 --rows 20         # 경기
bash "$SCRIPT_DIR/plan_kopis_ingest.sh" --apply --confirm APPLY_KOPIS_INGEST --signgucode 11 --rows 20         # 서울
bash "$SCRIPT_DIR/plan_franchise_reference_ingest.sh" --apply --confirm APPLY_FRANCHISE_REFERENCE_INGEST

# Phase 2: 처리
echo "--- Phase 2: processing ---"
bash "$SCRIPT_DIR/plan_franchise_identity_batch.sh" --apply --confirm APPLY_FRANCHISE_IDENTITY_BATCH --category all --limit 500

# Phase 3: 집계 (data_freshness 직접 타겟)
echo "--- Phase 3: aggregation ---"
bash "$SCRIPT_DIR/plan_place_score_batch.sh" --apply --confirm APPLY_PLACE_SCORE_BATCH --category all --limit 500

# Phase 4: RAG 임베딩 (live_ai 임시 활성화 → 실행 → 비활성화)
echo "--- Phase 4: RAG indexing (LALA_ENABLE_LIVE_AI=true) ---"
export LALA_ENABLE_LIVE_AI=true
bash "$SCRIPT_DIR/plan_rag_index.sh" --apply --confirm APPLY_RAG_INDEX --source all --embedding-method openai --limit 500
unset LALA_ENABLE_LIVE_AI

# Phase 5: 날씨 (24h freshness, 가장 마지막)
echo "--- Phase 5: weather refresh ---"
bash "$SCRIPT_DIR/plan_weather_observation_refresh.sh" --apply --confirm APPLY_WEATHER_OBSERVATION_REFRESH --limit 20

echo "=== Weekly pipeline completed at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
