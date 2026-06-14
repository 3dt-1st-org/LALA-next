#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/_common.sh"

REQUIRE_DART="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-dart)
      REQUIRE_DART="true"
      shift
      ;;
    -h|--help)
      echo "Usage: scripts/unix/verify_flutter_client.sh [--require-dart]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ROOT="$(repo_root)"
CLIENT_DIR="$ROOT/clients/flutter"

if ! command -v dart >/dev/null 2>&1; then
  if [[ "$REQUIRE_DART" == "true" ]]; then
    echo "Dart SDK is required for Flutter client verification." >&2
    exit 2
  fi
  echo "Dart SDK is not available; skipping Flutter client Dart analyze/test."
  echo "Python OpenAPI/client contract check still runs in verify_repo."
  exit 0
fi

cd "$CLIENT_DIR"

echo "Resolving Flutter reference client dependencies..."
dart pub get

echo "Formatting Flutter reference client in check-only mode..."
dart format --set-exit-if-changed lib/lala_api_client.dart test/lala_api_client_test.dart

echo "Analyzing Flutter reference client..."
dart analyze lib/lala_api_client.dart test/lala_api_client_test.dart

echo "Running Flutter reference client tests..."
dart test
