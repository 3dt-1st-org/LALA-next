#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"
source "$SCRIPT_DIR/_flutter_public_build_config.sh"

SOURCE_ENV=""
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PREFIX="${LALA_AWS_SM_PREFIX:-lala-next/}"
API_BASE_URL="${LALA_API_BASE_URL:-https://api.lala-next.cloud}"
# SSM Parameter Store name for the public build credential is operator-supplied
# only. The Naver Search API client id/secret are separate server credentials.
NAVER_MAP_CLIENT_ID_SSM_PARAM="${LALA_NAVER_MAP_CLIENT_ID_SSM_PARAM:-}"

usage() {
  cat <<'EOF'
Usage: scripts/unix/flutter_with_build_env.sh [options] -- <flutter command...>

Runs a Flutter build/test command with only public build configuration injected.
NAVER_MAP_CLIENT_ID is resolved in this order: AWS SSM Parameter Store when
--naver-map-client-id-ssm-param (or LALA_NAVER_MAP_CLIENT_ID_SSM_PARAM) is set, then AWS
Secrets Manager (the approved restricted build secret), then trusted
.env.local and .env files parsed in isolated subshells. No API bearer token, database DSN,
OpenAI key, Naver Search API secret, or Logto management secret is read.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-env) SOURCE_ENV="${2:-}"; shift 2 ;;
    --region) REGION="${2:-}"; shift 2 ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --api-base-url) API_BASE_URL="${2:-}"; shift 2 ;;
    --naver-map-client-id-ssm-param) NAVER_MAP_CLIENT_ID_SSM_PARAM="${2:-}"; shift 2 ;;
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

# Public build-credential resolution order:
#   1. Operator-selected SSM Parameter Store mapping for the Naver map id.
#   2. AWS Secrets Manager entries under the approved project prefix.
#   3. Trusted .env.local, then .env, each read in an isolated subshell.
key="${NAVER_MAP_CLIENT_ID:-}"

if [[ -z "${key//[[:space:]]/}" ]] && [[ -n "$NAVER_MAP_CLIENT_ID_SSM_PARAM" ]] && command -v aws >/dev/null 2>&1; then
  key="$(aws ssm get-parameter --with-decryption --name "$NAVER_MAP_CLIENT_ID_SSM_PARAM" --region "$REGION" --query 'Parameter.Value' --output text --no-cli-pager 2>/dev/null || true)"
fi

NAVER_MAP_CLIENT_ID="$key"

if [[ -n "$SOURCE_ENV" ]]; then
  FLUTTER_PUBLIC_ENV_FILES=("$SOURCE_ENV")
else
  FLUTTER_PUBLIC_ENV_FILES=("$ROOT/.env.local" "$ROOT/.env")
fi

BUILD_SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
platform="any"
for arg in "$@"; do
  case "$arg" in
    web) platform="web" ;;
    ios|apk|appbundle) platform="native" ;;
  esac
done

resolve_flutter_public_build_config "$platform" false
append_flutter_public_dart_defines

cd "$ROOT/apps/flutter_app"
echo "Flutter public build configuration resolved (map and optional Logto client identifiers)."
echo "server_secret_printing=false"
exec "$@" "${FLUTTER_PUBLIC_DART_DEFINES[@]}"
