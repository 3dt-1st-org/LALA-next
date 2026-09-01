#!/usr/bin/env bash

# Build and deploy the public Flutter bundle. The Naver Dynamic Map client id is a
# build-time public browser credential, but it must still be supplied so the
# map bridge cannot silently fall back to its unavailable state.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts/unix"
source "$SCRIPT_DIR/_common.sh"
source "$SCRIPT_DIR/_flutter_public_build_config.sh"
APP_DIR="$ROOT_DIR/apps/flutter_app"
STAGING_DIR="$ROOT_DIR/static-output"
API_BASE_URL="${LALA_API_BASE_URL:-https://api.lala-next.cloud}"
BUILD_SHA="${LALA_BUILD_SHA:-$(git -C "$ROOT_DIR" rev-parse --short HEAD)}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PREFIX="${LALA_AWS_SM_PREFIX:-lala-next/}"
DRY_RUN=false

case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=true ;;
  *)
    echo "Usage: $0 [--dry-run]" >&2
    exit 2
    ;;
esac

if [[ -n "${LALA_FLUTTER_BUILD_ENV:-}" ]]; then
  FLUTTER_PUBLIC_ENV_FILES=("$LALA_FLUTTER_BUILD_ENV")
else
  FLUTTER_PUBLIC_ENV_FILES=("$ROOT_DIR/.env.local" "$ROOT_DIR/.env")
fi
resolve_flutter_public_build_config web true
append_flutter_public_dart_defines

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is required but was not found on PATH." >&2
  exit 2
fi

if ! command -v vercel >/dev/null 2>&1; then
  echo "vercel is required but was not found on PATH." >&2
  exit 2
fi

if [[ -z "${VERCEL_ORG_ID:-}" || -z "${VERCEL_PROJECT_ID:-}" ]]; then
  binding_path="$ROOT_DIR/.vercel/project.json"
  if [[ ! -f "$binding_path" ]]; then
    echo "Set VERCEL_ORG_ID and VERCEL_PROJECT_ID, or link this checkout with Vercel." >&2
    exit 2
  fi

  export VERCEL_ORG_ID="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["orgId"])' "$binding_path")"
  export VERCEL_PROJECT_ID="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["projectId"])' "$binding_path")"
fi

(
  cd "$APP_DIR"
  flutter pub get
  flutter build web --release \
    --pwa-strategy=none \
    "${FLUTTER_PUBLIC_DART_DEFINES[@]}"
)

python3 "$ROOT_DIR/scripts/prepare_flutter_vercel_static_output.py"

for build_name in \
  NAVER_MAP_CLIENT_ID LOGTO_ENDPOINT LOGTO_API_AUDIENCE LOGTO_WEB_APP_ID; do
  if ! grep -Fq -- "${!build_name}" "$STAGING_DIR/main.dart.js"; then
    echo "$build_name was not compiled into the Flutter bundle." >&2
    exit 1
  fi
done

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Flutter production bundle built and verified; Vercel deployment skipped."
  exit 0
fi

(
  cd "$STAGING_DIR"
  vercel deploy . --prod --yes --force --local-config vercel.json --format json
)
