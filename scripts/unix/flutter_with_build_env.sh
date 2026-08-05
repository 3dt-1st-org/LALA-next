#!/usr/bin/env bash
#
# Flutter build environment wrapper with AWS-first secret resolution.
# This shared wrapper provides a unified interface for building Flutter apps
# with proper build-time secret injection using AWS-first resolution.
#
# Usage:
#   scripts/unix/flutter_with_build_env.sh [--source-env env_file] [--region region] [--prefix prefix] [--api-base-url url] [flutter_args...]
#
# Options:
#   --source-env env_file   Additional env file to load (after AWS and .env.local/.env)
#   --region region         AWS region for Secrets Manager (default: AWS_REGION or us-east-1)
#   --prefix prefix         AWS Secrets Manager prefix (default: LALA_AWS_SM_PREFIX or lala-next/)
#   --api-base-url url      API base URL to inject via --dart-define
#   --build-sha sha         Build SHA to inject via --dart-define
#
# This wrapper:
# 1. Resolves build secrets from AWS Secrets Manager first
# 2. Falls back to .env.local, then .env (and optional --source-env)
# 3. Fails closed if no source provides required secrets
# 4. Injects only allowlisted Dart defines (KAKAO_JAVASCRIPT_KEY, LALA_API_BASE_URL, LALA_BUILD_SHA)
# 5. Never prints secret values to stdout/stderr
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

# Default options
SOURCE_ENV_FILE=""
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
SM_PREFIX="${LALA_AWS_SM_PREFIX:-}"
API_BASE_URL="${LALA_API_BASE_URL:-}"
BUILD_SHA="${GITHUB_SHA:-}"
FLUTTER_ARGS=()

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-env)
      SOURCE_ENV_FILE="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --prefix)
      SM_PREFIX="$2"
      shift 2
      ;;
    --api-base-url)
      API_BASE_URL="$2"
      shift 2
      ;;
    --build-sha)
      BUILD_SHA="$2"
      shift 2
      ;;
    -h|--help)
      grep '^#' "$0" | grep -v '#!' | sed 's/^# //; s/^#//'
      exit 0
      ;;
    *)
      FLUTTER_ARGS+=("$1")
      shift
      ;;
  esac
done

# Validate Flutter command
if [[ ${#FLUTTER_ARGS[@]} -eq 0 ]]; then
  echo "Error: No Flutter command specified." >&2
  echo "Usage: $0 [--source-env env_file] [--region region] [--prefix prefix] [--api-base-url url] [--build-sha sha] [flutter_args...]" >&2
  exit 2
fi

# Export AWS configuration for the helper
if [[ -n "$AWS_REGION" ]]; then
  export AWS_REGION
fi
if [[ -n "$SM_PREFIX" ]]; then
  export LALA_AWS_SM_PREFIX="$SM_PREFIX"
fi

# AWS-first resolution for build secrets; must run before other loaders
if ! load_flutter_build_secrets "KAKAO_JAVASCRIPT_KEY" "kakao-javascript-key"; then
  echo "Error: KAKAO_JAVASCRIPT_KEY could not be resolved from any source." >&2
  echo "Required for Flutter build. Configure AWS Secrets Manager or approved local secret source." >&2
  exit 2
fi

# Local dotenv and Azure Key Vault for other non-build configuration only
ROOT="$(repo_root)"
load_env_file "$ROOT/.env.local" 2>/dev/null || true
load_env_file "$ROOT/.env" 2>/dev/null || true

# Optional source env file (after AWS and standard dotenv)
if [[ -n "$SOURCE_ENV_FILE" && -f "$SOURCE_ENV_FILE" ]]; then
  load_env_file "$SOURCE_ENV_FILE"
fi

load_lala_key_vault_secrets 2>/dev/null || true

# Build Flutter arguments with injected defines
FINAL_FLUTTER_ARGS=("${FLUTTER_ARGS[@]}")

# Inject only allowlisted Dart defines
if [[ -n "${KAKAO_JAVASCRIPT_KEY:-}" ]]; then
  FINAL_FLUTTER_ARGS+=(--dart-define "KAKAO_JAVASCRIPT_KEY=$KAKAO_JAVASCRIPT_KEY")
fi

if [[ -n "$API_BASE_URL" ]]; then
  FINAL_FLUTTER_ARGS+=(--dart-define "LALA_API_BASE_URL=$API_BASE_URL")
fi

if [[ -n "$BUILD_SHA" ]]; then
  FINAL_FLUTTER_ARGS+=(--dart-define "LALA_BUILD_SHA=$BUILD_SHA")
fi

# Verify Flutter is available
if ! command -v flutter >/dev/null 2>&1; then
  echo "Error: flutter command not found on PATH." >&2
  exit 2
fi

# Execute Flutter with the final arguments
cd "$ROOT/apps/flutter_app"
exec flutter "${FINAL_FLUTTER_ARGS[@]}"
