#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

PYTHON_ARG=""
START_COMPOSE="false"
APPLY_CANONICAL="false"
APPLY_DEV_RESET="false"
SCORE_APPLY="false"
RAG_APPLY="false"
SNAPSHOT_WRITE="false"
RUN_ALL="false"
CONNECT_TIMEOUT="5"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      RUN_ALL="true"
      shift
      ;;
    --start-compose)
      START_COMPOSE="true"
      shift
      ;;
    --apply-canonical)
      APPLY_CANONICAL="true"
      shift
      ;;
    --apply-dev-reset)
      APPLY_DEV_RESET="true"
      shift
      ;;
    --score-apply)
      SCORE_APPLY="true"
      shift
      ;;
    --rag-apply)
      RAG_APPLY="true"
      shift
      ;;
    --snapshot-write)
      SNAPSHOT_WRITE="true"
      shift
      ;;
    --connect-timeout)
      CONNECT_TIMEOUT="${2:-}"
      shift 2
      ;;
    --python)
      PYTHON_ARG="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/bootstrap_local_mvp_db.sh [--all] [--start-compose] [--apply-canonical] [--apply-dev-reset] [--score-apply] [--rag-apply] [--snapshot-write] [--python PATH]"
      echo "Default mode is plan only. Execution uses compose.local.yml and a localhost-only DB_DSN built from LALA_POSTGRES_* env values."
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
load_env_file "$ROOT/.env"

hydrate_local_postgres_env_from_db_dsn() {
  [[ -n "${DB_DSN:-}" ]] || return 0
  if [[ -n "${LALA_POSTGRES_PASSWORD:-}" &&
        -n "${LALA_POSTGRES_PORT:-}" &&
        -n "${LALA_POSTGRES_DB:-}" &&
        -n "${LALA_POSTGRES_USER:-}" ]]; then
    return 0
  fi

  local exports
  exports="$("$PYTHON" - <<'PY'
import os
import shlex
from urllib.parse import unquote, urlparse

dsn = os.environ.get("DB_DSN", "").strip()
if not dsn:
    raise SystemExit(0)

parsed = urlparse(dsn)
host = parsed.hostname or ""
if host not in {"localhost", "127.0.0.1", "::1"}:
    raise SystemExit(0)

values = {
    "LALA_POSTGRES_USER": unquote(parsed.username or "lala"),
    "LALA_POSTGRES_PASSWORD": unquote(parsed.password or ""),
    "LALA_POSTGRES_PORT": str(parsed.port or 5432),
    "LALA_POSTGRES_DB": unquote((parsed.path or "/lala").lstrip("/") or "lala"),
}

for key, value in values.items():
    if os.environ.get(key, "").strip():
        continue
    if key == "LALA_POSTGRES_PASSWORD" and not value:
        continue
    print(f"export {key}={shlex.quote(value)}")
PY
)"
  if [[ -n "$exports" ]]; then
    eval "$exports"
  fi
}

hydrate_local_postgres_env_from_db_dsn

if [[ "$RUN_ALL" == "true" ]]; then
  START_COMPOSE="true"
  APPLY_CANONICAL="true"
  APPLY_DEV_RESET="true"
  SCORE_APPLY="true"
  RAG_APPLY="true"
  SNAPSHOT_WRITE="true"
fi

requested_any="false"
for flag in "$START_COMPOSE" "$APPLY_CANONICAL" "$APPLY_DEV_RESET" "$SCORE_APPLY" "$RAG_APPLY" "$SNAPSHOT_WRITE"; do
  if [[ "$flag" == "true" ]]; then
    requested_any="true"
  fi
done

print_plan() {
  echo "LALA-next local MVP DB bootstrap"
  echo "mode=plan"
  echo "uses_docker_compose=true"
  echo "compose_file=compose.local.yml"
  echo "db_host=localhost"
  echo "db_port=${LALA_POSTGRES_PORT:-55432}"
  echo "db_name=${LALA_POSTGRES_DB:-lala}"
  echo "db_user=${LALA_POSTGRES_USER:-lala}"
  echo "secret_printing=false"
  echo "step=1 start local PostgreSQL: scripts/unix/bootstrap_local_mvp_db.sh --start-compose"
  echo "step=2 apply canonical SQL: scripts/unix/bootstrap_local_mvp_db.sh --apply-canonical"
  echo "step=3 seed local review data: scripts/unix/bootstrap_local_mvp_db.sh --apply-dev-reset"
  echo "step=4 compute scores: scripts/unix/bootstrap_local_mvp_db.sh --score-apply"
  echo "step=5 build RAG vectors: scripts/unix/bootstrap_local_mvp_db.sh --rag-apply"
  echo "step=6 write bundled public snapshot: scripts/unix/bootstrap_local_mvp_db.sh --snapshot-write"
  echo "step=all run the local pipeline: scripts/unix/bootstrap_local_mvp_db.sh --all"
  echo "DB_DSN and LALA_POSTGRES_PASSWORD values are never printed by this script."
}

build_local_dsn() {
  if [[ -z "${LALA_POSTGRES_PASSWORD:-}" ]]; then
    echo "LALA_POSTGRES_PASSWORD is required for local DB execution." >&2
    return 2
  fi

  LALA_POSTGRES_USER="${LALA_POSTGRES_USER:-lala}" \
  LALA_POSTGRES_PASSWORD="${LALA_POSTGRES_PASSWORD}" \
  LALA_POSTGRES_HOST="localhost" \
  LALA_POSTGRES_PORT="${LALA_POSTGRES_PORT:-55432}" \
  LALA_POSTGRES_DB="${LALA_POSTGRES_DB:-lala}" \
  "$PYTHON" - <<'PY'
import os
from urllib.parse import quote

user = quote(os.environ["LALA_POSTGRES_USER"], safe="")
password = quote(os.environ["LALA_POSTGRES_PASSWORD"], safe="")
host = os.environ["LALA_POSTGRES_HOST"]
port = os.environ["LALA_POSTGRES_PORT"]
db = quote(os.environ["LALA_POSTGRES_DB"], safe="")
scheme = "postgresql"
print(f"{scheme}://{user}:{password}@{host}:{port}/{db}")
PY
}

wait_for_postgres() {
  local attempts=60
  local status=""
  for _ in $(seq 1 "$attempts"); do
    status="$(docker inspect --format '{{.State.Health.Status}}' lala-next-postgres 2>/dev/null || true)"
    if [[ "$status" == "healthy" ]]; then
      echo "local_postgres=healthy"
      return 0
    fi
    sleep 2
  done
  echo "Local PostgreSQL did not become healthy." >&2
  return 1
}

if [[ "$requested_any" != "true" ]]; then
  print_plan
  exit 0
fi

LOCAL_DSN="$(build_local_dsn)"
export DB_DSN="$LOCAL_DSN"

echo "LALA-next local MVP DB bootstrap"
echo "mode=execute"
echo "secret_printing=false"
echo "DB_DSN and LALA_POSTGRES_PASSWORD values are never printed by this script."

if [[ "$START_COMPOSE" == "true" ]]; then
  require_command docker
  echo "Starting local PostgreSQL with compose.local.yml..."
  docker compose -f compose.local.yml up -d postgres
  wait_for_postgres
fi

if [[ "$APPLY_CANONICAL" == "true" ]]; then
  echo "Applying canonical SQL to local PostgreSQL..."
  ALLOW_CANONICAL_SQL_APPLY=1 "$ROOT/scripts/unix/apply_canonical_sql.sh" \
    --apply \
    --confirm APPLY_CANONICAL_SQL \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --python "$PYTHON"
  "$ROOT/scripts/unix/verify_db_schema.sh" \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --python "$PYTHON"
fi

if [[ "$APPLY_DEV_RESET" == "true" ]]; then
  echo "Applying local dev seed/reset SQL..."
  ALLOW_DEV_RESET_APPLY=1 "$ROOT/scripts/unix/plan_dev_reset.sh" \
    --apply \
    --confirm APPLY_DEV_RESET_SQL \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --python "$PYTHON"
fi

if [[ "$SCORE_APPLY" == "true" ]]; then
  echo "Computing local-value score snapshots..."
  ALLOW_PLACE_SCORE_BATCH_APPLY=1 "$ROOT/scripts/unix/plan_place_score_batch.sh" \
    --apply \
    --confirm APPLY_PLACE_SCORE_BATCH \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --python "$PYTHON"
fi

if [[ "$RAG_APPLY" == "true" ]]; then
  echo "Building local RAG knowledge vectors..."
  ALLOW_RAG_INDEX_APPLY=1 "$ROOT/scripts/unix/plan_rag_index.sh" \
    --apply \
    --confirm APPLY_RAG_INDEX \
    --source all \
    --embedding-method local-hash \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --python "$PYTHON"
fi

if [[ "$SNAPSHOT_WRITE" == "true" ]]; then
  echo "Writing bundled public MVP snapshot from local DB..."
  ALLOW_PUBLIC_MVP_SNAPSHOT_WRITE=1 "$ROOT/scripts/unix/export_public_mvp_snapshot.sh" \
    --write \
    --confirm WRITE_PUBLIC_MVP_SNAPSHOT \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --python "$PYTHON"
fi

echo "local_mvp_db_bootstrap=ok"
