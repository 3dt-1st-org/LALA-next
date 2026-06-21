#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

REQUIRE_FLUTTER="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-flutter)
      REQUIRE_FLUTTER="true"
      shift
      ;;
    -h|--help)
      echo "Usage: scripts/unix/verify_flutter_app.sh [--require-flutter]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ROOT="$(repo_root)"
APP_DIR="$ROOT/apps/flutter_app"
load_env_file "$ROOT/.env"
load_lala_key_vault_secrets

if ! command -v flutter >/dev/null 2>&1; then
  if [[ "$REQUIRE_FLUTTER" == "true" ]]; then
    echo "Flutter SDK is required for Flutter app verification." >&2
    exit 2
  fi
  echo "Flutter SDK is not available; skipping Flutter app analyze/test."
  exit 0
fi

cd "$APP_DIR"

echo "Resolving Flutter app dependencies..."
flutter pub get

echo "Formatting Flutter app in check-only mode..."
dart format --set-exit-if-changed lib/main.dart lib/kakao_*.dart test/widget_test.dart

echo "Analyzing Flutter app..."
flutter analyze

echo "Running Flutter app widget tests..."
flutter test

echo "Building Flutter web release bundle..."
FLUTTER_BUILD_ARGS=(build web --release --pwa-strategy=none)
if [[ -n "${KAKAO_JAVASCRIPT_KEY:-}" ]]; then
  FLUTTER_BUILD_ARGS+=(--dart-define "KAKAO_JAVASCRIPT_KEY=$KAKAO_JAVASCRIPT_KEY")
fi
flutter "${FLUTTER_BUILD_ARGS[@]}"
