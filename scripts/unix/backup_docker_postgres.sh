#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

ENV_FILE=""
CONTAINER_NAME="lala-next-postgres"
BACKUP_DIR=""
OFFSITE_DIR=""
RETENTION_DAYS="14"
REQUIRE_OFFSITE="false"
APPLY="false"
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --container)
      CONTAINER_NAME="${2:-}"
      shift 2
      ;;
    --backup-dir)
      BACKUP_DIR="${2:-}"
      shift 2
      ;;
    --offsite-dir)
      OFFSITE_DIR="${2:-}"
      shift 2
      ;;
    --require-offsite)
      REQUIRE_OFFSITE="true"
      shift
      ;;
    --retention-days)
      RETENTION_DAYS="${2:-}"
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
      echo "Usage: scripts/unix/backup_docker_postgres.sh [--env-file PATH] [--backup-dir PATH] [--offsite-dir PATH] [--require-offsite] [--retention-days DAYS] --apply --confirm BACKUP_DOCKER_POSTGRES"
      echo "Creates a custom-format PostgreSQL dump from the Docker PostgreSQL container."
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
  if [[ -f "$ROOT/runtime/onprem-api.env" ]]; then
    ENV_FILE="$ROOT/runtime/onprem-api.env"
  else
    ENV_FILE="$ROOT/runtime/local-postgres.env"
  fi
fi
if [[ -z "$BACKUP_DIR" ]]; then
  BACKUP_DIR="$ROOT/runtime/backups"
fi

if [[ -f "$ENV_FILE" ]]; then
  load_env_file "$ENV_FILE"
fi

if [[ -z "${LALA_POSTGRES_USER:-}" ]]; then
  LALA_POSTGRES_USER="lala"
fi
if [[ -z "${LALA_POSTGRES_DB:-}" ]]; then
  LALA_POSTGRES_DB="lala"
fi

case "$RETENTION_DAYS" in
  ''|*[!0-9]*)
    echo "--retention-days must be a non-negative integer." >&2
    exit 2
    ;;
esac

echo "LALA Docker PostgreSQL backup"
echo "container=$CONTAINER_NAME"
echo "backup_dir=$BACKUP_DIR"
echo "offsite_dir=${OFFSITE_DIR:-disabled}"
echo "require_offsite=$REQUIRE_OFFSITE"
echo "retention_days=$RETENTION_DAYS"
echo "db_name=$LALA_POSTGRES_DB"
echo "db_user=$LALA_POSTGRES_USER"
echo "secret_printing=false"

if [[ "$APPLY" != "true" || "$CONFIRM" != "BACKUP_DOCKER_POSTGRES" ]]; then
  echo "mode=plan"
  echo "To execute: add --apply --confirm BACKUP_DOCKER_POSTGRES"
  exit 0
fi

require_command docker

if [[ "$REQUIRE_OFFSITE" == "true" && -z "$OFFSITE_DIR" ]]; then
  echo "--require-offsite requires --offsite-dir." >&2
  exit 2
fi
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Env file is missing: $ENV_FILE" >&2
  exit 1
fi
if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "Docker container is not available: $CONTAINER_NAME" >&2
  exit 1
fi

health_status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"
if [[ "$health_status" != "healthy" ]]; then
  echo "Docker PostgreSQL container is not healthy: ${health_status:-unknown}" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_name="lala-docker-postgres-$timestamp.dump"
tmp_path="$BACKUP_DIR/.$backup_name.tmp"
final_path="$BACKUP_DIR/$backup_name"

rm -f "$tmp_path"

echo "Creating Docker PostgreSQL dump..."
docker exec "$CONTAINER_NAME" \
  pg_dump \
  -U "$LALA_POSTGRES_USER" \
  -d "$LALA_POSTGRES_DB" \
  --format=custom \
  --no-owner \
  --no-privileges \
  > "$tmp_path"

docker exec -i "$CONTAINER_NAME" pg_restore --list < "$tmp_path" >/dev/null
mv "$tmp_path" "$final_path"
chmod 600 "$final_path"

backup_bytes="$(wc -c < "$final_path" | tr -d '[:space:]')"
echo "backup_created=$final_path"
echo "backup_bytes=$backup_bytes"

if [[ -n "$OFFSITE_DIR" ]]; then
  mkdir -p "$OFFSITE_DIR"
  cp -p "$final_path" "$OFFSITE_DIR/$backup_name"
  copied_bytes="$(wc -c < "$OFFSITE_DIR/$backup_name" | tr -d '[:space:]')"
  if [[ "$copied_bytes" != "$backup_bytes" ]]; then
    echo "Offsite backup copy size mismatch." >&2
    exit 1
  fi
  echo "offsite_copy=$OFFSITE_DIR/$backup_name"
elif [[ "$REQUIRE_OFFSITE" == "true" ]]; then
  echo "Offsite backup is required but was not created." >&2
  exit 1
fi

find "$BACKUP_DIR" -type f -name 'lala-docker-postgres-*.dump' -mtime +"$RETENTION_DAYS" -print -delete
if [[ -n "$OFFSITE_DIR" ]]; then
  find "$OFFSITE_DIR" -type f -name 'lala-docker-postgres-*.dump' -mtime +"$RETENTION_DAYS" -print -delete
fi

backup_count="$(find "$BACKUP_DIR" -type f -name 'lala-docker-postgres-*.dump' | wc -l | tr -d '[:space:]')"
echo "backup_count=$backup_count"
echo "docker_postgres_backup=ok"
