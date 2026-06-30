#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

DUMP_PATH=""
IMAGE="lala-next-postgres-local:16-postgis-vector"
CONTAINER_NAME=""
DB_USER="lala"
DB_NAME="lala"
PYTHON_ARG=""
APPLY="false"
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dump)
      DUMP_PATH="${2:-}"
      shift 2
      ;;
    --image)
      IMAGE="${2:-}"
      shift 2
      ;;
    --container)
      CONTAINER_NAME="${2:-}"
      shift 2
      ;;
    --db-user)
      DB_USER="${2:-}"
      shift 2
      ;;
    --db-name)
      DB_NAME="${2:-}"
      shift 2
      ;;
    --python)
      PYTHON_ARG="${2:-}"
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
      echo "Usage: scripts/unix/drill_restore_docker_postgres_backup.sh --dump PATH --apply --confirm DRILL_DOCKER_POSTGRES_RESTORE"
      echo "Restores a backup into a disposable Docker PostgreSQL container and verifies canonical schema."
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
PYTHON="$(select_python "$PYTHON_ARG")"
cd "$ROOT"

if [[ -z "$DUMP_PATH" ]]; then
  latest_dump="$(find "$ROOT/runtime/backups" -type f -name 'lala-docker-postgres-*.dump' -print 2>/dev/null | sort | tail -n 1 || true)"
  DUMP_PATH="$latest_dump"
fi
if [[ -z "$CONTAINER_NAME" ]]; then
  CONTAINER_NAME="lala-restore-drill-$(date -u +%Y%m%dT%H%M%SZ)-$$"
fi

echo "LALA Docker PostgreSQL restore drill"
MODE="plan"
if [[ "$APPLY" == "true" && "$CONFIRM" == "DRILL_DOCKER_POSTGRES_RESTORE" ]]; then
  MODE="apply"
fi
echo "mode=$MODE"
echo "image=$IMAGE"
echo "container=$CONTAINER_NAME"
echo "dump=${DUMP_PATH:-missing}"
echo "db_name=$DB_NAME"
echo "db_user=$DB_USER"
echo "secret_printing=false"

if [[ "$APPLY" != "true" || "$CONFIRM" != "DRILL_DOCKER_POSTGRES_RESTORE" ]]; then
  echo "To execute: add --apply --confirm DRILL_DOCKER_POSTGRES_RESTORE"
  exit 0
fi

require_command docker

if [[ -z "$DUMP_PATH" || ! -s "$DUMP_PATH" ]]; then
  echo "Dump file is missing or empty: ${DUMP_PATH:-}" >&2
  exit 2
fi
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Docker image is missing: $IMAGE" >&2
  echo "Build it with: docker compose -f compose.local.yml build postgres" >&2
  exit 1
fi

password="restore-drill-$RANDOM-$(date -u +%s)"
cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  rm -f "${schema_result_path:-}"
}
trap cleanup EXIT

docker run -d --name "$CONTAINER_NAME" \
  -e "POSTGRES_USER=$DB_USER" \
  -e "POSTGRES_PASSWORD=$password" \
  -e "POSTGRES_DB=$DB_NAME" \
  -p "127.0.0.1::5432" \
  "$IMAGE" >/dev/null

for _ in $(seq 1 90); do
  if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "PostgreSQL init process complete"; then
    break
  fi
  sleep 1
done

if ! docker logs "$CONTAINER_NAME" 2>&1 | grep -q "PostgreSQL init process complete"; then
  echo "Restore drill container did not finish PostgreSQL initialization." >&2
  exit 1
fi

for _ in $(seq 1 60); do
  if docker exec "$CONTAINER_NAME" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! docker exec "$CONTAINER_NAME" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
  echo "Restore drill container did not become ready." >&2
  exit 1
fi

docker exec "$CONTAINER_NAME" \
  psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
  -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS vector;' \
  >/dev/null

docker exec -i "$CONTAINER_NAME" \
  pg_restore -U "$DB_USER" -d "$DB_NAME" --no-owner --no-acl \
  < "$DUMP_PATH" >/dev/null

host_port="$(docker inspect --format '{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}' "$CONTAINER_NAME")"
if [[ -z "$host_port" ]]; then
  echo "Could not resolve restore drill host port." >&2
  exit 1
fi

schema_result_path="$(mktemp /tmp/lala-restore-drill-schema.XXXXXX.json)"
dsn_scheme="postgresql"
DB_DSN="$dsn_scheme://$DB_USER:$password@127.0.0.1:$host_port/$DB_NAME" \
  "$PYTHON" -m apps.api.app.tools.verify_db_schema --json >"$schema_result_path"

docker exec "$CONTAINER_NAME" \
  psql -U "$DB_USER" -d "$DB_NAME" -Atqc \
  "select 'places', count(*) from travel.places union all select 'events', count(*) from culture.events union all select 'rag_chunks', count(*) from rag.knowledge_chunks union all select 'score_snapshots', count(*) from analytics.place_score_snapshots order by 1;"

echo "docker_postgres_restore_drill=ok"
