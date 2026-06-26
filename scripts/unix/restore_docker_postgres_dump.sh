#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

DUMP_PATH=""
ENV_FILE=""
CONTAINER_NAME="lala-next-postgres"
APPLY="false"
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dump)
      DUMP_PATH="${2:-}"
      shift 2
      ;;
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --container)
      CONTAINER_NAME="${2:-}"
      shift 2
      ;;
    --apply)
      APPLY="true"
      shift
      ;;
    --confirm)
      CONFIRM="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/unix/restore_docker_postgres_dump.sh --dump PATH [--env-file PATH] [--container NAME] --apply --confirm RESTORE_DOCKER_POSTGRES"
      echo "Restores a custom-format PostgreSQL dump into the Docker PostgreSQL container."
      echo "Secrets and DB_DSN values are never printed."
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

if [[ -z "$ENV_FILE" ]]; then
  ENV_FILE="$ROOT/runtime/local-postgres.env"
fi

if [[ -z "$DUMP_PATH" ]]; then
  echo "--dump is required." >&2
  exit 2
fi

if [[ ! -s "$DUMP_PATH" ]]; then
  echo "Dump file is missing or empty: $DUMP_PATH" >&2
  exit 2
fi

if [[ -f "$ENV_FILE" ]]; then
  load_env_file "$ENV_FILE"
fi
load_env_file "$ROOT/.env"

if [[ -z "${LALA_POSTGRES_USER:-}" ]]; then
  LALA_POSTGRES_USER="lala"
fi
if [[ -z "${LALA_POSTGRES_DB:-}" ]]; then
  LALA_POSTGRES_DB="lala"
fi

if [[ "$APPLY" != "true" || "$CONFIRM" != "RESTORE_DOCKER_POSTGRES" ]]; then
  echo "LALA Docker PostgreSQL dump restore"
  echo "mode=plan"
  echo "container=$CONTAINER_NAME"
  echo "dump=$DUMP_PATH"
  echo "env_file=$ENV_FILE"
  echo "db_name=$LALA_POSTGRES_DB"
  echo "db_user=$LALA_POSTGRES_USER"
  echo "destructive_restore=false"
  echo "To execute: add --apply --confirm RESTORE_DOCKER_POSTGRES"
  echo "Secrets and DB_DSN values are never printed."
  exit 0
fi

require_command docker

if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "Docker container is not available: $CONTAINER_NAME" >&2
  exit 1
fi

status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"
if [[ "$status" != "healthy" ]]; then
  echo "Docker PostgreSQL container is not healthy: ${status:-unknown}" >&2
  exit 1
fi

echo "Restoring dump into Docker PostgreSQL..."
echo "container=$CONTAINER_NAME"
echo "db_name=$LALA_POSTGRES_DB"
echo "secret_printing=false"

docker exec "$CONTAINER_NAME" \
  psql -U "$LALA_POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$LALA_POSTGRES_DB' AND pid <> pg_backend_pid();" \
  >/dev/null
docker exec "$CONTAINER_NAME" dropdb -U "$LALA_POSTGRES_USER" --if-exists "$LALA_POSTGRES_DB"
docker exec "$CONTAINER_NAME" createdb -U "$LALA_POSTGRES_USER" "$LALA_POSTGRES_DB"
docker exec "$CONTAINER_NAME" \
  psql -U "$LALA_POSTGRES_USER" -d "$LALA_POSTGRES_DB" -v ON_ERROR_STOP=1 \
  -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS vector;' \
  >/dev/null
docker exec -i "$CONTAINER_NAME" \
  pg_restore -U "$LALA_POSTGRES_USER" -d "$LALA_POSTGRES_DB" --no-owner --no-acl \
  < "$DUMP_PATH"

docker exec "$CONTAINER_NAME" \
  psql -U "$LALA_POSTGRES_USER" -d "$LALA_POSTGRES_DB" -Atqc \
  "select 'places', count(*) from travel.places union all select 'events', count(*) from culture.events union all select 'rag_chunks', count(*) from rag.knowledge_chunks union all select 'score_snapshots', count(*) from analytics.place_score_snapshots order by 1;"

echo "docker_postgres_restore=ok"
