#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

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
Secrets Manager (the approved restricted build secret), then a trusted local
dotenv file parsed in an isolated subshell. No API bearer token, database DSN,
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
SOURCE_ENV="${SOURCE_ENV:-$ROOT/.env}"

# Public build-credential resolution order:
#   1. AWS SSM Parameter Store -- only when the operator supplies a parameter name
#      (--naver-map-client-id-ssm-param / LALA_NAVER_MAP_CLIENT_ID_SSM_PARAM).
#      No default name is ever
#      assumed, so SSM is skipped until that mapping is decided (CORRECTION_REQUIRED).
#   2. AWS Secrets Manager -- the approved restricted build secret.
#   3. Trusted local dotenv -- parsed in an isolated subshell so only
#      NAVER_MAP_CLIENT_ID ever reaches this process or the Flutter build.
key=""

if [[ -z "${key//[[:space:]]/}" ]] && [[ -n "$NAVER_MAP_CLIENT_ID_SSM_PARAM" ]] && command -v aws >/dev/null 2>&1; then
  key="$(aws ssm get-parameter --with-decryption --name "$NAVER_MAP_CLIENT_ID_SSM_PARAM" --region "$REGION" --query 'Parameter.Value' --output text --no-cli-pager 2>/dev/null || true)"
fi

if [[ -z "${key//[[:space:]]/}" ]] && command -v aws >/dev/null 2>&1; then
  key="$(aws secretsmanager get-secret-value --secret-id "${PREFIX}naver-map-client-id" --region "$REGION" --query SecretString --output text --no-cli-pager 2>/dev/null || true)"
fi

if [[ -z "${key//[[:space:]]/}" ]]; then
  # Isolated: source the dotenv in a subshell so its other variables never enter
  # this process's environment; surface only the single build key.
  if [[ -f "$SOURCE_ENV" ]]; then
    # shellcheck disable=SC1090
    key="$( ( set -a; . "$SOURCE_ENV"; set +a; printf '%s' "${NAVER_MAP_CLIENT_ID:-}" ) )"
  fi
fi

if [[ -z "${key//[[:space:]]/}" ]]; then
  echo "NAVER_MAP_CLIENT_ID is required from restricted build configuration (SSM/Secrets Manager) or a trusted dotenv file." >&2
  exit 1
fi

cd "$ROOT/apps/flutter_app"
echo "Flutter build configuration resolved (API host and domain-restricted map key only)."
echo "server_secret_printing=false"
exec "$@" "--dart-define=LALA_API_BASE_URL=$API_BASE_URL" "--dart-define=NAVER_MAP_CLIENT_ID=$key" "--dart-define=LALA_BUILD_SHA=$(git -C "$ROOT" rev-parse --short HEAD)"
