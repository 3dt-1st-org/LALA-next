#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

SOURCE_ENV=""
PREFIX="${LALA_AWS_SM_PREFIX:-lala-next/}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
INCLUDE_BUILD_CONFIG="false"
APPLY="false"
CONFIRM=""

usage() {
  cat <<'EOF'
Usage: scripts/unix/sync_aws_secrets_manager.sh [options]

Safely synchronize approved LALA runtime values from a trusted local dotenv file
to individual AWS Secrets Manager entries. The default is a value-free plan.

Options:
  --source-env PATH              dotenv input (default: <repo>/.env)
  --prefix PREFIX                secret prefix (default: lala-next/)
  --region REGION                AWS region (default: AWS_REGION or us-east-1)
  --include-build-config         include public Flutter map and Logto client configuration
  --apply --confirm SYNC_AWS_SECRETS
                                 create/update entries after explicit confirmation
  -h, --help                     show this help

The command never prints values. It only accepts a locally trusted dotenv file;
do not use an untrusted file because dotenv parsing executes shell assignments.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-env) SOURCE_ENV="${2:-}"; shift 2 ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --region) REGION="${2:-}"; shift 2 ;;
    --include-build-config) INCLUDE_BUILD_CONFIG="true"; shift ;;
    --apply) APPLY="true"; shift ;;
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ROOT="$(repo_root)"
SOURCE_ENV="${SOURCE_ENV:-$ROOT/.env}"
cd "$ROOT"

if [[ -z "$PREFIX" || "$PREFIX" != */ ]]; then
  echo "--prefix must be non-empty and end with /." >&2
  exit 2
fi
if [[ ! -f "$SOURCE_ENV" ]]; then
  echo "Trusted dotenv input not found: $SOURCE_ENV" >&2
  exit 2
fi
if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required." >&2
  exit 2
fi

# Exact Settings.from_env AWS Secrets Manager mapping. Operational toggles stay
# in an instance-owned runtime env file; they are not credentials.
RUNTIME_NAMES=(
  IOS_API_KEY API_BEARER_TOKEN
  LOGTO_ENDPOINT LOGTO_API_AUDIENCE LOGTO_MANAGEMENT_ENDPOINT
  LOGTO_MANAGEMENT_CLIENT_ID LOGTO_MANAGEMENT_CLIENT_SECRET
  OAUTH_ISSUER OAUTH_AUDIENCE OAUTH_JWKS_URL OAUTH_CLIENT_ID OAUTH_REQUIRED_SCOPES
  KAKAO_REST_API_KEY KAKAO_REDIRECT_URI
  NAVER_CLIENT_ID NAVER_CLIENT_SECRET KOPIS_API_KEY PUBLIC_DATA_SERVICE_KEY
  GYEONGGI_DATA_DREAM_API_KEY DB_DSN
  OPENAI_API_KEY OPENAI_BASE_URL OPENAI_EMBEDDING_MODEL
  OPENAI_REVIEW_BATCH_MODEL OPENAI_REVIEW_RECHECK_MODEL OPENAI_DOCENT_MODEL
  OPENAI_PLACE_ENRICHMENT_MODEL
  AZURE_SPEECH_REGION AZURE_SPEECH_ENDPOINT AZURE_SPEECH_KEY
)
BUILD_NAMES=()
if [[ "$INCLUDE_BUILD_CONFIG" == "true" ]]; then
  BUILD_NAMES+=(
    NAVER_MAP_CLIENT_ID
    LOGTO_NATIVE_APP_ID LOGTO_WEB_APP_ID
    LOGTO_NATIVE_REDIRECT_URI LOGTO_WEB_REDIRECT_URI
    LOGTO_NATIVE_POST_LOGOUT_REDIRECT_URI LOGTO_WEB_POST_LOGOUT_REDIRECT_URI
    LOGTO_REDIRECT_URI LOGTO_POST_LOGOUT_REDIRECT_URI
  )
fi

secret_name_for_env() {
  local env_name="$1"
  printf '%s%s' "$PREFIX" "$(printf '%s' "$env_name" | tr '[:upper:]_' '[:lower:]-')"
}

echo "LALA AWS Secrets Manager synchronization"
echo "mode=$([[ "$APPLY" == "true" ]] && echo apply || echo plan)"
echo "region=$REGION"
echo "prefix=$PREFIX"
echo "source_env=provided"
echo "secret_value_printing=false"

# shellcheck disable=SC1090
set -a
source "$SOURCE_ENV"
set +a

names=("${RUNTIME_NAMES[@]}" "${BUILD_NAMES[@]}")
present=0
missing=0
for env_name in "${names[@]}"; do
  value="${!env_name:-}"
  if [[ -n "${value//[[:space:]]/}" ]]; then
    present=$((present + 1))
    echo "$(secret_name_for_env "$env_name"): present"
  else
    missing=$((missing + 1))
    echo "$(secret_name_for_env "$env_name"): absent (not changed)"
  fi
done
echo "present_count=$present"
echo "absent_count=$missing"

if [[ "$APPLY" != "true" || "$CONFIRM" != "SYNC_AWS_SECRETS" ]]; then
  echo "mode=plan"
  echo "To write approved values: add --apply --confirm SYNC_AWS_SECRETS"
  exit 0
fi

if ! aws sts get-caller-identity --region "$REGION" --no-cli-pager >/dev/null 2>&1; then
  echo "AWS credentials are unavailable or unauthorized for this region." >&2
  exit 1
fi

tmp_file="$(mktemp "${TMPDIR:-/tmp}/lala-aws-secret.XXXXXX")"
chmod 600 "$tmp_file"
cleanup() { rm -f "$tmp_file"; }
trap cleanup EXIT

updated=0
for env_name in "${names[@]}"; do
  value="${!env_name:-}"
  if [[ -z "${value//[[:space:]]/}" ]]; then
    continue
  fi

  secret_id="$(secret_name_for_env "$env_name")"
  printf '%s' "$value" >"$tmp_file"
  if aws secretsmanager describe-secret --secret-id "$secret_id" --region "$REGION" --no-cli-pager >/dev/null 2>&1; then
    aws secretsmanager put-secret-value --secret-id "$secret_id" --secret-string "file://$tmp_file" --region "$REGION" --no-cli-pager >/dev/null
    echo "$secret_id: updated"
  else
    aws secretsmanager create-secret --name "$secret_id" --secret-string "file://$tmp_file" --region "$REGION" --tags Key=project,Value=lala-next Key=managed-by,Value=sync_aws_secrets_manager --no-cli-pager >/dev/null
    echo "$secret_id: created"
  fi
  : >"$tmp_file"
  updated=$((updated + 1))
done

echo "updated_count=$updated"
echo "AWS Secrets Manager synchronization completed without printing values."
