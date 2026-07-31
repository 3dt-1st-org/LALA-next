#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

SOURCE_ENV=""
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PREFIX="${LALA_AWS_SM_PREFIX:-lala-next/}"
API_BASE_URL="${LALA_API_BASE_URL:-https://api.lala-next.cloud}"

usage() {
  cat <<'EOF'
Usage: scripts/unix/flutter_with_build_env.sh [options] -- <flutter command...>

Runs a Flutter build/test command with only public build configuration injected.
It reads KAKAO_JAVASCRIPT_KEY from a trusted local dotenv file when available, or
from AWS Secrets Manager when the caller has access to the single build setting.
No API bearer token, database DSN, OpenAI key, or Logto management secret is read.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-env) SOURCE_ENV="${2:-}"; shift 2 ;;
    --region) REGION="${2:-}"; shift 2 ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --api-base-url) API_BASE_URL="${2:-}"; shift 2 ;;
    --) shift; break ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $# -eq 0 ]]; then
  echo "A Flutter command is required after --." >&2
  exit 2
fi

ROOT="$(repo_root)"
SOURCE_ENV="${SOURCE_ENV:-$ROOT/.env}"
key=""
if [[ -f "$SOURCE_ENV" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "$SOURCE_ENV"
  set +a
  key="${KAKAO_JAVASCRIPT_KEY:-}"
fi

if [[ -z "${key//[[:space:]]/}" ]] && command -v aws >/dev/null 2>&1; then
  key="$(aws secretsmanager get-secret-value --secret-id "${PREFIX}kakao-javascript-key" --region "$REGION" --query SecretString --output text --no-cli-pager 2>/dev/null || true)"
fi

if [[ -z "${key//[[:space:]]/}" ]]; then
  echo "KAKAO_JAVASCRIPT_KEY is required from a trusted dotenv file or the restricted build secret." >&2
  exit 1
fi

cd "$ROOT/apps/flutter_app"
echo "Flutter build configuration resolved (API host and domain-restricted map key only)."
echo "server_secret_printing=false"
exec "$@" "--dart-define=LALA_API_BASE_URL=$API_BASE_URL" "--dart-define=KAKAO_JAVASCRIPT_KEY=$key" "--dart-define=LALA_BUILD_SHA=$(git -C "$ROOT" rev-parse --short HEAD)"
