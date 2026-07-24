#!/usr/bin/env bash

# Build and deploy the public Flutter bundle. The Kakao JavaScript key is a
# build-time public browser credential, but it must still be supplied so the
# map bridge cannot silently fall back to its unavailable state.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT_DIR/apps/flutter_app"
STAGING_DIR="$ROOT_DIR/static-output"
API_BASE_URL="${LALA_API_BASE_URL:-https://api.lala-next.cloud}"
BUILD_SHA="${LALA_BUILD_SHA:-$(git -C "$ROOT_DIR" rev-parse --short HEAD)}"
DRY_RUN=false

case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=true ;;
  *)
    echo "Usage: $0 [--dry-run]" >&2
    exit 2
    ;;
esac

if [[ -z "${KAKAO_JAVASCRIPT_KEY:-}" ]]; then
  echo "KAKAO_JAVASCRIPT_KEY is required for a production Flutter web build." >&2
  echo "Load it from the approved local secret source, then rerun this command." >&2
  exit 2
fi

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
    --dart-define="LALA_API_BASE_URL=$API_BASE_URL" \
    --dart-define="LALA_BUILD_SHA=$BUILD_SHA" \
    --dart-define="KAKAO_JAVASCRIPT_KEY=$KAKAO_JAVASCRIPT_KEY"
)

python3 "$ROOT_DIR/scripts/prepare_flutter_vercel_static_output.py"

if ! grep -Fq -- "$KAKAO_JAVASCRIPT_KEY" "$STAGING_DIR/main.dart.js"; then
  echo "Kakao JavaScript key was not compiled into the Flutter bundle." >&2
  exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Flutter production bundle built and verified; Vercel deployment skipped."
  exit 0
fi

(
  cd "$STAGING_DIR"
  vercel deploy . --prod --yes --force --local-config vercel.json --format json
)
