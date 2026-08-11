#!/bin/bash
# True compiled dart-define verification for LALA_API_BASE_URL.
#
# String.fromEnvironment is resolved at compile time, so override behavior can
# only be proven by compiling the test binary with the dart-define baked in.
# This script compiles test/core/config/app_config_test.dart twice:
#
#   1. Default  — no LALA_API_BASE_URL define (static public fallback expected).
#   2. Override — explicit LALA_API_BASE_URL, with a matching
#      TEST_EXPECTED_API_BASE_URL the compiled test asserts against.
#
# Both cases use the same data-driven test; only the compile-time constants
# differ. No secrets, tokens, or cloud identifiers are used — only a public
# endpoint and a loopback address. Run from anywhere; it resolves the app root.
#
#   bash apps/flutter_app/test/verification/override_test.sh

set -euo pipefail

cd "$(dirname "$0")/../.." # Navigate to flutter app root.

TEST_FILE="test/core/config/app_config_test.dart"
PASS_COUNT=0
FAIL_COUNT=0

run_case() {
  local label="$1"
  shift
  echo "── ${label} ──"
  # shellcheck disable=SC2086
  if flutter test "$TEST_FILE" "$@"; then
    echo "PASS: ${label}"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: ${label}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo "Testing LALA_API_BASE_URL compile-time override mechanism..."

# Case 1: Static default — no LALA_API_BASE_URL dart-define.
# config.baseUri and TEST_EXPECTED_API_BASE_URL both fall back to the public
# default, so the compiled test asserts the guest-safe endpoint.
run_case "default (no dart-define → public fallback)"

# Case 2: Explicit local override to the loopback dev endpoint.
# Both LALA_API_BASE_URL and TEST_EXPECTED_API_BASE_URL carry the same override,
# so the compiled test proves the dart-define flowed into config.baseUri.
run_case "explicit local override (loopback)" \
  --dart-define "LALA_API_BASE_URL=http://127.0.0.1:8080" \
  --dart-define "TEST_EXPECTED_API_BASE_URL=http://127.0.0.1:8080"

echo ""
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "CORRECTION_REQUIRED: compiled dart-define verification failed."
  exit 1
fi
echo "PASS: String.fromEnvironment uses dart-define values when provided, and the static public default otherwise."
